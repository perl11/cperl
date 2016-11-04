#include <perl_libyaml.h>

static yaml_encoding_t
set_dumper_options(perl_yaml_dumper_t *);
static yaml_encoding_t
set_loader_options(perl_yaml_loader_t *);
static SV *
load_node(perl_yaml_loader_t *);
static SV *
load_mapping(perl_yaml_loader_t *, char *);
static SV *
load_sequence(perl_yaml_loader_t *);
static SV *
load_scalar(perl_yaml_loader_t *);
static SV *
load_alias(perl_yaml_loader_t *);
static SV *
load_scalar_ref(perl_yaml_loader_t *);
static SV *
load_regexp(perl_yaml_loader_t *);
static SV *
load_glob(perl_yaml_loader_t *);
static void
dump_prewalk(perl_yaml_dumper_t *, SV *);
static void
dump_document(perl_yaml_dumper_t *, SV *);
static void
dump_node(perl_yaml_dumper_t *, SV *);
static void
dump_hash(perl_yaml_dumper_t *, SV *, yaml_char_t *, yaml_char_t *);
static void
dump_array(perl_yaml_dumper_t *, SV *);
static void
dump_scalar(perl_yaml_dumper_t *, SV *, yaml_char_t *);
static void
dump_ref(perl_yaml_dumper_t *, SV *);
static void
dump_code(perl_yaml_dumper_t *, SV *);
static SV*
dump_glob(perl_yaml_dumper_t *, SV *);
static yaml_char_t *
get_yaml_anchor(perl_yaml_dumper_t *, SV *);
static yaml_char_t *
get_yaml_tag(SV *);
static int
append_output(void *sv, unsigned char *buffer, size_t size);
static int
yaml_perlio_read_handler(void *data, unsigned char *buffer, size_t size, size_t *size_read);
static int
yaml_perlio_write_handler(void *data, unsigned char *buffer, size_t size);

static SV *
fold_results(I32 count)
{
    dSP;
    SV *retval = &PL_sv_undef;

    if (count > 1) {
        /* convert multiple return items into a list reference */
        AV *av = newAV();
        SV *sv = &PL_sv_undef;
        I32 i;

        av_extend(av, count - 1);
        for(i = 1; i <= count; i++) {
            sv = POPs;
            if (SvOK(sv) && !av_store(av, count - i, SvREFCNT_inc(sv)))
                SvREFCNT_dec(sv);
        }
        PUTBACK;

        retval = sv_2mortal((SV *) newRV_noinc((SV *) av));

        if (!SvOK(sv) || sv == &PL_sv_undef) {
            /* if first element was undef, die */
            croak("%sCall error", ERRMSG);
        }
        return retval;

    }
    else {
        if (count)
            retval = POPs;
        PUTBACK;
        return retval;
    }
}

static SV *
call_coderef(SV *code, AV *args)
{
    dSP;
    SV **svp;
    I32 count = args ? av_len(args) : -1;
    I32 i;

    PUSHMARK(SP);
    for (i = 0; i <= count; i++) {
        if ((svp = av_fetch(args, i, FALSE))) {
            XPUSHs(*svp);
        }
    }
    PUTBACK;
    count = call_sv(code, G_ARRAY);
    SPAGAIN;

    return fold_results(count);
}

static SV *
find_coderef(const char *perl_var)
{
    SV *coderef;

    if ((coderef = get_sv(perl_var, FALSE))
        && SvROK(coderef)
        && SvTYPE(SvRV(coderef)) == SVt_PVCV)
        return coderef;

    return NULL;
}

/*
 * Piece together a parser/loader error message
 */
static char *
loader_error_msg(perl_yaml_loader_t *loader, char *problem)
{
    char *msg;
    if (!problem)
        problem = (char *)loader->parser.problem;
    if (loader->filename)
      msg = form("%s%swas found at document: %s",
                 LOADFILEERRMSG,
                 (problem ? form("The problem\n\n    %s\n\n", problem)
                          : "A problem "),
                 loader->filename
                 );
    else
      msg = form("%s%swas found at document: %d",
                 LOADERRMSG,
                 (problem ? form("The problem\n\n    %s\n\n", problem)
                          : "A problem "),
                 loader->document
                 );
    if (loader->parser.problem_mark.line ||
        loader->parser.problem_mark.column)
        msg = form("%s, line: %ld, column: %ld\n",
                   msg,
                   (long)loader->parser.problem_mark.line + 1,
                   (long)loader->parser.problem_mark.column + 1
                   );
    else if (loader->parser.problem_offset)
        msg = form("%s, offset: %ld\n", msg, (long)loader->parser.problem_offset);
    else
        msg = form("%s\n", msg);
    if (loader->parser.context)
        msg = form("%s%s at line: %ld, column: %ld\n",
                   msg,
                   loader->parser.context,
                   (long)loader->parser.context_mark.line + 1,
                   (long)loader->parser.context_mark.column + 1
        );

    return msg;
}

/*
 * Set loader options from global variables.
 */
static yaml_encoding_t
set_loader_options(perl_yaml_loader_t *loader)
{
    GV *gv;
    yaml_encoding_t result = YAML_ANY_ENCODING;

    /* As with YAML::Tiny. Default: strict Load */
    gv = gv_fetchpv("YAML::XS::NonStrict", GV_NOADD_NOINIT, SVt_PV);
    loader->parser.problem_nonstrict = gv && SvTRUE(GvSV(gv)) ? 1 : 0;
    loader->document = 0;
    loader->filename = NULL;

    if ((gv = gv_fetchpv("YAML::XS::Encoding", GV_NOADD_NOINIT, SVt_PV))
         && SvPOK(GvSV(gv)))
    {
        const char *enc = SvPVX_const(GvSV(gv));
        if (memEQs(enc, 3, "any"))
            yaml_parser_set_encoding(&loader->parser,
                                     (result = YAML_ANY_ENCODING));
        else if (memEQs(enc, 4, "utf8"))
            yaml_parser_set_encoding(&loader->parser, YAML_UTF8_ENCODING);
        else if (memEQs(enc, 7, "utf16le"))
            yaml_parser_set_encoding(&loader->parser,
                                     (result = YAML_UTF16LE_ENCODING));
        else if (memEQs(enc, 7, "utf16be"))
            yaml_parser_set_encoding(&loader->parser,
                                     (result = YAML_UTF16BE_ENCODING));
        else
            croak("Invalid $YAML::XS::Encoding %s. Valid: any, utf8, utf16le, utf16be", enc);
    }

    /* Safety options, with names from YAML::Syck. Default to 0 */
    gv = gv_fetchpv("YAML::XS::DisableCode", GV_NOADD_NOINIT, SVt_PV);
    loader->disable_code = (gv && SvTRUE(GvSV(gv)));

    gv = gv_fetchpv("YAML::XS::DisableBlessed", GV_NOADD_NOINIT, SVt_PV);
    loader->disable_blessed = (gv && SvTRUE(GvSV(gv)));

    return result;
}

