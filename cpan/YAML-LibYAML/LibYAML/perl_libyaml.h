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
#include "ppport.h"

#ifndef GV_NOADD_NOINIT
#define GV_NOADD_NOINIT 0
#endif
#ifndef SvIV_please
#define SvIV_please(sv) \
  STMT_START {if (!SvIOKp(sv) && (SvFLAGS(sv) & (SVf_NOK|SVf_POK))) \
      (void) SvIV(sv); } STMT_END
#endif
#ifndef memEQs
/* checks length before. */
#define memEQs(s1, l, s2) \
	(sizeof(s2)-1 == l && memEQ(s1, ("" s2 ""), (sizeof(s2)-1)))
#endif
/* cperl optims */
#ifndef strEQc
/* the buffer ends with \0, includes comparison of the \0.
   better than strEQ as it uses memcmp, word-wise comparison. */
#define strEQc(s, c) memEQ(s, ("" c ""), sizeof(c))
#endif

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
    int document;
    char *filename;
    PerlIO *perlio;
    unsigned disable_code     : 1;	/** security: disable loading code */
    unsigned disable_blessed  : 1;	/** security: disable blessing objects */
} perl_yaml_loader_t;

typedef struct {
    yaml_emitter_t emitter;
    long anchor;
    HV *anchors;
    HV *shadows;
    char *filename;
    PerlIO *perlio;
    unsigned dump_code : 1;		/** security: disable dumping code */
    unsigned quote_number_strings : 1;
} perl_yaml_dumper_t;

int
Dump();

int
DumpFile(SV *);

int
Load(SV *);

int
LoadFile(SV *);

