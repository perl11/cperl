/*    universal.c
 *
 *    Copyright (C) 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004,
 *    2005, 2006, 2007, 2008 by Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

/*
 * '"The roots of those mountains must be roots indeed; there must be
 *   great secrets buried there which have not been discovered since the
 *   beginning."'                   --Gandalf, relating Gollum's history
 *
 *     [p.54 of _The Lord of the Rings_, I/ii: "The Shadow of the Past"]
 */

/* This file contains the code that implements the functions in Perl's
 * UNIVERSAL package, such as UNIVERSAL->can().
 *
 * It is also used to store XS functions that need to be present in
 * miniperl for a lack of a better place to put them. It might be
 * clever to move them to separate XS files which would then be pulled
 * in by some to-be-written build process.
 */

#include "EXTERN.h"
#define PERL_IN_UNIVERSAL_C
#include "perl.h"

#if defined(USE_PERLIO)
#include "perliol.h" /* For the PERLIO_F_XXX */
#endif

/*
 * Contributed by Graham Barr  <Graham.Barr@tiuk.ti.com>
 * The main guts of traverse_isa was actually copied from gv_fetchmeth
 */

STATIC bool
S_isa_lookup(pTHX_ HV *stash, const char * const name, STRLEN len, U32 flags)
{
    const struct mro_meta *const meta = HvMROMETA(stash);
    HV *isa = meta->isa;
    const HV *our_stash;

    PERL_ARGS_ASSERT_ISA_LOOKUP;

    if (!isa) {
	(void)mro_get_linear_isa(stash);
	isa = meta->isa;
    }

    if (hv_common(isa, NULL, name, len, ( flags & SVf_UTF8 ? HVhek_UTF8 : 0),
		  HV_FETCH_ISEXISTS, NULL, 0)) {
	/* Direct name lookup worked.  */
	return TRUE;
    }

    /* A stash/class can go by many names (ie. User == main::User), so 
       we use the HvENAME in the stash itself, which is canonical, falling
       back to HvNAME if necessary.  */
    our_stash = gv_stashpvn(name, len, flags);

    if (our_stash) {
	HEK *canon_name = HvENAME_HEK(our_stash);
	if (!canon_name) canon_name = HvNAME_HEK(our_stash);
	assert(canon_name);
	if (hv_common(isa, NULL, HEK_KEY(canon_name), HEK_LEN(canon_name),
		      HEK_FLAGS(canon_name),
		      HV_FETCH_ISEXISTS, NULL, HEK_HASH(canon_name))) {
	    return TRUE;
	}
    }

    return FALSE;
}

/*
=head1 SV Manipulation Functions

=for apidoc sv_derived_from_pvn

Returns a boolean indicating whether the SV is derived from the specified class
I<at the C level>.  To check derivation at the Perl level, call C<isa()> as a
normal Perl method.

Currently, the only significant value for C<flags> is SVf_UTF8.

=cut

=for apidoc sv_derived_from_sv

Exactly like L</sv_derived_from_pvn>, but takes the name string in the form
of an SV instead of a string/length pair.

=cut

*/

bool
Perl_sv_derived_from_sv(pTHX_ SV *sv, SV *namesv, U32 flags)
{
    char *namepv;
    STRLEN namelen;
    PERL_ARGS_ASSERT_SV_DERIVED_FROM_SV;
    namepv = SvPV(namesv, namelen);
    if (SvUTF8(namesv))
       flags |= SVf_UTF8;
    return sv_derived_from_pvn(sv, namepv, namelen, flags);
}

/*
=for apidoc sv_derived_from

Exactly like L</sv_derived_from_pv>, but doesn't take a C<flags> parameter.

=cut
*/

bool
Perl_sv_derived_from(pTHX_ SV *sv, const char *const name)
{
    PERL_ARGS_ASSERT_SV_DERIVED_FROM;
    return sv_derived_from_pvn(sv, name, strlen(name), 0);
}

/*
=for apidoc sv_derived_from_pv

Exactly like L</sv_derived_from_pvn>, but takes a nul-terminated string 
instead of a string/length pair.

=cut
*/


bool
Perl_sv_derived_from_pv(pTHX_ SV *sv, const char *const name, U32 flags)
{
    PERL_ARGS_ASSERT_SV_DERIVED_FROM_PV;
    return sv_derived_from_pvn(sv, name, strlen(name), flags);
}

bool
Perl_sv_derived_from_pvn(pTHX_ SV *sv, const char *const name, const STRLEN len, U32 flags)
{
    HV *stash;

    PERL_ARGS_ASSERT_SV_DERIVED_FROM_PVN;

    SvGETMAGIC(sv);

    if (SvROK(sv)) {
	const char *type;
        sv = SvRV(sv);
        type = sv_reftype(sv,0);
	if (type && strEQ(type,name))
	    return TRUE;
        if (!SvOBJECT(sv))
            return FALSE;
	stash = SvSTASH(sv);
    }
    else {
        stash = gv_stashsv(sv, 0);
    }

    if (stash && isa_lookup(stash, name, len, flags))
        return TRUE;

    stash = gv_stashpvs("UNIVERSAL", 0);
    return stash && isa_lookup(stash, name, len, flags);
}

/*
=for apidoc sv_does_sv

Returns a boolean indicating whether the SV performs a specific, named role.
The SV can be a Perl object or the name of a Perl class.

=cut
*/

#include "XSUB.h"

bool
Perl_sv_does_sv(pTHX_ SV *sv, SV *namesv, U32 flags)
{
    SV *classname;
    bool does_it;
    SV *methodname;
    dSP;

    PERL_ARGS_ASSERT_SV_DOES_SV;
    PERL_UNUSED_ARG(flags);

    ENTER;
    SAVETMPS;

    SvGETMAGIC(sv);

    if (!SvOK(sv) || !(SvROK(sv) || (SvPOK(sv) && SvCUR(sv)))) {
	LEAVE;
	return FALSE;
    }

    if (SvROK(sv) && SvOBJECT(SvRV(sv))) {
	classname = sv_ref(NULL,SvRV(sv),TRUE);
    } else {
	classname = sv;
    }

    if (sv_eq(classname, namesv)) {
	LEAVE;
	return TRUE;
    }

    PUSHMARK(SP);
    EXTEND(SP, 2);
    PUSHs(sv);
    PUSHs(namesv);
    PUTBACK;

    /* create a PV with value "isa", but with a special address
     * so that perl knows we're really doing "DOES" instead */
    methodname = newSV_type(SVt_PV);
    SvLEN_set(methodname, 0);
    SvCUR_set(methodname, strlen(PL_isa_DOES));
    SvPVX(methodname) = (char *)PL_isa_DOES; /* discard 'const' qualifier */
    SvPOK_on(methodname);
    sv_2mortal(methodname);
    call_sv(methodname, G_SCALAR | G_METHOD);
    SPAGAIN;

    does_it = SvTRUE_NN( TOPs );
    FREETMPS;
    LEAVE;

    return does_it;
}

