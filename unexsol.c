/* Trivial unexec for Solaris.  */

#include "unexec.h"
#define PERLIO_NOT_STDIO 0
#include "EXTERN.h"
#define PERL_IN_UNEXEC_C
#include "perl.h"
#define fatal Perl_croak_nocontext

#include <dlfcn.h>

void
unexec (const char *new_name, const char *old_name)
{
  if (! dldump (0, new_name, RTLD_MEMORY))
    return;

  fatal ("unexec: dldump to %s failed. %s", new_name, dlerror());
}
