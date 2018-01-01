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

#undef WINPATHSEP
#if defined(WIN32) || defined(OS2) || defined(__CYGWIN__) || defined(DOSISH) \
    || defined(__SYMBIAN32__) || defined(__amigaos4__)
#  define WINPATHSEP
#endif

/* A DynaLoader::bootstrap variant which takes the packagename name from caller() */
XS(XS_XSLoader_load) {
    dVAR; dXSARGS;
    HV *stash = CopSTASH(PL_curcop);
    SV *module = NULL, *file = NULL;
    char *modlibname = NULL;
    CV *bootc;
    AV *modparts;
    SV *modfname, *modpname, *boots;
    int modlibutf8 = 0;

    ENTER;
    if (items < 1) {
        modlibutf8 = HvNAMEUTF8(stash);
        module = newSVpvn_flags(HvNAME(stash), HvNAMELEN(stash), modlibutf8);
        modlibname = OutCopFILE(PL_curcop);
        DLDEBUG(2,PerlIO_printf(Perl_debug_log, "XSLoader::load from caller '%s', '%s'\n",
                HvNAME(stash), modlibname));
        if (modlibname && strEQc(modlibname, "-e"))
            modlibname = NULL;
    }
    else {
        module = ST(0);
        DLDEBUG(2,PerlIO_printf(Perl_debug_log, "XSLoader::load '%s' %d args\n",
                                SvPVX(module), (int)items));
        if (!SvPOK(module))
            Perl_die(aTHX_ "Usage: XSLoader::load([ $packagename [,$VERSION]])\n");
        modlibutf8 = SvUTF8(module);
    }

    boots = pv_copy(module);
    sv_catpvs(boots, "::bootstrap");
    if ((bootc = get_cv(SvPV_nolen_const(boots), 0))) {
        ENTER; SAVETMPS;
        PUSHMARK(MARK); /* goto &$boots */
        PUTBACK;
        items = call_sv(MUTABLE_SV(bootc), GIMME);
        SPAGAIN;
        FREETMPS; LEAVE;
        LEAVE;
        XSRETURN(items);
    }
    if (!modlibname) {
        modlibname = OutCopFILE(PL_curcop);
        if (memEQ(modlibname, "(eval ", 6)) /* This catches RT #115808 */
            modlibname = NULL;
    }
    if (!module) {
        ENTER; SAVETMPS;
        PUSHMARK(MARK);
        PUTBACK;
        items = call_pv("XSLoader::bootstrap_inherit", GIMME);
        SPAGAIN;
        PUTBACK; FREETMPS; LEAVE;
        LEAVE;
        XSRETURN(items);
    }
    modparts = dl_split_modparts(aTHX_ module);
    modfname = AvARRAY(modparts)[AvFILLp(modparts)];
    modpname = dl_construct_modpname(aTHX_ modparts);
    DLDEBUG(3,PerlIO_printf(Perl_debug_log, "  modpname (%s) => '%s','%s'\n",
                            av_tostr(aTHX_ modparts), modlibname, SvPVX(modpname)));
    file = modlibname ? newSVpvn_flags(modlibname, strlen(modlibname), modlibutf8)
                      : newSVpvs("");

    /* now step back @modparts+1 times: .../lib/Fcntl.pm => .../
       my $c = () = split(/::/,$caller,-1);
       $modlibname =~ s,[\\/][^\\/]+$,, while $c--;    # Q&D basename */
    if (items >= 1) {
        SV *caller = newSVpvn_flags(HvNAME(stash), HvNAMELEN(stash), modlibutf8);
        modparts = dl_split_modparts(aTHX_ caller);
        DLDEBUG(3,PerlIO_printf(Perl_debug_log, "  caller %s => (%s)\n",
                                SvPVX(caller), av_tostr(aTHX_ modparts)));
    }
    {
        SSize_t c = AvFILL(modparts) + 1;
        SSize_t i = SvCUR(file);
        char   *s = SvPVX_mutable(file);
        if (!i || !c)
            goto not_found;
        if (c==1 && memEQc(s, "(eval "))
            goto not_found;
        s += i-1;
        for (; c>0 && i>0 && *s; s--, i--) {
            if (*s == '/'
#ifdef WINPATHSEP
                || *s == '\\'
#endif
                ) {
                c--;
                if (c==0) {
                    s[1] = 0;
                    SvCUR_set(file, i); /* ensures ending / */
                    break;
                }
            }
        }

        /* Must be absolute or in @INC. See RT #115808
         * Someone may have a #line directive that changes the file name, or
         * may be calling XSLoader::load from inside a string eval.  We cer-
         * tainly do not want to go loading some code that is not in @INC,
         * as it could be untrusted.
         *
         * We could just fall back to DynaLoader here, but then the rest of
         * this function would go untested in the perl core, since all @INC
         * paths are relative during testing.  That would be a time bomb
         * waiting to happen, since bugs could be introduced into the code.
         *
         * So look through @INC to see if $modlibname is in it.  A rela-
         * tive $modlibname is not a common occurrence, so this block is
         * not hot code.
         */
        s = SvPVX_mutable(file);
        if (*s != '/'
#ifdef WINPATHSEP
            && *s != '\\'
            && !(*(s+1) && (*(s+1) == ':') && (*s >= 'A' && *s >= 'Z'))
#endif
            ) {
            /* but allow relative file if in @INC */
            c = SvCUR(file)-1;
            if (c<1) goto not_found;
            for (i=0; i<AvFILL(GvAV(PL_incgv)); i++) {
                SV * const dirsv = *av_fetch(GvAV(PL_incgv), i, TRUE);
                SvGETMAGIC(dirsv);
                /* ignore av and cv refs here. they will be caught later in DynaLoader */
                if (SvPOK(dirsv)
                    && SvCUR(dirsv) >= (Size_t)c
                    && memEQ(SvPVX(file), SvPVX(dirsv), c))
                    goto found;
            }
            goto not_found;
        }
        s = SvPVX_mutable(file) + SvCUR(file) - 1;
        /* And must end with /. Disallow "." in @INC for local XS libs */
        if (*s != '/'
#ifdef WINPATHSEP
            && *s != '\\'
#endif
            )
            goto not_found;
    }
  found:
    sv_catpv(file, "auto/");
    sv_catsv(file, modpname);
    sv_catpv(file, "/");
    sv_catsv(file, modfname);
    sv_catpv(file, DLEXT);

    /* Note: No dl_expand support with XSLoader */
    /* TODO no .bs support */
    if (fn_exists(SvPVX(file))) {
        DLDEBUG(3,PerlIO_printf(Perl_debug_log, "  found '%s'\n", SvPVX(file)));
    } else {
    not_found:
        DLDEBUG(3,PerlIO_printf(Perl_debug_log, "  not found '%s'\n", SvPVX(file)));
        ENTER; SAVETMPS;
        if (items < 1) {
            PUSHMARK(SP);
            XPUSHs(module);
        } else {
            PUSHMARK(MARK);
        }
        PUTBACK;
        SvREFCNT_dec(file);
        items = call_pv("XSLoader::bootstrap_inherit", GIMME);
        SPAGAIN;
        PUTBACK; FREETMPS; LEAVE;

        LEAVE;
        XSRETURN(items);
    }
    if ((items = dl_load_file(aTHX_ ax, file, module, GIMME))) {
        LEAVE;
        SvREFCNT_dec(file);
        XSRETURN(items);
    } else {
        LEAVE;
        SvREFCNT_dec(file);
        XSRETURN_UNDEF;
    }
}