/*
=for apidoc sv_does

Like L</sv_does_pv>, but doesn't take a C<flags> parameter.

=cut
*/

bool
Perl_sv_does(pTHX_ SV *sv, const char *const name)
{
    PERL_ARGS_ASSERT_SV_DOES;
    return sv_does_sv(sv, newSVpvn_flags(name, strlen(name), SVs_TEMP), 0);
}

/*
=for apidoc sv_does_pv

Like L</sv_does_sv>, but takes a nul-terminated string instead of an SV.

=cut
*/


bool
Perl_sv_does_pv(pTHX_ SV *sv, const char *const name, U32 flags)
{
    PERL_ARGS_ASSERT_SV_DOES_PV;
    return sv_does_sv(sv, newSVpvn_flags(name, strlen(name), SVs_TEMP | flags), flags);
}

/*
=for apidoc sv_does_pvn

Like L</sv_does_sv>, but takes a string/length pair instead of an SV.

=cut
*/

bool
Perl_sv_does_pvn(pTHX_ SV *sv, const char *const name, const STRLEN len, U32 flags)
{
    PERL_ARGS_ASSERT_SV_DOES_PVN;

    return sv_does_sv(sv, newSVpvn_flags(name, len, flags | SVs_TEMP), flags);
}

/*
=for apidoc croak_xs_usage

A specialised variant of C<croak()> for emitting the usage message for xsubs

    croak_xs_usage(cv, "eee_yow");

works out the package name and subroutine name from C<cv>, and then calls
C<croak()>.  Hence if C<cv> is C<&ouch::awk>, it would call C<croak> as:

 Perl_croak(aTHX_ "Usage: %" SVf "::%" SVf "(%s)", "ouch" "awk",
                                                     "eee_yow");

=cut
*/

void
Perl_croak_xs_usage(const CV *const cv, const char *const params)
{
    /* Avoid CvGV as it requires aTHX.  */
    const GV *gv = CvNAMED(cv) ? NULL : SvANY(cv)->xcv_gv_u.xcv_gv;

    PERL_ARGS_ASSERT_CROAK_XS_USAGE;

    if (gv) got_gv: {
	const HV *const stash = GvSTASH(gv);

	if (HvNAME_get(stash))
	    /* diag_listed_as: SKIPME */
	    Perl_croak_nocontext("Usage: %" HEKf "::%" HEKf "(%s)",
                                HEKfARG(HvNAME_HEK(stash)),
                                HEKfARG(GvNAME_HEK(gv)),
                                params);
	else
	    /* diag_listed_as: SKIPME */
	    Perl_croak_nocontext("Usage: %" HEKf "(%s)",
                                HEKfARG(GvNAME_HEK(gv)), params);
    } else {
        dTHX;
        if ((gv = CvGV(cv))) goto got_gv;

	/* Pants. I don't think that it should be possible to get here. */
	/* diag_listed_as: SKIPME */
	Perl_croak(aTHX_ "Usage: CODE(0x%" UVxf ")(%s)", PTR2UV(cv), params);
    }
}

XS(XS_UNIVERSAL_isa); /* prototype to pass -Wmissing-prototypes */
XS(XS_UNIVERSAL_isa)
{
    dXSARGS;

    if (items != 2)
	croak_xs_usage(cv, "reference, kind");
    else {
	SV * const sv = ST(0);

	SvGETMAGIC(sv);

	if (!SvOK(sv) || !(SvROK(sv) || (SvPOK(sv) && SvCUR(sv))))
	    XSRETURN_UNDEF;

	ST(0) = boolSV(sv_derived_from_sv(sv, ST(1), 0));
	XSRETURN(1);
    }
}

XS(XS_UNIVERSAL_can); /* prototype to pass -Wmissing-prototypes */
XS(XS_UNIVERSAL_can)
{
    dXSARGS;
    SV   *sv;
    SV   *rv;
    HV   *pkg = NULL;
    GV   *iogv;

    if (items != 2)
	croak_xs_usage(cv, "object-ref, method");

    sv = ST(0);

    SvGETMAGIC(sv);

    /* Reject undef and empty string.  Note that the string form takes
       precedence here over the numeric form, as (!1)->foo treats the
       invocant as the empty string, though it is a dualvar. */
    if (!SvOK(sv) || (SvPOK(sv) && !SvCUR(sv)))
	XSRETURN_UNDEF;

    rv = UNDEF;

    if (SvROK(sv)) {
        sv = MUTABLE_SV(SvRV(sv));
        if (SvOBJECT(sv))
            pkg = SvSTASH(sv);
        else if (isGV_with_GP(sv) && GvIO(sv))
	    pkg = SvSTASH(GvIO(sv));
    }
    else if (isGV_with_GP(sv) && GvIO(sv))
        pkg = SvSTASH(GvIO(sv));
    else if ((iogv = gv_fetchsv_nomg(sv, 0, SVt_PVIO)) && GvIO(iogv))
        pkg = SvSTASH(GvIO(iogv));
    else {
        pkg = gv_stashsv(sv, 0);
        if (!pkg)
            pkg = gv_stashpvs("UNIVERSAL", 0);
    }

    if (pkg) {
	GV * const gv = gv_fetchmethod_sv_flags(pkg, ST(1), 0);
        if (gv && isGV(gv))
	    rv = sv_2mortal(newRV(MUTABLE_SV(GvCV(gv))));
    }

    ST(0) = rv;
    XSRETURN(1);
}

XS(XS_UNIVERSAL_DOES); /* prototype to pass -Wmissing-prototypes */
XS(XS_UNIVERSAL_DOES)
{
    dXSARGS;
    PERL_UNUSED_ARG(cv);

    if (items != 2)
	Perl_croak(aTHX_ "Usage: invocant->DOES(kind)");
    else {
	SV * const sv = ST(0);
	if (sv_does_sv( sv, ST(1), 0 ))
	    XSRETURN_YES;

	XSRETURN_NO;
    }
}

