/* dlutils.c - handy functions and definitions for dl_*.xs files
 *
 * Currently this file is simply #included into dl_*.xs/.c files.
 * It should really be split into a dlutils.h and dlutils.c
 *
 * Modified:
 * 29th Feburary 2000 - Alan Burlison: Added functionality to close dlopen'd
 *                      files when the interpreter exits
 * March 2015         - Reini Urban: Added XS implementations for DynaLoader.pm
 *                      and XSLoader.pm
 */

#define PERL_EUPXS_ALWAYS_EXPORT
#ifndef START_MY_CXT /* Some IDEs try compiling this standalone. */
#   define PERL_NO_GET_CONTEXT
#   define PERL_EXT
#   include "EXTERN.h"
#   include "perl.h"
#   include "XSUB.h"
#endif

#ifndef XS_VERSION
#  define XS_VERSION "0"
#endif
#define MY_CXT_KEY "DynaLoader::_guts" XS_VERSION

/* disable version checking since DynaLoader can't be DynaLoaded */
#undef dXSBOOTARGSXSAPIVERCHK
#define dXSBOOTARGSXSAPIVERCHK dXSBOOTARGSNOVERCHK

typedef struct {
    SV*		x_dl_last_error;	/* pointer to allocated memory for
					   last error message */
#if defined(PERL_IN_DL_HPUX_XS) || defined(PERL_IN_DL_DLOPEN_XS)
    int		x_dl_nonlazy;		/* flag for immediate rather than lazy
					   linking (spots unresolved symbol) */
#endif
#ifdef DL_LOADONCEONLY
    HV *	x_dl_loaded_files;	/* only needed on a few systems */
#endif
#ifdef DL_CXT_EXTRA
    my_cxtx_t	x_dl_cxtx;		/* extra platform-specific data */
#endif
#ifdef DEBUGGING
    int		x_dl_debug;	/* value copied from $DynaLoader::dl_debug */
#endif
} my_cxt_t;


/* DynaLoader globals */
AV *dl_require_symbols;      /* names of symbols we need */
AV *dl_resolve_using;        /* names of files to link with */
AV *dl_library_path;         /* path to look for files */

EXTERN_C void dl_boot (pTHX);
static AV*    dl_split_modparts (pTHX_ SV* module);
static int    dl_load_file(pTHX_ I32 ax, SV* file, SV *module, int gimme);

START_MY_CXT

#define dl_last_error	(SvPVX(MY_CXT.x_dl_last_error))
#if defined(PERL_IN_DL_HPUX_XS) || defined(PERL_IN_DL_DLOPEN_XS)
#define dl_nonlazy	(MY_CXT.x_dl_nonlazy)
#endif
#ifdef DL_LOADONCEONLY
#define dl_loaded_files	(MY_CXT.x_dl_loaded_files)
#endif
#ifdef DL_CXT_EXTRA
#define dl_cxtx		(MY_CXT.x_dl_cxtx)
#endif
#ifdef DEBUGGING
#define dl_debug	(MY_CXT.x_dl_debug)
#endif

#ifdef DEBUGGING
#define DLDEBUG(level,code) \
    STMT_START {					\
	dMY_CXT;					\
	if (dl_debug>=level) { code; }			\
    } STMT_END
#else
#define DLDEBUG(level,code)	NOOP
#endif

#define pv_copy(pv)     newSVpvn_flags(SvPVX(pv), SvCUR(pv), SvUTF8(pv))
#define fn_exists(fn)   (PerlLIO_stat((fn), &PL_statcache) >= 0         \
                     && (S_ISLNK(PL_statcache.st_mode) || S_ISREG(PL_statcache.st_mode)))
#define dir_exists(dir) (PerlLIO_stat((dir), &PL_statcache) >= 0 \
                     && S_ISDIR(PL_statcache.st_mode))

#ifdef DL_UNLOAD_ALL_AT_EXIT
/* Close all dlopen'd files */
static void
dl_unload_all_files(pTHX_ void *unused)
{
    CV *sub;
    AV *dl_librefs;
    SV *dl_libref;

    if ((sub = get_cvs("DynaLoader::dl_unload_file", 0)) != NULL) {
        dl_librefs = get_av("DynaLoader::dl_librefs", 0);
        EXTEND(SP,1);
        while ((dl_libref = av_pop(dl_librefs)) != &PL_sv_undef) {
           dSP;
           ENTER;
           SAVETMPS;
           PUSHMARK(SP);
           PUSHs(sv_2mortal(dl_libref));
           PUTBACK;
           call_sv((SV*)sub, G_DISCARD | G_NODEBUG);
           FREETMPS;
           LEAVE;
        }
    }
}
#endif

static void
dl_generic_private_init(pTHX)	/* called by dl_*.xs dl_private_init() */
{
#if defined(PERL_IN_DL_HPUX_XS) || defined(PERL_IN_DL_DLOPEN_XS)
    char *perl_dl_nonlazy;
    UV uv;
#endif
    MY_CXT_INIT;

    MY_CXT.x_dl_last_error = newSVpvs("");
#ifdef DL_LOADONCEONLY
    dl_loaded_files = NULL;
#endif
#ifdef DEBUGGING
    {
	SV *sv = get_sv("DynaLoader::dl_debug", 0);
	dl_debug = sv ? SvIV(sv) : 0;
    }
#endif

#if defined(PERL_IN_DL_HPUX_XS) || defined(PERL_IN_DL_DLOPEN_XS)
    if ( (perl_dl_nonlazy = getenv("PERL_DL_NONLAZY")) != NULL
        && (grok_number(perl_dl_nonlazy, strlen(perl_dl_nonlazy), &uv) && IS_NUMBER_IN_UV)
	&& uv <= INT_MAX
    ) {
	dl_nonlazy = (int)uv;
    } else
	dl_nonlazy = 0;
    if (dl_nonlazy)
	DLDEBUG(1,PerlIO_printf(Perl_debug_log, "DynaLoader bind mode is 'non-lazy'\n"));
#endif
#ifdef DL_LOADONCEONLY
    if (!dl_loaded_files)
	dl_loaded_files = newHV(); /* provide cache for dl_*.xs if needed */
#endif
#ifdef DL_UNLOAD_ALL_AT_EXIT
    call_atexit(&dl_unload_all_files, (void*)0);
#endif
#ifdef DL_LOADONCEONLY
    if (!dl_loaded_files)
#else
    if (!get_cv("DynaLoader::bootstrap", 0))
#endif
      dl_boot(aTHX);
}


