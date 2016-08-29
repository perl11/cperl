/*    mro.h
 *
 *    Copyright (C) 1991, 1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000,
 *    2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008 by Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */


/* Subject to change.
   Don't access this directly.
   Use the funcs in mro_core.c
*/

struct mro_alg {
    AV *(*resolve)(pTHX_ HV* stash, U32 level);
    const char *name;
    U16 length;
    U16	kflags;	/* For the hash API - set HVhek_UTF8 if name is UTF-8 */
    U32 hash; /* or 0 */
};

struct mro_meta {
    /* a hash holding the different MROs private data.  */
    HV      *mro_linear_all;
    /* a pointer directly to the current MROs private data.  If mro_linear_all
       is NULL, this owns the SV reference, else it is just a pointer to a
       value stored in and owned by mro_linear_all.  */
    SV      *mro_linear_current;
    HV      *mro_nextmethod; /* next::method caching */
    U32     cache_gen;       /* Bumping this invalidates our method cache */
    U32     pkg_gen;         /* Bumps when local methods/@ISA change */
    const struct mro_alg *mro_which; /* which mro alg is in use? */
    HV      *isa;            /* Everything this class @ISA */
    HV      *super;          /* SUPER method cache */
    CV      *destroy;        /* DESTROY method if destroy_gen non-zero */
    U32     destroy_gen;     /* Generation number of DESTROY cache */
};

#define MRO_GET_PRIVATE_DATA(smeta, which)		   \
    (((smeta)->mro_which && (which) == (smeta)->mro_which) \
     ? (smeta)->mro_linear_current			   \
     : Perl_mro_get_private_data(aTHX_ (smeta), (which)))

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