XS(XS_XSLoader_load_file) {
    dVAR; dXSARGS;
    SV *file, *module;

    if (items < 2)
        die("Usage: XSLoader::load_file($module, $sofile)\n");
    ENTER; SAVETMPS;
    module = ST(0);
    file = ST(1);

    if (fn_exists(SvPVX(file))) {
        DLDEBUG(3,PerlIO_printf(Perl_debug_log, "  found %s\n", SvPVX(file)));
    } else {
        Perl_die(aTHX_ "Error: load_file %s not found\n", SvPVX(file));
    }
    PL_stack_sp--;
    if ((items = dl_load_file(aTHX_ ax, file, module, GIMME))) {
        FREETMPS; LEAVE;
        XSRETURN(items);
    } else {
        FREETMPS; LEAVE;
        XSRETURN_UNDEF;
    }
}

XS(XS_XSLoader_bootstrap_inherit) {
    dVAR; dXSARGS;

    DLDEBUG(2,PerlIO_printf(Perl_debug_log, "XSLoader::bootstrap_inherit '%s' %d args\n",
                            SvPVX(ST(0)), (int)items));
    if (items < 1 || !SvPOK(ST(0)))
        Perl_die(aTHX_ "Usage: XSLoader::bootstrap_inherit($packagename [,$VERSION])\n");
    ENTER; SAVETMPS;
    PUSHMARK(MARK);
    PUTBACK;
    if ((items = call_pv("DynaLoader::bootstrap_inherit", GIMME))) {
        FREETMPS; LEAVE;
        XSRETURN(items);
    } else {
        FREETMPS; LEAVE;
        XSRETURN_UNDEF;
    }
}
