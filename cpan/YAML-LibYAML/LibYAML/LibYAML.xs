#include <perl_libyaml.h>
/* XXX Make -Wall not complain about 'local_patches' not being used. */
#if !defined(PERL_PATCHLEVEL_H_IMPLICIT)
void xxx_local_patches_xs() { printf("%s", local_patches[0]); }
#endif

MODULE = YAML::XS::LibYAML		PACKAGE = YAML::XS::LibYAML		

PROTOTYPES: DISABLE

SV*
Load (yaml_sv)
        SV *yaml_sv
  PPCODE:
        PL_markstack_ptr++;
        if (!Load(yaml_sv))
          XSRETURN_UNDEF;

SV*
LoadFile (yaml_fname)
        SV *yaml_fname
  PPCODE:
        PL_markstack_ptr++;
        if (!LoadFile(yaml_fname))
          XSRETURN_UNDEF;

SV*
Dump (...)
  PPCODE:
        SV *dummy = NULL;
        PL_markstack_ptr++;
        if (!Dump(dummy))
          XSRETURN_UNDEF;

SV*
DumpFile (yaml_fname)
        SV *yaml_fname
  PPCODE:
        PL_markstack_ptr++;
        if (!DumpFile(yaml_fname))
          XSRETURN_UNDEF;