static int
load_impl(perl_yaml_loader_t *loader)
{
    dXCPT;
    dXSARGS;
    SV *node;

    sp = mark;
    if (0 && (items || ax)) {} /* XXX Quiet the -Wall warnings for now. */

    /* Get the first event. Must be a STREAM_START */
    if (!yaml_parser_parse(&loader->parser, &loader->event))
        goto load_error;
    if (loader->event.type != YAML_STREAM_START_EVENT)
        croak("%sExpected STREAM_START_EVENT; Got: %d != %d",
            ERRMSG,
            loader->event.type,
            YAML_STREAM_START_EVENT
         );

    loader->anchors = (HV *)sv_2mortal((SV *)newHV());

  XCPT_TRY_START {

    /* Keep calling load_node until end of stream */
    while (1) {
        loader->document++;
        /* We are through with the previous event - delete it! */
        yaml_event_delete(&loader->event);
        if (!yaml_parser_parse(&loader->parser, &loader->event))
            goto load_error;
        if (loader->event.type == YAML_STREAM_END_EVENT)
            break;
        node = load_node(loader);
        /* We are through with the previous event - delete it! */
        yaml_event_delete(&loader->event);
        hv_clear(loader->anchors);
        if (! node)
            break;
        XPUSHs(sv_2mortal(node));
        if (!yaml_parser_parse(&loader->parser, &loader->event))
            goto load_error;
        if (loader->event.type != YAML_DOCUMENT_END_EVENT)
            croak("%sExpected DOCUMENT_END_EVENT", ERRMSG);
    }

    /* Make sure the last event is a STREAM_END */
    if (loader->event.type != YAML_STREAM_END_EVENT)
        croak("%sExpected STREAM_END_EVENT; Got: %d != %d",
            ERRMSG,
            loader->event.type,
            YAML_STREAM_END_EVENT
         );
    } XCPT_TRY_END

    XCPT_CATCH
    {
        yaml_parser_delete(&loader->parser);
        XCPT_RETHROW;
    }

    yaml_parser_delete(&loader->parser);
    PUTBACK;
    return 1;

load_error:
    croak("%s", loader_error_msg(loader, NULL));
    return 0;
}

/*
 * It takes a file or filename and turns it into 0 or more Perl objects.
 */
int
LoadFile(SV *sv_file)
{
    perl_yaml_loader_t loader;
    FILE *file = NULL;
    const char *fname;
    STRLEN len;
    int ret;

    yaml_parser_initialize(&loader.parser);
    (void)set_loader_options(&loader);

    if (SvROK(sv_file)) { /* pv mg or io or gv */
        SV *rv = SvRV(sv_file);

        if (SvTYPE(rv) == SVt_PVIO) {
            loader.perlio = IoIFP(rv);
            yaml_parser_set_input(&loader.parser,
                                  &yaml_perlio_read_handler,
                                  &loader);
        } else if (SvTYPE(rv) == SVt_PVGV && GvIO(rv)) {
            loader.perlio = IoIFP(GvIOp(rv));
            yaml_parser_set_input(&loader.parser,
                                  &yaml_perlio_read_handler,
                                  &loader);
        } else if (SvMAGIC(rv)) {
            mg_get(rv);
            fname = SvPV_const(rv, len);
            goto pv_load;
        } else if (SvAMAGIC(sv_file)) {
            fname = SvPV_const(sv_file, len);
            goto pv_load;
        } else {
            croak("Invalid argument type: ref of %u", SvTYPE(rv));
            return 0;
        }
    }
    else if (SvPOK(sv_file)) {
        fname = SvPV_const(sv_file, len);
    pv_load:
        file = fopen(fname, "rb");
        if (!file) {
            croak("Can't open '%s' for input", fname);
            return 0;
        }
        loader.filename = (char *)fname;
        yaml_parser_set_input_file(&loader.parser, file);
    } else if (SvTYPE(sv_file) == SVt_PVIO) {
        loader.perlio = IoIFP(sv_file);
        yaml_parser_set_input(&loader.parser,
                              &yaml_perlio_read_handler,
                              &loader);
    } else if (SvTYPE(sv_file) == SVt_PVGV
               && GvIO(sv_file)) {
        loader.perlio = IoIFP(GvIOp(sv_file));
        yaml_parser_set_input(&loader.parser,
                              &yaml_perlio_read_handler,
                              &loader);
    } else {
        croak("Invalid argument type: %u", SvTYPE(sv_file));
        return 0;
    }

    ret = load_impl(&loader);
    if (file)
        fclose(file);
    else if (SvTYPE(sv_file) == SVt_PVIO)
        PerlIO_close(IoIFP(sv_file));
    return ret;
}

/*
 * This is the main Load function.
 * It takes a yaml stream and turns it into 0 or more Perl objects.
 */