#ifndef SYMBIAN
/* SaveError() takes printf style args and saves the result in dl_last_error */
static void
SaveError(pTHX_ const char* pat, ...)
{
    va_list args;
    SV *msv;
    const char *message;
    STRLEN len;

    /* This code is based on croak/warn, see mess() in util.c */

    va_start(args, pat);
    msv = vmess(pat, &args);
    va_end(args);

    message = SvPV(msv,len);
    len++;		/* include terminating null char */

    {
	dMY_CXT;
        char *end = (char*)message;
        /* printf security: strip % from message */
        while ((end = strchr(end, '%'))) { *end = ' '; }
        /* Copy message into dl_last_error (including terminating null char) */
	sv_setpvn(MY_CXT.x_dl_last_error, message, len);
	DLDEBUG(2,PerlIO_printf(Perl_debug_log, "DynaLoader: stored error msg '%s'\n",
                                dl_last_error));
    }
}
#endif

#include "dlboot.c"   /* bootstrap code converted from DynaLoader.pm */

XS(XS_DynaLoader_bootstrap_inherit)
{
    dVAR; dXSARGS;
    AV* isa;
    if (items < 1 || !SvPOK(ST(0)))
        Perl_die(aTHX_ "Usage: DynaLoader::bootstrap_inherit($packagename [,$VERSION])\n");
    {
        SV *module_isa = pv_copy(ST(0));
        char *s;
        sv_catpvs(module_isa, "::ISA");
        s = SvPVX(module_isa);
	DLDEBUG(2,PerlIO_printf(Perl_debug_log, "DynaLoader::bootstrap_inherit '%s' %d args\n",
                                SvPVX(ST(0)), (int)items));
	ENTER_with_name("bootstrap");
        SAVETMPS;
        if ((isa = get_av(s, GV_ADDMULTI))) {
            SAVESPTR(isa);
            if (AvFILL(isa)>=0)
                isa = av_make(AvFILL(isa), AvARRAY(isa));
            else
                isa = newAV();
            AV_PUSH(isa, newSVpvs("DynaLoader"));
            DLDEBUG(2,PerlIO_printf(Perl_debug_log, "@%s=(%s)\n", s, av_tostr(aTHX_ isa)));
            SAVEFREESV(isa);
        }
        PUSHMARK(MARK);
        PUTBACK;
        items = call_pv("DynaLoader::bootstrap", GIMME);
        SPAGAIN;
        FREETMPS;
        LEAVE_with_name("bootstrap");
        XSRETURN(items);
    }
}

/*
  now start splitting and walking modparts /::/
  module => ($modpname... /$modfname)
*/
static AV*
dl_split_modparts (pTHX_ SV* module) {
    AV *modparts = newAV();
    char *mn  = SvPVX(module);
    char *cur = mn;
    int  utf8 = SvUTF8(module);
    for (;; cur++) {
        if (!*cur) {
            AV_PUSH(modparts, newSVpvn_flags(mn, cur-mn, utf8));
            break;
        }
        /* We'd really need to check if there are embedded "::"
         seqs or just an ending ':' in utf8 codepoints.  But perl5
         core (gv_fetch*) also does not care.  So we rather stay
         incorrect and consistent.
         Checked now unicode range 0-0x10ffff and looked good. --rurban 2015-04-06 */
        else if (*cur == ':' && *(cur-1) == ':') {
            AV_PUSH(modparts, newSVpvn_flags(mn, cur-mn-1, utf8));
            mn = cur + 1;
        }
    }
    return modparts;
}

