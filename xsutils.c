/*    xsutils.c
 *
 *    Copyright (C) 1999, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008
 *    by Larry Wall and others
 *    Copyright (C) 2015 cPanel Inc
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

/*
 * 'Perilous to us all are the devices of an art deeper than we possess
 *  ourselves.'                                            --Gandalf
 *
 *     [p.597 of _The Lord of the Rings_, III/xi: "The Palantír"]
 */

#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#define PERL_IN_XSUTILS_C
#include "perl.h"
#include "XSUB.h"

/* public XS package methods */
/* -- converted to XS */
PERL_CALLCONV void XS_strict_bits(pTHX_ CV *cv);
PERL_CALLCONV void XS_strict_import(pTHX_ CV *cv);
PERL_CALLCONV void XS_strict_unimport(pTHX_ CV *cv);


/*
 * Note that only ${pkg}::bootstrap definitions should go here.
 * This helps keep down the start-up time, which is especially
 * relevant for users who don't invoke any features which are
 * (partially) implemented here.
 *
 * The various bootstrap definitions can take care of doing
 * package-specific newXS() calls.  Since the layout of the
 * bundled *.pm files is in a version-specific directory,
 * version checks in these bootstrap calls are optional.
 */

static const char file[] = __FILE__;

/* Boot the cperl builtins */

PERL_STATIC_INLINE void
xs_incset(pTHX_ const char *const unixname, const STRLEN unixlen, SV* xsfile)
{
    HV *inchv = GvHVn(PL_incgv);
#if 0
    SV** const svp = hv_fetch(inchv, unixname, unixlen, 0);
    if (!svp)
#endif
    (void)hv_store(inchv, unixname, unixlen, SvREFCNT_inc_simple_NN(xsfile), 0);
}

static void
set_version(pTHX_ const char *name, STRLEN nlen, const char *strval, STRLEN plen, NV nvval)
{
    SV* ver = GvSV(gv_add_by_type(gv_fetchpvn(name, nlen, GV_ADD, SVt_PVNV),
                                  SVt_PVNV));
    SvREADONLY_off(ver);
    SvUPGRADE(ver, SVt_PVNV);
    SvPVX(ver) = SvGROW(ver, plen+1);
    Move(strval, SvPVX(ver), plen, char);
    SvCUR_set(ver, plen);
    SvNVX(ver) = nvval;
    SvFLAGS(ver) |= (SVf_NOK|SVf_POK|SVf_READONLY|SVp_NOK|SVp_POK);
}

#ifdef USE_CPERL
#include "feature.h"

/* internal only */

/*
 * Set non-experimental/stable features for the compiler cop, to
 * be able to skip the use feature 'lexical_subs', 'signatures';
 * no warnings 'experimental'; nonsense on non-conflicting code.
 * Note that currently run-time still needs these features and no warnings.
 *
 * Initialize coretypes, the type inferencer and checker.
 * Well, type checks probably only with use types;
 * but the inferencer, yes.
 */

static void boot_core_cperl(pTHX) {
    const char he_name1[] = "feature_signatures";
    const char he_name2[] = "feature_lexsubs";
    SV* on = newSViv(1);

    /* use feature "signatures";
       i.e. $^H{$feature{signatures}} = 1; */
    /* This broke CM-364 by nasty side-effect. HINT_LOCALIZE_HH was added to fix
       strtable global destruction issues with wrong refcounts.
       So we get now only signatures and lexsubs for free.
    PL_hints |= HINT_LOCALIZE_HH | (FEATURE_BUNDLE_515 << HINT_FEATURE_SHIFT);
    */
    CopHINTHASH_set(&PL_compiling,
        cophh_store_pvn(CopHINTHASH_get(&PL_compiling), he_name1, sizeof(he_name1)-1, 0,
            on, 0));
    CopHINTHASH_set(&PL_compiling,
        cophh_store_pvn(CopHINTHASH_get(&PL_compiling), he_name2, sizeof(he_name2)-1, 0,
            on, 0));
    SvREFCNT(on) = 2;
}

#endif

static void
boot_strict(pTHX_ SV *xsfile)
{
    set_version(STR_WITH_LEN("strict::VERSION"), STR_WITH_LEN("1.10c"), 1.10);

    newXS("strict::bits",	XS_strict_bits,		file);
    newXS("strict::import",	XS_strict_import,	file);
    newXS("strict::unimport",	XS_strict_unimport,	file);
    xs_incset(aTHX_ STR_WITH_LEN("strict.pm"), xsfile);
}

