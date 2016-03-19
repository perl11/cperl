#include <perl_libyaml.h>

/* XXX Make -Wall not complain about 'local_patches' not being used. */
#if !defined(PERL_PATCHLEVEL_H_IMPLICIT)
void xxx_local_patches_xs() { printf("%s", local_patches[0]); }
#endif

MODULE = YAML::XS::LibYAML		PACKAGE = YAML::XS::LibYAML		

PROTOTYPES: DISABLE

void
Load (yaml_string)
        SV *yaml_string
  PPCODE:
        PL_markstack_ptr++;
        if (!Load(yaml_string))
            XSRETURN_UNDEF;
        else
            return;

void
LoadFile (yaml_file)
        SV *yaml_file
  PPCODE:
        PL_markstack_ptr++;
        if (!LoadFile(yaml_file))
            XSRETURN_UNDEF;
        else
            return;

void
Dump (...)
  PPCODE:
        PL_markstack_ptr++;
        if (!Dump())
            XSRETURN_UNDEF;
        else
            return;

void
DumpFile (yaml_file, ...)
        SV *yaml_file
  PPCODE:
        PL_markstack_ptr++;
        if (!DumpFile(yaml_file))
            XSRETURN_UNDEF;
        else
            XSRETURN_YES;
