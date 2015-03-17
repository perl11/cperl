/* XSLoader.c - XSLoader.pm converted to c to reuse DynaLoader code
 *
 * This was previously in dist/XSLoader as external module, but maintained
 * by p5p.
 * So far it's no standalone .c file, it is included into
 * DynaLoader.c, dlboot.c, dlutils.c.
 *
 * Copyright (C) 2015 cPanel Inc
 * Licensed under the same terms as Perl itself.
 */

/* A DynaLoader::bootstrap variant which takes the packagename name from caller() */
XS(XS_XSLoader_load) {
    dXSARGS;
    HV *stash;
    SV *module = NULL, *boots;
    CV *bootc;

    if (items < 1) {
      const PERL_CONTEXT *cx = caller_cx(0, NULL);
      if (cx && SvTYPE(CopSTASH(cx->blk_oldcop)) == SVt_PVHV) {
        stash = CopSTASH(cx->blk_oldcop);
        module = newSVpvn_flags(HvNAME(stash), HvNAMELEN(stash), HvNAMEUTF8(stash));
        DLDEBUG(2,PerlIO_printf(Perl_debug_log, "XSLoader::load from caller '%s'\n", HvNAME(stash)));
      }
      else {
        Perl_die(aTHX_ "Missing caller context in XSLoader::load. No package found.\n");
      }
    }
    else {
      DLDEBUG(2,PerlIO_printf(Perl_debug_log, "XSLoader::load '%s' %d args\n", TOPpx, items));
      module = TOPs;
    }

    boots = pv_copy(module);
    sv_catpvs(boots, "::bootstrap");
    if ((bootc = get_cv(SvPVx_nolen_const(boots), 0))) {
      DLax("goto &boots");
      PUSHMARK(SP - items); /* goto &$boots */
      XSRETURN(call_sv(MUTABLE_SV(bootc), GIMME));
    }
    if (!module) {
      DLax("goto &dl::bootstrap_inherit");
      PUSHMARK(SP - items);
      XSRETURN(call_pv("DynaLoader::bootstrap_inherit", GIMME));
    }
    /*
    my ($caller, $modlibname) = caller();
    XXX and now switch over to DynaLoader
    */
}

XS(XS_XSLoader_load_file) {
}

XS(XS_XSLoader_bootstrap_inherit) {
    dXSARGS;

    DLDEBUG(2,PerlIO_printf(Perl_debug_log, "XSLoader::bootstrap_inherit '%s' %d args\n", TOPpx, items));
    if (items < 1 || !SvPOK(TOPs))
        Perl_die(aTHX_ "Usage: XSLoader::bootstrap_inherit($packagename [ ,$VERSION ])\n");
    PUSHMARK(SP - items);
    DLax("inherit");
    XSRETURN(call_pv("DynaLoader::bootstrap_inherit", GIMME));
}