int
Load(SV *yaml_sv)
{
    perl_yaml_loader_t loader;
    const unsigned char *yaml_str;
    STRLEN yaml_len;

    yaml_str = (const unsigned char *)SvPV_const(yaml_sv, yaml_len);

    yaml_parser_initialize(&loader.parser);
    (void)set_loader_options(&loader);
    if (DO_UTF8(yaml_sv)) { /* overrides $YAML::XS::Encoding */
        loader.parser.encoding = YAML_UTF8_ENCODING;
    } /* else check the BOM. don't check for decoded utf8. */

    yaml_parser_set_input_string(
        &loader.parser,
        yaml_str,
        yaml_len
    );

    return load_impl(&loader);
}

/*
 * This is the main function for dumping any node.
 */
static SV *
load_node(perl_yaml_loader_t *loader)
{
    SV* return_sv = NULL;
    /* This uses stack, but avoids (severe!) memory leaks */
    yaml_event_t uplevel_event;

    uplevel_event = loader->event;

    /* Get the next parser event */
    if (!yaml_parser_parse(&loader->parser, &loader->event))
        goto load_error;

    /* These events don't need yaml_event_delete */
    /* Some kind of error occurred */
    if (loader->event.type == YAML_NO_EVENT)
        goto load_error;

    /* Return NULL when we hit the end of a scope */
    if (loader->event.type == YAML_DOCUMENT_END_EVENT ||
        loader->event.type == YAML_MAPPING_END_EVENT ||
        loader->event.type == YAML_SEQUENCE_END_EVENT)
    {
        /* restore the uplevel event, so it can be properly deleted */
        loader->event = uplevel_event;
        return return_sv;
    }

    /* The rest all need cleanup */
    switch (loader->event.type) {
        char *tag;

        /* Handle loading a mapping */
        case YAML_MAPPING_START_EVENT:
            tag = (char *)loader->event.data.mapping_start.tag;

            if (tag) {
                /* Handle mapping tagged as a Perl hard reference */
                if (strEQc(tag, TAG_PERL_REF)) {
                    return_sv = load_scalar_ref(loader);
                    break;
                }
                /* Handle mapping tagged as a Perl typeglob */
                if (strEQc(tag, TAG_PERL_GLOB)) {
                    return_sv = load_glob(loader);
                    break;
                }
            }

            return_sv = load_mapping(loader, NULL);
            break;

        /* Handle loading a sequence into an array */
        case YAML_SEQUENCE_START_EVENT:
            return_sv = load_sequence(loader);
            break;

        /* Handle loading a scalar */
        case YAML_SCALAR_EVENT:
            return_sv = load_scalar(loader);
            break;

        /* Handle loading an alias node */
        case YAML_ALIAS_EVENT:
            return_sv = load_alias(loader);
            break;

        default:
            croak("%sInvalid event '%d' at top level", ERRMSG, (int) loader->event.type);
    }

    yaml_event_delete(&loader->event);

    /* restore the uplevel event, so it can be properly deleted */
    loader->event = uplevel_event;

    return return_sv;

    load_error:
        croak("%s", loader_error_msg(loader, NULL));
}

/*
 * Load a YAML mapping into a Perl hash
 */
static SV *
load_mapping(perl_yaml_loader_t *loader, char *tag)
{
    SV *key_node;
    SV *value_node;
    HV *hash = newHV();
    SV *hash_ref = (SV *)newRV_noinc((SV *)hash);
    char *anchor = (char *)loader->event.data.mapping_start.anchor;

    if (!tag)
        tag = (char *)loader->event.data.mapping_start.tag;

    /* Store the anchor label if any */
    if (anchor)
      (void)hv_store(loader->anchors, anchor, strlen(anchor), SvREFCNT_inc(hash_ref), 0);

    /* Get each key string and value node and put them in the hash */
    while ((key_node = load_node(loader))) {
        assert(SvPOK(key_node));
        value_node = load_node(loader);
        (void)hv_store_ent(hash, sv_2mortal(key_node), value_node, 0);
    }

    /* Deal with possibly blessing the hash if the YAML tag has a class */
    if (tag && strEQc(tag, TAG_PERL_PREFIX "hash"))
        tag = NULL;
    if (tag && !loader->disable_blessed) {
        char *klass;
        const char *prefix = TAG_PERL_PREFIX "hash:";
        if (*tag == '!') {
            prefix = "!";
        }
        else if (strlen(tag) <= strlen(prefix) ||
                 ! strnEQ(tag, prefix, strlen(prefix)))
            croak("%s",
                loader_error_msg(loader, form("bad tag found for hash: '%s'", tag)));
        klass = tag + strlen(prefix);
        sv_bless(hash_ref, gv_stashpv(klass, TRUE));
    }

    return hash_ref;
}

/* Load a YAML sequence into a Perl array */
static SV *
load_sequence(perl_yaml_loader_t *loader)
{
    SV *node;
    AV *array = newAV();
    SV *array_ref = (SV *)newRV_noinc((SV *)array);
    char *anchor = (char *)loader->event.data.sequence_start.anchor;
    char *tag = (char *)loader->event.data.mapping_start.tag;
    if (anchor)
      (void)hv_store(loader->anchors, anchor, strlen(anchor), SvREFCNT_inc(array_ref), 0);
    while ((node = load_node(loader))) {
        av_push(array, node);
    }
    if (tag && strEQc(tag, TAG_PERL_PREFIX "array"))
        tag = NULL;
    if (tag && !loader->disable_blessed) {
        char *klass;
        char *prefix = (char*)TAG_PERL_PREFIX "array:";
        if (*tag == '!')
            prefix = (char*)"!";
        else if (strlen(tag) <= strlen(prefix) ||
                 ! strnEQ(tag, prefix, strlen(prefix)))
            croak("%s",
                loader_error_msg(loader, form("bad tag found for array: '%s'", tag)));
        klass = tag + strlen(prefix);
        sv_bless(array_ref, gv_stashpv(klass, TRUE));
    }
    return array_ref;
}