XS(XS_utf8_is_utf8); /* prototype to pass -Wmissing-prototypes */
XS(XS_utf8_is_utf8)
{
     dXSARGS;
     if (items != 1)
	 croak_xs_usage(cv, "sv");
     else {
	SV * const sv = ST(0);
	SvGETMAGIC(sv);
	    if (SvUTF8(sv))
		XSRETURN_YES;
	    else
		XSRETURN_NO;
     }
     XSRETURN_EMPTY;
}

XS(XS_utf8_valid); /* prototype to pass -Wmissing-prototypes */
XS(XS_utf8_valid)
{
     dXSARGS;
     if (items != 1)
	 croak_xs_usage(cv, "sv");
    else {
	SV * const sv = ST(0);
	STRLEN len;
	const char * const s = SvPV_const(sv,len);
	if (!SvUTF8(sv) || is_utf8_string((const U8*)s,len))
	    XSRETURN_YES;
	else
	    XSRETURN_NO;
    }
     XSRETURN_EMPTY;
}

XS(XS_utf8_encode); /* prototype to pass -Wmissing-prototypes */
XS(XS_utf8_encode)
{
    dXSARGS;
    if (items != 1)
	croak_xs_usage(cv, "sv");
    sv_utf8_encode(ST(0));
    SvSETMAGIC(ST(0));
    XSRETURN_EMPTY;
}

XS(XS_utf8_decode); /* prototype to pass -Wmissing-prototypes */
XS(XS_utf8_decode)
{
    dXSARGS;
    if (items != 1)
	croak_xs_usage(cv, "sv");
    else {
	SV * const sv = ST(0);
	bool RETVAL;
	SvPV_force_nolen(sv);
	RETVAL = sv_utf8_decode(sv);
	SvSETMAGIC(sv);
	ST(0) = boolSV(RETVAL);
    }
    XSRETURN(1);
}

XS(XS_utf8_upgrade); /* prototype to pass -Wmissing-prototypes */
XS(XS_utf8_upgrade)
{
    dXSARGS;
    if (items != 1)
	croak_xs_usage(cv, "sv");
    else {
	SV * const sv = ST(0);
	STRLEN	RETVAL;
	dXSTARG;

	RETVAL = sv_utf8_upgrade(sv);
	XSprePUSH; PUSHi((IV)RETVAL);
    }
    XSRETURN(1);
}

XS(XS_utf8_downgrade); /* prototype to pass -Wmissing-prototypes */
XS(XS_utf8_downgrade)
{
    dXSARGS;
    if (items < 1 || items > 2)
	croak_xs_usage(cv, "sv, failok=0");
    else {
	SV * const sv0 = ST(0);
	SV * const sv1 = ST(1);
        const bool failok = (items < 2) ? 0 : SvTRUE_NN(sv1) ? 1 : 0;
        const bool RETVAL = sv_utf8_downgrade(sv0, failok);

	ST(0) = boolSV(RETVAL);
    }
    XSRETURN(1);
}

XS(XS_utf8_native_to_unicode); /* prototype to pass -Wmissing-prototypes */
XS(XS_utf8_native_to_unicode)
{
 dXSARGS;
 const UV uv = SvUV(ST(0));

 if (items > 1)
     croak_xs_usage(cv, "sv");

 ST(0) = sv_2mortal(newSVuv(NATIVE_TO_UNI(uv)));
 XSRETURN(1);
}

XS(XS_utf8_unicode_to_native); /* prototype to pass -Wmissing-prototypes */
XS(XS_utf8_unicode_to_native)
{
 dXSARGS;
 const UV uv = SvUV(ST(0));

 if (items > 1)
     croak_xs_usage(cv, "sv");

 ST(0) = sv_2mortal(newSVuv(UNI_TO_NATIVE(uv)));
 XSRETURN(1);
}

XS(XS_Internals_SvREADONLY); /* prototype to pass -Wmissing-prototypes */
XS(XS_Internals_SvREADONLY)	/* This is dangerous stuff. */
{
    dXSARGS;
    SV * const svz = ST(0);
    SV * sv;

    /* [perl #77776] - called as &foo() not foo() */
    if (!SvROK(svz))
        croak_xs_usage(cv, "SCALAR[, ON]");

    sv = SvRV(svz);

    if (items == 1) {
	 if (SvREADONLY(sv))
	     XSRETURN_YES;
	 else
	     XSRETURN_NO;
    }
    else if (items == 2) {
        SV *sv1 = ST(1);
	if (SvTRUE_NN(sv1)) {
	    SvFLAGS(sv) |= SVf_READONLY;
	    XSRETURN_YES;
	}
	else {
	    /* I hope you really know what you are doing. */
#ifdef USE_CPERL
            dVAR;
            /*static GV* S_main_stash = gv_fetchpvs("main::", GV_NOTQUAL, SVt_PVHV); */
            /* fail on some protected values: yes, no, undef, ... */
            if (   sv == PLACEHOLDER
                || sv == UNDEF
                || sv == SV_YES
                || sv == SV_NO
              /*|| sv == (SV*)S_main_stash*/
                || sv == (SV*)&PL_defstash) /* only %main:: or also *main:: ? */
                croak_no_modify_sv(sv);
#endif
	    SvFLAGS(sv) &=~ SVf_READONLY;
	    XSRETURN_NO;
	}
    }
    XSRETURN_UNDEF; /* Can't happen. */
}

XS(XS_Internals_HvCLASS); /* prototype to pass -Wmissing-prototypes */
XS(XS_Internals_HvCLASS)	/* Needed for base to fake cperl classes */
{
    dXSARGS;
    SV * const svz = ST(0);
    SV * stash;

    if (!SvROK(svz))
        croak_xs_usage(cv, "STASH[, ON] (RV)");
    else
        stash = SvRV(svz);
    if (SvPOK(stash)) {
        stash = (SV*)gv_stashsv(stash, SvUTF8(stash));
        if (!stash)
            Perl_croak(aTHX_ "Internals::HvCLASS: Unknown classname %s",
                       SvPVX(SvRV(svz)));
    }
    if (SvTYPE(stash) != SVt_PVHV)
        croak_xs_usage(cv, "STASH[, ON] (HV)");

    if (items == 1) {
	 if (HvCLASS(stash))
	     XSRETURN_YES;
	 else
	     XSRETURN_NO;
    }
    else if (items == 2) {
	if (SvTRUE(ST(1))) {
            if (!HvCLASS(stash)) {
                /* make it an almost closed class.
                   prefer damians' perl5i policy over larry's use oo :closed,
                   which is still not here. */
                GV* isa;
                SV *name = newSVpvn_flags(HvNAME(stash), HvNAMELEN(stash),
                               SVs_TEMP | (HvNAMEUTF8(stash) ? SVf_UTF8 : 0));
                sv_catpvs(name, "::ISA");
                isa = gv_fetchsv(name, GV_ADD, SVt_PVAV);
                HvCLASS_on(stash);
                SvREADONLY_on(GvAVn(isa));
                XSRETURN_YES;
            }
	}
	else {
            croak_xs_usage(cv, "STASH[, ON]");
	}
    }
    XSRETURN_UNDEF; /* Can't happen. */
}

