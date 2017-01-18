/*    jit.c
 *
 *    Copyright (C) 2017 by cPanel Inc.
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */
/* This file contains a simple LLVM method jit compiler,
 * simply linking the linearized ops with libperl.bc, storing the sub in
 * the XSUBANY ptr, and running it via jit_run().
 * The LLVM ipo (Interprocedural Optimizations) tries to inline and globally
 * optimize the pp subs, without any run-time type knowledge yet, we have no
 * PIC.
 * Optionally stores the code in a F<.bc> along a F<.pmc>/F<.plc>, which
 * allows skipping the compilation step.
 */

#include "EXTERN.h"
#define PERL_IN_JIT_C
#include "perl.h"

#if defined(USE_LLVMJIT) && !defined(PERL_IS_MINIPERL)

#include <llvm-c/Core.h>
#include <llvm-c/ExecutionEngine.h>
#include <llvm-c/Target.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/BitReader.h>
#include <llvm-c/BitWriter.h>
#include <llvm-c/Transforms/PassManagerBuilder.h>
#include <llvm-c/Transforms/Scalar.h>
#include <llvm-c/Transforms/IPO.h>

/* not yet my_perl specific */
static struct jit_t {
    LLVMExecutionEngineRef engine;
    LLVMModuleRef          corelib;
    LLVMPassManagerRef     pass;
    LLVMValueRef           op;
#ifdef USE_ITHREADS
    LLVMValueRef           myperl;
#endif  
} jit;

/*
=for apidoc jit_init

Initializes at startup the F<libperl.bc> module,
and the globals needed for L</jit_compile>.

=cut
*/
bool Perl_jit_init() {
    LLVMMemoryBufferRef MemBuf;
    char *env;
    char path[MAXPATHLEN];
    char *error = NULL;

    if ((env = PerlEnv_getenv("PERL_CORE")) && *env == '1') {
        strcpy(path, "libperl.bc");
    } else {
        strcpy(path, ARCHLIB_EXP);
        strcat(path, "/libperl.bc");
    }
    /* not yet enabled */
#if 1
    if (!LLVMCreateMemoryBufferWithContentsOfFile(path, &MemBuf, &error))
        Perl_croak(aTHX_ "jit: not enough memory or %s not found: %s", path, error);
#if ((LLVM_VERSION_MAJOR * 100) + LLVM_VERSION_MINOR) > 308
    if (!LLVMGetBitcodeModule2(MemBuf, &jit.corelib)) {
        Perl_ck_warner(aTHX_ packWARN(WARN_INTERNAL),
                       "jit: Could not load %s\n", path);
        return FALSE;
    }
#else
    /* XXX crash here */
    error = NULL;
    if (!LLVMGetBitcodeModule(MemBuf, &jit.corelib, &error)) {
        Perl_ck_warner(aTHX_ packWARN(WARN_INTERNAL),
                       "jit: Could not load %s: %s\n", path, error);
        return FALSE;
    }
#endif

#ifdef USE_ITHREADS
    jit.myperl  = LLVMGetNamedGlobal(jit.corelib, "my_perl");
    jit.op      = LLVMBuildStructGEP(builder, myperl, 1, 0, "Iop");
#else
    jit.op      = LLVMGetNamedGlobal(jit.corelib, "PL_op");
#endif

    jit.pass    = LLVMCreatePassManager();
    LLVMLinkInJIT();
    LLVMInitializeNativeTarget();
    LLVMDisposeMemoryBuffer(MemBuf);
    return TRUE;
#endif
    return FALSE;
}

/*
=for apidoc jit_destroy

Destroys some jit globals.

=cut
*/
void Perl_jit_destroy() {
    /* A module not, just the builder, pass and engine */
    LLVMDisposePassManager(jit.pass);
    LLVMDisposeExecutionEngine(jit.engine);
}

/* .pmc or .plc => .bc */
STATIC char *
S_jit_bcpath(pTHX_ CV* cv, char *pmcpath) {
    if (!pmcpath) {
        COP* op = (COP*)CvSTART(cv);
        if (OP_IS_COP(op->op_type)) {
            pmcpath = strdup(CopFILE(op));
        }
        else {
            /* TODO: which path? */
            const char* subname = SvPVX_const(cv_name(cv, NULL, 0));
            pmcpath = (char*)malloc(128);
            strncpy(pmcpath, subname, 128);
            strcat(pmcpath, ".bc");
        }
    } else {
        /* replace .pmc with .bc */
        pmcpath = strdup(pmcpath);
        int len = strlen(pmcpath);
        if (pmcpath[len-4] == '.') {
            pmcpath[len-3] = 'b';
            pmcpath[len-2] = 'c';
            pmcpath[len-1] = '\0';
        }
    }
    return pmcpath;
}

