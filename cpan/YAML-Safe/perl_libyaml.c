#include "perl_libyaml.h"

static SV *
load_node(YAML *self);
static SV *
load_mapping(YAML *self, char *tag);
static SV *
load_sequence(YAML *);
static SV *
load_scalar(YAML *);
static SV *
load_alias(YAML *);
static SV *
load_scalar_ref(YAML *);
static SV *
load_regexp(YAML *);
static SV *
load_glob(YAML *);
static SV *
load_code(YAML *);
static void
dump_prewalk(YAML *, SV *);
static void
dump_document(YAML *, SV *);
static void
dump_node(YAML *, SV *);
static void
dump_hash(YAML *, SV *, yaml_char_t *, yaml_char_t *);
static void
dump_array(YAML *, SV *);
static void
dump_scalar(YAML *, SV *, yaml_char_t *);
static void
dump_ref(YAML *, SV *);
static void
dump_code(YAML *, SV *);
static SV*
dump_glob(YAML *, SV *);
static yaml_char_t *
get_yaml_anchor(YAML *, SV *);
static yaml_char_t *
get_yaml_tag(SV *);
static int
yaml_sv_write_handler(void *sv, unsigned char *buffer, size_t size);
static int
yaml_perlio_read_handler(void *data, unsigned char *buffer, size_t size, size_t *size_read);
static int
yaml_perlio_write_handler(void *data, unsigned char *buffer, size_t size);

/* can honor lexical warnings and $^W */
#if PERL_VERSION > 11
#define Perl_warner Perl_ck_warner
#endif

#if 0
static const char* options[] =
  {
   /* Both */
   "boolean",         /* "JSON::PP", "boolean" or 0 */
   "disableblessed",  /* bool, default: 0 */
   "enablecode",      /* bool, default: 0 */
   /* Loader */
   "nonstrict",       /* bool, default: 0 */
   "loadcode",        /* bool, default: 0 */
   /* Dumper */
   "dumpcode",        /* bool, default: 0 */
   "noindentmap",     /* bool, default: 0 */
   "indent",          /* int, default: 2 */
   "wrapwidth",       /* int, default: 80 */
   "canonical",       /* bool, default: 0 */
   "quotenum",        /* bool, default: 1 */
   "unicode",         /* bool, default: 1 If unescaped Unicode characters are allowed */
   "encoding",        /* "any", "utf8", "utf16le" or "utf16be" */
   "linebreak",       /* "any", "cr", "ln" or "crln" */
   "openended",       /* bool, default: 0 */
  };
static int numoptions = sizeof(options)/sizeof(options[0]);

#endif

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
loader_error_msg(YAML *self, char *problem)
{
    char *msg;
    if (!problem)
        problem = (char *)self->parser.problem;
    if (self->filename)
      msg = form("%s%s at file %s",
                 ERRMSG, (problem ? problem : "A problem"), self->filename);
    else
      msg = form("%s%s at document %d",
                 ERRMSG, (problem ? problem : "A problem"), self->document);
    if (self->parser.problem_mark.line ||
        self->parser.problem_mark.column)
        msg = form("%s, line: %ld, column: %ld\n",
                   msg,
                   (long)self->parser.problem_mark.line + 1,
                   (long)self->parser.problem_mark.column + 1);
    else if (self->parser.problem_offset)
        msg = form("%s, offset: %ld\n", msg, (long)self->parser.problem_offset);
    else
        msg = form("%s\n", msg);
    if (self->parser.context)
        msg = form("%s%s at line: %ld, column: %ld\n",
                   msg,
                   self->parser.context,
                   (long)self->parser.context_mark.line + 1,
                   (long)self->parser.context_mark.column + 1);

    return msg;
}

/*
 * Set loader options from YAML* object.
 */
void
set_parser_options(YAML *self, yaml_parser_t *parser)
{
    self->document = 0;
    self->filename = NULL;
    self->parser.read_handler = NULL; /* we allow setting it mult. times */

    if ((int)self->encoding)
        yaml_parser_set_encoding(parser, self->encoding);

    /* As with YAML::Tiny. Default: strict Load */
    /* allow while parsing a quoted scalar found unknown escape character */
    parser->problem_nonstrict = self->flags & F_NONSTRICT;
}

/*
 * Set dumper options from YAML* object
 */
void
set_emitter_options(YAML *self, yaml_emitter_t *emitter)
{
    yaml_emitter_set_unicode(emitter, self->flags & F_UNICODE);
    yaml_emitter_set_indent(emitter, self->indent);
    yaml_emitter_set_width(emitter, self->wrapwidth);
    if ((int)self->encoding)
        yaml_emitter_set_encoding(emitter, self->encoding);
    if ((int)self->linebreak)
        yaml_emitter_set_break(emitter, self->linebreak);
    emitter->indentless_map = self->flags & F_NOINDENTMAP;
    emitter->open_ended = self->flags & F_OPENENDED;
    yaml_emitter_set_canonical(emitter, self->flags & F_CANONICAL);
}