XS(XS_constant__make_const); /* prototype to pass -Wmissing-prototypes */
XS(XS_constant__make_const)	/* This is dangerous stuff. */
{
    dXSARGS;
    SV * const svz = ST(0);
    SV * sv;

    /* [perl #77776] - called as &foo() not foo() */
    if (!SvROK(svz) || items != 1)
        croak_xs_usage(cv, "SCALAR");

    sv = SvRV(svz);

    SvREADONLY_on(sv);
    if (SvTYPE(sv) == SVt_PVAV && AvFILLp(sv) != -1) {
	/* for constant.pm; nobody else should be calling this
	   on arrays anyway. */
	SV **svp;
	for (svp = AvARRAY(sv) + AvFILLp(sv)
	   ; svp >= AvARRAY(sv)
	   ; --svp)
	    if (*svp) SvPADTMP_on(*svp);
    }
    XSRETURN(0);
}

XS(XS_Internals_SvREFCNT); /* prototype to pass -Wmissing-prototypes */
XS(XS_Internals_SvREFCNT)	/* This is dangerous stuff. */
{
    dXSARGS;
    SV * const svz = ST(0);
    SV * sv;
    U32 refcnt;

    /* [perl #77776] - called as &foo() not foo() */
    if ((items != 1 && items != 2) || !SvROK(svz))
        croak_xs_usage(cv, "SCALAR[, REFCOUNT]");

    sv = SvRV(svz);

         /* I hope you really know what you are doing. */
    /* idea is for SvREFCNT(sv) to be accessed only once */
    refcnt = items == 2 ?
                /* we free one ref on exit */
                (SvREFCNT(sv) = SvUV(ST(1)) + 1)
                : SvREFCNT(sv);
    XSRETURN_UV(refcnt - 1); /* Minus the ref created for us. */        

}

XS(XS_Internals_hv_clear_placehold); /* prototype to pass -Wmissing-prototypes */
XS(XS_Internals_hv_clear_placehold)
{
    dXSARGS;

    if (items != 1 || !SvROK(ST(0)))
	croak_xs_usage(cv, "hv");
    else {
	HV * const hv = MUTABLE_HV(SvRV(ST(0)));
	hv_clear_placeholders(hv);
	XSRETURN(0);
    }
}

XS(XS_PerlIO_get_layers); /* prototype to pass -Wmissing-prototypes */
XS(XS_PerlIO_get_layers)
{
    dXSARGS;
    if (items < 1 || items % 2 == 0)
	croak_xs_usage(cv, "filehandle[,args]");
#if defined(USE_PERLIO)
    {
	SV *	sv;
	GV *	gv;
	IO *	io;
	bool	input = TRUE;
	bool	details = FALSE;

	if (items > 1) {
	     SV * const *svp;
	     for (svp = MARK + 2; svp <= SP; svp += 2) {
		  SV * const * const varp = svp;
		  SV * const * const valp = svp + 1;
		  STRLEN klen;
		  const char * const key = SvPV_const(*varp, klen);

		  switch (*key) {
		  case 'i':
                       if (memEQs(key, klen, "input")) {
			    input = SvTRUE(*valp);
			    break;
		       }
		       goto fail;
		  case 'o': 
                       if (memEQs(key, klen, "output")) {
			    input = !SvTRUE(*valp);
			    break;
		       }
		       goto fail;
		  case 'd':
                       if (memEQs(key, klen, "details")) {
			    details = SvTRUE(*valp);
			    break;
		       }
		       goto fail;
		  default:
		  fail:
		       Perl_croak(aTHX_
				  "get_layers: unknown argument '%s'",
				  key);
		  }
	     }

	     SP -= (items - 1);
	}

	sv = POPs;
	gv = MAYBE_DEREF_GV(sv);

	if (!gv && !SvROK(sv))
	    gv = gv_fetchsv_nomg(sv, 0, SVt_PVIO);

	if (gv && (io = GvIO(gv))) {
	     AV* const av = PerlIO_get_layers(aTHX_ input ?
					IoIFP(io) : IoOFP(io));
	     SSize_t i;
	     const SSize_t last = av_tindex(av);
	     SSize_t nitem = 0;
	     
	     for (i = last; i >= 0; i -= 3) {
		  SV * const * const namsvp = av_fetch(av, i - 2, FALSE);
		  SV * const * const argsvp = av_fetch(av, i - 1, FALSE);
		  SV * const * const flgsvp = av_fetch(av, i,     FALSE);

		  const bool namok = namsvp && *namsvp && SvPOK(*namsvp);
		  const bool argok = argsvp && *argsvp && SvPOK(*argsvp);
		  const bool flgok = flgsvp && *flgsvp && SvIOK(*flgsvp);

		  EXTEND(SP, 3); /* Three is the max in all branches: better check just once */
		  if (details) {
		      /* Indents of 5? Yuck.  */
		      /* We know that PerlIO_get_layers creates a new SV for
			 the name and flags, so we can just take a reference
			 and "steal" it when we free the AV below.  */
		       PUSHs(namok
			      ? sv_2mortal(SvREFCNT_inc_simple_NN(*namsvp))
			      : UNDEF);
		       PUSHs(argok
			      ? newSVpvn_flags(SvPVX_const(*argsvp),
					       SvCUR(*argsvp),
					       (SvUTF8(*argsvp) ? SVf_UTF8 : 0)
					       | SVs_TEMP)
			      : UNDEF);
		       PUSHs(flgok
			      ? sv_2mortal(SvREFCNT_inc_simple_NN(*flgsvp))
			      : UNDEF);
		       nitem += 3;
		  }
		  else {
		       if (namok && argok)
			    PUSHs(sv_2mortal(Perl_newSVpvf(aTHX_ "%" SVf "(%" SVf ")",
						 SVfARG(*namsvp),
						 SVfARG(*argsvp))));
		       else if (namok)
			    PUSHs(sv_2mortal(SvREFCNT_inc_simple_NN(*namsvp)));
		       else
			    PUSHs(UNDEF);
		       nitem++;
		       if (flgok) {
			    const IV flags = SvIVX(*flgsvp);

			    if (flags & PERLIO_F_UTF8) {
				 PUSHs(newSVpvs_flags("utf8", SVs_TEMP));
				 nitem++;
			    }
		       }
		  }
	     }

	     SvREFCNT_dec(av);

	     XSRETURN(nitem);
	}
    }
#endif

    XSRETURN(0);
}