/* Load a YAML scalar into a Perl scalar */
static SV *
load_scalar(perl_yaml_loader_t *loader)
{
    SV *scalar;
    char *string = (char *)loader->event.data.scalar.value;
    STRLEN length = (STRLEN)loader->event.data.scalar.length;
    char *anchor = (char *)loader->event.data.scalar.anchor;
    char *tag = (char *)loader->event.data.scalar.tag;
    if (tag) {
        char *klass = NULL;
        char *prefix = (char*)TAG_PERL_PREFIX "regexp";
        if (strnEQ(tag, prefix, strlen(prefix)))
            return load_regexp(loader);
        prefix = (char*)TAG_PERL_PREFIX "scalar:";
        if (*tag == '!')
            prefix = (char*)"!";
        else if (strlen(tag) <= strlen(prefix)
                 || !strnEQ(tag, prefix, strlen(prefix)))
            croak("%sbad tag found for scalar: '%s'", ERRMSG, tag);
        if (!loader->disable_blessed) /* NULL class will not bless */
            klass = tag + strlen(prefix);
        scalar = sv_setref_pvn(newSV(0), klass, string, strlen(string));
        SvUTF8_on(scalar);
        return scalar;
    }

    if (loader->event.data.scalar.style == YAML_PLAIN_SCALAR_STYLE) {
        if (strEQc(string, "~"))
            return newSV(0);
        else if (strEQc(string, ""))
            return newSV(0);
        else if (strEQc(string, "null"))
            return newSV(0);
        else if (strEQc(string, "true"))
            return &PL_sv_yes;
        else if (strEQc(string, "false"))
            return &PL_sv_no;
    }

    scalar = newSVpvn(string, length);

    if (loader->event.data.scalar.style == YAML_PLAIN_SCALAR_STYLE && looks_like_number(scalar) ) {
        /* numify */
        SvIV_please(scalar);
    }

    (void)sv_utf8_decode(scalar);
    if (anchor)
      (void)hv_store(loader->anchors, anchor, strlen(anchor), SvREFCNT_inc(scalar), 0);
    return scalar;
}

/* Load a scalar marked as a regexp as a Perl regular expression.
 * This operation is less common and is tricky, so doing it in Perl code for
 * now.
 */
static SV *
load_regexp(perl_yaml_loader_t * loader)
{
    dSP;
    char *string = (char *)loader->event.data.scalar.value;
    STRLEN length = (STRLEN)loader->event.data.scalar.length;
    char *anchor = (char *)loader->event.data.scalar.anchor;
    char *tag = (char *)loader->event.data.scalar.tag;
    char *prefix = (char*)TAG_PERL_PREFIX "regexp:";

    SV *regexp = newSVpvn(string, length);
    SvUTF8_on(regexp);

    ENTER;
    SAVETMPS;
    PUSHMARK(sp);
    XPUSHs(regexp);
    PUTBACK;
    call_pv("YAML::XS::__qr_loader", G_SCALAR);
    SPAGAIN;
    regexp = newSVsv(POPs);

    if (tag && !loader->disable_blessed
        && strlen(tag) > strlen(prefix)
        && strnEQ(tag, prefix, strlen(prefix)))
    {
        char *klass = tag + strlen(prefix);
        sv_bless(regexp, gv_stashpv(klass, TRUE));
    }

    if (anchor)
      (void)hv_store(loader->anchors, anchor, strlen(anchor), SvREFCNT_inc(regexp), 0);
    return regexp;
}

/*
 * Load a reference to a previously loaded node.
 */
static SV *
load_alias(perl_yaml_loader_t *loader)
{
    char *anchor = (char *)loader->event.data.alias.anchor;
    SV **entry = hv_fetch(loader->anchors, anchor, strlen(anchor), 0);
    if (entry)
        return SvREFCNT_inc(*entry);
    croak("%sNo anchor for alias '%s'", ERRMSG, anchor);
}

/*
 * Load a Perl hard reference.
 */
SV *
load_scalar_ref(perl_yaml_loader_t *loader)
{
    SV *value_node;
    char *anchor = (char *)loader->event.data.mapping_start.anchor;
    SV *rv = newRV_noinc(&PL_sv_undef);
    if (anchor)
      (void)hv_store(loader->anchors, anchor, strlen(anchor), SvREFCNT_inc(rv), 0);
    load_node(loader);  /* Load the single hash key (=) */
    value_node = load_node(loader);
    SvRV(rv) = value_node;
    if (load_node(loader))
        croak("%sExpected end of node", ERRMSG);
    return rv;
}

/*
 * Load a Perl typeglob.
 */
static SV *
load_glob(perl_yaml_loader_t *loader)
{
    /* XXX Call back a Perl sub to do something interesting here */
    return load_mapping(loader, (char*)TAG_PERL_PREFIX "hash");
}

/* -------------------------------------------------------------------------- */

/*
 * Set dumper options from global variables.
 */
