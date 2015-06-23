/*    pp_type.c
 *
 *    Copyright (C) 2015 by cPanel Inc
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

/* This file contains optimized type variants of general pp functions,
   see also regen/opcodes.  The types starting with an uppercase
   letter are "boxed", a SV typed as Int or Str or Num.  The native
   unboxed types starting with lowercase are special values on the
   stack, and can only be used within certain op basic blocks. The
   compiler has to ensure that no unboxed value remains on the stack
   with non-local exits, and at function call boundaries.
 */

#include "EXTERN.h"
#define PERL_IN_PP_TYPE_C
#include "perl.h"
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
PPt(pp_uint_lshift, "(:int,:uint):uint")
{
    dSP;
    UV uv = PTR2UV(TOPs);
    sp--;
    TOPs = INT2PTR(SV*, uv << PTR2IV(TOPs));
    RETURN;
}
/* unboxed right bitshift (>>) ck_bitop	pfiT2	I I */
PPt(pp_uint_rshift, "(:int,:uint):uint")
{
    dSP;
    UV uv = PTR2UV(TOPs);
    sp--;
    TOPs = INT2PTR(SV*, uv >> PTR2IV(TOPs));
    RETURN;
}
/* unboxed preincrement (++)  ck_lfun	is1	I */
/* PPt(pp_int_preinc, "(:int):int")
{
    dSP;
    IV iv = PTR2IV(TOPs);
    TOPs = INT2PTR(SV*, ++iv);
    RETURN;
} */
/* unboxed predecrement (--)  ck_lfun	is1	I */
/* PPt(pp_int_predec, "(:int):int")
{
    dSP;
    IV iv = PTR2IV(TOPs);
    TOPs = INT2PTR(SV*, --iv);
    RETURN;
} */
/* unboxed postincrement (++) ck_lfun	is1	I */
/* same as pp_int_preinc */
/* unboxed postdecrement (--) ck_lfun	is1	I */
/* same as pp_int_predec */

#define UNBOXED_INT_BINOP(name, op)             \
PPt(pp_int_##name, "(:int,:int):int")           \
{                                               \
    dSP;                                        \
    IV iv = PTR2IV(TOPs);                       \
    sp--;                                       \
    TOPs = INT2PTR(SV*, iv op PTR2IV(TOPs));    \
    RETURN;                                     \
}
#define UNBOXED_INT_UNOP(name, op)              \
PPt(pp_##name, "(:int):int")                    \
{                                               \
    dSP;                                        \
    IV iv = PTR2IV(TOPs);                       \
    TOPs = INT2PTR(SV*, op(iv));                \
    return NORMAL;                              \
}

/* unboxed addition (+)		ck_null		pif2	I I */
UNBOXED_INT_BINOP(add, +)
/* unboxed subtraction (-)	ck_null		pif2	I I */
UNBOXED_INT_BINOP(subtract, -)
/* unboxed multiplication (*)	ck_null		pif2	I I */
UNBOXED_INT_BINOP(multiply, *)
UNBOXED_INT_BINOP(divide, /)
UNBOXED_INT_BINOP(modulo, %)
UNBOXED_INT_BINOP(lt, <)
UNBOXED_INT_BINOP(le, <=)
UNBOXED_INT_BINOP(gt, >)
UNBOXED_INT_BINOP(ge, >=)
UNBOXED_INT_BINOP(eq, ==)
UNBOXED_INT_BINOP(ne, !=)

/* unboxed negation (-)	ck_null		pif1	I */
UNBOXED_INT_UNOP(int_negate, -)
/* unboxed integer not	ck_null		pif1	I */
UNBOXED_INT_UNOP(int_not, !)
/* unboxed 1's complement (~) ck_bitop	pif1	I */
UNBOXED_INT_UNOP(int_complement, ~)
UNBOXED_INT_UNOP(int_predec, --)
UNBOXED_INT_UNOP(int_preinc, ++)
UNBOXED_INT_UNOP(int_abs, abs)

#if IVSIZE == NVSIZE
#define UNBOXED_NUM_BINOP(name, op)             \
PPt(pp_num_##name, "(:num,:num):num")           \
{                                               \
    dSP;                                        \
    union { NV n; SV* sv; } num1, num2;         \
    num1.sv = TOPs;                             \
    sp--;                                       \
    num2.sv = TOPs;                             \
    num1.n = num1.n op num2.n;                  \
    TOPs = num1.sv;                             \
    RETURN;                                     \
}
#define UNBOXED_NUM_BINFUNC(name, func)         \
PPt(pp_num_##name, "(:num,:num):num")           \
{                                               \
    dSP;                                        \
    union { NV n; SV* sv; } num1, num2;         \
    num1.sv = TOPs;                             \
    sp--;                                       \
    num2.sv = TOPs;                             \
    num1.n = func(num1.n, num2.n);              \
    TOPs = num1.sv;                             \
    RETURN;                                     \
}
#define UNBOXED_NUM_UNOP(name, op)              \
PPt(pp_num_##name, "(:num):num")                \
{                                               \
    dSP;                                        \
    union { NV n; SV* sv; } num;                \
    num.sv = TOPs;                              \
    num.n = Perl_##op(num.n);                   \
    TOPs = num.sv;                              \
    return NORMAL;                              \
}
#else
#define UNBOXED_NUM_BINOP(name, op)             \
PPt(pp_num_##name, "(:num,:num):num") {         \
    assert(IVSIZE == NVSIZE);                   \
    return NORMAL;                              \
}
#define UNBOXED_NUM_BINFUNC(name, op)           \
PPt(pp_num_##name, "(:num,:num):num") {         \
    assert(IVSIZE == NVSIZE);                   \
    return NORMAL;                              \
}
#define UNBOXED_NUM_UNOP(name, op)              \
PPt(pp_num_##name, "(:num):num") {              \
    assert(IVSIZE == NVSIZE);                   \
    return NORMAL;                              \
}
#endif

UNBOXED_NUM_BINOP(add, +)
UNBOXED_NUM_BINOP(subtract, -)
UNBOXED_NUM_BINOP(multiply, *)
UNBOXED_NUM_BINOP(divide, /)
UNBOXED_NUM_BINFUNC(atan2, Perl_atan2)
UNBOXED_NUM_UNOP(sin, sin)
UNBOXED_NUM_UNOP(cos, cos)
UNBOXED_NUM_UNOP(exp, exp)
UNBOXED_NUM_UNOP(log, log)
UNBOXED_NUM_UNOP(sqrt, sqrt)

/* native str ops for now disabled.
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
#endif

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
		    "Use of reference \"%"SVf"\" as array index",
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
    sv = (svp ? *svp : &PL_sv_undef);
    PUSHs(sv);
    RETURN;
}

/* same as pp_num_aelem and pp_str_aelem.
   no bounds check */
PPt(pp_int_aelem, "(:Array(:int),:int):int")
{
    dSP;
    SV *sv = AvARRAY((AV*)TOPs)[(IV)TOPm1s];
    sp--;
    TOPs = sv;
    RETURN;
}

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

# if 0
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

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
