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
    PerlIO *perlio;
} perl_yaml_loader_t;

typedef struct {
    yaml_emitter_t emitter;
    long anchor;
    HV *anchors;
    HV *shadows;
    int dump_code;
    int quote_number_strings;
    char *filename;
    PerlIO *perlio;
} perl_yaml_dumper_t;

int
Dump();

int
DumpFile(SV *);

int
Load(SV *);

int
LoadFile(SV *);