static yaml_encoding_t
set_dumper_options(perl_yaml_dumper_t *dumper)
{
    GV *gv;
    yaml_encoding_t result = YAML_UTF8_ENCODING;
    dumper->dump_code = (
        ((gv = gv_fetchpv("YAML::XS::UseCode", GV_NOADD_NOINIT, SVt_IV))
         && SvTRUE(GvSV(gv)))
    ||
        ((gv = gv_fetchpv("YAML::XS::DumpCode", GV_NOADD_NOINIT, SVt_IV)) &&
        SvTRUE(GvSV(gv)))
                         );
    dumper->quote_number_strings = (
        ((gv = gv_fetchpv("YAML::XS::QuoteNumericStrings", GV_NOADD_NOINIT, SVt_IV)) &&
        SvTRUE(GvSV(gv))));
    dumper->filename = NULL;

    /* Set if unescaped non-ASCII characters are allowed. */
    yaml_emitter_set_unicode(&dumper->emitter, 1);
    yaml_emitter_set_indent(&dumper->emitter, 2);
    yaml_emitter_set_width(&dumper->emitter, 80);

    dumper->emitter.indentless_map =
        ((gv = gv_fetchpv("YAML::XS::IndentlessMap", GV_NOADD_NOINIT, SVt_IV))
          && SvTRUE(GvSV(gv))) ? 1 : 0;
    dumper->emitter.open_ended =
        ((gv = gv_fetchpv("YAML::XS::OpenEnded", GV_NOADD_NOINIT, SVt_IV))
         && SvTRUE(GvSV(gv))) ? 1 : 0;

    if ((gv = gv_fetchpv("YAML::XS::Encoding", GV_NOADD_NOINIT, SVt_PV))
        && SvPOK(GvSV(gv)))
    {
        const char *enc = SvPVX_const(GvSV(gv));
        if (memEQs(enc, 3, "any"))
            yaml_emitter_set_encoding(&dumper->emitter, (result = YAML_ANY_ENCODING));
        else if (memEQs(enc, 4, "utf8"))
            yaml_emitter_set_encoding(&dumper->emitter, YAML_UTF8_ENCODING);
        else if (memEQs(enc, 7, "utf16le"))
            yaml_emitter_set_encoding(&dumper->emitter, (result = YAML_UTF16LE_ENCODING));
        else if (memEQs(enc, 7, "utf16be"))
            yaml_emitter_set_encoding(&dumper->emitter, (result = YAML_UTF16BE_ENCODING));
        else
            croak("Invalid $YAML::XS::Encoding %s. Valid: any, utf8, utf16le, utf16be", enc);
    }
    if ((gv = gv_fetchpv("YAML::XS::LineBreak", GV_NOADD_NOINIT, SVt_PV))
        && SvPOK(GvSV(gv)))
    {
        const char *lb = SvPVX_const(GvSV(gv));
        if (memEQs(lb, 3, "any"))
            yaml_emitter_set_break(&dumper->emitter, YAML_ANY_BREAK);
        else if (memEQs(lb, 2, "cr"))
            yaml_emitter_set_break(&dumper->emitter, YAML_CR_BREAK);
        else if (memEQs(lb, 2, "ln"))
            yaml_emitter_set_break(&dumper->emitter, YAML_LN_BREAK);
        else if (memEQs(lb, 4, "crln"))
            yaml_emitter_set_break(&dumper->emitter, YAML_CRLN_BREAK);
        else
            croak("Invalid $YAML::XS::LineBreak %s. Valid: any, ln, cr, crln", lb);
    }

#define IVCHK(name,field) \
    if ((gv = gv_fetchpv("YAML::XS::" name, GV_NOADD_NOINIT, SVt_IV)) \
        && SvIOK(GvSV(gv)))                                           \
        yaml_emitter_set_##field(&dumper->emitter, SvIV(GvSV(gv)))

    IVCHK("Indent", indent);
    IVCHK("BestWidth", width);
    IVCHK("Canonical", canonical);
    IVCHK("Unicode", unicode);

#undef IVCHK
    return result;
}

/*
 * This is the main Dump function.
 * Take zero or more Perl objects and return a YAML stream (as a string)
 * Does take options only via globals.
 */
int
Dump()
{
    dXSARGS;
    perl_yaml_dumper_t dumper;
    yaml_event_t event_stream_start;
    yaml_event_t event_stream_end;
    yaml_encoding_t encoding;
    int i;
    SV *yaml = sv_2mortal(newSVpvn("", 0));

    sp = mark;

    /* Set up the emitter object and begin emitting */
    yaml_emitter_initialize(&dumper.emitter);
    encoding = set_dumper_options(&dumper);
    yaml_emitter_set_output(&dumper.emitter,
        &append_output,
        (void *)yaml
    );

    yaml_stream_start_event_initialize(&event_stream_start, encoding);
    yaml_emitter_emit(&dumper.emitter, &event_stream_start);

    dumper.anchors = (HV *)sv_2mortal((SV *)newHV());
    dumper.shadows = (HV *)sv_2mortal((SV *)newHV());

    for (i = 0; i < items; i++) {
        dumper.anchor = 0;

        dump_prewalk(&dumper, ST(i));
        dump_document(&dumper, ST(i));

        hv_clear(dumper.anchors);
        hv_clear(dumper.shadows);
    }

    /* End emitting and destroy the emitter object */
    yaml_stream_end_event_initialize(&event_stream_end);
    yaml_emitter_emit(&dumper.emitter, &event_stream_end);
    yaml_emitter_delete(&dumper.emitter);

    /* Put the YAML stream scalar on the XS output stack */
    if (yaml) {
        SvUTF8_off(yaml);
        XPUSHs(yaml);
        PUTBACK;
        return 1;
    } else {
        PUTBACK;
        return 0;
    }
}

/*
 * Dump zero or more Perl objects into the file
 */