static SV*
dl_construct_modpname(pTHX_ AV* modparts) {
    dSP;
    SSize_t i;
    SV *modpname;

    /* Some systems have restrictions on files names for DLL's etc.
       mod2fname returns appropriate file base name (typically truncated).
       It may also edit @modparts if required. */
    CV *mod2fname = get_cv("DynaLoader::mod2fname", 0);
    if (mod2fname) {
	DLDEBUG(2,PerlIO_printf(Perl_debug_log, "DynaLoader: Enter mod2fname with '%s'\n", SvPVX(AvARRAY(modparts)[AvFILLp(modparts)])));
        SPAGAIN;
        PUSHMARK(SP);
        PUTBACK;
        XPUSHs(newRV((SV*)modparts));
        call_sv((SV*)mod2fname, G_SCALAR);
        SPAGAIN;
	DLDEBUG(2,PerlIO_printf(Perl_debug_log, "DynaLoader: Got mod2fname => '%s'\n", SvPVX(POPs)));
    }
#ifdef NETWARE
    /* Truncate the module name to 8.3 format for NetWare */
    if (SvCUR(modfname) > 8)
	SvCUR_set((modfname, 8);
#endif
    modpname = newSVpvs("");
    for (i=0; i<=AvFILLp(modparts)-1; i++) {
        sv_catsv(modpname, AvARRAY(modparts)[i]);
        sv_catpvs(modpname, "/");
    }
    sv_catsv(modpname, AvARRAY(modparts)[AvFILLp(modparts)]);
    return modpname;
}

XS(XS_DynaLoader_bootstrap)
{
    dVAR; dXSARGS;
    SSize_t i;
    char *modulename;
    CV *cv_load_file;
    AV *modparts, *dirs;
    SV *module, *modfname, *modpname, *file;

    DLDEBUG(2,PerlIO_printf(Perl_debug_log, "DynaLoader::bootstrap '%s' %d args\n",
                            SvPVX(ST(0)), (int)items));
    if (items < 1 || !SvPOK(ST(0)))
        Perl_die(aTHX_ "Usage: DynaLoader::bootstrap($packagename [,$VERSION])\n");
    module = ST(0);
    modulename = SvPVX(module);
    cv_load_file = get_cv("DynaLoader::dl_load_file", 0);
    if (!cv_load_file) {
      Perl_die(aTHX_ "Can't load module %s, dynamic loading not available in this perl.\n"
               "  (You may need to build a new perl executable which either supports\n"
               "  dynamic loading or has the %s module statically linked into it.)\n",
               modulename, modulename);
    }

#ifdef OS2
    if (!SvTRUE_NN(get_sv("OS2::is_static")))
        Perl_die(aTHX_ "Dynaloaded Perl modules are not available in this build of Perl");
#endif

    /* now start splitting and walking modparts /::/ */
    modparts = dl_split_modparts(aTHX_ module);
    modfname = AvARRAY(modparts)[AvFILLp(modparts)];
    modpname = dl_construct_modpname(aTHX_ modparts);

    DLDEBUG(1, PerlIO_printf(Perl_debug_log, "DynaLoader::bootstrap for %s "
        "(auto/%s/%s%s)\n", modulename, SvPVX(modpname), SvPVX(modfname), DLEXT));

    SvREFCNT_inc_NN(modfname); /* is needed later */
    SvREFCNT_dec(modparts);

    dirs = newAV();
    for (i=0; i<=AvFILL(GvAV(PL_incgv)); i++) {
        SV * const dirsv = *av_fetch(GvAV(PL_incgv), i, TRUE);
        SV *slib, *dir;

        /* Handle avref or cvref in @INC. eg: Class::Load::XS.
           Code from pp_ctl.c: pp_require without source filters */
        SvGETMAGIC(dirsv);
        if (SvROK(dirsv)) {
            int count;
            SV *loader = dirsv;
            SV** oldsp = sp;

            if (SvTYPE(SvRV(loader)) == SVt_PVAV && !SvOBJECT(SvRV(loader))) {
                loader = *av_fetch(MUTABLE_AV(SvRV(loader)), 0, TRUE);
                SvGETMAGIC(loader);
            }
            ENTER_with_name("call_INC");
            EXTEND(SP, 2);
            PUSHMARK(SP);
            PUSHs(dirsv);
            PUSHs(modpname);
            PUTBACK;
            if (SvGMAGICAL(loader)) {
                SV *l = sv_newmortal();
                sv_setsv_nomg(l, loader);
                loader = l;
            }
            if (sv_isobject(loader))
                count = call_method("INC", G_ARRAY);
            else
                count = call_sv(loader, G_ARRAY);
            SPAGAIN;

            if (count > 0) {
                /*int i = 0;
                  SV *arg;*/
#if 1
                if (SvPOK(TOPs))
                    dir = pv_copy(TOPs);
                else
                    dir = newSVpvs(".");
                SP -= count - 1;
#else
                arg = SP[i++];
                if (SvROK(arg) && (SvTYPE(SvRV(arg)) <= SVt_PVLV)
                    && !isGV_with_GP(SvRV(arg))) {
                    if (i < count) {
                        arg = SP[i++];
                    }
                }
                if (SvROK(arg) && isGV_with_GP(SvRV(arg))) {
                    arg = SvRV(arg);
                }
                if (isGV_with_GP(arg)) {
                    IO * const io = GvIO((const GV *)arg);
                    if (io) {
                        if (IoOFP(io) && IoOFP(io) != IoIFP(io)) {
                            PerlIO_close(IoOFP(io));
                        }
                        IoIFP(io) = NULL;
                        IoOFP(io) = NULL;
                    }
                    if (i < count) {
                        arg = SP[i++];
                    }
                }
                SP--;
#endif
            }
            else {
                dir = newSVpvs(".");
            }
            PUTBACK;
            LEAVE_with_name("call_INC");
            sp = oldsp;
            PUTBACK;
        } else {
            dir = pv_copy(dirsv);
        }
#ifdef VMS
        char *buf = tounixpath_utf8_ts(aTHX_ dir, NULL, SvUTF8(dir));
        int len = strlen(buf);
        SvGROW(dir, len);
        SvPV_set(dir, buf);
        SvCUR_set(dir, len);
#endif
        file = NULL;
        sv_catpvs(dir, "/auto/");
        sv_catsv(dir, modpname);
        {
            const char *path = SvPV_nolen_const(dir);
	    if (!dir_exists(path)) { /* skip over uninteresting directories */
	        DLDEBUG(3,PerlIO_printf(Perl_debug_log, " skipping %s (not existing)\n",
                                        path));
                continue;
            }
        }

        slib = pv_copy(dir);
        sv_catpvs(slib, "/");
        sv_catsv(slib, modfname);
        sv_catpv(slib, DLEXT);

        if (SvIVX(do_expand)) {
            PUSHMARK(SP);
            PUTBACK;
            XPUSHs(slib);
            call_pv("DynaLoader::dl_expandspec", G_SCALAR);
            SPAGAIN;
            file = POPs;
            if (file == &PL_sv_undef)
                file = NULL;
            else
                break;
        }
        else {
	    if (fn_exists(SvPVX(slib))) {
                file = slib;
	        DLDEBUG(3,PerlIO_printf(Perl_debug_log, "  found %s\n",
                                        SvPVX(slib)));
                break;
            }
        }
        av_push(dirs, dir);
    }
    if (!file) {
	DLDEBUG(3,PerlIO_printf(Perl_debug_log, "DynaLoader: @INC/auto/%s/%s%s not found\n",
                                SvPVX(modpname), SvPVX(modfname), DLEXT));
	DLDEBUG(3,PerlIO_printf(Perl_debug_log, "DynaLoader: Searching now %s and %s\n",
                                av_tostr(aTHX_ dirs), av_tostr(aTHX_ GvAV(PL_incgv))));
        /* last resort, let dl_findfile have a go in all known locations */
        if (AvFILLp(dirs) >= 0) {
            AV *tmp = newAV();
            for (i=0; i<=AvFILLp(dirs); i++) {
                SV *dir = newSVpvs("-L");
                sv_catsv(dir, AvARRAY(dirs)[i]);
                AV_PUSH(tmp, dir);
            }
            AV_PUSH(tmp, modfname);
            file = dl_findfile(aTHX_ tmp, G_SCALAR);
            SvREFCNT_dec_NN(tmp);
        }
        if (!file && AvFILLp(GvAV(PL_incgv)) >= 0) {
            AV *ori = GvAV(PL_incgv);
            AV *tmp = newAV();
            for (i=0; i<=AvFILLp(ori); i++) {
                SV *dir = newSVpvs("-L");
                sv_catsv(dir, AvARRAY(ori)[i]);
                AV_PUSH(tmp, dir);
            }
            AV_PUSH(tmp, modfname);
            file = dl_findfile(aTHX_ tmp, G_SCALAR);
            SvREFCNT_dec_NN(tmp);
        }
    }
    SvREFCNT_dec(modpname);
    /*SvREFCNT_dec(modfname);*/
    if (!file) {
        /* wording similar to error from 'require' */
        Perl_die(aTHX_ "Can't locate loadable object for module %s in @INC (@INC contains: %s)",
                 modulename, av_tostr(aTHX_ GvAV(PL_incgv)));
    } else {
	DLDEBUG(2,PerlIO_printf(Perl_debug_log, "DynaLoader: Found %s\n", SvPVX(file)));
    }
    DLDEBUG(3,PerlIO_printf(Perl_debug_log, "calling dl_load_file: ax=%d, items=%d\n", (int)ax, (int)items));
    if ((items = dl_load_file(aTHX_ ax, file, module, GIMME))) {
        XSRETURN(items);
    } else {
        XSRETURN_UNDEF;
    }
}

XS(XS_DynaLoader_dl_findfile)
{
    dVAR; dXSARGS;
    AV *args;
    SV *file;

    args = av_make(items, SP);
    file = dl_findfile(aTHX_ args, GIMME);
    if (!file)
        XSRETURN_UNDEF;
    SP -= items;
    if (GIMME == G_SCALAR) {
        mXPUSHs(file);
        XSRETURN(1);
    }
    else {
        SSize_t i;
        AV* found = (AV*)file;
        if (AvFILLp(found)>=0) {
            for (i=0; i<=AvFILLp(found); i++) {
                mXPUSHs(AvARRAY(found)[i]);
            }
            XSRETURN(i+1);
        }
        else
            XSRETURN_UNDEF;
    }
}

#ifndef VMS
/* Optional function invoked if DynaLoader sets do_expand.
   Most systems do not require or use this function.
   Some systems may implement it in the dl_*.xs file in which case
   this Perl version should be excluded at build time.

   This function is designed to deal with systems which treat some
   'filenames' in a special way. For example VMS 'Logical Names'
   (something like unix environment variables - but different).
   This function should recognise such names and expand them into
   full file paths.
   Must return undef if file is invalid or file does not exist. */
XS(XS_DynaLoader_dl_expandspec)
{
    dVAR; dXSARGS;
    SV *file;
    char *fn;
    if (items != 1 || !SvPOK(ST(0)))
        Perl_die(aTHX_ "Usage: DynaLoader::dl_expandspec($filename)\n");

    file = ST(0);
    fn = SvPVX(file);
    if (!fn_exists(fn)) {
        DLDEBUG(1,PerlIO_printf(Perl_debug_log, "dl_expandspec(%s) => %s\n",
                                fn, "undef"));
        file = &PL_sv_undef;
    } else {
        DLDEBUG(1,PerlIO_printf(Perl_debug_log, "dl_expandspec(%s) => %s\n",
                                fn, fn));
    }
    ST(0) = file;
    XSRETURN(1);
}
#endif

XS(XS_DynaLoader_dl_find_symbol_anywhere)
{
    dVAR; dXSARGS;
    SV *sym, *dl_find_symbol;
    AV *dl_librefs;
    SSize_t i;
    if (items != 1 || !SvPOK(ST(0)))
        Perl_die(aTHX_ "Usage: DynaLoader::dl_find_symbol_anywhere($symbol)\n");

    sym = ST(0);
    dl_librefs = get_av("DynaLoader::dl_librefs", GV_ADDMULTI);
    dl_find_symbol = (SV*)get_cv("DynaLoader::dl_find_symbol", 0);
    for (i=0; i<=AvFILLp(dl_librefs); i++) {
        SV *libref = AvARRAY(dl_librefs)[i];
	DLDEBUG(2,PerlIO_printf(Perl_debug_log, "dl_find_symbol_anywhere(symbol=%s, libref=%p)\n",
                                SvPVX(sym), libref));
        PUSHMARK(SP);
        XPUSHs(libref);
        XPUSHs(sym);
        PUTBACK;
        items = call_sv(dl_find_symbol, G_SCALAR);
        SPAGAIN;
        if (items == 1 && SvIOK(TOPs)) {
            DLDEBUG(2,PerlIO_printf(Perl_debug_log, " symbolref=0x%lx\n", TOPi));
            SvTEMP_off(TOPs);
            ST(0) = TOPs;
            XSRETURN(1);
        }
    }
    XSRETURN_UNDEF;
}

/* set on linux-android, which does support utf8 pathnames */
#ifdef HAS_LIBNAME_UNIQUE
XS(XS_DynaLoader_mod2fname)
{
    dVAR; dXSARGS;
    AV* parts;
    sonst int so_len = sizeof(dlext);
    const int name_max = 255;
    SV *libname;
    U32 i, len;

    if (items != 1 || !SvROK(ST(0)) || SvTYPE(SvRV(ST(0))) != SVt_PVAV))
        Perl_die(aTHX_ "Usage: mod2fname(\@parts)\n");
    parts = (AV*)SvRV(ST(0));
    libname = newSVpvs("PL_"):
    len = AvFILLp(parts);
    for (i=0; i<len; i++) {
        sv_catsv(libname, AvARRAY(parts)[i]);
        if (i < len-1)
            sv_catpvs(libname, "__");
    }
    if (SvCUR(libname) + so_len_ <= name_max)
        return libname;

    /* It's too darned big, so we need to go strip. We use the same
       algorithm as xsubpp does. First, strip out doubled "__".
       TODO: Check if there are "__" seqs or an ending '_' in utf8 codepoints.
       $libname =~ s/__/_/g; */
    for (i=1; i<SvCUR(libname); i++) {
        char *s = SvPVX(libname);
        if (s[i] == '_' && s[i-1] == '_') {
            Move(s[i], s[i-1], len-i, char);
            ((XPV*)SvANY(libname))->xpv_cur--;
      }
    }
    if (SvCUR(libname) + so_len_ <= name_max)
        return libname;
  /* TODO
    # Strip duplicate letters
    1 while $libname =~ s/(.)\1/\U$1/i;
    return $libname if (length($libname)+$so_len) <= $name_max;
  */

    SvCUR_set(libname, name_max - so_len);
    return libname;
}
#endif

