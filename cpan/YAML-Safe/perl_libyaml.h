/* These definitions affect -pedantic warnings...

#define PERL_GCC_BRACE_GROUPS_FORBIDDEN 1
#define __STRICT_ANSI__ 1
#define PERL_GCC_PEDANTIC 1
*/

#include "EXTERN.h"
#include "perl.h"
#define NO_XSLOCKS
#include "XSUB.h"
#define NEED_newRV_noinc
#define NEED_sv_2pv_nolen
#define NEED_sv_2pvbyte
#define NEED_gv_fetchpvn_flags
#include "ppport.h"
#include "yaml.h"
#include "ppport_sort.h"

#ifndef PERL_STATIC_INLINE
#define PERL_STATIC_INLINE static
#endif

#if PERL_VERSION < 5
#define sv_peek(pTHX_ sv_file) ""
#endif

/* 5.8.9 */
#ifndef GV_NOADD_NOINIT
# ifdef GV_NOINIT
#  define GV_NOADD_NOINIT GV_NOINIT
# else
#  define GV_NOADD_NOINIT 0
# endif
#endif

#ifndef HvNAMEUTF8
# define HvNAMEUTF8(hv) 0
#endif

#define TAG_PERL_PREFIX "tag:yaml.org,2002:perl/"
#define TAG_PERL_REF TAG_PERL_PREFIX "ref"
#define TAG_PERL_STR TAG_PERL_PREFIX "str"
#define TAG_PERL_GLOB TAG_PERL_PREFIX "glob"
#define ERRMSG "yaml error: "
#define WARNMSG "YAML::Safe warning: "

#define F_UNICODE          0x00000001
#define F_DISABLEBLESSED   0x00000002
#define F_QUOTENUM         0x00000004
#define F_NONSTRICT        0x00000008
#define F_LOADCODE         0x00000010
#define F_DUMPCODE         0x00000020
/* both: */
#define F_ENABLECODE       0x00000030
#define F_NOINDENTMAP      0x00000040
#define F_CANONICAL        0x00000080
#define F_OPENENDED        0x00000100
#define F_SAFEMODE         0x00000200

typedef enum {
    YAML_BOOLEAN_NONE = 0,
    YAML_BOOLEAN_JSONPP,
    YAML_BOOLEAN_BOOLEAN,
} yaml_boolean_t;

typedef struct {
    yaml_parser_t  parser; /* inlined */
    yaml_event_t   event;
    yaml_emitter_t emitter;
    U32 flags;
    char *filename;
    PerlIO *perlio;
    HV *anchors;
    HV *shadows;
    HV *safeclasses;
    long anchor;
    int document;
    int indent;
    int wrapwidth;
    yaml_encoding_t encoding;
    yaml_break_t linebreak;
    yaml_boolean_t boolean;
} YAML;

#if 0
typedef struct {
    YAML yaml; /* common options */
    yaml_parser_t parser;
    yaml_event_t event;
    int document;
    HV *anchors;
} perl_yaml_loader_t;

typedef struct {
    YAML yaml; /* common options */
    yaml_emitter_t emitter;
    long anchor;
    HV *anchors;
    HV *shadows;
} perl_yaml_dumper_t;

PERL_STATIC_INLINE YAML*
yaml_new ()
{
  return (YAML*)calloc(1, sizeof(YAML));
}
#endif

PERL_STATIC_INLINE YAML*
yaml_init (YAML *self)
{
  Zero (self, 1, YAML);
  self->flags = F_UNICODE|F_QUOTENUM;
  self->indent = 2;
  self->wrapwidth = 80;
  return self;
}

void
yaml_destroy (YAML *self);

int
Dump(YAML*, int);

int
DumpFile(YAML*, SV*, int);

int
Load(YAML*, SV*);

int
LoadFile(YAML*, SV*);

void
set_parser_options(YAML *self, yaml_parser_t *parser);
void
set_emitter_options(YAML *self, yaml_emitter_t *emitter);