int
DumpFile(SV *sv_file)
{
    dXSARGS;
    perl_yaml_dumper_t dumper;
    yaml_event_t event_stream_start;
    yaml_event_t event_stream_end;
    yaml_encoding_t encoding;
    FILE *file = NULL;
    const char *fname;
    STRLEN len;
    long i;

    sp = mark;

    yaml_emitter_initialize(&dumper.emitter);
    encoding = set_dumper_options(&dumper);

    if (SvROK(sv_file)) { /* pv mg or io or gv */
        SV *rv = SvRV(sv_file);

        if (SvTYPE(rv) == SVt_PVIO) {
            dumper.perlio = IoOFP(rv);
            yaml_emitter_set_output(&dumper.emitter,
                                    &yaml_perlio_write_handler,
                                    &dumper);
        } else if (SvTYPE(rv) == SVt_PVGV && GvIO(rv)) {
            dumper.perlio = IoOFP(GvIOp(SvRV(sv_file)));
            yaml_emitter_set_output(&dumper.emitter,
                                    &yaml_perlio_write_handler,
                                    &dumper);
        } else if (SvMAGIC(rv)) {
            mg_get(rv);
            fname = SvPV_const(rv, len);
            goto pv_dump;
        } else if (SvAMAGIC(sv_file)) {
            fname = SvPV_const(sv_file, len);
            goto pv_dump;
        } else {
            croak("Invalid argument type: ref of %u", SvTYPE(rv));
            return 0;
        }
    }
    else if (SvPOK(sv_file)) {
        fname = (const char *)SvPV_const(sv_file, len);
    pv_dump:
        file = fopen(fname, "wb");
        if (!file) {
            croak("Can't open '%s' for output", fname);
            return 0;
        }
        dumper.filename = (char *)fname;
        yaml_emitter_set_output_file(&dumper.emitter, file);
    } else if (SvTYPE(sv_file) == SVt_PVIO) {
        dumper.perlio = IoOFP(sv_file);
        yaml_emitter_set_output(&dumper.emitter,
                                &yaml_perlio_write_handler,
                                &dumper);
    } else if (SvTYPE(sv_file) == SVt_PVGV && GvIO(sv_file)) {
        dumper.perlio = IoOFP(GvIOp(sv_file));
        yaml_emitter_set_output(&dumper.emitter,
                                &yaml_perlio_write_handler,
                                &dumper);
    } else {
        croak("Invalid argument type: %u", SvTYPE(sv_file));
        return 0;
    }

    yaml_stream_start_event_initialize(&event_stream_start, encoding);
    if (!yaml_emitter_emit(&dumper.emitter, &event_stream_start)) {
        PUTBACK;
        return 0;
    }

    dumper.anchors = (HV *)sv_2mortal((SV *)newHV());
    dumper.shadows = (HV *)sv_2mortal((SV *)newHV());

    /* ST(0) is the file */
    for (i = 1; i < items; i++) {
        dumper.anchor = 0;

        dump_prewalk(&dumper, ST(i));
        dump_document(&dumper, ST(i));

        hv_clear(dumper.anchors);
        hv_clear(dumper.shadows);
    }

    /* End emitting and destroy the emitter object */
    yaml_stream_end_event_initialize(&event_stream_end);
    if (!yaml_emitter_emit(&dumper.emitter, &event_stream_end)) {
        PUTBACK;
        return 0;
    }
    yaml_emitter_delete(&dumper.emitter);
    if (file)
        fclose(file);
    else if (SvTYPE(sv_file) == SVt_PVIO)
        PerlIO_close(IoOFP(sv_file));

    PUTBACK;
    return 1;
}

/*
 * In order to know which nodes will need anchors (for later aliasing) it is
 * necessary to walk the entire data structure first. Once a node has been
 * seen twice you can stop walking it. That way we can handle circular refs.
 * All the node information is stored in an HV.
 */
static void
dump_prewalk(perl_yaml_dumper_t *dumper, SV *node)
{
    int i;
    U32 ref_type;

    if (! (SvROK(node) || SvTYPE(node) == SVt_PVGV)) return;

    {
        SV *object = SvROK(node) ? SvRV(node) : node;
        SV **seen = hv_fetch(dumper->anchors, (char *)&object, sizeof(object), 0);
        if (seen) {
            if (*seen == &PL_sv_undef) {
              (void)hv_store(dumper->anchors, (char *)&object, sizeof(object),
                             &PL_sv_yes, 0);
            }
            return;
        }
        (void)hv_store(dumper->anchors, (char *)&object, sizeof(object),
                       &PL_sv_undef, 0);
    }

    if (SvTYPE(node) == SVt_PVGV) {
        node = dump_glob(dumper, node);
    }

    ref_type = SvTYPE(SvRV(node));
    if (ref_type == SVt_PVAV) {
        AV *array = (AV *)SvRV(node);
        int array_size = av_len(array) + 1;
        for (i = 0; i < array_size; i++) {
            SV **entry = av_fetch(array, i, 0);
            if (entry)
                dump_prewalk(dumper, *entry);
        }
    }
    else if (ref_type == SVt_PVHV) {
        HV *hash = (HV *)SvRV(node);
        HE *he;
        hv_iterinit(hash);
        while ((he = hv_iternext(hash))) {
            SV *val = HeVAL(he);
            if (val)
                dump_prewalk(dumper, val);
        }
    }
    else if (ref_type <= SVt_PVNV || ref_type == SVt_PVGV) {
        SV *scalar = SvRV(node);
        dump_prewalk(dumper, scalar);
    }
}

static void
dump_document(perl_yaml_dumper_t *dumper, SV *node)
{
    yaml_event_t event_document_start;
    yaml_event_t event_document_end;
    yaml_document_start_event_initialize(
        &event_document_start, NULL, NULL, NULL, 0
    );
    yaml_emitter_emit(&dumper->emitter, &event_document_start);
    dump_node(dumper, node);
    yaml_document_end_event_initialize(&event_document_end, 1);
    yaml_emitter_emit(&dumper->emitter, &event_document_end);
}

static void
dump_node(perl_yaml_dumper_t *dumper, SV *node)
{
    yaml_char_t *anchor = NULL;
    yaml_char_t *tag = NULL;
    const char *klass = NULL;

    if (SvTYPE(node) == SVt_PVGV) {
        SV **svr;
        tag = (yaml_char_t *)TAG_PERL_PREFIX "glob";
        anchor = get_yaml_anchor(dumper, node);
        if (anchor && strEQc((char *)anchor, "")) return;
        svr = hv_fetch(dumper->shadows, (char *)&node, sizeof(node), 0);
        if (svr) {
            node = SvREFCNT_inc(*svr);
        }
    }

    if (SvROK(node)) {
        SV *rnode = SvRV(node);
        U32 ref_type = SvTYPE(rnode);
        if (ref_type == SVt_PVHV)
            dump_hash(dumper, node, anchor, tag);
        else if (ref_type == SVt_PVAV)
            dump_array(dumper, node);
        else if (ref_type <= SVt_PVNV || ref_type == SVt_PVGV)
            dump_ref(dumper, node);
        else if (ref_type == SVt_PVCV)
            dump_code(dumper, node);
        else if (ref_type == SVt_PVMG) {
            MAGIC *mg;
            yaml_char_t *tag = NULL;
            if (SvMAGICAL(rnode)) {
                if ((mg = mg_find(rnode, PERL_MAGIC_qr))) {
                    tag = (yaml_char_t *)form(TAG_PERL_PREFIX "regexp");
                    klass = sv_reftype(rnode, TRUE);
                    if (!strEQc(klass, "Regexp"))
                        tag = (yaml_char_t *)form("%s:%s", tag, klass);
                }
            }
            else {
                tag = (yaml_char_t *)form(
                    TAG_PERL_PREFIX "scalar:%s",
                    sv_reftype(rnode, TRUE)
                );
                node = rnode;
            }
            dump_scalar(dumper, node, tag);
        }
#if PERL_VERSION >= 11
        else if (ref_type == SVt_REGEXP) {
            yaml_char_t *tag = (yaml_char_t *)form(TAG_PERL_PREFIX "regexp");
            klass = sv_reftype(rnode, TRUE);
            if (!strEQc(klass, "Regexp"))
                tag = (yaml_char_t *)form("%s:%s", tag, klass);
            dump_scalar(dumper, node, tag);
        }
#endif
        else {
            printf(
                "YAML::XS dump unhandled ref. type == '%d'!\n",
                (int)ref_type
            );
            dump_scalar(dumper, rnode, NULL);
        }
    }
    else {
        dump_scalar(dumper, node, NULL);
    }
}