/*
=for apidoc jit_checkcache

This is called by C<require package.pmc>.
Exported as C<Internals::JitCache::load>.

Stat the parallel .bc, check the timestamps, verify the IR, load it and set the
CvJIT flags on all included subs.
Similar to java.

This allows pre-compilation via F<cperl -jc> - jit-compile, store and exit.
A script jitcache is a .plc

Returns the LLVMModuleRef pointer if the cv at the pmcpath was found
in the cache, otherwise we have to compile it.  If called via require
the cv is empty. Just return if the .bc was successfully loaded
instead.

Allocates fresh memory for bcpath.

=cut
*/
void*
Perl_jit_checkcache(pTHX_ const CV* cv, const char* pmcpath, char** bcpath) {
    LLVMMemoryBufferRef MemBuf;
    LLVMModuleRef module;
    char *error = NULL;
    PERL_ARGS_ASSERT_JIT_CHECKCACHE;

    *bcpath = S_jit_bcpath(aTHX_ cv, pmcpath);
    if (!LLVMCreateMemoryBufferWithContentsOfFile(*bcpath, &MemBuf, &error))
        Perl_croak(aTHX_ "jit: not enough memory for %s %s", pmcpath, error);
#if ((LLVM_VERSION_MAJOR * 100) + LLVM_VERSION_MINOR) > 308
    if (!LLVMGetBitcodeModule2(MemBuf, &module))
        return NULL;
#else
    error = NULL;
    if (!LLVMGetBitcodeModule(MemBuf, &module, &error))
        return NULL;
#endif
    /* iterate over all funcs and set CvJIT */
    LLVMDisposeMemoryBuffer(MemBuf);
    return module;
}

