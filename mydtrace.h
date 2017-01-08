/*    mydtrace.h
 *
 *    Copyright (C) 2008, 2010, 2011 by Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 *	Provides macros that wrap the various DTrace probes we use. We add
 *	an extra level of wrapping to encapsulate the _ENABLED tests.
 */

#if defined(USE_DTRACE) && defined(PERL_CORE)

#  include "perldtrace.h"

#  define PERL_DTRACE_PROBE_SUB_ENTRY(cv)           \
    if (PERL_SUB_ENTRY_ENABLED())                   \
        Perl_dtrace_probe_call(aTHX_ cv, TRUE);

#  define PERL_DTRACE_PROBE_SUB_RETURN(cv)          \
    if (PERL_SUB_RETURN_ENABLED())                  \
        Perl_dtrace_probe_call(aTHX_ cv, FALSE);

#  define PERL_DTRACE_PROBE_LOAD_ENTRY(name)        \
    if (PERL_LOAD_ENTRY_ENABLED())                  \
        Perl_dtrace_probe_load(aTHX_ name, TRUE);

#  define PERL_DTRACE_PROBE_LOAD_RETURN(name)       \
    if (PERL_LOAD_RETURN_ENABLED())                 \
        Perl_dtrace_probe_load(aTHX_ name, FALSE);

#  define PERL_DTRACE_PROBE_OP(op)                  \
    if (PERL_OP_ENTRY_ENABLED())                    \
        Perl_dtrace_probe_op(aTHX_ op);

#  define PERL_DTRACE_PROBE_PHASE(phase)            \
    if (PERL_PHASE_CHANGE_ENABLED())                \
        Perl_dtrace_probe_phase(aTHX_ phase);

#  define PERL_DTRACE_PROBE_GLOB_ENTRY(mode, name)  \
    if (PERL_GLOB_ENTRY_ENABLED())                  \
        Perl_dtrace_probe_glob(aTHX_ mode, name, TRUE);

#  define PERL_DTRACE_PROBE_GLOB_RETURN(mode, name) \
    if (PERL_GLOB_RETURN_ENABLED())                 \
        Perl_dtrace_probe_glob(aTHX_ mode, name, FALSE);

#  define PERL_DTRACE_PROBE_HASH_ENTRY(mode, name)  \
    if (PERL_HASH_ENTRY_ENABLED())                  \
        Perl_dtrace_probe_hash(aTHX_ mode, name, TRUE);

#  define PERL_DTRACE_PROBE_HASH_RETURN(mode, name) \
    if (PERL_HASH_RETURN_ENABLED())                 \
        Perl_dtrace_probe_hash(aTHX_ mode, name, FALSE);

#else

/* NOPs */
#  define PERL_DTRACE_PROBE_SUB_ENTRY(cv)
#  define PERL_DTRACE_PROBE_SUB_RETURN(cv)
#  define PERL_DTRACE_PROBE_LOAD_ENTRY(fn)
#  define PERL_DTRACE_PROBE_LOAD_RETURN(fn)
#  define PERL_DTRACE_PROBE_OP(op)
#  define PERL_DTRACE_PROBE_PHASE(phase)
#  define PERL_DTRACE_PROBE_GLOB_ENTRY(mode, name)
#  define PERL_DTRACE_PROBE_GLOB_RETURN(mode, name)
#  define PERL_DTRACE_PROBE_HASH_ENTRY(mode, name)
#  define PERL_DTRACE_PROBE_HASH_RETURN(mode, name)

#endif

#define PERL_DTRACE_GLOB_MODE_INIT      0
#define PERL_DTRACE_GLOB_MODE_ADD       1
#define PERL_DTRACE_GLOB_MODE_FETCH     2
#define PERL_DTRACE_GLOB_MODE_FETCHMETH 3

#define PERL_DTRACE_HASH_MODE_FETCH     0
#define PERL_DTRACE_HASH_MODE_STORE     1
#define PERL_DTRACE_HASH_MODE_EXISTS    2
#define PERL_DTRACE_HASH_MODE_DELETE    3

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