static yaml_char_t *
get_yaml_anchor(perl_yaml_dumper_t *dumper, SV *node)
{
    yaml_event_t event_alias;
    SV *iv;
    SV **seen = hv_fetch(dumper->anchors, (char *)&node, sizeof(node), 0);
    if (seen && *seen != &PL_sv_undef) {
        if (*seen == &PL_sv_yes) {
            dumper->anchor++;
            iv = newSViv(dumper->anchor);
            (void)hv_store(dumper->anchors, (char *)&node, sizeof(node), iv, 0);
            return (yaml_char_t*)SvPV_nolen(iv);
        }
        else {
            yaml_char_t *anchor = (yaml_char_t *)SvPV_nolen(*seen);
            yaml_alias_event_initialize(&event_alias, anchor);
            yaml_emitter_emit(&dumper->emitter, &event_alias);
            return (yaml_char_t *) "";
        }
    }
    return NULL;
}

static yaml_char_t *
get_yaml_tag(SV *node)
{
    yaml_char_t *tag = NULL;
    char *kind = (char*)"";
    char *klass;

    if (! (sv_isobject(node)
           || (SvRV(node) && ( SvTYPE(SvRV(node)) == SVt_PVCV))))
        return NULL;
    klass = (char *)sv_reftype(SvRV(node), TRUE);

    switch (SvTYPE(SvRV(node))) {
        case SVt_PVAV:
          tag = (yaml_char_t *)form("%s%s:%s", TAG_PERL_PREFIX, "array", klass);
          break;
        case SVt_PVHV:
          tag = (yaml_char_t *)form("%s%s:%s", TAG_PERL_PREFIX, "hash", klass);
          break;
        case SVt_PVCV:
          kind = (char*)"code";
          if (strEQc(klass, "CODE"))
            tag = (yaml_char_t *)form("%s%s", TAG_PERL_PREFIX, kind);
          break;
        default:
          tag = (yaml_char_t *)form("%s%s", TAG_PERL_PREFIX, klass);
          break;
    }
    if (!tag)
      tag = (yaml_char_t *)form("%s%s:%s", TAG_PERL_PREFIX, kind, klass);
    return tag;
}

static void
dump_hash(
    perl_yaml_dumper_t *dumper, SV *node,
    yaml_char_t *anchor, yaml_char_t *tag)
{
    yaml_event_t event_mapping_start;
    yaml_event_t event_mapping_end;
    STRLEN i, len;
    AV *av;
    HV *hash = (HV *)SvRV(node);
    HE *he;

    if (!anchor)
        anchor = get_yaml_anchor(dumper, (SV *)hash);
    if (anchor && !*anchor) return;

    if (!tag)
        tag = get_yaml_tag(node);

    yaml_mapping_start_event_initialize(
        &event_mapping_start, anchor, tag, 0, YAML_BLOCK_MAPPING_STYLE
    );
    yaml_emitter_emit(&dumper->emitter, &event_mapping_start);

    av = newAV();
    len = 0;
    hv_iterinit(hash);
    while ((he = hv_iternext(hash))) {
        SV *key = hv_iterkeysv(he);
        av_store(av, AvFILLp(av)+1, key); /* av_push(), really */
        len++;
    }
    STORE_HASH_SORT;
    for (i = 0; i < len; i++) {
        SV *key = av_shift(av);
        HE *he  = hv_fetch_ent(hash, key, 0, 0);
        SV *val = he ? HeVAL(he) : NULL;
        if (val == NULL) { val = &PL_sv_undef; }
        dump_node(dumper, key);
        dump_node(dumper, val);
    }

    SvREFCNT_dec(av);

    yaml_mapping_end_event_initialize(&event_mapping_end);
    yaml_emitter_emit(&dumper->emitter, &event_mapping_end);
}

static void
dump_array(perl_yaml_dumper_t *dumper, SV *node)
{
    yaml_event_t event_sequence_start;
    yaml_event_t event_sequence_end;
    yaml_char_t *tag;
    AV *array = (AV *)SvRV(node);
    STRLEN i;
    STRLEN array_size = av_len(array) + 1;

    yaml_char_t *anchor = get_yaml_anchor(dumper, (SV *)array);
    if (anchor && strEQc((char *)anchor, "")) return;
    tag = get_yaml_tag(node);

    yaml_sequence_start_event_initialize(
        &event_sequence_start, anchor, tag, 0, YAML_BLOCK_SEQUENCE_STYLE
    );
    yaml_emitter_emit(&dumper->emitter, &event_sequence_start);

    for (i = 0; i < array_size; i++) {
        SV **entry = av_fetch(array, i, 0);
        if (entry == NULL)
            dump_node(dumper, &PL_sv_undef);
        else
            dump_node(dumper, *entry);
    }
    yaml_sequence_end_event_initialize(&event_sequence_end);
    yaml_emitter_emit(&dumper->emitter, &event_sequence_end);
}

