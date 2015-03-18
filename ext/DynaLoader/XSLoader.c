/* XSLoader.c - XSLoader.pm converted to c, reusing DynaLoader code
 *
 * This was previously in dist/XSLoader as external module, but
 * maintained by p5p.
 * So far it's not a standalone .c file, it is included with
 * DynaLoader.c, dlboot.c, dlutils.c into one DynaLoader.o
 *
 * Copyright (C) 2015 cPanel Inc
 * Licensed under the same terms as Perl itself.
 */

/* XSLoader::load - A DynaLoader::bootstrap variant which takes the
                    optional packagename from caller()
   Marked as CvCALLER - a new feature for XSUBs, needed also for Carp.
   Reuses many functions from DynaLoader */
XS(XS_XSLoader_load) {
    dVAR; dXSARGS;
    HV *stash;
    SV *module = NULL, *modlibname = NULL, *file = NULL;
    CV *bootc;
    AV *modparts;
    SV *modfname, *modpname, *boots;

    if (items < 1) {
        const PERL_CONTEXT *cx = caller_cx(0, NULL);
        DLax("load()");
        if (cx && SvTYPE(CopSTASH(cx->blk_oldcop)) == SVt_PVHV) {
            stash = CopSTASH(cx->blk_oldcop);
            module = newSVpvn_flags(HvNAME(stash), HvNAMELEN(stash), HvNAMEUTF8(stash));
            modlibname = newSVpv(OutCopFILE(cx->blk_oldcop), 0);
            DLDEBUG(2,PerlIO_printf(Perl_debug_log, "XSLoader::load from caller '%s', '%s'\n",
                    HvNAME(stash), SvPVX(modlibname)));
        }
        else {
            Perl_die(aTHX_ "Missing caller context in XSLoader::load. No package found.\n");
        }
    }
    else {
        DLDEBUG(2,PerlIO_printf(Perl_debug_log, "XSLoader::load '%s' %d args\n",
                TOPpx, items));
        DLax("load args");
        module = TOPs;
#if 1
        /* XXX HACK! */
        if (SvPOK(module)) {
            const char *modulename = SvPVX(module);
            if (modulename[0] >= '0' && modulename[0] <= '9' && SvPOK(ST(-1))) {
                DLDEBUG(1,PerlIO_printf(Perl_debug_log,
                        "!! ax corruption. wrong package \"%s\"\n",
                        modulename));
                goto hack;
            }
        }
        else if (SvNOK(module) && SvPOK(ST(-1))) {
            DLDEBUG(1,PerlIO_printf(Perl_debug_log, "!! ax corruption %g\n",
                    TOPn));
        hack:
            ax--;
            sp--;
            MARK--;
            SPAGAIN;
            module = ST(0);
            DLDEBUG(1,PerlIO_printf(Perl_debug_log, "!! module %s\n",
                    SvPVX(module)));
        }
#endif
    }

    boots = pv_copy(module);
    sv_catpvs(boots, "::bootstrap");
    if ((bootc = get_cv(SvPV_nolen_const(boots), 0))) {
      DLax("goto &boots");
      PUSHMARK(MARK); /* goto &$boots */
      XSRETURN(call_sv(MUTABLE_SV(bootc), GIMME));
    }
    if (!module) {
      xsl_bsinherit:
        DLax("goto &dl::bs_inherit");
        PUSHMARK(MARK);
        XSRETURN(call_pv("DynaLoader::bootstrap_inherit", GIMME));
    }
    if (!modlibname) {
        DLax("goto &dl::bootstrap_inherit");
        PUSHMARK(MARK);
        XSRETURN(call_pv("DynaLoader::bootstrap", GIMME));
    }
    modparts = dl_split_modparts(aTHX_ module);
    modfname = AvARRAY(modparts)[AvFILLp(modparts)];
    modpname = dl_construct_modpname(aTHX_ modparts);
    DLDEBUG(3,PerlIO_printf(Perl_debug_log, "modpname (%s) => '%s'\n",
            av_tostr(aTHX_ modparts), SvPVX(file)));
    file = modlibname;
    sv_catpv(file, "auto/");
    sv_catsv(file, modpname);
    sv_catpv(file, "/");
    sv_catsv(file, modfname);
    sv_catpv(file, DLEXT);
    SvREFCNT_inc_NN(modfname);
    SvREFCNT_dec(modparts);

    /* Note: No dl_expand support with XSLoader */
    /* TODO no .bs support */
    if (fn_exists(SvPVX(file))) {
        DLDEBUG(3,PerlIO_printf(Perl_debug_log, " found %s\n", SvPVX(file)));
    } else {
        goto xsl_bsinherit;
    }
    if ((items = dl_load_file(aTHX_ file, module, GIMME))) {
        XSRETURN(items);
    } else {
        XSRETURN_UNDEF;
    }
}

/* XSLoader::load_file - A DynaLoader variant optimized when you already know
   the path of the shared library. */
XS(XS_XSLoader_load_file) {
    dVAR; dXSARGS;
    SV *file, *module;

    if (items < 2)
        die("Usage: XSLoader::load_file($module, $file)\n");
    module = POPs;
    file = POPs;

    if (fn_exists(SvPVX(file))) {
        DLDEBUG(3,PerlIO_printf(Perl_debug_log, " found %s\n", SvPVX(file)));
    } else {
        die("Error: load_file $file not found\n");
    }
    if ((items = dl_load_file(aTHX_ file, module, GIMME))) {
        XSRETURN(items);
    } else {
        XSRETURN_UNDEF;
    }
}

/* XSLoader::bootstrap_inherit - Just forwards to the DynaLoader method.
   No special caller information is searched for */
XS(XS_XSLoader_bootstrap_inherit) {
    dVAR; dXSARGS;

    DLDEBUG(2,PerlIO_printf(Perl_debug_log, "XSLoader::bootstrap_inherit '%s' %d args\n",
            TOPpx, items));
    if (items < 1 || !SvPOK(TOPs))
        Perl_die(aTHX_ "Usage: XSLoader::bootstrap_inherit($packagename [,$VERSION])\n");
    PUSHMARK(MARK);
    DLax("inherit");
    PUTBACK;
    XSRETURN(call_pv("DynaLoader::bootstrap_inherit", GIMME));
}