/*
=for apidoc jit_compile

Loads the precompiled libperl.bc modules, adds all ops for the sub, compile,
optimize (so far only simple inline, ...) and link it with the corelib and
optionally stores the module (= package of all jit-compiled subs) in a jitcache
file as F<.pmc> and F<.bc>.
There is not a 1:1 equivalence of cop_file and package file yet.

=cut
*/
bool Perl_jit_compile(pTHX_ const CV* cv, const char* pmcpath) {
    OP *op = CvSTART(cv);
    char *bcpath;
    const char* package = HvNAME(CvSTASH(cv));
    const char* subname = SvPVX_const(cv_name(cv, NULL, 0));
    /* TODO: cchars(subname) */
    LLVMExecutionEngineRef jitengine;
    LLVMModuleProviderRef provider;
    LLVMPassManagerRef pass   = jit.pass;
    LLVMModuleRef corelib     = jit.corelib;
    LLVMValueRef  opval       = jit.op;
    /* module will be the package, where we store the jitcache of all subs */
    /* check for existing module */
    LLVMModuleRef module      = (LLVMModuleRef)jit_checkcache(cv, pmcpath, &bcpath);

#ifndef PERL_LLVM_NOBUILDER
#  if PTRSIZE == 8
    LLVMTypeRef ptrty         = LLVMPointerType(LLVMInt8Type(), 0);
#  else
    LLVMTypeRef ptrty         = LLVMPointerType(LLVMInt4Type(), 0);
#  endif
#  ifdef USE_ITHREADS
    LLVMTypeRef  param_types[]= { ptrty };
    LLVMTypeRef  ppret_type   = LLVMFunctionType(ptrty, param_types, 1, 0);
#  else
    LLVMTypeRef  ppret_type   = LLVMFunctionType(ptrty, NULL, 0, 0);
#  endif  
    LLVMTypeRef  subret_type  = LLVMFunctionType(LLVMVoidType(), NULL, 0, 0);
    LLVMValueRef sub          = LLVMAddFunction(module
                                                  ? module
                                                  : LLVMModuleCreateWithName(package),
                                                subname, subret_type);
    LLVMBasicBlockRef entry   = LLVMAppendBasicBlock(sub, "entry");
    LLVMBuilderRef builder    = LLVMCreateBuilder();
    char ppname[48] = { "_Perl_pp_" };
    const int len = sizeof("_Perl_pp_")-1;

#else

    LLVMMemoryBufferRef MemBuf;
    SV* irbuf = newSVpvs(
      "; ModuleID = '_jitted.c'\n\n"
      "@PL_op = external global %struct.op*, align 8\n\n"
      "; Function Attrs: nounwind ssp uwtable\n");
    unsigned i;
#endif
    /*llvm_lto_t lto        = llvm_create_optimizer();*/
    char *error = NULL;
    PERL_ARGS_ASSERT_JIT_COMPILE;
    assert(corelib);

#ifdef PERL_LLVM_NOBUILDER
    if (!module) module = LLVMModuleCreateWithName(package);

    /* Instead of the Builder API we could simply assemble
       the code from IRReader.h: LLVMParseIRInContext().
       It is a bit slower though. */
    sv_catpvf(irbuf, "define void @_jitted_%s() #0 {\n", subname);
    for (i=0; op; op = op->op_next) {
        const char *name = OP_NAME(op);
        /* XXX 64bit only so far */
#ifdef USE_ITHREADS
        /* my_perl->Iop = Perl_pp_%s( my_perl);", name */
        sv_catpvf(irbuf,
          "  %u = load %%struct.interpreter*, %struct.interpreter** @my_perl, align 8, !tbaa !2\n",
          i++);
        sv_catpvf(irbuf,
          "  %u = tail call %%struct.op* @Perl_pp_%s(%%struct.interpreter* %u) #2\n",
          i+1, name, i-1);
        sv_catpvf(irbuf,
          "  %u = load %%struct.interpreter*, %%struct.interpreter** @my_perl, align 8, !tbaa !2\n",
          ++i);
        sv_catpvf(irbuf,
          "  %u = getelementptr inbounds %%struct.interpreter, %%struct.interpreter* %u, i64 0, i32 1\n",
          i, i-1);
        i++;
#else
        sv_catpvf(irbuf, "  %u = tail call %%struct.op* @Perl_pp_%s() #2\n", i, name);
        sv_catpvf(irbuf, "  store %%struct.op* %u, %struct.op** @PL_op, align 8, !tbaa !2\n", i++);
        /* TODO PERL_DTRACE_PROBE_OP(op); */
#endif
    }
    sv_catpvs(irbuf, "  ret void\n}\n");
    MemBuf = LLVMCreateMemoryBufferWithMemoryRange(SvPVX_const(irbuf),
        SvCUR(irbuf), "ir", 1);
    LLVMParseIRInContext(LLVMGetGlobalContext(), MemBuf, &module, &error);
#else    
    LLVMPositionBuilderAtEnd(builder, entry);
    for (; op; op = op->op_next) {
        /* linearize the PL_op = Perl_pp_opname(aTHX); calls */
        const char *name = OP_NAME(op);
        /* TODO find the proper pp name belonging to the address: aliases.
           We need the name even if we have the address for lookup and optims
           into libperl.bc */
        memcpy(&ppname[len], name, strlen(name));
        {
            /* better search the addr by PL_ppaddr[opcode], not by name */
            /* see http://lists.llvm.org/pipermail/llvm-dev/2016-May/099964.html */
            LLVMValueRef fn      = LLVMGetNamedFunction(corelib, ppname);
#ifdef USE_ITHREADS
            /* my_perl->Iop = Perl_pp_%s(my_perl) */
            LLVMValueRef call = LLVMBuildCall(builder, fn,
                                              param_types, 1, name);
            /* store into a struct offset */
            LLVMBuildStore(builder, call, opval);
#else
            /* PL_op = Perl_pp_%s(); */
            LLVMValueRef call = LLVMBuildCall(builder, fn,
                                              NULL, 0, name);
            LLVMBuildStore(builder, call, opval);
#endif
      
            /*TODO PERL_ASYNC_CHECK() signal handling */
        }
    }
    LLVMBuildRetVoid(builder);
#endif

#ifdef DEBUGGING
    LLVMVerifyModule(module, LLVMAbortProcessAction, &error);
    if (error) {
        PerlIO_printf(Perl_error_log, "jit verify error: %s\n", error);
        LLVMDisposeMessage(error);
        error = NULL;
        return FALSE;
    }
#endif
    jitengine = jit.engine;

    /* simple jit variants:
       LLVMCreateJITCompilerForModule(&jitengine, module, Aggressive) optlevel or detailled passes
       LLVMCreateExecutionEngineForModule(&jitengine, module, &error)
    */
    provider = LLVMCreateModuleProviderForExistingModule(module);
    error = NULL;
    if (LLVMCreateJITCompiler(&jitengine, provider, 2, &error) != 0) {
        PerlIO_printf(Perl_error_log, "error: %s\n", error);
        LLVMDisposeMessage(error);
        DIE("failed to create LLVM jit execution engine\n");
    }

    /* detailed optimization passes, tunable. need to analyse and time it */
    LLVMAddTargetData(LLVMGetExecutionEngineTargetData(jitengine), pass);
    /*LLVMAddConstantPropagationPass(pass);*/
    LLVMAddInstructionCombiningPass(pass);
    LLVMAddPromoteMemoryToRegisterPass(pass);
    /* LLVMAddDemoteMemoryToRegisterPass(pass); */ /* Demotes every possible value to memory */
    LLVMAddGVNPass(pass);
    LLVMAddCFGSimplificationPass(pass);
    /* expensive IPO libs: */
    LLVMAddArgumentPromotionPass(pass);
    LLVMAddConstantMergePass(pass);
    LLVMAddDeadArgEliminationPass(pass);
    LLVMAddFunctionAttrsPass(pass);
    LLVMAddFunctionInliningPass(pass);
    LLVMAddGlobalDCEPass(pass);
    LLVMAddGlobalOptimizerPass(pass);

    LLVMRunPassManager(pass, module);

    jit.engine = jitengine;
    CvJIT_on(cv);
    CvXSUBANY(cv).any_ptr = (void*)sub;

    /* save jitcache of the whole module, not just this sub */
    if (LLVMWriteBitcodeToFile(module, bcpath) != 0) {
        PerlIO_printf(Perl_error_log, "jit: error writing bitcode to %s, skipping\n",
            bcpath);
    }
    if (DEBUG_j_TEST_) { /* -Dj prints the bitcode: lldm-dis subname.bc */
        PerlIO_printf(Perl_debug_log, "subname %s:\n", subname);
        LLVMDumpModule(module);
    }
    LLVMDisposeBuilder(builder);
    return TRUE;
}


