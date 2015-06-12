/*    pp_type.c
 *
 *    Copyright (C) 2015 by cPanel Inc
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

/* This file contains type variants of general pp functions, see also regen/opcodes.
   The types starting with an uppercase letter are "boxed", a SV typed as Int or Str or Num.
   The native unboxed types starting with lowercase are special values on the stack, and can
   only be used within certain op basic blocks. The compiler has to ensure that no unboxed value
   remains on the stack with non-local exits, and at function call boundaries.
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
    RETURN;
}
/* box uint to UV */
PPt(pp_box_uint, "(:uint):UInt")
{
    dSP;
    TOPs = newSVuv((UV)TOPs);
    RETURN;
}
/* box double to NV if IVSIZE==NVSIZE */
PPt(pp_box_num, "(:num):Num")
{
    /* The compiler is allowed to use native dbl on 64 bit,
       or NV = float and 32 bit */
    dSP;
#if IVSIZE == NVSIZE
    TOPs = newSVnv(PTR2NV(TOPs));
#else
    assert(0);
#endif
    RETURN;
}
/* box ASCIIZ string to PV */
PPt(pp_box_str, "(:str):Str")
{
    dSP;
    TOPs = newSVpv((const char *const)TOPs, 0);
    RETURN;
}
/* unbox IV to int */
PPt(pp_unbox_int, "(:Int):int")
{
    die("NYI");
}
/* unbox UV to uint */
PPt(pp_unbox_uint, "(:Int):uint")
{
    die("NYI");
}
/* unbox PV to ASCIIZ */
PPt(pp_unbox_str, "(:Str):str")
{
    die("NYI");
}
/* unbox NV to double if IVSIZE==NVSIZE */
PPt(pp_unbox_num, ""(:Num):num"")
{
    die("NYI");
}
/* unboxed left bitshift (<<)  ck_bitop	pfiT2	I I */
PPt(pp_uint_lshift, "(:int,:uint):uint")
{
    die("NYI");
}
/* unboxed right bitshift (>>) ck_bitop	pfiT2	I I */
PPt(pp_uint_rshift, "(:int,:uint):uint")
{
    die("NYI");
}
/* unboxed preincrement (++)  ck_lfun	dis1	I */
PPt(pp_int_preinc, "(:int):int")
{
    die("NYI");
}
/* unboxed predecrement (--)  ck_lfun	dis1	I */
PPt(pp_int_predec, "(:int):int")
{
    die("NYI");
}
/* unboxed postincrement (++) ck_lfun	ist1	I */
PPt(pp_int_postinc, "(:int):int")
{
    die("NYI");
}
/* unboxed postdecrement (--) ck_lfun	ist1	I */
PPt(pp_int_postdec, "(:int):int")
{
    die("NYI");
}
/* unboxed addition (+)	ck_null		pifsT2	I I */
PPt(pp_int_add, "(:int,:int):int")
{
    die("NYI");
}
/* unboxed subtraction (-)	ck_null		pifsT2	I I */
PPt(pp_int_subtract, "(:int,:int):int")
{
    die("NYI");
}
/* unboxed negation (-)	ck_null		pifst1	I */
PPt(pp_int_negate, "(:int):int")
{
    die("NYI");
}
/* unboxed integer not	ck_null		pifs1	I */
PPt(pp_int_not, "(:int):int")
{
    die("NYI");
}
/* unboxed 1's complement (~) ck_bitop	pifst1	I */
PPt(pp_int_complement, "(:int):int")
{
    die("NYI");
}
/* unboxed concatenation   ck_concat	pzfsT2	Z Z */
PPt(pp_str_concat, "(:str,:str):str")
{
    die("NYI");
}
/* unboxed length		ck_length	fsTu%	Z */
PPt(pp_str_length, "(:str):Int")
{
    die("NYI");
}
/* No magic allowed, but out of bounds, negative i, lval, defer allowed */
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

PPt(pp_int_aelem, "(:Array(:int),:int):int")
{
    dSP;
    TOPs = AvARRAY((AV*)TOPs)[(IV)(sp+1)];
    RETURN;
}

/* n_aelem		num array element  ck_null	s2	A S */
PPt(pp_n_aelem, "(:Array(:Num),:Int):Num")
{
    die("NYI");
}

/* unboxed	num array element ck_null	s2	A I */
PPt(pp_num_aelem, "(:Array(:num),:int):num")
{
    die("NYI");
}

/* str array element  ck_null	s2	A S */
PPt(pp_s_aelem, "(:Array(:Str),:Int):Str")
{
    die("NYI");
}

/* unboxed	str array element ck_null	z2	A Z */
PPt(pp_str_aelem, "(:Array(:str),:int):str")
{
    die("NYI");
}

/* unboxed hash element	ck_null		s2	H Z */
PPt(pp_str_helem, "(:Hash(:Scalar),:str):Scalar")
{
    die("NYI");
}

/* str_delete	unboxed delete		ck_delete	%	H Z */
PPt(pp_str_delete, "(:Hash(:Scalar),:str):Void")
{
    die("NYI");
}

/* str_exists	unboxed exists		ck_exists	s%	H Z */
PPt(pp_str_exists, "(:Hash(:Scalar),:str):Bool")
{
    die("NYI");
}

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
