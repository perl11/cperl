/*    pp_type.c
 *
 *    Copyright (C) 2015 by cPanel Inc
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 *  This file contains optimized type variants of general pp functions,
 *  see also regen/opcodes.  The types starting with an uppercase
 *  letter are "boxed", a SV typed as Int, UInt, Str or Num.
 *
 *  The native unboxed types starting with lowercase are special
 *  values on the stack and pad, and can only be used within certain
 *  op basic blocks, i.e. expressions, not crossing statement
 *  boundaries, i.e. nextstate. The compiler has to ensure that no
 *  unboxed value remains on the stack with non-local exits and at
 *  function call boundaries. We cannot yet handle native types across
 *  user code signatures, enterxssub XS and entersub PP.
 *  On the stack we use raw unboxed values, on the pad we need to use
 *  PADTMP like SV containers without a body, marked as SVf_NATIVE.
 */

#include "EXTERN.h"
#define PERL_IN_PP_TYPE_C
#include "perl.h"

#ifdef PERL_NATIVE_TYPES

#include "keywords.h"
#include "reentr.h"
#include "regcharclass.h"

/* box and unbox */

/* Replace the raw IV with a SvIV, needed on the stack
   for ops not able to handle a raw value. */
PPt(pp_box_int, "(:int):Int")
{
    dSP;
    TOPs = newSViv((IV)TOPs);
    return NORMAL;
}
/* box uint to UV */
PPt(pp_box_uint, "(:uint):UInt")
{
    dSP;
    TOPs = newSVuv((UV)TOPs);
    return NORMAL;
}
/* box double to NV if IVSIZE==NVSIZE */
PPt(pp_box_num, "(:num):Num")
{
    /* The compiler is allowed to use native dbl on 64 bit,
       or NV = float and 32 bit */
#if IVSIZE == NVSIZE
    dSP;
    TOPs = newSVnv(PTR2NV(TOPs));
#else
    assert(IVSIZE == NVSIZE);
#endif
    return NORMAL;
}
/* box ASCIIZ string to PV */
PPt(pp_box_str, "(:str):Str")
{
    dSP;
    TOPs = newSVpv((const char *const)TOPs, 0);
    return NORMAL;
}
/* unbox IV to int */
PPt(pp_unbox_int, "(:Int):int")
{
    dSP;
    TOPs = (SV*)SvIVX(TOPs);
    return NORMAL;
}
/* unbox UV to uint */
PPt(pp_unbox_uint, "(:Int):uint")
{
    dSP;
    TOPs = (SV*)SvUVX(TOPs);
    return NORMAL;
}
/* unbox PV to ASCIIZ */
PPt(pp_unbox_str, "(:Str):str")
{
    dSP;
    TOPs = (SV*)SvPVX(TOPs);
    return NORMAL;
}
/* unbox NV to double if IVSIZE==NVSIZE */
PPt(pp_unbox_num, "(:Num):num")
{
#if IVSIZE == NVSIZE
    dSP;
    union { NV n; SV* sv; } num;
    num.n = SvNVX(TOPs);
    TOPs = num.sv;
#else
    assert(IVSIZE == NVSIZE);
#endif
    return NORMAL;
}

/* unboxed left bitshift (<<)  ck_bitop	pfiT2	I I */
/* unboxed right bitshift (>>) ck_bitop	pfiT2	I I */
/* unboxed preincrement (++)  ck_lfun	b1	I */
/* unboxed predecrement (--)  ck_lfun	b1	I */
/* unboxed postincrement (++) ck_lfun	bt1	I */
/* unboxed postdecrement (--) ck_lfun	bt1	I */