static int
dl_load_file(pTHX_ I32 ax, SV* file, SV *module, int gimme)
{
    dSP;
    dMY_CXT;
    SSize_t i;
    IV nret, flags = 0;
    CV *cv_load_file, *dl_find_symbol;
    SV *bootname, *libref, *boot_symbol_ref, *flagsiv;
    char *modulename = SvPVX(module);
    SV *xs = NULL;
    SV **mark = PL_stack_base + ax - 1;
    dITEMS;

    DLDEBUG(1,PerlIO_printf(Perl_debug_log, "dl_load_file(%d,'%s','%s',%d)\n",
                            (int)ax, SvPVX(file), SvPVX(module), gimme));

    /* utf8 uc slowness only on VMS */
#if defined(VMS) && defined(HAS_VMS_CASE_SENSITIVE_SYMBOLS)
    if (!SvUTF8(file)) {
        char *fn = SvPVX(file);
	for (; *fn; fn++)
#ifdef USE_LOCALE_CTYPE
            *fn = (U8)toUPPER_LC(*fn);
#else
            *fn = (U8)toUPPER(*fn);
#endif
    } else {
        /* call pp_uc */
        SV *savestack = *Perl_stack_sp;
        *Perl_stack_sp = file;
        Perl_pp_uc();
        file = *Perl_stack_sp;
        *Perl_stack_sp = savestack;
    }
#endif

    bootname = newSVpvs("boot_");
    sv_catsv(bootname, module);
    /* Strip non-word chars from the boot name, meant to replace '::' by '__' only.
       This was highly suspicious and locale sensitive code.
       I added a warning, when other chars were replaced also. --rurban */
    {
        int warn_nonword = 0;
        if (!SvUTF8(module)) {
            char *s = SvPVX(bootname);
            for (i=5; i<(IV)SvCUR(bootname); i++) { /* $bootname =~ s/\W/_/g; */
                if (s[i] != '_' && !isWORDCHAR_A(s[i])) {
                    if (s[i] != ':')
                        warn_nonword++;
                    s[i] = '_';
                }
            }
        } else {
            STRLEN len;
            U8* s = (U8*)SvPV_const(bootname, len);
            for (i=5; i<(IV)len;) {
                int l = UTF8SKIP(&s[i]);
                if (s[i] != '_' && !isWORDCHAR_utf8(&s[i])) {
                    if (s[i] != ':')
                        warn_nonword++;
                    if (l > 1) { /* shrink */
                        SvCUR_set(bootname, len-l+1);
                        Move(&s[i+l], &s[i+1], len-i-1, char);
                        len -= (l-1);
                    }
                    s[i++] = '_';
                } else {
                    i += l;
                }
            }
        }
        if (warn_nonword)
            Perl_warner(aTHX_ packWARN(WARN_LOCALE),
                "Invalid XS module boot function name changed to '%s', %d non-word chars",
                SvPVX(bootname), warn_nonword);
    }
    dl_require_symbols = get_av("DynaLoader::dl_require_symbols", GV_ADDMULTI);
    av_store(dl_require_symbols, 0, bootname);
    dl_find_symbol = get_cv("DynaLoader::dl_find_symbol", 0);

    /* TODO .bs support, call flags method */
    flagsiv = newSViv(flags);
    {
        const char *save_last_error = dl_last_error;
	DLDEBUG(2,PerlIO_printf(Perl_debug_log, "DynaLoader: Enter dl_find_symbol with 0, '%s'\n",
                                SvPVX(bootname)));
        SPAGAIN;
        PUSHMARK(SP);
        mXPUSHs(newSViv(0)); /* first try empty library handle, may already be loaded */
        XPUSHs(bootname);
        mXPUSHs(newSViv(1)); /* ignore error, cperl only */
        PUTBACK;
        nret = call_sv((SV*)dl_find_symbol, G_SCALAR);
        SPAGAIN;
        if (nret == 1 && SvIOK(TOPs))
            boot_symbol_ref = POPs;
        else
            boot_symbol_ref = NULL;
	DLDEBUG(3,PerlIO_printf(Perl_debug_log, "DynaLoader: Got loaded boot_symbol_ref => %lx\n",
            boot_symbol_ref ? SvIVX(boot_symbol_ref) : 0));
        if (boot_symbol_ref)
            goto boot;
        dl_last_error = (char*)save_last_error;
    }

    {
	DLDEBUG(3,PerlIO_printf(Perl_debug_log, "DynaLoader: Enter XS dl_load_file with '%s' %ld\n",
                                SvPVX(file), flags));
        cv_load_file = get_cv("DynaLoader::dl_load_file", 0);
        PUSHMARK(SP);
        XPUSHs(file);
        mXPUSHs(flagsiv);
        PUTBACK;
        nret = call_sv((SV*)cv_load_file, G_SCALAR);
        SPAGAIN;
        if (nret == 1 && SvIOK(TOPs))
            libref = POPs;
        else
            libref = NULL;
	DLDEBUG(3,PerlIO_printf(Perl_debug_log, "DynaLoader: Got libref=%lx\n",
                libref ? SvIVX(libref) : 0));
    }
    if (!libref) {
        SaveError(aTHX_ "Can't load '%s' for module %s: %s", file, modulename, dl_last_error);
#ifdef carp_shortmess
        Perl_die(aTHX_ SvPVX_const(carp_shortmess(ax, MY_CXT.x_dl_last_error)));
#else
        /*CLANG_DIAG_IGNORE(-Wformat-security)*/
        /* dl_last_error is secured in SaveError */
        Perl_die(aTHX_ dl_last_error);
        /*CLANG_DIAG_RESTORE*/
#endif
    }
    {
        AV *dl_librefs = get_av("DynaLoader::dl_librefs", GV_ADDMULTI);
        AV_PUSH(dl_librefs, SvREFCNT_inc_simple_NN(libref)); /* record loaded object */
    }
    {
        PUSHMARK(SP);
        PUTBACK;
        nret = call_pv("DynaLoader::dl_undef_symbols", G_ARRAY);
        SPAGAIN;
        if (nret > 0) {
            AV *unresolved = newAV();
            for (i=0; i<nret; i++) {
                SV *sym = POPs;
                if (SvPOK(sym))
                    AV_PUSH(unresolved, sym);
            }
            SaveError(aTHX_ "Undefined symbols present after loading %s: %s\n", SvPVX(file), av_tostr(aTHX_ unresolved));
            Perl_die(aTHX_ dl_last_error);
        }
    }
    {
	DLDEBUG(3,PerlIO_printf(Perl_debug_log, "DynaLoader: Enter dl_find_symbol with %p '%s'\n",
                                libref, SvPVX(bootname)));
        PUSHMARK(SP);
        XPUSHs(libref);
        XPUSHs(bootname);
        PUTBACK;
        nret = call_sv((SV*)dl_find_symbol, G_SCALAR);
        SPAGAIN;
        if (nret == 1 && SvIOK(TOPs))
            boot_symbol_ref = POPs;
        else
            boot_symbol_ref = NULL;
	DLDEBUG(3,PerlIO_printf(Perl_debug_log, "DynaLoader: Got boot_symbol_ref => %lx\n",
                                boot_symbol_ref ? SvIVX(boot_symbol_ref) : 0));
    }
    if (!boot_symbol_ref) {
        Perl_die(aTHX_ "Can't find '%s' symbol in %s\n", SvPVX(bootname), SvPVX(file));
    }
    {
        AV *dl_modules = get_av("DynaLoader::dl_modules", GV_ADDMULTI);
        AV_PUSH(dl_modules, pv_copy(module)); /* record loaded module */
    }

    {
        CV *dl_install_xsub = get_cv("DynaLoader::dl_install_xsub", 0);
        SV *bootstrap = newSVpvs("");
	DLDEBUG(3,PerlIO_printf(Perl_debug_log,
            "DynaLoader: Enter dl_install_xsub with %s::bootstrap %lx %s\n",
            modulename, SvIVX(boot_symbol_ref), SvPVX(file)));
        PUSHMARK(SP);
        sv_catsv(bootstrap, module);
        sv_catpvs(bootstrap, "::bootstrap");
        XPUSHs(bootstrap);
        XPUSHs(boot_symbol_ref);
        XPUSHs(file);
        PUTBACK;
        nret = call_sv((SV*)dl_install_xsub, G_SCALAR);
        SPAGAIN;
        if (nret == 1 && SvROK(TOPs))
            xs = POPs;                /* cannot return NULL */
	DLDEBUG(3,PerlIO_printf(Perl_debug_log, "DynaLoader: Got %s::bootstrap => CV<%p>\n",
                                modulename, xs));
    }
    {
        AV *dl_shared_objects = get_av("DynaLoader::dl_shared_objects", GV_ADDMULTI);
        AV_PUSH(dl_shared_objects, SvREFCNT_inc_simple_NN(file)); /* record loaded files */
    }

   boot:
    {
        /* Note: the 1st arg must be the package name,
           the opt. 2nd arg the VERSION */
	DLDEBUG(3,PerlIO_printf(Perl_debug_log,
                "DynaLoader: Enter &%s::bootstrap CV<%p> with %d args\n",
                                modulename, xs, (int)items));
        PUSHMARK(MARK);
        PL_stack_sp = MARK + items;
        assert(items > 0 ? SvPOK(*(MARK+1)) : 1);
        assert(items > 1 ? SvOKp(*(MARK+2)) : 1);
        return call_sv(xs, gimme);
    }
    return 0;
}