static void
dump_scalar(perl_yaml_dumper_t *dumper, SV *node, yaml_char_t *tag)
{
    yaml_event_t event_scalar;
    char *string;
    STRLEN string_len;
    int plain_implicit, quoted_implicit;
    yaml_scalar_style_t style = YAML_PLAIN_SCALAR_STYLE;

    if (tag) {
        plain_implicit = quoted_implicit = 0;
    }
    else {
        tag = (yaml_char_t *)TAG_PERL_STR;
        plain_implicit = quoted_implicit = 1;
    }

    SvGETMAGIC(node);
    if (!SvOK(node)) {
        string = "~";
        string_len = 1;
        style = YAML_PLAIN_SCALAR_STYLE;
    }
    else if (node == &PL_sv_yes) {
        string = "true";
        string_len = 4;
        style = YAML_PLAIN_SCALAR_STYLE;
    }
    else if (node == &PL_sv_no) {
        string = "false";
        string_len = 5;
        style = YAML_PLAIN_SCALAR_STYLE;
    }
    else {
        string = SvPV_nomg(node, string_len);
        if (
            (string_len == 0) ||
            strEQc(string, "~") ||
            strEQc(string, "true") ||
            strEQc(string, "false") ||
            strEQc(string, "null") ||
            (SvTYPE(node) >= SVt_PVGV) ||
            ( dumper->quote_number_strings && !SvNIOK(node) && looks_like_number(node) )
        ) {
            style = YAML_SINGLE_QUOTED_SCALAR_STYLE;
        } else {
            if (!SvUTF8(node)) {
                /* copy to new SV and promote to utf8 */
                SV *utf8sv = sv_mortalcopy(node);

                /* get string and length out of utf8 */
                string = SvPVutf8(utf8sv, string_len);
            }
            if(strchr(string, '\n'))
               style = (string_len > 30) ? YAML_LITERAL_SCALAR_STYLE
                                         : YAML_DOUBLE_QUOTED_SCALAR_STYLE;
        }
    }
    yaml_scalar_event_initialize(
        &event_scalar,
        NULL, /* anchor */
        tag,
        (unsigned char *) string,
        (int) string_len,
        plain_implicit,
        quoted_implicit,
        style
    );
    if (! yaml_emitter_emit(&dumper->emitter, &event_scalar))
        croak("%sEmit scalar '%s', error: %s\n",
            ERRMSG,
            string, dumper->emitter.problem
        );
}

static void
dump_code(perl_yaml_dumper_t *dumper, SV *node)
{
    yaml_event_t event_scalar;
    yaml_char_t *tag;
    yaml_scalar_style_t style = YAML_SINGLE_QUOTED_SCALAR_STYLE;
    char *string = "{ \"DUMMY\" }";
    if (dumper->dump_code) {
        /* load_module(PERL_LOADMOD_NOIMPORT, newSVpv("B::Deparse", 0), NULL);
         */
        SV *result;
        SV *code = find_coderef("YAML::XS::coderef2text");
        AV *args = newAV();
        av_push(args, SvREFCNT_inc(node));
        args = (AV *)sv_2mortal((SV *)args);
        result = call_coderef(code, args);
        if (result && result != &PL_sv_undef) {
            string = SvPV_nolen(result);
            style = YAML_LITERAL_SCALAR_STYLE;
        }
    }
    tag = get_yaml_tag(node);

    yaml_scalar_event_initialize(
        &event_scalar,
        NULL, /* anchor */
        tag,
        (unsigned char *)string,
        strlen(string),
        0,
        0,
        style
    );

    yaml_emitter_emit(&dumper->emitter, &event_scalar);
}

static SV *
dump_glob(perl_yaml_dumper_t *dumper, SV *node)
{
    SV *result;
    SV *code = find_coderef("YAML::XS::glob2hash");
    AV *args = newAV();
    av_push(args, SvREFCNT_inc(node));
    args = (AV *)sv_2mortal((SV *)args);
    result = call_coderef(code, args);
    (void)hv_store(dumper->shadows, (char *)&node, sizeof(node),
                   result, 0);
    return result;
}

/* XXX Refo this to just dump a special map */
static void
dump_ref(perl_yaml_dumper_t *dumper, SV *node)
{
    yaml_event_t event_mapping_start;
    yaml_event_t event_mapping_end;
    yaml_event_t event_scalar;
    SV *referent = SvRV(node);

    yaml_char_t *anchor = get_yaml_anchor(dumper, referent);
    if (anchor && strEQc((char *)anchor, "")) return;

    yaml_mapping_start_event_initialize(
        &event_mapping_start, anchor,
        (unsigned char *)TAG_PERL_PREFIX "ref",
        0, YAML_BLOCK_MAPPING_STYLE
    );
    yaml_emitter_emit(&dumper->emitter, &event_mapping_start);

    yaml_scalar_event_initialize(
        &event_scalar,
        NULL, /* anchor */
        NULL, /* tag */
        (unsigned char *)"=", 1,
        1, 1,
        YAML_PLAIN_SCALAR_STYLE
    );
    yaml_emitter_emit(&dumper->emitter, &event_scalar);
    dump_node(dumper, referent);

    yaml_mapping_end_event_initialize(&event_mapping_end);
    yaml_emitter_emit(&dumper->emitter, &event_mapping_end);
}

static int
append_output(void *sv, unsigned char *buffer, size_t size)
{
    sv_catpvn((SV *)sv, (const char *)buffer, (STRLEN)size);
    return 1;
}

static int
yaml_perlio_read_handler(void *data, unsigned char *buffer, size_t size, size_t *size_read)
{
    perl_yaml_loader_t *loader = (perl_yaml_loader_t *)data;

    *size_read = PerlIO_read(loader->perlio, buffer, size);
    return !PerlIO_error(loader->perlio);
}

static int
yaml_perlio_write_handler(void *data, unsigned char *buffer, size_t size)
{
    perl_yaml_dumper_t *dumper = (perl_yaml_dumper_t *)data;
    return (PerlIO_write(dumper->perlio, (char*)buffer, (long)size) == (SSize_t)size);
}

/* XXX Make -Wall not complain about 'local_patches' not being used. */
#if !defined(PERL_PATCHLEVEL_H_IMPLICIT)
void xxx_local_patches() {
    printf("%s", local_patches[0]);
}
#endif