#define UNBOXED_UINT_BINOP_T(name, op)          \
PPt(pp_uint_##name, "(:uint,:int):uint")        \
{                                               \
    dSP; dATARGET;                              \
    UV uv = PTR2UV(TOPs);                       \
    sp--;                                       \
    TARG = (PL_op->op_private & OPpBOXRET)      \
        || !(PL_op->op_flags & OPf_STACKED)     \
        ? newSVuv(uv op PTR2IV(TOPs))           \
        : INT2PTR(SV*, uv op PTR2IV(TOPs));     \
    SETs(TARG);                                 \
    RETURN;                                     \
}
#define UNBOXED_UINT_UNOP_t(name, op)           \
PPt(pp_uint_##name, "(:uint):uint")             \
{                                               \
    dSP; dTARGET;                               \
    IV iv = PTR2IV(TOPs);                       \
    TARG = (PL_op->op_private & OPpBOXRET)      \
        ? newSViv(op(iv))                       \
        : INT2PTR(SV*, op(iv));                 \
    SETs(TARG);                                 \
    RETURN;                                     \
}
#define UNBOXED_INT_UNOP_t(name, op)            \
PPt(pp_##name, "(:int):int")                    \
{                                               \
    dSP; dTARGET;                               \
    IV iv = PTR2IV(TOPs);                       \
    TARG = (PL_op->op_private & OPpBOXRET)      \
        ? newSViv(op(iv))                       \
        : INT2PTR(SV*, (intptr_t)(op(iv)));     \
    SETs(TARG);                                 \
    RETURN;                                     \
}
#define UNBOXED_INT_UNOP_T(name, op)            \
PPt(pp_##name, "(:int):int")                    \
{                                               \
    dSP; dATARGET;                              \
    IV iv = PTR2IV(TOPs);                       \
    TARG = (PL_op->op_private & OPpBOXRET)      \
        || !(PL_op->op_flags & OPf_STACKED)     \
        ? newSViv(op(iv))                       \
        : INT2PTR(SV*, (intptr_t)(op(iv)));     \
    SETs(TARG);                                 \
    RETURN;                                     \
}
#define UNBOXED_INT_BINOP_T(name, op)           \
PPt(pp_int_##name, "(:int,:int):int")           \
{                                               \
    dSP; dATARGET;                              \
    IV iv = PTR2IV(TOPs);                       \
    sp--;                                       \
    TARG = (PL_op->op_private & OPpBOXRET)      \
        || !(PL_op->op_flags & OPf_STACKED)     \
        ? newSViv(iv op PTR2IV(TOPs))           \
        : INT2PTR(SV*, (intptr_t)(iv op PTR2IV(TOPs))); \
    SETs(TARG);                                 \
    RETURN;                                     \
}
#define UNBOXED_INT_BINOP(name, op)             \
PPt(pp_int_##name, "(:int,:int):int")           \
{                                               \
    dSP;                                        \
    IV iv = PTR2IV(TOPs);                       \
    sp--;                                       \
    TOPs = (PL_op->op_private & OPpBOXRET)      \
        ? newSViv(iv op PTR2IV(TOPs))           \
        : INT2PTR(SV*, (intptr_t)(iv op PTR2IV(TOPs))); \
    RETURN;                                     \
}
#define UNBOXED_INT_UNOP(name, op)              \
PPt(pp_##name, "(:int):int")                    \
{                                               \
    dSP;                                        \
    IV iv = PTR2IV(TOPs);                       \
    TOPs = (PL_op->op_private & OPpBOXRET)      \
        ? newSViv(op(iv))                       \
        : INT2PTR(SV*, (intptr_t)(op(iv)));     \
    return NORMAL;                              \
}

/* unboxed left bitshift (<<)  ck_bitop	pfT2	U I */
UNBOXED_UINT_BINOP_T(right_shift, >>)
/* unboxed right bitshift (>>) ck_bitop	pfT2	U I */
UNBOXED_UINT_BINOP_T(left_shift, <<)
/* unboxed 1's complement (~) 	ck_bitop pft1	U */
UNBOXED_UINT_UNOP_t(complement, ~)

PERL_STATIC_INLINE
UV S_upow(UV base, IV exp) {
    UV result = 1;
    if (base == 2) return 2 << exp;
    while (exp) {
        if (exp & 1)
            result *= base;
        exp >>= 1;
        base *= base;
    }
    return result;    
}
/* unboxed int exp (**)	ck_null		pfT2	I I	"(:uint,:int):uint" */
PPt(pp_uint_pow, "(:uint,:int):uint")
{
    dSP; dATARGET;
    UV uv = PTR2UV(TOPs);
    sp--;
    TARG = (PL_op->op_private & OPpBOXRET)
        || !(PL_op->op_flags & OPf_STACKED)
        ? newSVuv(S_upow(uv, PTR2IV(TOPs)))
        : INT2PTR(SV*, S_upow(uv, PTR2IV(TOPs)));
    SETs(TARG);
    RETURN;
}

/* unboxed addition (+)		ck_null	pbfT2	I I */
/* with TARGLEX support */
UNBOXED_INT_BINOP_T(add, +)
UNBOXED_INT_BINOP_T(subtract, -)
UNBOXED_INT_BINOP_T(multiply, *)
UNBOXED_INT_BINOP_T(divide, /)
UNBOXED_INT_BINOP_T(modulo, %)
/* without TARGLEX support, stack only */
UNBOXED_INT_BINOP(lt, <)
UNBOXED_INT_BINOP(le, <=)
UNBOXED_INT_BINOP(gt, >)
UNBOXED_INT_BINOP(ge, >=)
UNBOXED_INT_BINOP(eq, ==)
UNBOXED_INT_BINOP(ne, !=)

/* here we need the int_ prefix, because of the reserved keyword not */
/* unboxed negation (-)		ck_null	 pif1	I */
UNBOXED_INT_UNOP_t(int_negate, -)
UNBOXED_INT_UNOP_t(int_postdec, --)
UNBOXED_INT_UNOP_t(int_postinc, ++)
UNBOXED_INT_UNOP_T(int_abs, abs)
UNBOXED_INT_UNOP(int_not, !)
UNBOXED_INT_UNOP(int_predec, --)
UNBOXED_INT_UNOP(int_preinc, ++)

#if IVSIZE == NVSIZE
/* without t nor T TARGLEX */
#define UNBOXED_NUM_BINOP(name, op)             \
PPt(pp_num_##name, "(:num,:num):num")           \
{                                               \
    dSP;                                        \
    union { NV n; SV* sv; } num1, num2;         \
    num1.sv = TOPs;                             \
    sp--;                                       \
    num2.sv = TOPs;                             \
    num1.n = num1.n op num2.n;                  \
    TOPs = (PL_op->op_private & OPpBOXRET)      \
        ? newSVnv(num1.n)                       \
        : num1.sv;                              \
    RETURN;                                     \
}
/* with TARGLEX */
#define UNBOXED_NUM_BINOP_T(name, op)           \
PPt(pp_num_##name, "(:num,:num):num")           \
{                                               \
    dSP; dATARGET;                              \
    union { NV n; SV* sv; } num1, num2;         \
    num1.sv = TOPs;                             \
    sp--;                                       \
    num2.sv = TOPs;                             \
    num1.n = num1.n op num2.n;                  \
    TARG = (PL_op->op_private & OPpBOXRET)      \
        || !(PL_op->op_flags & OPf_STACKED)     \
        ? newSVnv(num1.n)                       \
        : num1.sv;                              \
    (void)POPs;                                 \
    SETs(TARG);                                 \
    RETURN;                                     \
}
#define UNBOXED_NUM_BINFUNC_T(name, func)       \
PPt(pp_num_##name, "(:num,:num):num")           \
{                                               \
    dSP; dATARGET;                              \
    union { NV n; SV* sv; } num1, num2;         \
    num1.sv = TOPs;                             \
    sp--;                                       \
    num2.sv = TOPs;                             \
    num1.n = func(num1.n, num2.n);              \
    TARG = (PL_op->op_private & OPpBOXRET)      \
        || !(PL_op->op_flags & OPf_STACKED)     \
        ? newSVnv(num1.n)                       \
        : num1.sv;                              \
    (void)POPs;                                 \
    SETs(TARG);                                 \
    RETURN;                                     \
}
#define UNBOXED_NUM_UNOP_T(name, op)            \
PPt(pp_num_##name, "(:num):num")                \
{                                               \
    dSP; dATARGET;                              \
    union { NV n; SV* sv; } num;                \
    num.sv = TOPs;                              \
    num.n = Perl_##op(num.n);                   \
    TARG = (PL_op->op_private & OPpBOXRET)      \
        || !(PL_op->op_flags & OPf_STACKED)     \
        ? newSVnv(num.n)                        \
        : num.sv;                               \
    (void)POPs;                                 \
    SETs(TARG);                                 \
    RETURN;                                     \
}
#else
#define UNBOXED_NUM_BINOP_T(name, op)           \
PPt(pp_num_##name, "(:num,:num):num") {         \
    assert(IVSIZE == NVSIZE);                   \
    return NORMAL;                              \
}
#define UNBOXED_NUM_BINFUNC_T(name, op)         \
PPt(pp_num_##name, "(:num,:num):num") {         \
    assert(IVSIZE == NVSIZE);                   \
    return NORMAL;                              \
}
#define UNBOXED_NUM_UNOP_T(name, op)            \
PPt(pp_num_##name, "(:num):num") {              \
    assert(IVSIZE == NVSIZE);                   \
    return NORMAL;                              \
}
#endif

/* all with TARGLEX/OPpTARGET_MY support */
UNBOXED_NUM_BINOP_T(add, +)
UNBOXED_NUM_BINOP_T(subtract, -)
UNBOXED_NUM_BINOP_T(multiply, *)
UNBOXED_NUM_BINOP_T(divide, /)
UNBOXED_NUM_BINFUNC_T(atan2, Perl_atan2)
UNBOXED_NUM_BINFUNC_T(pow, Perl_pow)
UNBOXED_NUM_UNOP_T(sin, sin)
UNBOXED_NUM_UNOP_T(cos, cos)
UNBOXED_NUM_UNOP_T(exp, exp)
UNBOXED_NUM_UNOP_T(log, log)
UNBOXED_NUM_UNOP_T(sqrt, sqrt)

/* native str ops for now disabled. maybe use HEKs for them.
   strcat: it might be too hard for the optimizer to prove
   that the first arg is big enough. and with only one remaining op it
   makes not much sense */
#if 0

/* unboxed concatenation   ck_concat	pzfsT2	Z Z
   buffer needs to be large enough! only with sized Str. */
PPt(pp_str_concat, "(:str,:str):str")
{
    dSP;
    char * first = (char *)TOPs;
    sp--;
    TOPs = (SV*)strcat(first, (char *)TOPs);
    RETURN;
}
/* unboxed length		ck_length	fsTu%	Z */
PPt(pp_str_length, "(:str):int")
{
    dSP;
    TOPs = (SV*)strlen((char *)TOPs);
    return NORMAL;
}

/* str hashes */

/* unboxed hash element	ck_null		s2	H Z */
PPt(pp_str_helem, "(:Hash(:Scalar),:str):Scalar")
{
    die("NYI");
}
/* unboxed delete	ck_delete	%	H Z */
PPt(pp_str_delete, "(:Hash(:Scalar),:str):Void")
{
    die("NYI");
}
/* unboxed exists	ck_exists	s%	H Z */
PPt(pp_str_exists, "(:Hash(:Scalar),:str):Bool")
{
    die("NYI");
}
#endif


/* for all native types. 
   Note: the type should really be :native, as just the unboxed value is copied.
     typedef :native :int|:uint|:str|:num;
     "(:native,:native):native"
*/

PPt(pp_int_sassign, "(:int,:int):int")
{
    dSP;
    /* sassign keeps its args in the optree traditionally backwards.
       So we pop them differently.
    */
    SV* left = POPs; SV* right = TOPs;
#if 0
    /* no typed {or,and,dor}assign yet */
    if (PL_op->op_private & OPpASSIGN_BACKWARDS) { /* {or,and,dor}assign */
	const SV* temp = left;
	left = right; right = temp;
    }
#endif
    /* we can only assign to *_padsv here, not to const and not to gvsv.
       later to *_aelem */
    if (LIKELY(SvNATIVE(left)))
        left->sv_u.svu_iv = (IV)right; /* fill the curpad */
    SETs(right); /* and the stack */
    RETURN;
}

/* needs a different side-effect, push the native value onto the stack */
PPt(pp_int_padsv, "():int")
{
    dSP;
    EXTEND(SP, 1);
    {
        dTARG;
	OP * const op = PL_op;
	/* access PL_curpad once */
	SV ** const padentry = &(PAD_SVl(op->op_targ));
        assert(PL_op->op_type != OP_NUM_PADSV || IVSIZE == NVSIZE);
	{
	    TARG = *padentry;
            assert(SvNATIVE(TARG));
            if (!(op->op_flags & OPf_MOD || op->op_private & OPpBOXRET))
                TARG = (SV*)(TARG->sv_u.svu_iv);
	    PUSHs(TARG);
	    PUTBACK; /* no pop/push after this, TOPs ok */
	}
	if (op->op_flags & OPf_MOD) {
	    if (op->op_private & OPpLVAL_INTRO)
		if (!(op->op_private & OPpPAD_STATE))
		    save_clearsv(padentry);
	    if (op->op_private & OPpDEREF)
		TOPs = vivify_ref(*padentry, op->op_private & OPpDEREF);
	}
	return op->op_next;
    }
}

/* same as pp_num_aelem_u and pp_str_aelem_u.
   without bounds check */
PPt(pp_int_aelem_u, "(:Array(:int),:int):int")
{
    dSP;
    SV *sv = AvARRAY((AV*)TOPs)[(IV)TOPm1s];
    sp--;
    TOPs = sv;
    RETURN;
}

/* same as pp_num_aelem and pp_str_aelem.
   with bounds check */
PPt(pp_int_aelem, "(:Array(:int),:int):int")
{
    dVAR; dSP;
    SV** svp = NULL;

    AV * const av = MUTABLE_AV(POPs);
    IV index = (IV)TOPm1s;
    if (index >= 0 && index < AvFILLp(av))
        svp = &AvARRAY(av)[index];
    else if (index < 0 && index > -AvFILLp(av) ) { /* @a[20] just declares the len not the size */
        svp = &AvARRAY(av)[AvFILL(av) + index];
    }

    if (UNLIKELY(!svp)) /* unassigned elem or fall through for > AvFILL */
        DIE(aTHX_ PL_no_aelem, index);

    TOPs = *svp;
    RETURN;
}

#endif /* PERL_NATIVE_TYPES */

/* No magic allowed, but with bounds check,
   negative i, lval, defer allowed */
PPt(pp_i_aelem, "(:Array(:Int),:Int):Int")
{
    dSP;
    SV** svp;
    SV* const elemsv = POPs;
    IV elem = SvIV(elemsv);
    AV *const av = MUTABLE_AV(POPs);
    const U32 lval = PL_op->op_flags & OPf_MOD || LVRET;
    const U32 defer = PL_op->op_private & OPpLVAL_DEFER;
    SV *sv;

    if (UNLIKELY(SvROK(elemsv) && ckWARN(WARN_MISC)))
	Perl_warner(aTHX_ packWARN(WARN_MISC),
		    "Use of reference \"%" SVf "\" as array index",
		    SVfARG(elemsv));
    if (UNLIKELY(SvTYPE(av) != SVt_PVAV))
	RETPUSHUNDEF;

    svp = av_fetch(av, elem, lval && !defer);
    if (lval) {
#ifdef PERL_MALLOC_WRAP
	 if (SvUOK(elemsv)) {
	      const UV uv = SvUV(elemsv);
	      elem = uv > IV_MAX ? IV_MAX : uv;
	 }
	 if (elem > 0) {
	      static const char oom_array_extend[] =
		"Out of memory during array extend"; /* Duplicated in av.c */
	      MEM_WRAP_CHECK_1(elem,SV*,oom_array_extend);
	 }
#endif
	if (!svp || !*svp) {
	    IV len;
	    if (!defer)
		DIE(aTHX_ PL_no_aelem, elem);
	    len = av_tindex(av);
	    mPUSHs(newSVavdefelem(av,
	    /* Resolve a negative index now, unless it points before the
	       beginning of the array, in which case record it for error
	       reporting in magic_setdefelem. */
		elem < 0 && len + elem >= 0 ? len + elem : elem,
		1));
	    RETURN;
	}
        if (PL_op->op_private & OPpDEREF) {
	    PUSHs(vivify_ref(*svp, PL_op->op_private & OPpDEREF));
	    RETURN;
	}
    }
    sv = (svp ? *svp : UNDEF);
    PUSHs(sv);
    RETURN;
}

/* pp_i_aelem_u, "(:Array(:Int),:Int):Int")
   same as pp_aelem_u */

/* n_aelem		num array element  ck_null	s2	A S */
/* same as pp_i_aelem */
/* this version below is different than i_aelem, for bounds checked indices already.
   no negative index, lvalue, no out of bounds, no defer
PPt(pp_n_aelem, "(:Array(:Num),:Int):Num")
{
    dSP;
    SV *sv = AvARRAY((AV*)TOPs)[SvIVX(TOPm1s)];
    sp--;
    TOPs = sv;
    RETURN;
}
*/
/* unboxed	num array element ck_null	s2	A I */
/* same as int_aelem
PPt(pp_num_aelem, "(:Array(:num),:int):num")
{
    dSP;
    SV *sv = AvARRAY((AV*)TOPs)[(IV)TOPm1s];
    sp--;
    TOPs = sv;
    RETURN;
}
*/
/* str array element  ck_null	s2	A S */
/* same as pp_i_aelem
PPt(pp_s_aelem, "(:Array(:Str),:Int):Str")
{
    dSP;
    SV *sv = AvARRAY((AV*)TOPs)[SvIVX(TOPm1s)];
    sp--;
    TOPs = sv;
    RETURN;
}
*/
/* unboxed	str array element ck_null	z2	A Z */
/* same as int_aelem
PPt(pp_str_aelem, "(:Array(:str),:int):str")
{
    dSP;
    SV *sv = AvARRAY((AV*)TOPs)[(IV)TOPm1s];
    sp--;
    TOPs = sv;
    RETURN;
}
*/

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