static int
load_impl(YAML *self)
{
    dXCPT;
    dXSARGS; /* does POPMARK */
    SV *node;

    sp = mark;
    if (0 && (items || ax)) {} /* XXX Quiet the -Wall warnings for now. */

    /* Get the first event. Must be a STREAM_START */
    if (!yaml_parser_parse(&self->parser, &self->event))
        goto load_error;
    if (self->event.type != YAML_STREAM_START_EVENT)
        croak("%sExpected STREAM_START_EVENT; Got: %d != %d",
            ERRMSG, self->event.type, YAML_STREAM_START_EVENT);

    self->anchors = (HV *)sv_2mortal((SV *)newHV());

    XCPT_TRY_START {

        /* Keep calling load_node until end of stream */
        while (1) {
            self->document++;
            /* We are through with the previous event - delete it! */
            yaml_event_delete(&self->event);
            if (!yaml_parser_parse(&self->parser, &self->event))
                goto load_error;
            if (self->event.type == YAML_STREAM_END_EVENT)
                break;
            node = load_node(self);
            /* We are through with the previous event - delete it! */
            yaml_event_delete(&self->event);
            hv_clear(self->anchors);
            if (! node) break;
            XPUSHs(sv_2mortal(node));
            if (!yaml_parser_parse(&self->parser, &self->event))
                goto load_error;
            if (self->event.type != YAML_DOCUMENT_END_EVENT)
                croak("%sExpected DOCUMENT_END_EVENT", ERRMSG);
        }

        /* Make sure the last event is a STREAM_END */
        if (self->event.type != YAML_STREAM_END_EVENT)
            croak("%sExpected STREAM_END_EVENT; Got: %d != %d",
                ERRMSG, self->event.type, YAML_STREAM_END_EVENT);

    } XCPT_TRY_END

    XCPT_CATCH
    {
        yaml_parser_delete(&self->parser);
        XCPT_RETHROW;
    }

    yaml_parser_delete(&self->parser);
    PUTBACK;
    return 1;

load_error:
    croak("%s", loader_error_msg(self, NULL));
    return 0;
}

/*
 * It takes a file or filename and turns it into 0 or more Perl objects.
 */