/* Read L<DynaLoader> for detailed information.
 * This function does not automatically consider the architecture
 * or the perl library auto directories.
 * May return NULL if not found.
 *
 * Warning: Note that the old code traditionally will also find static libs (.a)
 * and not dynaloadable libs (.dylib).
 * No idea how to sanitize that and where it is used or should be used. ExtUtils::Embed?
 * We might need to use a strict flag.
 */
static SV * dl_findfile(pTHX_ AV* args, int gimme) {
    dMY_CXT;
    AV* dirs;   /* which directories to search */
    AV *found;  /* full paths to real files we have found */
    SSize_t i, j;
    DLDEBUG(1,PerlIO_printf(Perl_debug_log, "dl_findfile(%s) %d\n",
                           av_tostr(aTHX_ args), gimme));
    found = newAV();
    dirs  = newAV();

    /* accumulate directories but process files as they appear */
    for (i=0; i<=AvFILLp(args); i++) {
        SV *file = AvARRAY(args)[i];
        char *fn = SvPVX(file);
        SSize_t dirsize, lsize;
        AV *names;
        DLDEBUG(3,PerlIO_printf(Perl_debug_log, "  find %s\n", fn));
        /* Special fast case: full filepath may require no search */
#ifndef VMS
        if (strchr(fn, '/')) {
	    if (fn_exists(fn)) {
                if (gimme != G_ARRAY) {
                    DLDEBUG(1,PerlIO_printf(Perl_debug_log, "dl_findfile found (%s)\n",
                                fn));
                    return file;
                }
                AV_PUSH(found, file);
                DLDEBUG(3,PerlIO_printf(Perl_debug_log, "  found %s\n", fn));
            }
        }
#else
        /* Originally: if (m%[:>/\]]% && -f $_) but stat'ing looks cheaper than searching for
           those chars. */
	if (fn_exists(fn)) {
            PUSHMARK(SP);
            PUTBACK;
            XPUSHs(file);
            call_pv("VMS::Filespec::vmsify", G_SCALAR);
#if DEBUGGING
            SPAGAIN;
            file = TOPs;
            PUTBACK;
#endif
            call_pv("DynaLoader::dl_expandspec", G_SCALAR);
            SPAGAIN;
            file = POPs;
            if (gimme != G_ARRAY) {
                SvREFCNT_dec_NN(found);
                SvREFCNT_dec_NN(dirs);
                DLDEBUG(1,PerlIO_printf(Perl_debug_log, "dl_findfile found (%s)\n",
                            fn));
                return file;
            }
            AV_PUSH(found, file);
            DLDEBUG(3,PerlIO_printf(Perl_debug_log, "  found %s\n", fn));
        }
#endif
        /* Deal with directories first:
           Using a -L prefix is the preferred option (faster and more robust)
           if (m:^-L:) { s/^-L//; push(@dirs, $_); next; } */
        if (fn[0] == '-' && fn[1] == 'L') {
	    if (dir_exists(&fn[2])) {
                SV *tmp = newSVpvn_flags(&fn[2], SvCUR(file)-2, SvUTF8(file));
                AV_PUSH(dirs, tmp);
                DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +dirs %s\n", &fn[2]));
            }
            continue;
        }
        /*  Otherwise we try to try to spot directories by a heuristic
            (this is a more complicated issue than it first appears)
            if (m:/: && -d $_) {   push(@dirs, $_); next; } */
        if (strchr(fn, '/')) {
	    if (dir_exists(fn)) {
                AV_PUSH(dirs, pv_copy(file));
                DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +dirs %s\n", fn));
                continue;
            }
        }
#ifdef VMS
        /* VMS: we may be using native VMS directory syntax instead of
           Unix emulation, so check this as well. We've already stat'ed this string.
           if (/[:>\]]/ && -d $_) {   push(@dirs, $_); next; } */
        if (dir_exists(fn)) {
            AV_PUSH(dirs, pv_copy(file));
            DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +dirs %s\n", fn));
            continue;
        }
#endif
        /* Now we have either a single local subdir or a file */
        names = newAV();
        if (fn[0] == '-' && fn[1] == 'l') {
            SV *name = newSVpvs("lib");
            SV *copy;
            sv_catpv(name, &fn[2]);
            copy = newSVpvn(SvPVX(name), SvCUR(name));
#ifdef PERL_DARWIN
            sv_catpv(name, DLEXT);
#else
            sv_catpv(name, DLSO);
#endif
            AV_PUSH(names, name);
            DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +names %s\n", SvPVX(name)));
            /* .a is very questionable and should be avoided (only useful for Extutils::Embed) */
            sv_catpvs(copy, ".a");
            AV_PUSH(names, copy);
            DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +names %s\n", SvPVX(copy)));
        }
        else { /* Umm, a bare name. Try various alternatives */
               /* these should be ordered with the most likely first */
            SV *name = pv_copy(file);
            char *fn = SvPVX(file);
             /* push(@names,"$_.$dl_dlext")    unless m/\.$dl_dlext$/o; */
            if (!strstr(fn, DLEXT)) {
                sv_catpv(name, DLEXT);
                AV_PUSH(names, name);
                DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +names %s\n", SvPVX(name)));
                name = newSVpvn(fn, SvCUR(file));
            }
#if defined(PERL_DARWIN) && !defined(DL_SO_EQ_EXT)
            /* .dylib is very questionable and should be avoided
               (only useful for Extutils::Embed, with a non-dl flag) */
            /* push(@names,"$_.$dl_so")     unless m/\.$dl_so$/o; */
            if (!strstr(fn, DLSO)) {
                sv_catpv(name, DLSO);
                AV_PUSH(names, name);
                DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +names %s\n", SvPVX(name)));
                name = newSVpvn(fn, SvCUR(file));
            }
#endif
#ifdef __CYGWIN__
            if (!strchr(fn, '/')) { /* push(@names,"cyg$_.$dl_so")  unless m:/:; */
                name = newSVpvs("cyg");
                sv_catsv(name, file);
                sv_catpv(name, DLEXT);
                AV_PUSH(names, name);
                DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +names %s\n", SvPVX(name)));
                name = newSVpvn(fn, SvCUR(file));
            }
#endif
#ifndef PERL_DARWIN
            if (!strchr(fn, '/')) { /* push(@names,"lib$_.$dl_so")  unless m:/:; */
                name = newSVpvs("lib");
                sv_catsv(name, file);
                sv_catpv(name, DLSO);
                AV_PUSH(names, name);
                DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +names %s\n", SvPVX(name)));
                name = newSVpvn(fn, SvCUR(file));
            }
#endif
            AV_PUSH(names, name);
            DLDEBUG(3,PerlIO_printf(Perl_debug_log, " +names %s\n", SvPVX(name)));
        }
#ifdef __SYMBIAN32__
        if (fn[1] == ':'
           && ((fn[0] >= 'a' && fn[0] <= 'z')
            || (fn[0] >= 'A' && fn[0] <= 'Z'))) {
            SSize_t j;
            char drive[2];
            drive[0] = fn[0]; drive[1] = fn[1]; drive[2] = '\0';
            for (j=0; j<=AvFILLp(dirs); j++) {
                SV *newdir = newSVpvn(drive, 2);
                sv_catsv(newdir, AvARRAY(dirs)[j]);
                AvARRAY(dirs)[j] = newdir;
            }
            for (j=0; j<=AvFILLp(dl_library_path); j++) {
                SV *newdir = newSVpvn(drive, 2);
                sv_catsv(newdir, AvARRAY(dl_library_path)[j]);
                AvARRAY(dl_library_path)[j] = newdir;
            }
        }
#endif
        dirsize = AvFILLp(dirs);
        lsize = AvFILLp(dl_library_path);
        if (dirsize + lsize > -1) /* if one of them is not empty */
          /* loop both arrays in one loop. -1 means empty */
          for (j=0; j<=(dirsize>=0?dirsize:0)+(lsize>=0?lsize:0); j++) {
            SSize_t k;
            SV *dir = (dirsize >= 0 && j <= dirsize)
                      ? AvARRAY(dirs)[j]
                      : AvARRAY(dl_library_path)[j-dirsize-1];
            char *dirn = SvPVX(dir);
	    if (!dir_exists(dirn)) {
                DLDEBUG(3,PerlIO_printf(Perl_debug_log, " skip %s\n", dirn));
                continue;
            }
#ifdef VMS
            {
                dSP;
                PUSHMARK(SP);
                PUTBACK;
                XPUSHs(dir);
                call_pv("VMS::Filespec::unixpath", G_SCALAR);
                SPAGAIN;
                dir = POPs;
                SvCUR_set(dir, SvCUR(dir)-1);
            }
#endif
            for (k=0; k<=AvFILLp(names); k++) {
                SV* name = AvARRAY(names)[k];
                SV* file = newSVpv(dirn, SvCUR(dir));
#ifdef __SYMBIAN32__
                sv_catpvs(file,"\\");
#else
                sv_catpvs(file, "/");
#endif
                sv_catsv(file, name);
                DLDEBUG(1,PerlIO_printf(Perl_debug_log, " checking in %s for %s\n",
                                dirn, SvPVX(name)));
                if (SvIVX(do_expand)) {
                    dSP;
                    PUSHMARK(SP);
                    PUTBACK;
                    XPUSHs(file);
                    call_pv("DynaLoader::dl_expandspec", G_SCALAR);
                    SPAGAIN;
                    file = POPs;
                    if (file != &PL_sv_undef) {
                        if (gimme != G_ARRAY) {
                            SvREFCNT_dec_NN(found);
                            SvREFCNT_dec_NN(dirs);
                            SvREFCNT_dec_NN(names);
                            DLDEBUG(1,PerlIO_printf(Perl_debug_log, "dl_findfile found (%s)\n",
                                SvPVX(file)));
                            return file;
                        } else {
                            AV_PUSH(found, file);
                            break;
                        }
                    }
                } else {
	            if (fn_exists(SvPVX(file))) {
                        if (gimme != G_ARRAY) {
                            SvREFCNT_dec_NN(found);
                            SvREFCNT_dec_NN(dirs);
                            SvREFCNT_dec_NN(names);
                            DLDEBUG(1,PerlIO_printf(Perl_debug_log, "dl_findfile found (%s)\n",
                                        SvPVX(file)));
                            return file;
                        } else {
                            AV_PUSH(found, file);
                            break;
                        }
                    }
                }
            }
        }
        SvREFCNT_dec_NN(names);
    }
#ifdef DEBUGGING
    if (dl_debug) {
        for (i=0; i<=AvFILLp(dirs); i++) {
            const char* fn = SvPVX(AvARRAY(dirs)[i]);
	    if (!dir_exists(fn)) {
                PerlIO_printf(Perl_debug_log, " dl_findfile ignored non-existent directory: %s\n",
                                fn);
            }
        }
    }
#endif
    SvREFCNT_dec_NN(dirs);
    if (gimme != G_ARRAY) {
        DLDEBUG(1,PerlIO_printf(Perl_debug_log, "dl_findfile found (%s)\n",
                                av_tostr(aTHX_ found)));
        return AvFILLp(found)>=0 ? AvARRAY(found)[0] : NULL;
    }
    return (SV*)found;
}

static char * av_tostr(pTHX_ AV *args) {
    SSize_t i;
    SV *pv = newSVpvs("");
    for (i=0; i<=AvFILLp(args); i++) {
        SV **sv = av_fetch(args, i, 0);
        if (*sv && SvPOK(*sv)) {
            sv_catsv(pv, *sv);
            sv_catpvs(pv, " ");
        }
    }
    if (SvCUR(pv)) {
        STRLEN cur = ((XPV*)SvANY(pv))->xpv_cur--;
        SvPVX_mutable(pv)[cur-1] = '\0';
    }
    return SvPVX(pv);
}

#include "XSLoader.c"