/*
=for apidoc jit_run

Calls the compiled CvXSUBANY(cv).any_ptr.

=cut
*/
OP* Perl_jit_run(pTHX_ const CV* cv) {
    LLVMValueRef sub = (LLVMValueRef)CvXSUBANY(cv).any_ptr;
    assert(CvJIT(cv));
    LLVMRunFunction(jit.engine, sub, 0, NULL);
    return PL_op;
}

#else

bool  Perl_jit_init()    { return FALSE; }
void  Perl_jit_destroy() { NOOP; }
void* Perl_jit_checkcache(pTHX_ const CV* cv, const char* pmcpath, char** bcpath) {
    PERL_UNUSED_ARG(cv);
    PERL_UNUSED_ARG(pmcpath);
    PERL_UNUSED_ARG(bcpath);
    return NULL;
}
bool Perl_jit_compile(pTHX_ const CV* cv, const char* pmcpath) {
    PERL_UNUSED_ARG(cv);
    PERL_UNUSED_ARG(pmcpath);
    return FALSE;
}
OP* Perl_jit_run(pTHX_ const CV* cv) {
    PERL_UNUSED_ARG(cv);
    return NULL;
}

#endif

/*
=for apidoc runops_jit

A special runloop for the C<cperl -j> method jit, which compiles and
runs all functions jitted. This can be used with C<-jc> to save the
jitcaches for all packages at compile-time or C<-j> warm-up runs for
run-time added subs.

=cut
*/
int
Perl_runops_jit(pTHX)
{
    /* runs all the subs compiled. needs the compiler op.c call jit_compile. */
    CV * const cv = deb_curcv(cxstack_ix);

    if (!CvJIT(cv))
        jit_compile(cv, NULL);
    jit_run(cv);
    PERL_ASYNC_CHECK();

    TAINT_NOT;
    return 0;
}