int
LoadFile(YAML *self, SV *sv_file)
{
    FILE *file = NULL;
    const char *fname;
    STRLEN len;
    int ret;

    yaml_parser_initialize(&self->parser);
    set_parser_options(self, &self->parser);
    if (SvROK(sv_file)) { /* pv mg or io or gv */
        SV *rv = SvRV(sv_file);

        if (SvTYPE(rv) == SVt_PVIO) {
            self->perlio = IoIFP(rv);
            yaml_parser_set_input(&self->parser,
                                  &yaml_perlio_read_handler,
                                  self);
        } else if (SvTYPE(rv) == SVt_PVGV && GvIO(rv)) {
            self->perlio = IoIFP(GvIOp(rv));
            yaml_parser_set_input(&self->parser,
                                  &yaml_perlio_read_handler,
                                  self);
        } else if (SvMAGIC(rv)) {
            mg_get(rv);
            fname = SvPV_const(rv, len);
            goto pv_load;
        } else if (SvAMAGIC(sv_file)) {
            fname = SvPV_const(sv_file, len);
            goto pv_load;
        } else {
            croak("Invalid argument type for file: ref of %s", Perl_sv_peek(aTHX_ rv));
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
        self->filename = (char *)fname;
        yaml_parser_set_input_file(&self->parser, file);
    } else if (SvTYPE(sv_file) == SVt_PVIO) {
        self->perlio = IoIFP(sv_file);
        yaml_parser_set_input(&self->parser,
                              &yaml_perlio_read_handler,
                              self);
    } else if (SvTYPE(sv_file) == SVt_PVGV
               && GvIO(sv_file)) {
        self->perlio = IoIFP(GvIOp(sv_file));
        yaml_parser_set_input(&self->parser,
                              &yaml_perlio_read_handler,
                              self);
    } else {
        croak("Invalid argument type for file: %s", Perl_sv_peek(aTHX_ sv_file));
        return 0;
    }

    ret = load_impl(self);
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
Load(YAML *self, SV* yaml_sv)
{
    const unsigned char *yaml_str;
    STRLEN yaml_len;

    yaml_str = (const unsigned char *)SvPV_const(yaml_sv, yaml_len);
    yaml_parser_initialize(&self->parser);
    set_parser_options(self, &self->parser);
    if (DO_UTF8(yaml_sv)) { /* overrides encoding setting */
        if (self->encoding == YAML_ANY_ENCODING)
            self->parser.encoding = YAML_UTF8_ENCODING;
    } /* else check the BOM. don't check for decoded utf8. */

    yaml_parser_set_input_string(
        &self->parser,
        yaml_str,
        yaml_len);

    return load_impl(self);
}

/*
 * This is the main function for dumping any node.
 */
static SV *
load_node(YAML *self)
{
    SV* return_sv = NULL;
    /* This uses stack, but avoids (severe!) memory leaks */
    yaml_event_t uplevel_event;

    uplevel_event = self->event;

    /* Get the next parser event */
    if (!yaml_parser_parse(&self->parser, &self->event))
        goto load_error;

    /* These events don't need yaml_event_delete */
    /* Some kind of error occurred */
    if (self->event.type == YAML_NO_EVENT)
        goto load_error;

    /* Return NULL when we hit the end of a scope */
    if (self->event.type == YAML_DOCUMENT_END_EVENT ||
        self->event.type == YAML_MAPPING_END_EVENT ||
        self->event.type == YAML_SEQUENCE_END_EVENT)
    {
        /* restore the uplevel event, so it can be properly deleted */
        self->event = uplevel_event;
        return return_sv;
    }

    /* The rest all need cleanup */
    switch (self->event.type) {
        char *tag;

        /* Handle loading a mapping */
        case YAML_MAPPING_START_EVENT:
            tag = (char *)self->event.data.mapping_start.tag;

            if (tag) {
                /* Handle mapping tagged as a Perl hard reference */
                if (strEQ(tag, TAG_PERL_REF)) {
                    return_sv = load_scalar_ref(self);
                    break;
                }
                /* Handle mapping tagged as a Perl typeglob */
                if (strEQ(tag, TAG_PERL_GLOB)) {
                    return_sv = load_glob(self);
                    break;
                }
            }

            return_sv = load_mapping(self, NULL);
            break;

        /* Handle loading a sequence into an array */
        case YAML_SEQUENCE_START_EVENT:
            return_sv = load_sequence(self);
            break;

        /* Handle loading a scalar */
        case YAML_SCALAR_EVENT:
            return_sv = load_scalar(self);
            break;

        /* Handle loading an alias node */
        case YAML_ALIAS_EVENT:
            return_sv = load_alias(self);
            break;

        default:
            croak("%sInvalid event '%d' at top level",
                  ERRMSG, (int) self->event.type);
    }

    yaml_event_delete(&self->event);

    /* restore the uplevel event, so it can be properly deleted */
    self->event = uplevel_event;

    return return_sv;

    load_error:
        croak("%s", loader_error_msg(self, NULL));
}

/*
 * Load a YAML mapping into a Perl hash
 */
static SV *
load_mapping(YAML *self, char *tag)
{
    SV *key_node;
    SV *value_node;
    HV *hash = newHV();
    SV *hash_ref = (SV *)newRV_noinc((SV *)hash);
    char *anchor = (char *)self->event.data.mapping_start.anchor;

    if (!tag)
        tag = (char *)self->event.data.mapping_start.tag;

    /* Store the anchor label if any */
    if (anchor)
        (void)hv_store(self->anchors, anchor, strlen(anchor),
                       SvREFCNT_inc(hash_ref), 0);

    /* Get each key string and value node and put them in the hash */
    while ((key_node = load_node(self))) {
        assert(SvPOK(key_node));
        value_node = load_node(self);
        (void)hv_store_ent(hash, sv_2mortal(key_node), value_node, 0);
    }

    /* Deal with possibly blessing the hash if the YAML tag has a class */
    if (tag) {
        if (strEQ(tag, TAG_PERL_PREFIX "hash")) {
        }
        else if (strEQ(tag, YAML_MAP_TAG)) {
        }
        else {
            char *klass;
            char *prefix = TAG_PERL_PREFIX "hash:";
            if (*tag == '!') {
                prefix = "!";
            }
            else if (strlen(tag) <= strlen(prefix) ||
                     ! strnEQ(tag, prefix, strlen(prefix)))
                croak("%s", loader_error_msg(self,
                                form("bad tag found for hash: '%s'", tag)));
            if (!(self->flags & F_DISABLEBLESSED)) {
                klass = tag + strlen(prefix);
                if (self->flags & F_SAFEMODE &&
                    (!self->safeclasses ||
                     !hv_exists(self->safeclasses, klass, strlen(klass))))
                {
                    Perl_warner(aTHX_ packWARN(WARN_MISC),
                                WARNMSG "skipped loading unsafe HASH for class %s",
                                klass);
                    return hash_ref;
                }
                sv_bless(hash_ref, gv_stashpv(klass, TRUE));
            }
        }
    }

    return hash_ref;
}

/* Load a YAML sequence into a Perl array */
static SV *
load_sequence(YAML *self)
{
    SV *node;
    AV *array = newAV();
    SV *array_ref = (SV *)newRV_noinc((SV *)array);
    char *anchor = (char *)self->event.data.sequence_start.anchor;
    char *tag = (char *)self->event.data.mapping_start.tag;
    if (anchor)
        (void)hv_store(self->anchors, anchor, strlen(anchor),
                       SvREFCNT_inc(array_ref), 0);
    while ((node = load_node(self))) {
        av_push(array, node);
    }
    if (tag) {
        if (strEQ(tag, TAG_PERL_PREFIX "array")) {
        }
        else if (strEQ(tag, YAML_SEQ_TAG)) {
        }
        else {
            char *klass;
            char *prefix = TAG_PERL_PREFIX "array:";

            if (*tag == '!')
                prefix = "!";
            else if (strlen(tag) <= strlen(prefix) ||
                     ! strnEQ(tag, prefix, strlen(prefix)))
                croak("%s", loader_error_msg(self,
                              form("bad tag found for array: '%s'", tag)));
            if (!(self->flags & F_DISABLEBLESSED)) {
                klass = tag + strlen(prefix);
                if (self->flags & F_SAFEMODE &&
                    (!self->safeclasses ||
                     !hv_exists(self->safeclasses, klass, strlen(klass))))
                {
                    Perl_warner(aTHX_ packWARN(WARN_MISC),
                                WARNMSG "skipped loading unsafe ARRAY for class %s",
                                klass);
                    return array_ref;
                }
                sv_bless(array_ref, gv_stashpv(klass, TRUE));
            }
        }
    }
    return array_ref;
}

/* Load a YAML scalar into a Perl scalar */
static SV *
load_scalar(YAML *self)
{
    SV *scalar;
    char *string = (char *)self->event.data.scalar.value;
    STRLEN length = (STRLEN)self->event.data.scalar.length;
    char *anchor = (char *)self->event.data.scalar.anchor;
    char *tag = (char *)self->event.data.scalar.tag;
    yaml_scalar_style_t style = self->event.data.scalar.style;
    if (tag) {
        if (strEQ(tag, YAML_STR_TAG)) {
            style = YAML_SINGLE_QUOTED_SCALAR_STYLE;
        }
        else if (strEQ(tag, YAML_INT_TAG) || strEQ(tag, YAML_FLOAT_TAG)) {
            /* TODO check int/float */
            scalar = newSVpvn(string, length);
            if ( looks_like_number(scalar) ) {
                /* numify */
                SvIV_please(scalar);
            }
            else {
                croak("%s", loader_error_msg(self,
                                form("Invalid content found for !!int tag: '%s'",
                                     tag)));
            }
            if (anchor)
              (void)hv_store(self->anchors, anchor, strlen(anchor),
                             SvREFCNT_inc(scalar), 0);
            return scalar;
        }
        else if (strEQ(tag, YAML_NULL_TAG) &&
                 (strEQ(string, "~") ||
                  strEQ(string, "null") ||
                  strEQ(string, "")))
        {
            scalar = newSV(0);
            if (anchor)
                (void)hv_store(self->anchors, anchor, strlen(anchor),
                               SvREFCNT_inc(scalar), 0);
            return scalar;
        }
        else {
            char *klass;
            char *prefix = TAG_PERL_PREFIX "regexp";
            if (strnEQ(tag, prefix, strlen(prefix)))
                return load_regexp(self);
            prefix = TAG_PERL_PREFIX "code";
            if (strnEQ(tag, prefix, strlen(prefix)))
                return load_code(self);
            prefix = TAG_PERL_PREFIX "scalar:";
            if (*tag == '!')
                prefix = "!";
            else if (strlen(tag) <= strlen(prefix) ||
                     !strnEQ(tag, prefix, strlen(prefix)))
                croak("%sbad tag found for scalar: '%s'", ERRMSG, tag);
            klass = tag + strlen(prefix);
            if (!(self->flags & F_DISABLEBLESSED))
                if (self->flags & F_SAFEMODE &&
                    (!self->safeclasses ||
                     !hv_exists(self->safeclasses, klass, strlen(klass))))
                {
                    Perl_warner(aTHX_ packWARN(WARN_MISC),
                                WARNMSG "skipped loading unsafe SCALAR for class %s",
                                klass);
                    scalar = newSVpvn(string, length);
                } else {
                    scalar = sv_setref_pvn(newSV(0), klass, string, strlen(string));
                }
            else
                scalar = newSVpvn(string, length);
            SvUTF8_on(scalar);
            if (anchor)
                (void)hv_store(self->anchors, anchor, strlen(anchor),
                               SvREFCNT_inc(scalar), 0);
            return scalar;
        }
    }

    else if (style == YAML_PLAIN_SCALAR_STYLE) {
        if (strEQ(string, "~") || strEQ(string, "null") || strEQ(string, "")) {
            scalar = newSV(0);
            if (anchor)
                (void)hv_store(self->anchors, anchor, strlen(anchor),
                               SvREFCNT_inc(scalar), 0);
            return scalar;
        }
        else if (strEQ(string, "true")) {
#if (PERL_BCDVERSION >= 0x5008009)
            if (self->boolean == YAML_BOOLEAN_JSONPP) {
                scalar = sv_setref_iv(newSV(1), "JSON::PP::Boolean", 1);
            }
            else if (self->boolean == YAML_BOOLEAN_BOOLEAN) {
                scalar = sv_setref_iv(newSV(1), "boolean", 1);
            }
            else
#endif
            {
                scalar = &PL_sv_yes;
            }
            if (anchor)
                (void)hv_store(self->anchors, anchor, strlen(anchor),
                               SvREFCNT_inc(scalar), 0);
            return scalar;
        }
        else if (strEQ(string, "false")) {
#if (PERL_BCDVERSION >= 0x5008009)
            if (self->boolean == YAML_BOOLEAN_JSONPP) {
                scalar = sv_setref_iv(newSV(0), "JSON::PP::Boolean", 0);
            }
            else if (self->boolean == YAML_BOOLEAN_BOOLEAN) {
                scalar = sv_setref_iv(newSV(0), "boolean", 0);
            }
            else
#endif
            {
                scalar = &PL_sv_no;
            }
            if (anchor)
              (void)hv_store(self->anchors, anchor, strlen(anchor),
                             SvREFCNT_inc(scalar), 0);
            return scalar;
        }
    }

    scalar = newSVpvn(string, length);

    if (style == YAML_PLAIN_SCALAR_STYLE && looks_like_number(scalar) ) {
        /* numify */
        SvIV_please(scalar);
    }

    (void)sv_utf8_decode(scalar);
    if (anchor)
        (void)hv_store(self->anchors, anchor, strlen(anchor),
                       SvREFCNT_inc(scalar), 0);
    return scalar;
}

/* Load a scalar marked as a regexp as a Perl regular expression.
 * This operation is less common and is tricky, so doing it in Perl code for
 * now.
 */
static SV *
load_regexp(YAML * self)
{
    dSP;
    char *string = (char *)self->event.data.scalar.value;
    STRLEN length = (STRLEN)self->event.data.scalar.length;
    char *anchor = (char *)self->event.data.scalar.anchor;
    char *tag = (char *)self->event.data.scalar.tag;
    char *prefix = (char*)TAG_PERL_PREFIX "regexp:";

    SV *regexp = newSVpvn(string, length);
    SvUTF8_on(regexp);

    ENTER;
    SAVETMPS;
    PUSHMARK(sp);
    XPUSHs(regexp);
    PUTBACK;
    call_pv("YAML::Safe::__qr_loader", G_SCALAR);
    SPAGAIN;
    regexp = newSVsv(POPs);

    PUTBACK;
    FREETMPS;
    LEAVE;

    if (strlen(tag) > strlen(prefix) && strnEQ(tag, prefix, strlen(prefix))) {
        if (!(self->flags & F_DISABLEBLESSED)) {
            char *klass = tag + strlen(prefix);
            if (self->flags & F_SAFEMODE) {
                if (!self->safeclasses ||
                    !hv_exists(self->safeclasses, klass, strlen(klass)))
                {
                    Perl_warner(aTHX_ packWARN(WARN_MISC),
                                WARNMSG "skipped loading unsafe REGEXP for class %s",
                                klass);
                    goto cont_rx;
                }
            }
            sv_bless(regexp, gv_stashpv(klass, TRUE));
        }
    }
 cont_rx:
    if (anchor)
        (void)hv_store(self->anchors, anchor, strlen(anchor),
                       SvREFCNT_inc(regexp), 0);
    return regexp;
}

/* Load a scalar marked as code as a Perl code reference.
 * This operation is less common and is tricky, so doing it in Perl code for
 * now.
 */
SV*
load_code(YAML * self)
{
    dSP;
    char *string = (char *)self->event.data.scalar.value;
    STRLEN length = (STRLEN)self->event.data.scalar.length;
    char *anchor = (char *)self->event.data.scalar.anchor;
    char *tag = (char *)self->event.data.scalar.tag;
    char *prefix = TAG_PERL_PREFIX "code:";
    SV *code;

    if (strlen(tag) > strlen(prefix) && strnEQ(tag, prefix, strlen(prefix))) {
        char *klass = tag + strlen(prefix);
        if (self->flags & F_SAFEMODE &&
            (!self->safeclasses ||
             !hv_exists(self->safeclasses, klass, strlen(klass))))
        {
            Perl_warner(aTHX_ packWARN(WARN_MISC),
                        WARNMSG "skipped loading unsafe CODE for class %s",
                        klass);
            return &PL_sv_undef;
        }
    }

    if (!(self->flags & F_LOADCODE)) {
        tag = "";
        string = "{}";
        length = 2;
    }

    code = newSVpvn(string, length);
    SvUTF8_on(code);

    ENTER;
    SAVETMPS;
    PUSHMARK(sp);
    XPUSHs(code);
    PUTBACK;
    call_pv("YAML::Safe::__code_loader", G_SCALAR);
    SPAGAIN;
    code = newSVsv(POPs);

    PUTBACK;
    FREETMPS;
    LEAVE;

    if (strlen(tag) > strlen(prefix) && strnEQ(tag, prefix, strlen(prefix))) {
        if (!(self->flags & F_DISABLEBLESSED)) {
            char *klass = tag + strlen(prefix);
            sv_bless(code, gv_stashpv(klass, TRUE));
        }
    }

    if (anchor)
        (void)hv_store(self->anchors, anchor, strlen(anchor),
                       SvREFCNT_inc(code), 0);
    return code;
}


/*
 * Load a reference to a previously loaded node.
 */
static SV *
load_alias(YAML *self)
{
    char *anchor = (char *)self->event.data.alias.anchor;
    SV **entry = hv_fetch(self->anchors, anchor, strlen(anchor), 0);
    if (entry)
        return SvREFCNT_inc(*entry);
    croak("%sNo anchor for alias '%s'", ERRMSG, anchor);
}

/*
 * Load a Perl hard reference.
 */
SV *
load_scalar_ref(YAML *self)
{
    SV *value_node;
    char *anchor = (char *)self->event.data.mapping_start.anchor;
    SV *rv = newRV_noinc(&PL_sv_undef);
    if (anchor)
        (void)hv_store(self->anchors, anchor, strlen(anchor),
                       SvREFCNT_inc(rv), 0);
    load_node(self);  /* Load the single hash key (=) */
    value_node = load_node(self);
    SvRV(rv) = value_node;
    if (load_node(self))
        croak("%sExpected end of node", ERRMSG);
    return rv;
}

/*
 * Load a Perl typeglob.
 */
static SV *
load_glob(YAML *self)
{
    /* XXX Call back a Perl sub to do something interesting here */
    return load_mapping(self, (char*)TAG_PERL_PREFIX "hash");
}

/* -------------------------------------------------------------------------- */


/*
 * This is the main Dump function.
 * Take zero or more Perl objects from the stack
 * and return a YAML stream (as a string)
 */
int
Dump(YAML *self, int yaml_ix)
{
    dXSARGS;  /* does POPMARK */
    yaml_event_t event_stream_start;
    yaml_event_t event_stream_end;
    int i;
    SV *yaml = sv_2mortal(newSVpvn("", 0));

    sp = mark;

    yaml_emitter_initialize(&self->emitter);
    set_emitter_options(self, &self->emitter);
    yaml_emitter_set_output(
        &self->emitter,
        &yaml_sv_write_handler,
        (void *)yaml);

    yaml_stream_start_event_initialize(&event_stream_start, self->encoding);
    yaml_emitter_emit(&self->emitter, &event_stream_start);

    self->anchors = (HV *)sv_2mortal((SV *)newHV());
    self->shadows = (HV *)sv_2mortal((SV *)newHV());

    for (i = yaml_ix; i < items; i++) {
        self->anchor = 0;

        dump_prewalk(self, ST(i));
        dump_document(self, ST(i));

        hv_clear(self->anchors);
        hv_clear(self->shadows);
    }

    /* End emitting and destroy the emitter object */
    yaml_stream_end_event_initialize(&event_stream_end);
    yaml_emitter_emit(&self->emitter, &event_stream_end);
    yaml_emitter_delete(&self->emitter);

    /* Put the YAML stream scalar on the XS output stack */
    if (yaml) {
        sp = PL_stack_base + ax - 1; /* ax 0 */
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
DumpFile(YAML *self, SV *sv_file, int yaml_ix)
{
    dXSARGS;
    yaml_event_t event_stream_start;
    yaml_event_t event_stream_end;
    FILE *file = NULL;
    const char *fname;
    STRLEN len;
    long i;

    sp = mark;

    yaml_emitter_initialize(&self->emitter);
    set_emitter_options(self, &self->emitter);

    if (SvROK(sv_file)) { /* pv mg or io or gv */
        SV *rv = SvRV(sv_file);

        if (SvTYPE(rv) == SVt_PVIO) {
            self->perlio = IoOFP(rv);
            yaml_emitter_set_output(&self->emitter,
                                    &yaml_perlio_write_handler,
                                    self);
        } else if (SvTYPE(rv) == SVt_PVGV && GvIO(rv)) {
            self->perlio = IoOFP(GvIOp(SvRV(sv_file)));
            yaml_emitter_set_output(&self->emitter,
                                    &yaml_perlio_write_handler,
                                    self);
        } else if (SvMAGIC(rv)) {
            mg_get(rv);
            fname = SvPV_const(rv, len);
            goto pv_dump;
        } else if (SvAMAGIC(sv_file)) {
            fname = SvPV_const(sv_file, len);
            goto pv_dump;
        } else {
            croak("Invalid argument type for file: ref of %s", Perl_sv_peek(aTHX_ rv));
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
        self->filename = (char *)fname;
        yaml_emitter_set_output_file(&self->emitter, file);
    } else if (SvTYPE(sv_file) == SVt_PVIO) {
        self->perlio = IoOFP(sv_file);
        yaml_emitter_set_output(&self->emitter,
                                &yaml_perlio_write_handler,
                                self);
    } else if (SvTYPE(sv_file) == SVt_PVGV && GvIO(sv_file)) {
        self->perlio = IoOFP(GvIOp(sv_file));
        yaml_emitter_set_output(&self->emitter,
                                &yaml_perlio_write_handler,
                                self);
    } else {
        /* sv_peek since 5.005 */
        croak("Invalid argument type for file: %s", Perl_sv_peek(aTHX_ sv_file));
        return 0;
    }

    yaml_stream_start_event_initialize(&event_stream_start,
                                       self->encoding);
    if (!yaml_emitter_emit(&self->emitter, &event_stream_start)) {
        PUTBACK;
        return 0;
    }

    self->anchors = (HV *)sv_2mortal((SV *)newHV());
    self->shadows = (HV *)sv_2mortal((SV *)newHV());

    /* ST(yaml_ix) is the file */
    for (i = yaml_ix+1; i < items; i++) {
        self->anchor = 0;

        dump_prewalk(self, ST(i));
        dump_document(self, ST(i));

        hv_clear(self->anchors);
        hv_clear(self->shadows);
    }

    /* End emitting and destroy the emitter object */
    yaml_stream_end_event_initialize(&event_stream_end);
    if (!yaml_emitter_emit(&self->emitter, &event_stream_end)) {
        PUTBACK;
        return 0;
    }
    yaml_emitter_delete(&self->emitter);
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
dump_prewalk(YAML *self, SV *node)
{
    int i;
    U32 ref_type;

    if (! (SvROK(node) || SvTYPE(node) == SVt_PVGV)) return;

    {
        SV *object = SvROK(node) ? SvRV(node) : node;
        SV **seen =
            hv_fetch(self->anchors, (char *)&object, sizeof(object), 0);
        if (seen) {
            if (*seen == &PL_sv_undef) {
                (void)hv_store(self->anchors, (char *)&object, sizeof(object),
                               &PL_sv_yes, 0);
            }
            return;
        }
        (void)hv_store(self->anchors, (char *)&object, sizeof(object),
                       &PL_sv_undef, 0);
    }

    if (SvTYPE(node) == SVt_PVGV) {
        node = dump_glob(self, node);
    }

    ref_type = SvTYPE(SvRV(node));
    if (ref_type == SVt_PVAV) {
        AV *array = (AV *)SvRV(node);
        int array_size = av_len(array) + 1;
        for (i = 0; i < array_size; i++) {
            SV **entry = av_fetch(array, i, 0);
            if (entry)
                dump_prewalk(self, *entry);
        }
    }
    else if (ref_type == SVt_PVHV) {
        HV *hash = (HV *)SvRV(node);
        HE *he;
        hv_iterinit(hash);
        while ((he = hv_iternext(hash))) {
            SV *val = HeVAL(he);
            if (val)
                dump_prewalk(self, val);
        }
    }
    else if (ref_type <= SVt_PVNV || ref_type == SVt_PVGV) {
        SV *scalar = SvRV(node);
        dump_prewalk(self, scalar);
    }
}

static void
dump_document(YAML *self, SV *node)
{
    yaml_event_t event_document_start;
    yaml_event_t event_document_end;
    yaml_document_start_event_initialize(
        &event_document_start, NULL, NULL, NULL, 0);
    yaml_emitter_emit(&self->emitter, &event_document_start);
    dump_node(self, node);
    yaml_document_end_event_initialize(&event_document_end, 1);
    yaml_emitter_emit(&self->emitter, &event_document_end);
}

static void
dump_node(YAML *self, SV *node)
{
    yaml_char_t *anchor = NULL;
    yaml_char_t *tag = NULL;
    const char *klass = NULL;

    if (SvTYPE(node) == SVt_PVGV) {
        SV **svr;
        tag = (yaml_char_t *)TAG_PERL_PREFIX "glob";
        anchor = get_yaml_anchor(self, node);
        if (anchor && strEQ((char *)anchor, ""))
            return;
        svr = hv_fetch(self->shadows, (char *)&node, sizeof(node), 0);
        if (svr) {
            node = SvREFCNT_inc(*svr);
        }
    }

    if (SvROK(node)) {
        SV *rnode = SvRV(node);
        U32 ref_type = SvTYPE(rnode);
        if (ref_type == SVt_PVHV)
            dump_hash(self, node, anchor, tag);
        else if (ref_type == SVt_PVAV)
            dump_array(self, node);
        else if (ref_type <= SVt_PVNV || ref_type == SVt_PVGV)
            dump_ref(self, node);
        else if (ref_type == SVt_PVCV)
            dump_code(self, node);
        else if (ref_type == SVt_PVMG) {
            MAGIC *mg;
            yaml_char_t *tag = NULL;
            if (SvMAGICAL(rnode)) {
                if ((mg = mg_find(rnode, PERL_MAGIC_qr))) {
                    tag = (yaml_char_t *)form(TAG_PERL_PREFIX "regexp");
                    klass = sv_reftype(rnode, TRUE);
                    if (!strEQ(klass, "Regexp"))
                        tag = (yaml_char_t *)form("%s:%s", tag, klass);
                }
                dump_scalar(self, node, tag);
            }
            else {
                klass = sv_reftype(rnode, TRUE);
                if (self->boolean != YAML_BOOLEAN_NONE) {
                    if (SvIV(node))
                        dump_scalar(self, &PL_sv_yes, NULL);
                    else
                        dump_scalar(self, &PL_sv_no, NULL);
                }
                else {
                    tag = (yaml_char_t *)form(
                        TAG_PERL_PREFIX "scalar:%s",
                        klass);
                    node = rnode;
                    dump_scalar(self, node, tag);
                }
            }
        }
#if PERL_VERSION >= 11
        else if (ref_type == SVt_REGEXP) {
            yaml_char_t *tag = (yaml_char_t *)form(TAG_PERL_PREFIX "regexp");
            klass = sv_reftype(rnode, TRUE);
            if (!strEQ(klass, "Regexp"))
                tag = (yaml_char_t *)form("%s:%s", tag, klass);
            dump_scalar(self, node, tag);
        }
#endif
        else {
            printf("YAML::Safe dump unhandled ref. type == '%d'!\n",
                   (int)ref_type);
            dump_scalar(self, rnode, NULL);
        }
    }
    else {
        dump_scalar(self, node, NULL);
    }
}

static yaml_char_t *
get_yaml_anchor(YAML *self, SV *node)
{
    yaml_event_t event_alias;
    SV *iv;
    SV **seen = hv_fetch(self->anchors, (char *)&node, sizeof(node), 0);
    if (seen && *seen != &PL_sv_undef) {
        if (*seen == &PL_sv_yes) {
            self->anchor++;
            iv = newSViv(self->anchor);
            (void)hv_store(self->anchors, (char *)&node, sizeof(node), iv, 0);
            return (yaml_char_t*)SvPV_nolen(iv);
        }
        else {
            yaml_char_t *anchor = (yaml_char_t *)SvPV_nolen(*seen);
            yaml_alias_event_initialize(&event_alias, anchor);
            yaml_emitter_emit(&self->emitter, &event_alias);
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
            if (strEQ(klass, "CODE"))
                tag = (yaml_char_t *)form("%s%s", TAG_PERL_PREFIX, kind);
            else
                tag = (yaml_char_t *)form("%s%s:%s", TAG_PERL_PREFIX, kind, klass);
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
    YAML *self, SV *node,
    yaml_char_t *anchor, yaml_char_t *tag)
{
    yaml_event_t event_mapping_start;
    yaml_event_t event_mapping_end;
    STRLEN i, len;
    AV *av;
    HV *hash = (HV *)SvRV(node);
    HE *he;

    if (!anchor)
        anchor = get_yaml_anchor(self, (SV *)hash);
    if (anchor && strEQ((char*)anchor, ""))
        return;

    if (!tag)
        tag = get_yaml_tag(node);
    if (tag && self->flags & F_SAFEMODE) {
        char *prefix = TAG_PERL_PREFIX "hash:";
        char *klass = (char*)tag + strlen(prefix);
        STRLEN len = strlen(klass);
        if (SvOBJECT(node)) {
            HV* stash = SvSTASH(node);
            klass = HvNAME_get(stash);
            len = HvNAMELEN_get(stash);
            if (HvNAMEUTF8(stash))
                len = -len;
        }
        if (!self->safeclasses ||
            !hv_exists(self->safeclasses, klass, len))
        {
            Perl_warner(aTHX_ packWARN(WARN_MISC),
                        WARNMSG "skipped dumping unsafe HASH in class %s",
                        klass);
            hash = (HV*)sv_2mortal((SV*)newHV());
        }
    }

    yaml_mapping_start_event_initialize(
        &event_mapping_start, anchor, tag, 0, YAML_BLOCK_MAPPING_STYLE);
    yaml_emitter_emit(&self->emitter, &event_mapping_start);

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
        if (val == NULL)
            val = &PL_sv_undef;
        dump_node(self, key);
        dump_node(self, val);
    }

    SvREFCNT_dec(av);

    yaml_mapping_end_event_initialize(&event_mapping_end);
    yaml_emitter_emit(&self->emitter, &event_mapping_end);
}

static void
dump_array(YAML *self, SV *node)
{
    yaml_event_t event_sequence_start;
    yaml_event_t event_sequence_end;
    yaml_char_t *tag;
    AV *array = (AV *)SvRV(node);
    STRLEN i;
    STRLEN array_size = av_len(array) + 1;

    yaml_char_t *anchor = get_yaml_anchor(self, (SV *)array);
    if (anchor && strEQ((char *)anchor, ""))
        return;
    tag = get_yaml_tag(node);
    if (tag && self->flags & F_SAFEMODE) {
        char *prefix = TAG_PERL_PREFIX "array:";
        char *klass = (char*)tag + strlen(prefix);
        STRLEN len = strlen(klass);
        if (SvOBJECT(node)) {
            HV* stash = SvSTASH(node);
            klass = HvNAME_get(stash);
            len = HvNAMELEN_get(stash);
            if (HvNAMEUTF8(stash))
                len = -len;
        }
        if (!self->safeclasses ||
            !hv_exists(self->safeclasses, klass, len))
        {
            Perl_warner(aTHX_ packWARN(WARN_MISC),
                        WARNMSG "skipped dumping unsafe ARRAY in class %s",
                        klass);
            array_size = 0;
        }
    }

    yaml_sequence_start_event_initialize(
        &event_sequence_start, anchor, tag, 0, YAML_BLOCK_SEQUENCE_STYLE);
    yaml_emitter_emit(&self->emitter, &event_sequence_start);

    for (i = 0; i < array_size; i++) {
        SV **entry = av_fetch(array, i, 0);
        if (entry == NULL)
            dump_node(self, &PL_sv_undef);
        else
            dump_node(self, *entry);
    }
    yaml_sequence_end_event_initialize(&event_sequence_end);
    yaml_emitter_emit(&self->emitter, &event_sequence_end);
}

static void
dump_scalar(YAML *self, SV *node, yaml_char_t *tag)
{
    yaml_event_t event_scalar;
    char *string;
    STRLEN string_len;
    int plain_implicit, quoted_implicit;
    yaml_scalar_style_t style = YAML_PLAIN_SCALAR_STYLE;

    if (tag) {
        if (self->flags & F_SAFEMODE && SvOBJECT(node)) {
            HV* stash = SvSTASH(node);
            char *klass = HvNAME_get(stash);
            STRLEN len = HvNAMELEN_get(stash);
            if (HvNAMEUTF8(stash))
                len = -len;
            if (!self->safeclasses ||
                !hv_exists(self->safeclasses, klass, len))
            {
                Perl_warner(aTHX_ packWARN(WARN_MISC),
                            WARNMSG "skipped dumping unsafe SCALAR for class %s",
                            klass);
                node = &PL_sv_undef;
            }
        }
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
        SV *node_clone = sv_mortalcopy(node);
        string = SvPV_nomg(node_clone, string_len);
        if (
            (string_len == 0) ||
            (string_len == 1 && strEQ(string, "~")) ||
            (string_len == 4 &&
             (strEQ(string, "true") || strEQ(string, "null"))) ||
            (string_len == 5 && strEQ(string, "false")) ||
            (SvTYPE(node_clone) >= SVt_PVGV) ||
            ( (self->flags & F_QUOTENUM) &&
              !SvNIOK(node_clone) &&
              looks_like_number(node_clone) ) )
        {
            style = YAML_SINGLE_QUOTED_SCALAR_STYLE;
        } else {
            if (!SvUTF8(node_clone)) {
                /* copy to new SV and promote to utf8 */
                SV *utf8sv = sv_mortalcopy(node_clone);

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
        style);
    if (! yaml_emitter_emit(&self->emitter, &event_scalar))
        croak("%sEmit scalar '%s', error: %s\n",
            ERRMSG, string, self->emitter.problem);
}

static void
dump_code(YAML *self, SV *node)
{
    yaml_event_t event_scalar;
    yaml_char_t *tag;
    yaml_scalar_style_t style = YAML_SINGLE_QUOTED_SCALAR_STYLE;
    char *string = "{ \"DUMMY\" }";

    tag = get_yaml_tag(node);

    if (self->flags & F_DUMPCODE) {
        /* load_module(PERL_LOADMOD_NOIMPORT, newSVpv("B::Deparse", 0), NULL);
         */
        SV *code;
        SV *result = NULL;
        if (self->flags & F_SAFEMODE) {
            char *klass; STRLEN len;
            SV* rnode = SvRV(node);
            HV* stash = SvOBJECT(rnode)
                ? SvSTASH(rnode)
                : GvSTASH(CvGV(rnode));
            if (!stash)
                stash = CvSTASH(rnode);
            klass = HvNAME_get(stash);
            len = HvNAMELEN_get(stash);
            if (HvNAMEUTF8(stash))
                len = -len;
            if (!self->safeclasses || !hv_exists(self->safeclasses, klass, len)) {
                Perl_warner(aTHX_ packWARN(WARN_MISC),
                            WARNMSG "skipped dumping unsafe CODE for class %s",
                            klass);
                string = "{ \"UNSAFE\" }";
                result = &PL_sv_undef;
            }
        }
        if (result != &PL_sv_undef) {
            AV *args = newAV();
            av_push(args, SvREFCNT_inc(node));
            code = find_coderef("YAML::Safe::coderef2text");
            result = call_coderef(code, (AV*)sv_2mortal((SV *)args));
        }
        if (result && result != &PL_sv_undef) {
            string = SvPV_nolen(result);
            style = YAML_LITERAL_SCALAR_STYLE;
        }
    }

    yaml_scalar_event_initialize(
        &event_scalar,
        NULL, /* anchor */
        tag,
        (unsigned char *)string,
        string ? strlen(string) : 0,
        0,
        0,
        style);
    yaml_emitter_emit(&self->emitter, &event_scalar);
}

static SV *
dump_glob(YAML *self, SV *node)
{
    SV *result;
    SV *code = find_coderef("YAML::Safe::glob2hash");
    AV *args = newAV();
    /* TODO: safemode */
    av_push(args, SvREFCNT_inc(node));
    args = (AV *)sv_2mortal((SV *)args);
    result = call_coderef(code, args);
    (void)hv_store(self->shadows, (char *)&node, sizeof(node),
                   result, 0);
    return result;
}

/* XXX Refo this to just dump a special map */
static void
dump_ref(YAML *self, SV *node)
{
    yaml_event_t event_mapping_start;
    yaml_event_t event_mapping_end;
    yaml_event_t event_scalar;
    SV *referent = SvRV(node);

    yaml_char_t *anchor = get_yaml_anchor(self, referent);
    if (anchor && strEQ((char *)anchor, ""))
        return;

    yaml_mapping_start_event_initialize(
        &event_mapping_start, anchor,
        (unsigned char *)TAG_PERL_PREFIX "ref",
        0, YAML_BLOCK_MAPPING_STYLE);
    yaml_emitter_emit(&self->emitter, &event_mapping_start);

    yaml_scalar_event_initialize(
        &event_scalar,
        NULL, /* anchor */
        NULL, /* tag */
        (unsigned char *)"=", 1,
        1, 1,
        YAML_PLAIN_SCALAR_STYLE);
    yaml_emitter_emit(&self->emitter, &event_scalar);
    dump_node(self, referent);

    yaml_mapping_end_event_initialize(&event_mapping_end);
    yaml_emitter_emit(&self->emitter, &event_mapping_end);
}

static int
yaml_sv_write_handler(void *sv, unsigned char *buffer, size_t size)
{
    sv_catpvn((SV *)sv, (const char *)buffer, (STRLEN)size);
    return 1;
}

static int
yaml_perlio_read_handler(void *data, unsigned char *buffer, size_t size, size_t *size_read)
{
    YAML *self = (YAML *)data;

    *size_read = PerlIO_read(self->perlio, buffer, size);
    return !PerlIO_error(self->perlio);
}

static int
yaml_perlio_write_handler(void *data, unsigned char *buffer, size_t size)
{
    YAML *self = (YAML *)data;
    return (PerlIO_write(self->perlio, (char*)buffer, (long)size) == (SSize_t)size);
}

/* XXX Make -Wall not complain about 'local_patches' not being used. */
#if !defined(PERL_PATCHLEVEL_H_IMPLICIT)
void xxx_local_patches() {
    printf("%s", local_patches[0]);
}
#endif

void
yaml_destroy (YAML *self)
{
    if (!self)
        return;
    /* self->filename gets deleted with sv_file */
    yaml_parser_delete (&self->parser);
    yaml_event_delete (&self->event);
    yaml_emitter_delete (&self->emitter);
    Zero(self, 1, YAML);
}
