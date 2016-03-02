#include <perl_libyaml.h>
/* XXX Make -Wall not complain about 'local_patches' not being used. */
#if !defined(PERL_PATCHLEVEL_H_IMPLICIT)
void xxx_local_patches_xs() { printf("%s", local_patches[0]); }
#endif

MODULE = YAML::XS::LibYAML		PACKAGE = YAML::XS::LibYAML		

PROTOTYPES: DISABLE

void
Load (yaml_sv)
        SV *yaml_sv
        PPCODE:
        PL_markstack_ptr++;
        Load(yaml_sv);
        return;

void
LoadFile (yaml_fname)
        SV *yaml_fname
        PPCODE:
        PL_markstack_ptr++;
        LoadFile(yaml_fname);
        return;

void
Dump (...)
        PPCODE:
        SV *dummy = NULL;
        PL_markstack_ptr++;
        Dump(dummy);
        return;