XS(XS_re_is_regexp); /* prototype to pass -Wmissing-prototypes */
XS(XS_re_is_regexp)
{
    dXSARGS;

    if (items != 1)
	croak_xs_usage(cv, "sv");

    if (SvRXOK(ST(0))) {
        XSRETURN_YES;
    } else {
        XSRETURN_NO;
    }
}

XS(XS_re_regnames_count); /* prototype to pass -Wmissing-prototypes */
XS(XS_re_regnames_count)
{
    REGEXP *rx = PL_curpm ? PM_GETRE(PL_curpm) : NULL;
    SV * ret;
    dXSARGS;

    if (items != 0)
	croak_xs_usage(cv, "");

    if (!rx)
        XSRETURN_UNDEF;

    ret = CALLREG_NAMED_BUFF_COUNT(rx);

    SPAGAIN;
    PUSHs(ret ? sv_2mortal(ret) : UNDEF);
    XSRETURN(1);
}

XS(XS_re_regname); /* prototype to pass -Wmissing-prototypes */
XS(XS_re_regname)
{
    dXSARGS;
    REGEXP * rx;
    U32 flags;
    SV * ret;

    if (items < 1 || items > 2)
	croak_xs_usage(cv, "name[, all ]");

    SP -= items;
    PUTBACK;

    rx = PL_curpm ? PM_GETRE(PL_curpm) : NULL;

    if (!rx)
        XSRETURN_UNDEF;

    if (items == 2 && SvTRUE_NN(ST(1))) {
        flags = RXapif_ALL;
    } else {
        flags = RXapif_ONE;
    }
    ret = CALLREG_NAMED_BUFF_FETCH(rx, ST(0), (flags | RXapif_REGNAME));

    SPAGAIN;
    PUSHs(ret ? sv_2mortal(ret) : UNDEF);
    XSRETURN(1);
}


XS(XS_re_regnames); /* prototype to pass -Wmissing-prototypes */
XS(XS_re_regnames)
{
    dXSARGS;
    REGEXP * rx;
    U32 flags;
    SV *ret;
    AV *av;
    SSize_t length;
    SSize_t i;
    SV **entry;

    if (items > 1)
	croak_xs_usage(cv, "[all]");

    rx = PL_curpm ? PM_GETRE(PL_curpm) : NULL;

    if (!rx)
        XSRETURN_UNDEF;

    if (items == 1 && SvTRUE_NN(ST(0))) {
        flags = RXapif_ALL;
    } else {
        flags = RXapif_ONE;
    }

    SP -= items;
    PUTBACK;

    ret = CALLREG_NAMED_BUFF_ALL(rx, (flags | RXapif_REGNAMES));

    SPAGAIN;

    if (!ret)
        XSRETURN_UNDEF;

    av = MUTABLE_AV(SvRV(ret));
    length = av_tindex(av);

    EXTEND(SP, length+1); /* better extend stack just once */
    for (i = 0; i <= length; i++) {
        entry = av_fetch(av, i, FALSE);
        
        if (!entry)
            Perl_croak(aTHX_ "NULL array element in re::regnames()");

        mPUSHs(SvREFCNT_inc_simple_NN(*entry));
    }

    SvREFCNT_dec(ret);

    PUTBACK;
    return;
}

XS(XS_re_regexp_pattern); /* prototype to pass -Wmissing-prototypes */
XS(XS_re_regexp_pattern)
{
    dXSARGS;
    REGEXP *re;
    U8 const gimme = GIMME_V;

    EXTEND(SP, 2);
    SP -= items;
    if (items != 1)
	croak_xs_usage(cv, "sv");

    /*
       Checks if a reference is a regex or not. If the parameter is
       not a ref, or is not the result of a qr// then returns false
       in scalar context and an empty list in list context.
       Otherwise in list context it returns the pattern and the
       modifiers, in scalar context it returns the pattern just as it
       would if the qr// was stringified normally, regardless as
       to the class of the variable and any stringification overloads
       on the object.
    */

    if ((re = SvRX(ST(0)))) /* assign deliberate */
    {
        /* Houston, we have a regex! */
        SV *pattern;

        if ( gimme == G_ARRAY ) {
	    STRLEN left = 0;
	    char reflags[sizeof(INT_PAT_MODS) + MAX_CHARSET_NAME_LENGTH];
            const char *fptr;
            char ch;
            U16 match_flags;

            /*
               we are in list context so stringify
               the modifiers that apply. We ignore "negative
               modifiers" in this scenario, and the default character set
            */

	    if (get_regex_charset(RX_EXTFLAGS(re)) != REGEX_DEPENDS_CHARSET) {
		STRLEN len;
		const char* const name = get_regex_charset_name(RX_EXTFLAGS(re),
								&len);
		Copy(name, reflags + left, len, char);
		left += len;
	    }
            fptr = INT_PAT_MODS;
            match_flags = (U16)((RX_EXTFLAGS(re) & RXf_PMf_COMPILETIME)
                                    >> RXf_PMf_STD_PMMOD_SHIFT);

            while((ch = *fptr++)) {
                if(match_flags & 1) {
                    reflags[left++] = ch;
                }
                match_flags >>= 1;
            }

            pattern = newSVpvn_flags(RX_PRECOMP(re),RX_PRELEN(re),
				     (RX_UTF8(re) ? SVf_UTF8 : 0) | SVs_TEMP);

            /* return the pattern and the modifiers */
            PUSHs(pattern);
            PUSHs(newSVpvn_flags(reflags, left, SVs_TEMP));
            XSRETURN(2);
        } else {
            /* Scalar, so use the string that Perl would return */
            /* return the pattern in (?msixn:..) format */
#if PERL_VERSION >= 11
            pattern = sv_2mortal(newSVsv(MUTABLE_SV(re)));
#else
            pattern = newSVpvn_flags(RX_WRAPPED(re), RX_WRAPLEN(re),
				     (RX_UTF8(re) ? SVf_UTF8 : 0) | SVs_TEMP);
#endif
            PUSHs(pattern);
            XSRETURN(1);
        }
    } else {
        /* It ain't a regexp folks */
        if ( gimme == G_ARRAY ) {
            /* return the empty list */
            XSRETURN_EMPTY;
        } else {
            /* Because of the (?:..) wrapping involved in a
               stringified pattern it is impossible to get a
               result for a real regexp that would evaluate to
               false. Therefore we can return PL_sv_no to signify
               that the object is not a regex, this means that one
               can say

                 if (regex($might_be_a_regex) eq '(?:foo)') { }

               and not worry about undefined values.
            */
            XSRETURN_NO;
        }
    }
    NOT_REACHED; /* NOTREACHED */
}