void
Perl_boot_core_xsutils(pTHX)
{
    SV* xsfile = newSVpv_share(__FILE__, 0);

    /* static internal builtins */
    boot_strict(aTHX_ xsfile);

#if 0
    boot_attributes(aTHX_ xsfile);
    boot_Carp(aTHX_ xsfile);

    /* static_xs: not with miniperl */
    boot_Exporter(aTHX_ xsfile);
    boot_DynaLoader("DynaLoader");
    xs_incset(aTHX_ STR_WITH_LEN("DynaLoader.pm"), xsfile);

    /* shared xs: generated external modules without .pm */
    newXS("warnings::bootstrap",	XS_warnings_bootstrap,	file);
    newXS("Config::bootstrap",		XS_Config_bootstrap,	file);
    newXS("unicode::bootstrap",		XS_unicode_bootstrap,	file);
    xs_incset(aTHX_ STR_WITH_LEN("warnings.pm"),   xsfile);
    xs_incset(aTHX_ STR_WITH_LEN("Config.pm"),     xsfile);
    xs_incset(aTHX_ STR_WITH_LEN("utf8_heavy.pl"), xsfile);
#endif

#ifdef USE_CPERL
    boot_core_cperl(aTHX);
#endif
}

/*
   F<strict.pm> converted to a builtin
*/

/* perl.h */
/* TODO: use strict "names" */
#define HINT_ALL_STRICTS (HINT_STRICT_REFS      \
        | HINT_STRICT_SUBS                      \
        | HINT_STRICT_VARS)
/* 3 EXPLICIT bits used only once in use >= v5.11 (on) vs use <= v5.10 (off).
   TODO:
   This needs to be replaced by a single bit to denote argless import vs
   argful import. We need this to support strict "names" CM-327.
*/
#define HINT_ALL_EXPLICIT_STRICTS (HINT_EXPLICIT_STRICT_REFS \
        | HINT_EXPLICIT_STRICT_SUBS                      \
        | HINT_EXPLICIT_STRICT_VARS)

/* Needed by B::Deparse and vars */
XS(XS_strict_bits)
{
    dVAR;
    dXSARGS;
    UV bits = 0;
    int i;

    for (i=0; i<items; i++) {
        SV *pv = ST(i);
        char *name;
        if (!SvPOK(pv)) {
            Perl_croak(aTHX_ "Unknown 'strict' tag(s) ");
        }
        name = SvPVX(pv);
        if (strEQ(name, "refs"))
            bits |= HINT_STRICT_REFS;
        else if (strEQ(name, "subs"))
            bits |= HINT_STRICT_SUBS;
        else if (strEQ(name, "vars"))
            bits |= HINT_STRICT_VARS;
        else /* Maybe join all the wrong names. or not */
            Perl_croak(aTHX_ "Unknown 'strict' tag(s) '%s'", name);
    }
    XSRETURN_UV(bits);
}

/*
  See L<strict>
*/
XS(XS_strict_import)
{
    dVAR;
    dXSARGS;
    int i;

    if (items == 1) {
        PL_hints |= (HINT_ALL_STRICTS | HINT_ALL_EXPLICIT_STRICTS);
    } else {
        for (i=1; i<items; i++) {
            SV *pv = ST(i);
            char *name;
            if (!SvPOK(pv)) {
                Perl_croak(aTHX_ "Unknown 'strict' tag(s) ");
            }
            name = SvPVX(pv);
            if (strEQ(name, "refs"))
                PL_hints |= HINT_STRICT_REFS | HINT_EXPLICIT_STRICT_REFS;
            else if (strEQ(name, "subs"))
                PL_hints |= HINT_STRICT_SUBS | HINT_EXPLICIT_STRICT_SUBS;
            else if (strEQ(name, "vars"))
                PL_hints |= HINT_STRICT_VARS | HINT_EXPLICIT_STRICT_VARS;
            else /* Maybe join all the wrong names. or not */
                Perl_croak(aTHX_ "Unknown 'strict' tag(s) '%s'", name);
        }
    }
    XSRETURN_EMPTY;
}

/*
  See L<strict>
*/
XS(XS_strict_unimport)
{
    dVAR;
    dXSARGS;
    int i;

    if (items == 1) {
        PL_hints &= ~HINT_ALL_STRICTS;
        PL_hints |=  HINT_ALL_EXPLICIT_STRICTS;
    } else {
        for (i=1; i<items; i++) {
            SV *pv = ST(i);
            char *name;
            if (!SvPOK(pv)) {
                Perl_croak(aTHX_ "Unknown 'strict' tag(s) ");
            }
            name = SvPVX(pv);
            if (strEQ(name, "refs"))
                PL_hints &= ~(HINT_STRICT_REFS | HINT_EXPLICIT_STRICT_REFS);
            else if (strEQ(name, "subs"))
                PL_hints &= ~(HINT_STRICT_SUBS | HINT_EXPLICIT_STRICT_SUBS);
            else if (strEQ(name, "vars"))
                PL_hints &= ~(HINT_STRICT_VARS | HINT_EXPLICIT_STRICT_VARS);
            else /* Maybe join all the wrong names. or not */
                Perl_croak(aTHX_ "Unknown 'strict' tag(s) '%s'", name);
        }
    }
    XSRETURN_EMPTY;
}

/*
 * Local variables:
 * c-indentation-style: bsd
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 *
 * ex: set ts=8 sts=4 sw=4 et:
 */
