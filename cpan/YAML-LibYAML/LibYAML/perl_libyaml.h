/* These definitions affect -pedantic warnings...

#define PERL_GCC_BRACE_GROUPS_FORBIDDEN 1
#define __STRICT_ANSI__ 1
#define PERL_GCC_PEDANTIC 1
*/

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_newRV_noinc
#define NEED_sv_2pv_nolen
#define NEED_sv_2pvbyte
#include "ppport.h"
#include <yaml.h>
#include <ppport_sort.h>

#define TAG_PERL_PREFIX "tag:yaml.org,2002:perl/"
#define TAG_PERL_REF TAG_PERL_PREFIX "ref"
#define TAG_PERL_STR TAG_PERL_PREFIX "str"
#define TAG_PERL_GLOB TAG_PERL_PREFIX "glob"
#define ERRMSG "YAML::XS Error: "
#define LOADERRMSG "YAML::XS::Load Error: "
#define LOADFILEERRMSG "YAML::XS::LoadFile Error: "
#define DUMPERRMSG "YAML::XS::Dump Error: "

typedef struct {
    yaml_parser_t parser;
    yaml_event_t event;
    HV *anchors;
    int load_code;
    int document;
    char *filename;
} perl_yaml_loader_t;

typedef struct {
    yaml_emitter_t emitter;
    long anchor;
    HV *anchors;
    HV *shadows;
    int dump_code;
    int quote_number_strings;
    char *filename;
} perl_yaml_dumper_t;

static SV *
call_coderef(SV *, AV *);

static SV *
fold_results(I32);

static SV *
find_coderef(char *);

yaml_encoding_t
set_dumper_options(perl_yaml_dumper_t *);

yaml_encoding_t
set_loader_options(perl_yaml_loader_t *);

int
Dump(SV *);

int
DumpFile(SV *);

int
Load(SV *);

int
LoadFile(SV *);

SV *
load_node(perl_yaml_loader_t *);

SV *
load_mapping(perl_yaml_loader_t *, char *);

SV *
load_sequence(perl_yaml_loader_t *);

SV *
load_scalar(perl_yaml_loader_t *);

SV *
load_alias(perl_yaml_loader_t *);

SV *
load_scalar_ref(perl_yaml_loader_t *);

SV *
load_regexp(perl_yaml_loader_t *);

SV *
load_glob(perl_yaml_loader_t *);


void
dump_prewalk(perl_yaml_dumper_t *, SV *);

void
dump_document(perl_yaml_dumper_t *, SV *);

void
dump_node(perl_yaml_dumper_t *, SV *);

void
dump_hash(perl_yaml_dumper_t *, SV *, yaml_char_t *, yaml_char_t *);

void
dump_array(perl_yaml_dumper_t *, SV *);

void
dump_scalar(perl_yaml_dumper_t *, SV *, yaml_char_t *);

void
dump_ref(perl_yaml_dumper_t *, SV *);

void
dump_code(perl_yaml_dumper_t *, SV *);

SV*
dump_glob(perl_yaml_dumper_t *, SV *);


yaml_char_t *
get_yaml_anchor(perl_yaml_dumper_t *, SV *);

yaml_char_t *
get_yaml_tag(SV *);


int
append_output(void *, unsigned char *, size_t size);