/* TODO: put these into oo.c */
/* Copies over has field :const.
   Allows new [array] being assigned to an @array,
   and {href} being assigned to an %hash.
 */

XS(XS_Mu_new); /* prototype to pass -Wmissing-prototypes */
XS(XS_Mu_new)
{
    dXSARGS;
    SP -= items;
    if (items < 1 || !SvPOK(ST(0)))
	croak_xs_usage(cv, "classname");
    else {
        SV *name = ST(0);
        HV *stash = gv_stashsv(name, SvUTF8(name));
        AV *av = newAV();
#ifdef OLD_FIELDS_GV
        if (hv_existss(stash, "FIELDS")) { /* has fields? */
            AV *fields;
#else
        char *fields;
        if ((fields = HvFIELDS_get(stash))) { /* has fields? */
# ifdef FIELDS_DYNAMIC_PADSIZE
            const char padsize = *fields;
# else
            const char padsize = sizeof(PADOFFSET);
# endif
#endif
            SSize_t i, fill;
            if (SvREADONLY(name))
                name = newSVpvn_flags(SvPVX(name), SvCUR(name), SvUTF8(name)|SVs_TEMP);
#ifdef OLD_FIELDS_GV
            sv_catpvs(name, "::FIELDS");
            fields = GvAVn(gv_fetchsv(name, 0, SVt_PVAV));
            fill = AvFILLp(fields);
#else
            fill = numfields(stash);
#endif
            av_extend(av, fill);
            AvFILLp(av) = fill;
            items--; /* skip $self */
#ifdef OLD_FIELDS_GV
            for (i=0; i<=fill; i++) {
                const SV *padix = AvARRAY(fields)[i];
                const PADOFFSET po = SvIVX(padix);
#else
#ifdef FIELDS_DYNAMIC_PADSIZE
            fields++;
#endif
            for (i=0; *fields; i++ ) {
                int l = strlen(fields);
                const PADOFFSET po = fields_padoffset(fields, l+1, padsize);
#endif
                const PADNAME *pn = PAD_COMPNAME(po);
#ifndef OLD_FIELDS_GV
                fields += l+padsize+1;
#endif
                /* use a pseudohash or string with all the names as first element?
                   no, this is just an optional new method. */
                if (items > i) { /* copy from args */
                    /* deref [ah]vrefs to lists? */
                    SV* arg = ST(i+1);
                    if (UNLIKELY(*PadnamePV(pn) != '$') && SvROK(arg)) {
                        arg = SvRV(arg);
                        if ( (*PadnamePV(pn) == '@' && SvTYPE(arg) != SVt_PVAV)
                          || (*PadnamePV(pn) == '%' && SvTYPE(arg) != SVt_PVHV) )
                            Perl_croak(aTHX_ "Invalid object field type");
                    }
                    AvARRAY(av)[i] = arg;
                }
                else { /* new CLASS field1, field2, ... */
                    SV * const sv = PAD_SVl(po);
                    SvPADSTALE_off(sv);
                    AvARRAY(av)[i] = SvREFCNT_inc_NN(sv);
                    DEBUG_kv(Perl_deb(aTHX_ "  Mu->new: %s[%d] use default %s [%d]\n",
                                      SvPVX(name), (int)i, SvPEEK(sv),
                                      (int)po));
                }
            }
        }
        AvSHAPED_on(av);
        ST(0) = sv_bless(newRV((SV*)av), stash);
        XSRETURN(1);
    }
}

XS(XS_Mu_CREATE); /* prototype to pass -Wmissing-prototypes */
XS(XS_Mu_CREATE)
{
    dXSARGS;
    SP -= items;
    if (items != 1 || !SvPOK(ST(0)))
	croak_xs_usage(cv, "classname");
    else {
        SV *name = ST(0);
        AV *av = newAV();
        HV *stash = gv_stashsv(name, SvUTF8(name));
#ifdef OLD_FIELDS_GV
        if (hv_existss(stash, "FIELDS")) { /* has fields? */
            AV *fields;
            if (SvREADONLY(name))
                name = newSVpvn_flags(SvPVX(name), SvCUR(name), SvUTF8(name)|SVs_TEMP);
            sv_catpvs(name, "::FIELDS");
            fields = GvAVn(gv_fetchsv(name, 0, SVt_PVAV));
            if (fields)
                av_extend(av, AvFILLp(fields));
        }
#else
        SSize_t fill;
        if (HvFIELDS_get(stash)) { /* has fields? */
            fill = numfields(stash);
            av_extend(av, fill);
        }
#endif

        AvSHAPED_on(av);
        ST(0) = sv_bless(newRV((SV*)av), stash);
        XSRETURN(1);
    }
}

/* Returns a list of all fields, as fields objects.
   Of a class or an object. */

#define FIELDS_INDEX_PO    0
#define FIELDS_INDEX_IX    1
#define FIELDS_INDEX_CLASS 2
#define FIELDS_INDEX_OBJ   3

XS(XS_Mu_fields); /* prototype to pass -Wmissing-prototypes */
XS(XS_Mu_fields)
{
    dXSARGS;
    SV *name = NULL;
    SV *obj  = NULL;
    HV *klass;
    if (items != 1)
	croak_xs_usage(cv, "classname or classobject");
    if (SvPOK(ST(0))) {
        name = ST(0);
        if (!(klass = gv_stashsv(name,0)) || !HvCLASS(klass))
            croak_xs_usage(cv, "not a class");
    } else {
        obj = ST(0);
        if ( !SvROK(obj) ||
             !(SvFLAGS(SvRV(obj)) & SVs_OBJECT) ||
             !HvCLASS(SvSTASH(SvRV(obj))) )
            croak_xs_usage(cv, "not an object");
        klass = SvSTASH(SvRV(obj));
    }
    assert(klass);
    SP--;
    {
        U16 i;
        U16 num = numfields(klass);
        HV* fields = gv_stashpvs("fields", GV_ADD);
        if (UNLIKELY(PL_stack_max - SP < num))
            (void)stack_grow(sp,SP,num);
        /*EXTEND(SP, num);*/
        for (i=0; i<num; i++) {
            PADOFFSET po = field_index(klass, i);
            AV* field;
            assert(po != NOT_IN_PAD);
            field = newAV();
            AvFILLp(field) = obj ? FIELDS_INDEX_OBJ : FIELDS_INDEX_CLASS;
            av_extend(field, AvFILLp(field));
            AvARRAY(field)[FIELDS_INDEX_PO] = newSVuv(po); /* [0] */
            AvARRAY(field)[FIELDS_INDEX_IX] = newSVuv(i);  /* [1] */
            AvARRAY(field)[FIELDS_INDEX_CLASS] = SvREFCNT_inc_NN(klass); /* [2] */
            if (obj)
                AvARRAY(field)[FIELDS_INDEX_OBJ] = SvREFCNT_inc_NN(obj); /* [3] */
            PUSHs(sv_bless(newRV((SV*)field), fields));
        }
        XSRETURN(num);
    }
}
#define FIELDS_OBJ_ASSERT \
    assert(SvTYPE(obj) == SVt_PVAV); \
    assert(AvFILLp((AV*)obj) >= FIELDS_INDEX_CLASS)

PERL_STATIC_INLINE PADOFFSET
S_fields_po(SV* obj) {
    FIELDS_OBJ_ASSERT;
    return SvUVX(AvARRAY(obj)[FIELDS_INDEX_PO]);
}
PERL_STATIC_INLINE U16
S_fields_ix(SV* obj) {
    FIELDS_OBJ_ASSERT;
    return (U16)SvUVX(AvARRAY(obj)[FIELDS_INDEX_IX]);
}
PERL_STATIC_INLINE HV*
S_fields_class(SV* obj) {
    FIELDS_OBJ_ASSERT;
    return (HV*)(AvARRAY(obj)[FIELDS_INDEX_CLASS]);
}
PERL_STATIC_INLINE SV*
S_fields_obj(SV* obj) {
    FIELDS_OBJ_ASSERT;
    return AvARRAY(obj)[FIELDS_INDEX_OBJ];
}
/* Methods for a fields object, representing a class fields
   definition via has, and a runtime object SV value. */
PERL_STATIC_INLINE
SV * S_fields_objcheck(SV* obj) {
    SV *rv;
    if (UNLIKELY(!obj || !SvROK(obj) ||
                 !(SvFLAGS((rv = SvRV(obj))) & SVs_OBJECT) ||
                 !HvNAME(SvSTASH(rv)) ||
                 strNEc(HvNAME_NN(SvSTASH(rv)), "fields")))
	return NULL;
    else
        return rv;
}
XS(XS_fields_name);
XS(XS_fields_name)
{
    dXSARGS;
    SV *obj;
    if ( items != 1 || !(obj = S_fields_objcheck(ST(0))) ) {
	croak_xs_usage(cv, "fields object");
    }
    {
        PADOFFSET po = S_fields_po(obj);
        PADNAME *pn  = PAD_COMPNAME(po);
        ST(0) = sv_2mortal(newSVpvn_flags(PadnamePV(pn), PadnameLEN(pn),
                                          PadnameUTF8(pn) ? SVf_UTF8 : 0));
        XSRETURN(1);
    }
}
XS(XS_fields_package);
XS(XS_fields_package)
{
    dXSARGS;
    SV *obj;
    if ( items != 1 || !(obj = S_fields_objcheck(ST(0))) ) {
	croak_xs_usage(cv, "fields object");
    }
    {
        HV *klass = S_fields_class(obj);
        ST(0) = sv_2mortal(newSVhek(HvNAME_HEK(klass)));
        XSRETURN(1);
    }
}
XS(XS_fields_const);
XS(XS_fields_const)
{
    dXSARGS;
    SV *obj;
    if ( items != 1 || !(obj = S_fields_objcheck(ST(0))) ) {
	croak_xs_usage(cv, "fields object");
    }
    if (AvFILLp(obj) < FIELDS_INDEX_OBJ) {
        PADOFFSET po = S_fields_po(obj);
        PADNAME *pn  = PAD_COMPNAME(po);
        ST(0) = PadnameCONST(pn) ? &PL_sv_yes : &PL_sv_no;
    } else {
        U16 ix    = S_fields_ix(obj);
        SV *avref = S_fields_obj(obj);
        SV *sv    = AvARRAY(SvRV(avref))[ix];
        ST(0)     = SvREADONLY(sv) ? &PL_sv_yes : &PL_sv_no;
    }
}
XS(XS_fields_type);
XS(XS_fields_type)
{
    dXSARGS;
    SV *obj;
    if ( items != 1 || !(obj = S_fields_objcheck(ST(0))) ) {
	croak_xs_usage(cv, "fields object");
    }
    {
        PADOFFSET po = S_fields_po(obj);
        HV *klass = PAD_COMPNAME_TYPE(po);
        ST(0) = klass ? sv_2mortal(newSVhek(HvNAME_HEK(klass))) : &PL_sv_undef;
        XSRETURN(1);
    }
}
/* Those only from $obj->fields, not class->fields */
XS(XS_fields_get_value);
XS(XS_fields_get_value)
{
    dXSARGS;
    SV *obj;
    if ( items != 1 || !(obj = S_fields_objcheck(ST(0))) )
	croak_xs_usage(cv, "fields object");
    if (AvFILLp(obj) < FIELDS_INDEX_OBJ) {
	croak_xs_usage(cv, "fields object of object");
    }
    {
        U16 ix     = S_fields_ix(obj);
        SV *avref  = S_fields_obj(obj);
        ST(0) = AvARRAY(SvRV(avref))[ix];
        XSRETURN(1);
    }
}
XS(XS_fields_set_value);
XS(XS_fields_set_value)
{
    dXSARGS;
    SV *obj;
    if ( items != 2 || !(obj = S_fields_objcheck(ST(0))) )
	croak_xs_usage(cv, "fields object");
    if (AvFILLp(obj) < FIELDS_INDEX_OBJ) {
	croak_xs_usage(cv, "fields object of object");
    }
    {
        U16 ix     = S_fields_ix(obj);
        SV *avref  = S_fields_obj(obj);
        AvARRAY(SvRV(avref))[ix] = ST(1);
        XSRETURN(1);
    }
}

#include "vutil.h"
#include "vxs.inc"

struct xsub_details {
    const char *name;
    XSUBADDR_t xsub;
    const char *proto;
};

static const struct xsub_details details[] = {
    {"UNIVERSAL::isa", XS_UNIVERSAL_isa, NULL},
    {"UNIVERSAL::can", XS_UNIVERSAL_can, NULL},
    {"UNIVERSAL::DOES", XS_UNIVERSAL_DOES, NULL},
#define VXS_XSUB_DETAILS
#include "vxs.inc"
#undef VXS_XSUB_DETAILS
    {"utf8::is_utf8", XS_utf8_is_utf8, NULL},
    {"utf8::valid", XS_utf8_valid, NULL},
    {"utf8::encode", XS_utf8_encode, NULL},
    {"utf8::decode", XS_utf8_decode, NULL},
    {"utf8::upgrade", XS_utf8_upgrade, NULL},
    {"utf8::downgrade", XS_utf8_downgrade, NULL},
    {"utf8::native_to_unicode", XS_utf8_native_to_unicode, NULL},
    {"utf8::unicode_to_native", XS_utf8_unicode_to_native, NULL},
    {"Internals::SvREADONLY", XS_Internals_SvREADONLY, "\\[$%@];$"},
    {"Internals::HvCLASS", XS_Internals_HvCLASS, "\\[$%];$"},
    {"Internals::SvREFCNT", XS_Internals_SvREFCNT, "\\[$%@];$"},
    {"Internals::hv_clear_placeholders", XS_Internals_hv_clear_placehold, "\\%"},
    {"constant::_make_const", XS_constant__make_const, "\\[$@]"},
    {"PerlIO::get_layers", XS_PerlIO_get_layers, "*;@"},
    {"re::is_regexp", XS_re_is_regexp, "$"},
    {"re::regname", XS_re_regname, ";$$"},
    {"re::regnames", XS_re_regnames, ";$"},
    {"re::regnames_count", XS_re_regnames_count, ""},
    {"re::regexp_pattern", XS_re_regexp_pattern, "$"},
    {"Mu::new", XS_Mu_new, "$;@"},
    {"Mu::CREATE", XS_Mu_CREATE, "$"},
    {"Mu::fields", XS_Mu_fields, "$"},
    {"fields::name", XS_fields_name, "$"},
    {"fields::package", XS_fields_package, "$"},
    {"fields::const", XS_fields_const, "$"},
    {"fields::type", XS_fields_type, "$"},
    {"fields::get_value", XS_fields_get_value, "$"},
    {"fields::set_value", XS_fields_set_value, "$$"},
};

STATIC OP*
optimize_out_native_convert_function(pTHX_ OP* entersubop,
                                           GV* namegv,
                                           SV* protosv)
{
    /* Optimizes out an identity function, i.e., one that just returns its
     * argument.  The passed in function is assumed to be an identity function,
     * with no checking.  This is designed to be called for utf8_to_native()
     * and native_to_utf8() on ASCII platforms, as they just return their
     * arguments, but it could work on any such function.
     *
     * The code is mostly just cargo-culted from Memoize::Lift */

    OP *pushop, *argop;
    OP *parent;
    SV* prototype = newSVpvs("$");

    PERL_UNUSED_ARG(protosv);

    assert(entersubop->op_type == OP_ENTERSUB);

    entersubop = ck_entersub_args_proto(entersubop, namegv, prototype);
    parent = entersubop;

    SvREFCNT_dec(prototype);

    pushop = cUNOPx(entersubop)->op_first;
    if (! OpHAS_SIBLING(pushop)) {
        parent = pushop;
        pushop = cUNOPx(pushop)->op_first;
    }
    argop = OpSIBLING(pushop);

    /* Carry on without doing the optimization if it is not something we're
     * expecting, so continues to work */
    if (   ! argop
        || ! OpHAS_SIBLING(argop)
        ||   OpHAS_SIBLING(OpSIBLING(argop))
    ) {
        return entersubop;
    }

    /* cut argop from the subtree */
    (void)op_sibling_splice(parent, pushop, 1, NULL);

    op_free(entersubop);
    return argop;
}

void
Perl_boot_core_UNIVERSAL(pTHX)
{
    static const char file[] = __FILE__;
    const struct xsub_details *xsub = details;
    const struct xsub_details *end = C_ARRAY_END(details);
    /* pre-extend internals stashes to avoid splits from small */
    hv_ksplit(gv_stashpvs("version", GV_ADD), 64);
    hv_ksplit(gv_stashpvs("utf8", GV_ADD), 16);
    /*hv_ksplit(gv_stashpvs("Mu", GV_ADD), 32);*/

    do {
	newXS_flags(xsub->name, xsub->xsub, file, xsub->proto, 0);
    } while (++xsub < end);

#ifndef EBCDIC
    { /* On ASCII platforms these functions just return their argument, so can
         be optimized away */

        CV* to_native_cv = get_cvs("utf8::unicode_to_native", 0);
        CV* to_unicode_cv = get_cvs("utf8::native_to_unicode", 0);

        assert(to_native_cv); assert(to_unicode_cv);
        cv_set_call_checker_flags(to_native_cv,
                            optimize_out_native_convert_function,
                            (SV*) to_native_cv, 0);
        cv_set_call_checker_flags(to_unicode_cv,
                            optimize_out_native_convert_function,
                            (SV*) to_unicode_cv, 0);
    }
#endif

    /* Providing a Regexp::DESTROY fixes #21347. See test in t/op/ref.t  */
    {
	CV * const cv =
	    newCONSTSUB(get_hvs("Regexp::", GV_ADD), "DESTROY", NULL);
	char ** cvfile = &CvFILE(cv);
	char * oldfile = *cvfile;
	CvDYNFILE_off(cv);
	*cvfile = (char *)file;
	Safefree(oldfile);
    }
}

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
