/*    locale.c
 *
 *    Copyright (C) 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001,
 *    2002, 2003, 2005, 2006, 2007, 2008 by Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

/*
 *      A Elbereth Gilthoniel,
 *      silivren penna míriel
 *      o menel aglar elenath!
 *      Na-chaered palan-díriel
 *      o galadhremmin ennorath,
 *      Fanuilos, le linnathon
 *      nef aear, si nef aearon!
 *
 *     [p.238 of _The Lord of the Rings_, II/i: "Many Meetings"]
 */

/* utility functions for handling locale-specific stuff like what
 * character represents the decimal point.
 *
 * All C programs have an underlying locale.  Perl code generally doesn't pay
 * any attention to it except within the scope of a 'use locale'.  For most
 * categories, it accomplishes this by just using different operations if it is
 * in such scope than if not.  However, various libc functions called by Perl
 * are affected by the LC_NUMERIC category, so there are macros in perl.h that
 * are used to toggle between the current locale and the C locale depending on
 * the desired behavior of those functions at the moment.  And, LC_MESSAGES is
 * switched to the C locale for outputting the message unless within the scope
 * of 'use locale'.
 */

#include "EXTERN.h"
#define PERL_IN_LOCALE_C
#include "perl_langinfo.h"
#include "perl.h"

#include "reentr.h"

/* If the environment says to, we can output debugging information during
 * initialization.  This is done before option parsing, and before any thread
 * creation, so can be a file-level static */
#ifdef DEBUGGING
#  ifdef PERL_GLOBAL_STRUCT
  /* no global syms allowed */
#    define debug_initialization 0
#    define DEBUG_INITIALIZATION_set(v)
#  else
static bool debug_initialization = FALSE;
#    define DEBUG_INITIALIZATION_set(v) (debug_initialization = v)
#  endif
#endif

/* strlen() of a literal string constant.  XXX We might want this more general,
 * but using it in just this file for now */
#define STRLENs(s)  (sizeof("" s "") - 1)

/* Is the C string input 'name' "C" or "POSIX"?  If so, and 'name' is the
 * return of setlocale(), then this is extremely likely to be the C or POSIX
 * locale.  However, the output of setlocale() is documented to be opaque, but
 * the odds are extremely small that it would return these two strings for some
 * other locale.  Note that VMS in these two locales includes many non-ASCII
 * characters as controls and punctuation (below are hex bytes):
 *   cntrl:  84-97 9B-9F
 *   punct:  A1-A3 A5 A7-AB B0-B3 B5-B7 B9-BD BF-CF D1-DD DF-EF F1-FD
 * Oddly, none there are listed as alphas, though some represent alphabetics
 * http://www.nntp.perl.org/group/perl.perl5.porters/2013/02/msg198753.html */
#define isNAME_C_OR_POSIX(name)                                              \
                             (   (name) != NULL                              \
                              && (( *(name) == 'C' && (*(name + 1)) == '\0') \
                                   || strEQc((name), "POSIX")))

#ifdef USE_LOCALE

/*
 * Standardize the locale name from a string returned by 'setlocale', possibly
 * modifying that string.
 *
 * The typical return value of setlocale() is either
 * (1) "xx_YY" if the first argument of setlocale() is not LC_ALL
 * (2) "xa_YY xb_YY ..." if the first argument of setlocale() is LC_ALL
 *     (the space-separated values represent the various sublocales,
 *      in some unspecified order).  This is not handled by this function.
 *
 * In some platforms it has a form like "LC_SOMETHING=Lang_Country.866\n",
 * which is harmful for further use of the string in setlocale().  This
 * function removes the trailing new line and everything up through the '='
 *
 */
STATIC char *
S_stdize_locale(pTHX_ char *locs)
{
    const char * const s = strchr(locs, '=');
    bool okay = TRUE;

    PERL_ARGS_ASSERT_STDIZE_LOCALE;

    if (s) {
	const char * const t = strchr(s, '.');
	okay = FALSE;
	if (t) {
	    const char * const u = strchr(t, '\n');
	    if (u && (u[1] == 0)) {
		const STRLEN len = u - s;
		Move(s + 1, locs, len, char);
		locs[len] = 0;
		okay = TRUE;
	    }
	}
    }

    if (!okay)
	Perl_croak(aTHX_ "Can't fix broken locale name \"%s\"", locs);

    return locs;
}

/* Two parallel arrays; first the locale categories Perl uses on this system;
 * the second array is their names.  These arrays are in mostly arbitrary
 * order. */

const int categories[] = {

#    ifdef USE_LOCALE_NUMERIC
                             LC_NUMERIC,
#    endif
#    ifdef USE_LOCALE_CTYPE
                             LC_CTYPE,
#    endif
#    ifdef USE_LOCALE_COLLATE
                             LC_COLLATE,
#    endif
#    ifdef USE_LOCALE_TIME
                             LC_TIME,
#    endif
#    ifdef USE_LOCALE_MESSAGES
                             LC_MESSAGES,
#    endif
#    ifdef USE_LOCALE_MONETARY
                             LC_MONETARY,
#    endif
#    ifdef LC_ALL
                             LC_ALL,
#    endif
                            -1  /* Placeholder because C doesn't allow a
                                   trailing comma, and it would get complicated
                                   with all the #ifdef's */
};

/* The top-most real element is LC_ALL */

const char * category_names[] = {

#    ifdef USE_LOCALE_NUMERIC
                                 "LC_NUMERIC",
#    endif
#    ifdef USE_LOCALE_CTYPE
                                 "LC_CTYPE",
#    endif
#    ifdef USE_LOCALE_COLLATE
                                 "LC_COLLATE",
#    endif
#    ifdef USE_LOCALE_TIME
                                 "LC_TIME",
#    endif
#    ifdef USE_LOCALE_MESSAGES
                                 "LC_MESSAGES",
#    endif
#    ifdef USE_LOCALE_MONETARY
                                 "LC_MONETARY",
#    endif
#    ifdef LC_ALL
                                 "LC_ALL",
#    endif
                                 NULL  /* Placeholder */
                            };

#  ifdef LC_ALL

    /* On systems with LC_ALL, it is kept in the highest index position.  (-2
     * to account for the final unused placeholder element.) */
#    define NOMINAL_LC_ALL_INDEX (C_ARRAY_LENGTH(categories) - 2)

#  else

    /* On systems without LC_ALL, we pretend it is there, one beyond the real
     * top element, hence in the unused placeholder element. */
#    define NOMINAL_LC_ALL_INDEX (C_ARRAY_LENGTH(categories) - 1)

#  endif

/* Pretending there is an LC_ALL element just above allows us to avoid most
 * special cases.  Most loops through these arrays in the code below are
 * written like 'for (i = 0; i < NOMINAL_LC_ALL_INDEX; i++)'.  They will work
 * on either type of system.  But the code must be written to not access the
 * element at 'LC_ALL_INDEX' except on platforms that have it.  This can be
 * checked for at compile time by using the #define LC_ALL_INDEX which is only
 * defined if we do have LC_ALL. */

/* Now create LC_foo_INDEX #defines for just those categories on this system */
#  ifdef USE_LOCALE_NUMERIC
#    define LC_NUMERIC_INDEX            0
#    define _DUMMY_NUMERIC              LC_NUMERIC_INDEX
#  else
#    define _DUMMY_NUMERIC              -1
#  endif
#  ifdef USE_LOCALE_CTYPE
#    define LC_CTYPE_INDEX              _DUMMY_NUMERIC + 1
#    define _DUMMY_CTYPE                LC_CTYPE_INDEX
#  else
#    define _DUMMY_CTYPE                _DUMMY_NUMERIC
#  endif
#  ifdef USE_LOCALE_COLLATE
#    define LC_COLLATE_INDEX            _DUMMY_CTYPE + 1
#    define _DUMMY_COLLATE              LC_COLLATE_INDEX
#  else
#    define _DUMMY_COLLATE              _DUMMY_COLLATE
#  endif
#  ifdef USE_LOCALE_TIME
#    define LC_TIME_INDEX               _DUMMY_COLLATE + 1
#    define _DUMMY_TIME                 LC_TIME_INDEX
#  else
#    define _DUMMY_TIME                 _DUMMY_COLLATE
#  endif
#  ifdef USE_LOCALE_MESSAGES
#    define LC_MESSAGES_INDEX           _DUMMY_TIME + 1
#    define _DUMMY_MESSAGES             LC_MESSAGES_INDEX
#  else
#    define _DUMMY_MESSAGES             _DUMMY_TIME
#  endif
#  ifdef USE_LOCALE_MONETARY
#    define LC_MONETARY_INDEX           _DUMMY_MESSAGES + 1
#    define _DUMMY_MONETARY             LC_MONETARY_INDEX
#  else
#    define _DUMMY_MONETARY             _DUMMY_MESSAGES
#  endif
#  ifdef LC_ALL
#    define LC_ALL_INDEX                _DUMMY_MONETARY + 1
#  endif
#endif /* ifdef USE_LOCALE */

/* Windows requres a customized base-level setlocale() */
#  ifdef WIN32
#    define my_setlocale(cat, locale) win32_setlocale(cat, locale)
#  else
#    define my_setlocale(cat, locale) setlocale(cat, locale)
#  endif

/* Just placeholders for now.  "_c" is intended to be called when the category
 * is a constant known at compile time; "_r", not known until run time  */
#  define do_setlocale_c(category, locale) my_setlocale(category, locale)
#  define do_setlocale_r(category, locale) my_setlocale(category, locale)

STATIC void
S_set_numeric_radix(pTHX_ const bool use_locale)
{
    /* If 'use_locale' is FALSE, set to use a dot for the radix character.  If
     * TRUE, use the radix character derived from the current locale */

#if defined(USE_LOCALE_NUMERIC) && (   defined(HAS_LOCALECONV)              \
                                    || defined(HAS_NL_LANGINFO))

    /* We only set up the radix SV if we are to use a locale radix ... */
    if (use_locale) {
        const char * radix = my_nl_langinfo(PERL_RADIXCHAR, FALSE);
                                          /* FALSE => already in dest locale */

        /* ... and the character being used isn't a dot */
        if (strNE(radix, ".")) { /* radix might be "", so we cannot use strNEc */
            if (PL_numeric_radix_sv) {
                sv_setpv(PL_numeric_radix_sv, radix);
            }
            else {
                PL_numeric_radix_sv = newSVpv(radix, 0);
            }

            if ( !  is_utf8_invariant_string(
                     (U8 *) SvPVX(PL_numeric_radix_sv), SvCUR(PL_numeric_radix_sv))
                &&  is_utf8_string(
                     (U8 *) SvPVX(PL_numeric_radix_sv), SvCUR(PL_numeric_radix_sv))
                && _is_cur_LC_category_utf8(LC_NUMERIC))
            {
                SvUTF8_on(PL_numeric_radix_sv);
            }
            goto done;
        }
    }

    SvREFCNT_dec(PL_numeric_radix_sv);
    PL_numeric_radix_sv = NULL;

  done: ;

#  ifdef DEBUGGING

    if (DEBUG_L_TEST || debug_initialization) {
        PerlIO_printf(Perl_debug_log, "Locale radix is '%s', ?UTF-8=%d\n",
                                          (PL_numeric_radix_sv)
                                           ? SvPVX(PL_numeric_radix_sv)
                                           : "NULL",
                                          (PL_numeric_radix_sv)
                                           ? cBOOL(SvUTF8(PL_numeric_radix_sv))
                                           : 0);
    }

#  endif
#endif /* USE_LOCALE_NUMERIC and can find the radix char */

}

void
Perl_new_numeric(pTHX_ const char *newnum)
{

#ifndef USE_LOCALE_NUMERIC

    PERL_UNUSED_ARG(newnum);

#else

    /* Called after all libc setlocale() calls affecting LC_NUMERIC, to tell
     * core Perl this and that 'newnum' is the name of the new locale.
     * It installs this locale as the current underlying default.
     *
     * The default locale and the C locale can be toggled between by use of the
     * set_numeric_underlying() and set_numeric_standard() functions, which
     * should probably not be called directly, but only via macros like
     * SET_NUMERIC_STANDARD() in perl.h.
     *
     * The toggling is necessary mainly so that a non-dot radix decimal point
     * character can be output, while allowing internal calculations to use a
     * dot.
     *
     * This sets several interpreter-level variables:
     * PL_numeric_name  The underlying locale's name: a copy of 'newnum'
     * PL_numeric_underlying  A boolean indicating if the toggled state is such
     *                  that the current locale is the program's underlying
     *                  locale
     * PL_numeric_standard An int indicating if the toggled state is such
     *                  that the current locale is the C locale.  If non-zero,
     *                  it is in C; if > 1, it means it may not be toggled away
     *                  from C.
     * Note that both of the last two variables can be true at the same time,
     * if the underlying locale is C.  (Toggling is a no-op under these
     * circumstances.)
     *
     * Any code changing the locale (outside this file) should use
     * POSIX::setlocale, which calls this function.  Therefore this function
     * should be called directly only from this file and from
     * POSIX::setlocale() */

    char *save_newnum;

    if (! newnum) {
	Safefree(PL_numeric_name);
	PL_numeric_name = NULL;
	PL_numeric_standard = TRUE;
	PL_numeric_underlying = TRUE;
	return;
    }

    save_newnum = stdize_locale(savepv(newnum));

    PL_numeric_standard = isNAME_C_OR_POSIX(save_newnum);
    PL_numeric_underlying = TRUE;

    if (! PL_numeric_name || strNE(PL_numeric_name, save_newnum)) {
	Safefree(PL_numeric_name);
	PL_numeric_name = save_newnum;
    }
    else {
	Safefree(save_newnum);
    }

    /* Keep LC_NUMERIC in the C locale.  This is for XS modules, so they don't
     * have to worry about the radix being a non-dot.  (Core operations that
     * need the underlying locale change to it temporarily). */
    set_numeric_standard();

#endif /* USE_LOCALE_NUMERIC */

}

void
Perl_set_numeric_standard(pTHX)
{

#ifdef USE_LOCALE_NUMERIC

    /* Toggle the LC_NUMERIC locale to C.  Most code should use the macros like
     * SET_NUMERIC_STANDARD() in perl.h instead of calling this directly.  The
     * macro avoids calling this routine if toggling isn't necessary according
     * to our records (which could be wrong if some XS code has changed the
     * locale behind our back) */

    do_setlocale_c(LC_NUMERIC, "C");
    PL_numeric_standard = TRUE;
    PL_numeric_underlying = isNAME_C_OR_POSIX(PL_numeric_name);
    set_numeric_radix(FALSE);

#  ifdef DEBUGGING

    if (DEBUG_L_TEST || debug_initialization) {
        PerlIO_printf(Perl_debug_log,
                          "LC_NUMERIC locale now is standard C\n");
    }

#  endif
#endif /* USE_LOCALE_NUMERIC */

}

void
Perl_set_numeric_underlying(pTHX)
{

#ifdef USE_LOCALE_NUMERIC

    /* Toggle the LC_NUMERIC locale to the current underlying default.  Most
     * code should use the macros like SET_NUMERIC_UNDERLYING() in perl.h
     * instead of calling this directly.  The macro avoids calling this routine
     * if toggling isn't necessary according to our records (which could be
     * wrong if some XS code has changed the locale behind our back) */

    do_setlocale_c(LC_NUMERIC, PL_numeric_name);
    PL_numeric_standard = isNAME_C_OR_POSIX(PL_numeric_name);
    PL_numeric_underlying = TRUE;
    set_numeric_radix(TRUE);

#  ifdef DEBUGGING

    if (DEBUG_L_TEST || debug_initialization) {
        PerlIO_printf(Perl_debug_log,
                          "LC_NUMERIC locale now is %s\n",
                          PL_numeric_name);
    }

#  endif
#endif /* USE_LOCALE_NUMERIC */

}

/*
 * Set up for a new ctype locale.
 */
STATIC void
S_new_ctype(pTHX_ const char *newctype)
{

#ifndef USE_LOCALE_CTYPE

    PERL_ARGS_ASSERT_NEW_CTYPE;
    PERL_UNUSED_ARG(newctype);
    PERL_UNUSED_CONTEXT;

#else

    /* Called after all libc setlocale() calls affecting LC_CTYPE, to tell
     * core Perl this and that 'newctype' is the name of the new locale.
     *
     * This function sets up the folding arrays for all 256 bytes, assuming
     * that tofold() is tolc() since fold case is not a concept in POSIX,
     *
     * Any code changing the locale (outside this file) should use
     * POSIX::setlocale, which calls this function.  Therefore this function
     * should be called directly only from this file and from
     * POSIX::setlocale() */

    dVAR;
    UV i;

    PERL_ARGS_ASSERT_NEW_CTYPE;

    /* We will replace any bad locale warning with 1) nothing if the new one is
     * ok; or 2) a new warning for the bad new locale */
    if (PL_warn_locale) {
        SvREFCNT_dec_NN(PL_warn_locale);
        PL_warn_locale = NULL;
    }

    PL_in_utf8_CTYPE_locale = _is_cur_LC_category_utf8(LC_CTYPE);

    /* A UTF-8 locale gets standard rules.  But note that code still has to
     * handle this specially because of the three problematic code points */
    if (PL_in_utf8_CTYPE_locale) {
        Copy(PL_fold_latin1, PL_fold_locale, 256, U8);
    }
    else {
        /* Assume enough space for every character being bad.  4 spaces each
         * for the 94 printable characters that are output like "'x' "; and 5
         * spaces each for "'\\' ", "'\t' ", and "'\n' "; plus a terminating
         * NUL */
        char bad_chars_list[ (94 * 4) + (3 * 5) + 1 ];

        /* Don't check for problems if we are suppressing the warnings */
        bool check_for_problems = ckWARN_d(WARN_LOCALE)
                               || UNLIKELY(DEBUG_L_TEST);
        bool multi_byte_locale = FALSE;     /* Assume is a single-byte locale
                                               to start */
        unsigned int bad_count = 0;         /* Count of bad characters */

        for (i = 0; i < 256; i++) {
            if (isUPPER_LC((U8) i))
                PL_fold_locale[i] = (U8) toLOWER_LC((U8) i);
            else if (isLOWER_LC((U8) i))
                PL_fold_locale[i] = (U8) toUPPER_LC((U8) i);
            else
                PL_fold_locale[i] = (U8) i;

            /* If checking for locale problems, see if the native ASCII-range
             * printables plus \n and \t are in their expected categories in
             * the new locale.  If not, this could mean big trouble, upending
             * Perl's and most programs' assumptions, like having a
             * metacharacter with special meaning become a \w.  Fortunately,
             * it's very rare to find locales that aren't supersets of ASCII
             * nowadays.  It isn't a problem for most controls to be changed
             * into something else; we check only \n and \t, though perhaps \r
             * could be an issue as well. */
            if (    check_for_problems
                && (isGRAPH_A(i) || isBLANK_A(i) || i == '\n'))
            {
                if ((    isALPHANUMERIC_A(i) && ! isALPHANUMERIC_LC(i))
                     || (isPUNCT_A(i) && ! isPUNCT_LC(i))
                     || (isBLANK_A(i) && ! isBLANK_LC(i))
                     || (i == '\n' && ! isCNTRL_LC(i)))
                {
                    if (bad_count) {    /* Separate multiple entries with a
                                           blank */
                        bad_chars_list[bad_count++] = ' ';
                    }
                    bad_chars_list[bad_count++] = '\'';
                    if (isPRINT_A(i)) {
                        bad_chars_list[bad_count++] = (char) i;
                    }
                    else {
                        bad_chars_list[bad_count++] = '\\';
                        if (i == '\n') {
                            bad_chars_list[bad_count++] = 'n';
                        }
                        else {
                            assert(i == '\t');
                            bad_chars_list[bad_count++] = 't';
                        }
                    }
                    bad_chars_list[bad_count++] = '\'';
                    bad_chars_list[bad_count] = '\0';
                }
            }
        }

#  ifdef MB_CUR_MAX

        /* We only handle single-byte locales (outside of UTF-8 ones; so if
         * this locale requires more than one byte, there are going to be
         * problems. */
        DEBUG_Lv(PerlIO_printf(Perl_debug_log,
                 "%s:%d: check_for_problems=%d, MB_CUR_MAX=%d\n",
                 __FILE__, __LINE__, check_for_problems, (int) MB_CUR_MAX));

        if (check_for_problems && MB_CUR_MAX > 1

               /* Some platforms return MB_CUR_MAX > 1 for even the "C"
                * locale.  Just assume that the implementation for them (plus
                * for POSIX) is correct and the > 1 value is spurious.  (Since
                * these are specially handled to never be considered UTF-8
                * locales, as long as this is the only problem, everything
                * should work fine */
            && strNEc(newctype, "C") && strNEc(newctype, "POSIX"))
        {
            multi_byte_locale = TRUE;
        }

#  endif

        if (bad_count || multi_byte_locale) {
            PL_warn_locale = Perl_newSVpvf(aTHX_
                             "Locale '%s' may not work well.%s%s%s\n",
                             newctype,
                             (multi_byte_locale)
                              ? "  Some characters in it are not recognized by"
                                " Perl."
                              : "",
                             (bad_count)
                              ? "\nThe following characters (and maybe others)"
                                " may not have the same meaning as the Perl"
                                " program expects:\n"
                              : "",
                             (bad_count)
                              ? bad_chars_list
                              : ""
                            );
            /* If we are actually in the scope of the locale or are debugging,
             * output the message now.  If not in that scope, we save the
             * message to be output at the first operation using this locale,
             * if that actually happens.  Most programs don't use locales, so
             * they are immune to bad ones.  */
            if (IN_LC(LC_CTYPE) || UNLIKELY(DEBUG_L_TEST)) {

                /* We have to save 'newctype' because the setlocale() just
                 * below may destroy it.  The next setlocale() further down
                 * should restore it properly so that the intermediate change
                 * here is transparent to this function's caller */
                const char * const badlocale = savepv(newctype);

                do_setlocale_c(LC_CTYPE, "C");

                /* The '0' below suppresses a bogus gcc compiler warning */
                Perl_warner(aTHX_ packWARN(WARN_LOCALE), SvPVX(PL_warn_locale), 0);

                do_setlocale_c(LC_CTYPE, badlocale);
                Safefree(badlocale);

                if (IN_LC(LC_CTYPE)) {
                    SvREFCNT_dec_NN(PL_warn_locale);
                    PL_warn_locale = NULL;
                }
            }
        }
    }

#endif /* USE_LOCALE_CTYPE */

}

void
Perl__warn_problematic_locale()
{

#ifdef USE_LOCALE_CTYPE

    dTHX;

    /* Internal-to-core function that outputs the message in PL_warn_locale,
     * and then NULLS it.  Should be called only through the macro
     * _CHECK_AND_WARN_PROBLEMATIC_LOCALE */

    if (PL_warn_locale) {
        /*GCC_DIAG_IGNORE(-Wformat-security);   Didn't work */
        Perl_ck_warner(aTHX_ packWARN(WARN_LOCALE),
                             SvPVX(PL_warn_locale),
                             0 /* dummy to avoid compiler warning */ );
        /* GCC_DIAG_RESTORE; */
        SvREFCNT_dec_NN(PL_warn_locale);
        PL_warn_locale = NULL;
    }

#endif

}

STATIC void
S_new_collate(pTHX_ const char *newcoll)
{

#ifndef USE_LOCALE_COLLATE

    PERL_UNUSED_ARG(newcoll);
    PERL_UNUSED_CONTEXT;

#else

    /* Called after all libc setlocale() calls affecting LC_COLLATE, to tell
     * core Perl this and that 'newcoll' is the name of the new locale.
     *
     * The design of locale collation is that every locale change is given an
     * index 'PL_collation_ix'.  The first time a string particpates in an
     * operation that requires collation while locale collation is active, it
     * is given PERL_MAGIC_collxfrm magic (via sv_collxfrm_flags()).  That
     * magic includes the collation index, and the transformation of the string
     * by strxfrm(), q.v.  That transformation is used when doing comparisons,
     * instead of the string itself.  If a string changes, the magic is
     * cleared.  The next time the locale changes, the index is incremented,
     * and so we know during a comparison that the transformation is not
     * necessarily still valid, and so is recomputed.  Note that if the locale
     * changes enough times, the index could wrap (a U32), and it is possible
     * that a transformation would improperly be considered valid, leading to
     * an unlikely bug */

    if (! newcoll) {
	if (PL_collation_name) {
	    ++PL_collation_ix;
	    Safefree(PL_collation_name);
	    PL_collation_name = NULL;
	}
	PL_collation_standard = TRUE;
      is_standard_collation:
	PL_collxfrm_base = 0;
	PL_collxfrm_mult = 2;
        PL_in_utf8_COLLATE_locale = FALSE;
        PL_strxfrm_NUL_replacement = '\0';
        PL_strxfrm_max_cp = 0;
	return;
    }

    /* If this is not the same locale as currently, set the new one up */
    if (! PL_collation_name || strNE(PL_collation_name, newcoll)) {
	++PL_collation_ix;
	Safefree(PL_collation_name);
	PL_collation_name = stdize_locale(savepv(newcoll));
	PL_collation_standard = isNAME_C_OR_POSIX(newcoll);
        if (PL_collation_standard) {
            goto is_standard_collation;
        }

        PL_in_utf8_COLLATE_locale = _is_cur_LC_category_utf8(LC_COLLATE);
        PL_strxfrm_NUL_replacement = '\0';
        PL_strxfrm_max_cp = 0;

        /* A locale collation definition includes primary, secondary, tertiary,
         * etc. weights for each character.  To sort, the primary weights are
         * used, and only if they compare equal, then the secondary weights are
         * used, and only if they compare equal, then the tertiary, etc.
         *
         * strxfrm() works by taking the input string, say ABC, and creating an
         * output transformed string consisting of first the primary weights,
         * A¹B¹C¹ followed by the secondary ones, A²B²C²; and then the
         * tertiary, etc, yielding A¹B¹C¹ A²B²C² A³B³C³ ....  Some characters
         * may not have weights at every level.  In our example, let's say B
         * doesn't have a tertiary weight, and A doesn't have a secondary
         * weight.  The constructed string is then going to be
         *  A¹B¹C¹ B²C² A³C³ ....
         * This has the desired effect that strcmp() will look at the secondary
         * or tertiary weights only if the strings compare equal at all higher
         * priority weights.  The spaces shown here, like in
         *  "A¹B¹C¹ A²B²C² "
         * are not just for readability.  In the general case, these must
         * actually be bytes, which we will call here 'separator weights'; and
         * they must be smaller than any other weight value, but since these
         * are C strings, only the terminating one can be a NUL (some
         * implementations may include a non-NUL separator weight just before
         * the NUL).  Implementations tend to reserve 01 for the separator
         * weights.  They are needed so that a shorter string's secondary
         * weights won't be misconstrued as primary weights of a longer string,
         * etc.  By making them smaller than any other weight, the shorter
         * string will sort first.  (Actually, if all secondary weights are
         * smaller than all primary ones, there is no need for a separator
         * weight between those two levels, etc.)
         *
         * The length of the transformed string is roughly a linear function of
         * the input string.  It's not exactly linear because some characters
         * don't have weights at all levels.  When we call strxfrm() we have to
         * allocate some memory to hold the transformed string.  The
         * calculations below try to find coefficients 'm' and 'b' for this
         * locale so that m*x + b equals how much space we need, given the size
         * of the input string in 'x'.  If we calculate too small, we increase
         * the size as needed, and call strxfrm() again, but it is better to
         * get it right the first time to avoid wasted expensive string
         * transformations. */

	{
            /* We use the string below to find how long the tranformation of it
             * is.  Almost all locales are supersets of ASCII, or at least the
             * ASCII letters.  We use all of them, half upper half lower,
             * because if we used fewer, we might hit just the ones that are
             * outliers in a particular locale.  Most of the strings being
             * collated will contain a preponderance of letters, and even if
             * they are above-ASCII, they are likely to have the same number of
             * weight levels as the ASCII ones.  It turns out that digits tend
             * to have fewer levels, and some punctuation has more, but those
             * are relatively sparse in text, and khw believes this gives a
             * reasonable result, but it could be changed if experience so
             * dictates. */
            const char longer[] = "ABCDEFGHIJKLMnopqrstuvwxyz";
            char * x_longer;        /* Transformed 'longer' */
            Size_t x_len_longer;    /* Length of 'x_longer' */

            char * x_shorter;   /* We also transform a substring of 'longer' */
            Size_t x_len_shorter;

            /* _mem_collxfrm() is used get the transformation (though here we
             * are interested only in its length).  It is used because it has
             * the intelligence to handle all cases, but to work, it needs some
             * values of 'm' and 'b' to get it started.  For the purposes of
             * this calculation we use a very conservative estimate of 'm' and
             * 'b'.  This assumes a weight can be multiple bytes, enough to
             * hold any UV on the platform, and there are 5 levels, 4 weight
             * bytes, and a trailing NUL.  */
            PL_collxfrm_base = 5;
            PL_collxfrm_mult = 5 * sizeof(UV);

            /* Find out how long the transformation really is */
            x_longer = _mem_collxfrm(longer,
                                     sizeof(longer) - 1,
                                     &x_len_longer,

                                     /* We avoid converting to UTF-8 in the
                                      * called function by telling it the
                                      * string is in UTF-8 if the locale is a
                                      * UTF-8 one.  Since the string passed
                                      * here is invariant under UTF-8, we can
                                      * claim it's UTF-8 even though it isn't.
                                      * */
                                     PL_in_utf8_COLLATE_locale);
            Safefree(x_longer);

            /* Find out how long the transformation of a substring of 'longer'
             * is.  Together the lengths of these transformations are
             * sufficient to calculate 'm' and 'b'.  The substring is all of
             * 'longer' except the first character.  This minimizes the chances
             * of being swayed by outliers */
            x_shorter = _mem_collxfrm(longer + 1,
                                      sizeof(longer) - 2,
                                      &x_len_shorter,
                                      PL_in_utf8_COLLATE_locale);
            Safefree(x_shorter);

            /* If the results are nonsensical for this simple test, the whole
             * locale definition is suspect.  Mark it so that locale collation
             * is not active at all for it.  XXX Should we warn? */
            if (   x_len_shorter == 0
                || x_len_longer == 0
                || x_len_shorter >= x_len_longer)
            {
                PL_collxfrm_mult = 0;
                PL_collxfrm_base = 0;
            }
            else {
                SSize_t base;       /* Temporary */

                /* We have both:    m * strlen(longer)  + b = x_len_longer
                 *                  m * strlen(shorter) + b = x_len_shorter;
                 * subtracting yields:
                 *          m * (strlen(longer) - strlen(shorter))
                 *                             = x_len_longer - x_len_shorter
                 * But we have set things up so that 'shorter' is 1 byte smaller
                 * than 'longer'.  Hence:
                 *          m = x_len_longer - x_len_shorter
                 *
                 * But if something went wrong, make sure the multiplier is at
                 * least 1.
                 */
                if (x_len_longer > x_len_shorter) {
                    PL_collxfrm_mult = (STRLEN) x_len_longer - x_len_shorter;
                }
                else {
                    PL_collxfrm_mult = 1;
                }

                /*     mx + b = len
                 * so:      b = len - mx
                 * but in case something has gone wrong, make sure it is
                 * non-negative */
                base = x_len_longer - PL_collxfrm_mult * (sizeof(longer) - 1);
                if (base < 0) {
                    base = 0;
                }

                /* Add 1 for the trailing NUL */
                PL_collxfrm_base = base + 1;
            }

#  ifdef DEBUGGING

            if (DEBUG_L_TEST || debug_initialization) {
                PerlIO_printf(Perl_debug_log,
                    "%s:%d: ?UTF-8 locale=%d; x_len_shorter=%zu, "
                    "x_len_longer=%zu,"
                    " collate multipler=%zu, collate base=%zu\n",
                    __FILE__, __LINE__,
                    PL_in_utf8_COLLATE_locale,
                    x_len_shorter, x_len_longer,
                    PL_collxfrm_mult, PL_collxfrm_base);
            }
#  endif

	}
    }

#endif /* USE_LOCALE_COLLATE */

}

#ifdef WIN32

STATIC char *
S_win32_setlocale(pTHX_ int category, const char* locale)
{
    /* This, for Windows, emulates POSIX setlocale() behavior.  There is no
     * difference between the two unless the input locale is "", which normally
     * means on Windows to get the machine default, which is set via the
     * computer's "Regional and Language Options" (or its current equivalent).
     * In POSIX, it instead means to find the locale from the user's
     * environment.  This routine changes the Windows behavior to first look in
     * the environment, and, if anything is found, use that instead of going to
     * the machine default.  If there is no environment override, the machine
     * default is used, by calling the real setlocale() with "".
     *
     * The POSIX behavior is to use the LC_ALL variable if set; otherwise to
     * use the particular category's variable if set; otherwise to use the LANG
     * variable. */

    bool override_LC_ALL = FALSE;
    char * result;
    unsigned int i;

    if (locale && strEQc(locale, "")) {

#  ifdef LC_ALL

        locale = PerlEnv_getenv("LC_ALL");
        if (! locale) {
            if (category ==  LC_ALL) {
                override_LC_ALL = TRUE;
            }
            else {

#  endif

                for (i = 0; i < NOMINAL_LC_ALL_INDEX; i++) {
                    if (category == categories[i]) {
                        locale = PerlEnv_getenv(category_names[i]);
                        goto found_locale;
                    }
                }

                locale = PerlEnv_getenv("LANG");
                if (! locale) {
                    locale = "";
                }

              found_locale: ;

#  ifdef LC_ALL

            }
        }

#  endif

    }

    result = setlocale(category, locale);
    DEBUG_L(PerlIO_printf(Perl_debug_log, "%s:%d: %s\n", __FILE__, __LINE__,
                            setlocale_debug_string(category, locale, result)));

    if (! override_LC_ALL)  {
        return result;
    }

    /* Here the input category was LC_ALL, and we have set it to what is in the
     * LANG variable or the system default if there is no LANG.  But these have
     * lower priority than the other LC_foo variables, so override it for each
     * one that is set.  (If they are set to "", it means to use the same thing
     * we just set LC_ALL to, so can skip) */

    for (i = 0; i < LC_ALL_INDEX; i++) {
        result = PerlEnv_getenv(category_names[i]);
        if (result && *result) {
            setlocale(categories[i], result);
            DEBUG_Lv(PerlIO_printf(Perl_debug_log, "%s:%d: %s\n",
                __FILE__, __LINE__,
                setlocale_debug_string(categories[i], result, "not captured")));
        }
    }

    result = setlocale(LC_ALL, NULL);
    DEBUG_L(PerlIO_printf(Perl_debug_log, "%s:%d: %s\n",
                               __FILE__, __LINE__,
                               setlocale_debug_string(LC_ALL, NULL, result)));

    return result;
}

#endif

char *
Perl_setlocale(int category, const char * locale)
{
    /* This wraps POSIX::setlocale() */

    char * retval;
    char * newlocale;
    dTHX;

#ifdef USE_LOCALE_NUMERIC

    /* A NULL locale means only query what the current one is.  We
     * have the LC_NUMERIC name saved, because we are normally switched
     * into the C locale for it.  Switch back so an LC_ALL query will yield
     * the correct results; all other categories don't require special
     * handling */
    if (locale == NULL) {
        if (category == LC_NUMERIC) {
            return savepv(PL_numeric_name);
        }

#  ifdef LC_ALL

        else if (category == LC_ALL) {
            SET_NUMERIC_UNDERLYING();
        }

#  endif

    }

#endif

    /* Save retval since subsequent setlocale() calls may overwrite it. */
    retval = savepv(do_setlocale_r(category, locale));

    DEBUG_L(PerlIO_printf(Perl_debug_log,
        "%s:%d: %s\n", __FILE__, __LINE__,
            setlocale_debug_string(category, locale, retval)));
    if (! retval) {
        /* Should never happen that a query would return an error, but be
         * sure and reset to C locale */
        if (locale == 0) {
            SET_NUMERIC_STANDARD();
        }

        return NULL;
    }

    /* If locale == NULL, we are just querying the state, but may have switched
     * to NUMERIC_UNDERLYING.  Switch back before returning. */
    if (locale == NULL) {
        SET_NUMERIC_STANDARD();
        return retval;
    }

    /* Now that have switched locales, we have to update our records to
     * correspond. */

    switch (category) {

#ifdef USE_LOCALE_CTYPE

        case LC_CTYPE:
            new_ctype(retval);
            break;

#endif
#ifdef USE_LOCALE_COLLATE

        case LC_COLLATE:
            new_collate(retval);
            break;

#endif
#ifdef USE_LOCALE_NUMERIC

        case LC_NUMERIC:
            new_numeric(retval);
            break;

#endif
#ifdef LC_ALL

        case LC_ALL:

            /* LC_ALL updates all the things we care about.  The values may not
             * be the same as 'retval', as the locale "" may have set things
             * individually */

#  ifdef USE_LOCALE_CTYPE

            newlocale = do_setlocale_c(LC_CTYPE, NULL);
            new_ctype(newlocale);

#  endif /* USE_LOCALE_CTYPE */
#  ifdef USE_LOCALE_COLLATE

            newlocale = do_setlocale_c(LC_COLLATE, NULL);
            new_collate(newlocale);

#  endif
#  ifdef USE_LOCALE_NUMERIC

            newlocale = do_setlocale_c(LC_NUMERIC, NULL);
            new_numeric(newlocale);

#  endif /* USE_LOCALE_NUMERIC */
#endif /* LC_ALL */

        default:
            break;
    }

    return retval;


}

PERL_STATIC_INLINE const char *
S_save_to_buffer(const char * string, char **buf, Size_t *buf_size, const Size_t offset)
{
    /* Copy the NUL-terminated 'string' to 'buf' + 'offset'.  'buf' has size 'buf_size',
     * growing it if necessary */

    const Size_t string_size = strlen(string) + offset + 1;

    PERL_ARGS_ASSERT_SAVE_TO_BUFFER;

    if (*buf_size == 0) {
        Newx(*buf, string_size, char);
        *buf_size = string_size;
    }
    else if (string_size > *buf_size) {
        Renew(*buf, string_size, char);
        *buf_size = string_size;
    }

    Copy(string, *buf + offset, string_size - offset, char);
    return *buf;
}

/*

=head1 Locale-related functions and macros

=for apidoc Perl_langinfo

This is an (almost ª) drop-in replacement for the system C<L<nl_langinfo(3)>>,
taking the same C<item> parameter values, and returning the same information.
But it is more thread-safe than regular C<nl_langinfo()>, and hides the quirks
of Perl's locale handling from your code, and can be used on systems that lack
a native C<nl_langinfo>.

Expanding on these:

=over

=item *

It delivers the correct results for the C<RADIXCHAR> and C<THOUSESEP> items,
without you having to write extra code.  The reason for the extra code would be
because these are from the C<LC_NUMERIC> locale category, which is normally
kept set to the C locale by Perl, no matter what the underlying locale is
supposed to be, and so to get the expected results, you have to temporarily
toggle into the underlying locale, and later toggle back.  (You could use
plain C<nl_langinfo> and C<L</STORE_LC_NUMERIC_FORCE_TO_UNDERLYING>> for this
but then you wouldn't get the other advantages of C<Perl_langinfo()>; not
keeping C<LC_NUMERIC> in the C locale would break a lot of CPAN, which is
expecting the radix (decimal point) character to be a dot.)

=item *

Depending on C<item>, it works on systems that don't have C<nl_langinfo>, hence
makes your code more portable.  Of the fifty-some possible items specified by
the POSIX 2008 standard,
L<http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/langinfo.h.html>,
only two are completely unimplemented.  It uses various techniques to recover
the other items, including calling C<L<localeconv(3)>>, and C<L<strftime(3)>>,
both of which are specified in C89, so should be always be available.  Later
C<strftime()> versions have additional capabilities; C<""> is returned for
those not available on your system.

The details for those items which may differ from what this emulation returns
and what a native C<nl_langinfo()> would return are:

=over

=item C<CODESET>

=item C<ERA>

Unimplemented, so returns C<"">.

=item C<YESEXPR>

=item C<YESSTR>

=item C<NOEXPR>

=item C<NOSTR>

Only the values for English are returned.  C<YESSTR> and C<NOSTR> have been
removed from POSIX 2008, and are retained for backwards compatibility.  Your
platform's C<nl_langinfo> may not support them.

=item C<D_FMT>

Always evaluates to C<%x>, the locale's appropriate date representation.

=item C<T_FMT>

Always evaluates to C<%X>, the locale's appropriate time representation.

=item C<D_T_FMT>

Always evaluates to C<%c>, the locale's appropriate date and time
representation.

=item C<CRNCYSTR>

The return may be incorrect for those rare locales where the currency symbol
replaces the radix character.
Send email to L<mailto:perlbug@perl.org> if you have examples of it needing
to work differently.

=item C<ALT_DIGITS>

Currently this gives the same results as Linux does.
Send email to L<mailto:perlbug@perl.org> if you have examples of it needing
to work differently.

=item C<ERA_D_FMT>

=item C<ERA_T_FMT>

=item C<ERA_D_T_FMT>

=item C<T_FMT_AMPM>

These are derived by using C<strftime()>, and not all versions of that function
know about them.  C<""> is returned for these on such systems.

=back

When using C<Perl_langinfo> on systems that don't have a native
C<nl_langinfo()>, you must

 #include "perl_langinfo.h"

before the C<perl.h> C<#include>.  You can replace your C<langinfo.h>
C<#include> with this one.  (Doing it this way keeps out the symbols that plain
C<langinfo.h> imports into the namespace for code that doesn't need it.)

You also should not use the bare C<langinfo.h> item names, but should preface
them with C<PERL_>, so use C<PERL_RADIXCHAR> instead of plain C<RADIXCHAR>.
The C<PERL_I<foo>> versions will also work for this function on systems that do
have a native C<nl_langinfo>.

=item *

It is thread-friendly, returning its result in a buffer that won't be
overwritten by another thread, so you don't have to code for that possibility.
The buffer can be overwritten by the next call to C<nl_langinfo> or
C<Perl_langinfo> in the same thread.

=item *

ª It returns S<C<const char *>>, whereas plain C<nl_langinfo()> returns S<C<char
*>>, but you are (only by documentation) forbidden to write into the buffer.
By declaring this C<const>, the compiler enforces this restriction.  The extra
C<const> is why this isn't an unequivocal drop-in replacement for
C<nl_langinfo>.

=back

The original impetus for C<Perl_langinfo()> was so that code that needs to
find out the current currency symbol, floating point radix character, or digit
grouping separator can use, on all systems, the simpler and more
thread-friendly C<nl_langinfo> API instead of C<L<localeconv(3)>> which is a
pain to make thread-friendly.  For other fields returned by C<localeconv>, it
is better to use the methods given in L<perlcall> to call
L<C<POSIX::localeconv()>|POSIX/localeconv>, which is thread-friendly.

=cut

*/

const char *
#ifdef HAS_NL_LANGINFO
Perl_langinfo(const nl_item item)
#else
Perl_langinfo(const int item)
#endif
{
    return my_nl_langinfo(item, TRUE);
}

const char *
#ifdef HAS_NL_LANGINFO
S_my_nl_langinfo(const nl_item item, bool toggle)
#else
S_my_nl_langinfo(const int item, bool toggle)
#endif
{
    dTHX;

#if defined(HAS_NL_LANGINFO) /* nl_langinfo() is available.  */
#if   ! defined(HAS_POSIX_2008_LOCALE)

    /* Here, use plain nl_langinfo(), switching to the underlying LC_NUMERIC
     * for those items dependent on it.  This must be copied to a buffer before
     * switching back, as some systems destroy the buffer when setlocale() is
     * called */

    LOCALE_LOCK;

    if (toggle) {
        if (item == PERL_RADIXCHAR || item == PERL_THOUSEP) {
            do_setlocale_c(LC_NUMERIC, PL_numeric_name);
        }
        else {
            toggle = FALSE;
        }
    }

    save_to_buffer(nl_langinfo(item), &PL_langinfo_buf, &PL_langinfo_bufsize, 0);

    if (toggle) {
        do_setlocale_c(LC_NUMERIC, "C");
    }

    LOCALE_UNLOCK;

#  else /* Use nl_langinfo_l(), avoiding both a mutex and changing the locale */

    bool do_free = FALSE;
    locale_t cur = uselocale((locale_t) 0);

    if (cur == LC_GLOBAL_LOCALE) {
        cur = duplocale(LC_GLOBAL_LOCALE);
        do_free = TRUE;
    }

    if (   toggle
        && (item == PERL_RADIXCHAR || item == PERL_THOUSEP))
    {
        cur = newlocale(LC_NUMERIC_MASK, PL_numeric_name, cur);
        do_free = TRUE;
    }

    save_to_buffer(nl_langinfo_l(item, cur),
                   &PL_langinfo_buf, &PL_langinfo_bufsize, 0);
    if (do_free) {
        freelocale(cur);
    }

#  endif

    if (strEQ(PL_langinfo_buf, "")) {
        if (item == PERL_YESSTR) {
            return "yes";
        }
        if (item == PERL_NOSTR) {
            return "no";
        }
    }

    return PL_langinfo_buf;

#else   /* Below, emulate nl_langinfo as best we can */
#  ifdef HAS_LOCALECONV

    const struct lconv* lc;

#  endif
#  ifdef HAS_STRFTIME

    struct tm tm;
    bool return_format = FALSE; /* Return the %format, not the value */
    const char * format;

#  endif

    /* We copy the results to a per-thread buffer, even if not multi-threaded.
     * This is in part to simplify this code, and partly because we need a
     * buffer anyway for strftime(), and partly because a call of localeconv()
     * could otherwise wipe out the buffer, and the programmer would not be
     * expecting this, as this is a nl_langinfo() substitute after all, so s/he
     * might be thinking their localeconv() is safe until another localeconv()
     * call. */

    switch (item) {
        Size_t len;
        const char * retval;

        /* These 2 are unimplemented */
        case PERL_CODESET:
        case PERL_ERA:	        /* For use with strftime() %E modifier */

        default:
            return "";

        /* We use only an English set, since we don't know any more */
        case PERL_YESEXPR:   return "^[+1yY]";
        case PERL_YESSTR:    return "yes";
        case PERL_NOEXPR:    return "^[-0nN]";
        case PERL_NOSTR:     return "no";

#  ifdef HAS_LOCALECONV

        case PERL_CRNCYSTR:

            LOCALE_LOCK;

            lc = localeconv();
            if (! lc || ! lc->currency_symbol || strEQ("", lc->currency_symbol))
            {
                LOCALE_UNLOCK;
                return "";
            }

            /* Leave the first spot empty to be filled in below */
            save_to_buffer(lc->currency_symbol, &PL_langinfo_buf,
                           &PL_langinfo_bufsize, 1);
            if (lc->mon_decimal_point && strEQ(lc->mon_decimal_point, ""))
            { /*  khw couldn't figure out how the localedef specifications
                  would show that the $ should replace the radix; this is
                  just a guess as to how it might work.*/
                *PL_langinfo_buf = '.';
            }
            else if (lc->p_cs_precedes) {
                *PL_langinfo_buf = '-';
            }
            else {
                *PL_langinfo_buf = '+';
            }

            LOCALE_UNLOCK;
            break;

        case PERL_RADIXCHAR:
        case PERL_THOUSEP:

            LOCALE_LOCK;

            if (toggle) {
                do_setlocale_c(LC_NUMERIC, PL_numeric_name);
            }

            lc = localeconv();
            if (! lc) {
                retval = "";
            }
            else {
                retval = (item == PERL_RADIXCHAR)
                         ? lc->decimal_point
                         : lc->thousands_sep;
                if (! retval) {
                    retval = "";
                }
            }

            save_to_buffer(retval, &PL_langinfo_buf, &PL_langinfo_bufsize, 0);

            if (toggle) {
                do_setlocale_c(LC_NUMERIC, "C");
            }

            LOCALE_UNLOCK;

            break;

#  endif
#  ifdef HAS_STRFTIME

        /* These are defined by C89, so we assume that strftime supports them,
         * and so are returned unconditionally; they may not be what the locale
         * actually says, but should give good enough results for someone using
         * them as formats (as opposed to trying to parse them to figure out
         * what the locale says).  The other format items are actually tested to
         * verify they work on the platform */
        case PERL_D_FMT:         return "%x";
        case PERL_T_FMT:         return "%X";
        case PERL_D_T_FMT:       return "%c";

        /* These formats are only available in later strfmtime's */
        case PERL_ERA_D_FMT: case PERL_ERA_T_FMT: case PERL_ERA_D_T_FMT:
        case PERL_T_FMT_AMPM:

        /* The rest can be gotten from most versions of strftime(). */
        case PERL_ABDAY_1: case PERL_ABDAY_2: case PERL_ABDAY_3:
        case PERL_ABDAY_4: case PERL_ABDAY_5: case PERL_ABDAY_6:
        case PERL_ABDAY_7:
        case PERL_ALT_DIGITS:
        case PERL_AM_STR: case PERL_PM_STR:
        case PERL_ABMON_1: case PERL_ABMON_2: case PERL_ABMON_3:
        case PERL_ABMON_4: case PERL_ABMON_5: case PERL_ABMON_6:
        case PERL_ABMON_7: case PERL_ABMON_8: case PERL_ABMON_9:
        case PERL_ABMON_10: case PERL_ABMON_11: case PERL_ABMON_12:
        case PERL_DAY_1: case PERL_DAY_2: case PERL_DAY_3: case PERL_DAY_4:
        case PERL_DAY_5: case PERL_DAY_6: case PERL_DAY_7:
        case PERL_MON_1: case PERL_MON_2: case PERL_MON_3: case PERL_MON_4:
        case PERL_MON_5: case PERL_MON_6: case PERL_MON_7: case PERL_MON_8:
        case PERL_MON_9: case PERL_MON_10: case PERL_MON_11: case PERL_MON_12:

            LOCALE_LOCK;

            init_tm(&tm);   /* Precaution against core dumps */
            tm.tm_sec = 30;
            tm.tm_min = 30;
            tm.tm_hour = 6;
            tm.tm_year = 2017 - 1900;
            tm.tm_wday = 0;
            tm.tm_mon = 0;
            switch (item) {
                default:
                    LOCALE_UNLOCK;
                    Perl_croak(aTHX_ "panic: %s: %d: switch case: %d problem",
                                             __FILE__, __LINE__, item);
                    NOT_REACHED; /* NOTREACHED */

                case PERL_PM_STR: tm.tm_hour = 18;
                case PERL_AM_STR:
                    format = "%p";
                    break;

                case PERL_ABDAY_7: tm.tm_wday++;
                case PERL_ABDAY_6: tm.tm_wday++;
                case PERL_ABDAY_5: tm.tm_wday++;
                case PERL_ABDAY_4: tm.tm_wday++;
                case PERL_ABDAY_3: tm.tm_wday++;
                case PERL_ABDAY_2: tm.tm_wday++;
                case PERL_ABDAY_1:
                    format = "%a";
                    break;

                case PERL_DAY_7: tm.tm_wday++;
                case PERL_DAY_6: tm.tm_wday++;
                case PERL_DAY_5: tm.tm_wday++;
                case PERL_DAY_4: tm.tm_wday++;
                case PERL_DAY_3: tm.tm_wday++;
                case PERL_DAY_2: tm.tm_wday++;
                case PERL_DAY_1:
                    format = "%A";
                    break;

                case PERL_ABMON_12: tm.tm_mon++;
                case PERL_ABMON_11: tm.tm_mon++;
                case PERL_ABMON_10: tm.tm_mon++;
                case PERL_ABMON_9: tm.tm_mon++;
                case PERL_ABMON_8: tm.tm_mon++;
                case PERL_ABMON_7: tm.tm_mon++;
                case PERL_ABMON_6: tm.tm_mon++;
                case PERL_ABMON_5: tm.tm_mon++;
                case PERL_ABMON_4: tm.tm_mon++;
                case PERL_ABMON_3: tm.tm_mon++;
                case PERL_ABMON_2: tm.tm_mon++;
                case PERL_ABMON_1:
                    format = "%b";
                    break;

                case PERL_MON_12: tm.tm_mon++;
                case PERL_MON_11: tm.tm_mon++;
                case PERL_MON_10: tm.tm_mon++;
                case PERL_MON_9: tm.tm_mon++;
                case PERL_MON_8: tm.tm_mon++;
                case PERL_MON_7: tm.tm_mon++;
                case PERL_MON_6: tm.tm_mon++;
                case PERL_MON_5: tm.tm_mon++;
                case PERL_MON_4: tm.tm_mon++;
                case PERL_MON_3: tm.tm_mon++;
                case PERL_MON_2: tm.tm_mon++;
                case PERL_MON_1:
                    format = "%B";
                    break;

                case PERL_T_FMT_AMPM:
                    format = "%r";
                    return_format = TRUE;
                    break;

                case PERL_ERA_D_FMT:
                    format = "%Ex";
                    return_format = TRUE;
                    break;

                case PERL_ERA_T_FMT:
                    format = "%EX";
                    return_format = TRUE;
                    break;

                case PERL_ERA_D_T_FMT:
                    format = "%Ec";
                    return_format = TRUE;
                    break;

                case PERL_ALT_DIGITS:
                    tm.tm_wday = 0;
                    format = "%Ow";	/* Find the alternate digit for 0 */
                    break;
            }

            /* We can't use my_strftime() because it doesn't look at tm_wday  */
            while (0 == strftime(PL_langinfo_buf, PL_langinfo_bufsize,
                                 format, &tm))
            {
                /* A zero return means one of:
                 *  a)  there wasn't enough space in PL_langinfo_buf
                 *  b)  the format, like a plain %p, returns empty
                 *  c)  it was an illegal format, though some implementations of
                 *      strftime will just return the illegal format as a plain
                 *      character sequence.
                 *
                 *  To quickly test for case 'b)', try again but precede the
                 *  format with a plain character.  If that result is still
                 *  empty, the problem is either 'a)' or 'c)' */

                Size_t format_size = strlen(format) + 1;
                Size_t mod_size = format_size + 1;
                char * mod_format;
                char * temp_result;

                Newx(mod_format, mod_size, char);
                Newx(temp_result, PL_langinfo_bufsize, char);
                *mod_format = '\a';
                my_strlcpy(mod_format + 1, format, mod_size);
                len = strftime(temp_result,
                               PL_langinfo_bufsize,
                               mod_format, &tm);
                Safefree(mod_format);
                Safefree(temp_result);

                /* If 'len' is non-zero, it means that we had a case like %p
                 * which means the current locale doesn't use a.m. or p.m., and
                 * that is valid */
                if (len == 0) {

                    /* Here, still didn't work.  If we get well beyond a
                     * reasonable size, bail out to prevent an infinite loop. */

                    if (PL_langinfo_bufsize > 100 * format_size) {
                        *PL_langinfo_buf = '\0';
                    }
                    else { /* Double the buffer size to retry;  Add 1 in case
                              original was 0, so we aren't stuck at 0. */
                        PL_langinfo_bufsize *= 2;
                        PL_langinfo_bufsize++;
                        Renew(PL_langinfo_buf, PL_langinfo_bufsize, char);
                        continue;
                    }
                }

                break;
            }

            /* Here, we got a result.
             *
             * If the item is 'ALT_DIGITS', PL_langinfo_buf contains the
             * alternate format for wday 0.  If the value is the same as the
             * normal 0, there isn't an alternate, so clear the buffer. */
            if (   item == PERL_ALT_DIGITS
                && strEQ(PL_langinfo_buf, "0"))
            {
                *PL_langinfo_buf = '\0';
            }

            /* ALT_DIGITS is problematic.  Experiments on it showed that
             * strftime() did not always work properly when going from alt-9 to
             * alt-10.  Only a few locales have this item defined, and in all
             * of them on Linux that khw was able to find, nl_langinfo() merely
             * returned the alt-0 character, possibly doubled.  Most Unicode
             * digits are in blocks of 10 consecutive code points, so that is
             * sufficient information for those scripts, as we can infer alt-1,
             * alt-2, ....  But for a Japanese locale, a CJK ideographic 0 is
             * returned, and the CJK digits are not in code point order, so you
             * can't really infer anything.  The localedef for this locale did
             * specify the succeeding digits, so that strftime() works properly
             * on them, without needing to infer anything.  But the
             * nl_langinfo() return did not give sufficient information for the
             * caller to understand what's going on.  So until there is
             * evidence that it should work differently, this returns the alt-0
             * string for ALT_DIGITS.
             *
             * wday was chosen because its range is all a single digit.  Things
             * like tm_sec have two digits as the minimum: '00' */

            LOCALE_UNLOCK;

            /* If to return the format, not the value, overwrite the buffer
             * with it.  But some strftime()s will keep the original format if
             * illegal, so change those to "" */
            if (return_format) {
                if (strEQ(PL_langinfo_buf, format)) {
                    *PL_langinfo_buf = '\0';
                }
                else {
                    save_to_buffer(format, &PL_langinfo_buf,
                                    &PL_langinfo_bufsize, 0);
                }
            }

            break;

#  endif

    }

    return PL_langinfo_buf;

#endif

}

/*
 * Initialize locale awareness.
 */
int
Perl_init_i18nl10n(pTHX_ int printwarn)
{
    /* printwarn is
     *
     *    0 if not to output warning when setup locale is bad
     *    1 if to output warning based on value of PERL_BADLANG
     *    >1 if to output regardless of PERL_BADLANG
     *
     * returns
     *    1 = set ok or not applicable,
     *    0 = fallback to a locale of lower priority
     *   -1 = fallback to all locales failed, not even to the C locale
     *
     * Under -DDEBUGGING, if the environment variable PERL_DEBUG_LOCALE_INIT is
     * set, debugging information is output.
     *
     * This looks more complicated than it is, mainly due to the #ifdefs.
     *
     * We try to set LC_ALL to the value determined by the environment.  If
     * there is no LC_ALL on this platform, we try the individual categories we
     * know about.  If this works, we are done.
     *
     * But if it doesn't work, we have to do something else.  We search the
     * environment variables ourselves instead of relying on the system to do
     * it.  We look at, in order, LC_ALL, LANG, a system default locale (if we
     * think there is one), and the ultimate fallback "C".  This is all done in
     * the same loop as above to avoid duplicating code, but it makes things
     * more complex.  The 'trial_locales' array is initialized with just one
     * element; it causes the behavior described in the paragraph above this to
     * happen.  If that fails, we add elements to 'trial_locales', and do extra
     * loop iterations to cause the behavior described in this paragraph.
     *
     * On Ultrix, the locale MUST come from the environment, so there is
     * preliminary code to set it.  I (khw) am not sure that it is necessary,
     * and that this couldn't be folded into the loop, but barring any real
     * platforms to test on, it's staying as-is
     *
     * A slight complication is that in embedded Perls, the locale may already
     * be set-up, and we don't want to get it from the normal environment
     * variables.  This is handled by having a special environment variable
     * indicate we're in this situation.  We simply set setlocale's 2nd
     * parameter to be a NULL instead of "".  That indicates to setlocale that
     * it is not to change anything, but to return the current value,
     * effectively initializing perl's db to what the locale already is.
     *
     * We play the same trick with NULL if a LC_ALL succeeds.  We call
     * setlocale() on the individual categores with NULL to get their existing
     * values for our db, instead of trying to change them.
     * */

    int ok = 1;

#ifndef USE_LOCALE

    PERL_UNUSED_ARG(printwarn);

#else  /* USE_LOCALE */
#  ifdef __GLIBC__

    const char * const language   = savepv(PerlEnv_getenv("LANGUAGE"));

#  endif

    /* NULL uses the existing already set up locale */
    const char * const setlocale_init = (PerlEnv_getenv("PERL_SKIP_LOCALE_INIT"))
                                        ? NULL
                                        : "";
    const char* trial_locales[5];   /* 5 = 1 each for "", LC_ALL, LANG, "", C */
    unsigned int trial_locales_count;
    const char * const lc_all     = savepv(PerlEnv_getenv("LC_ALL"));
    const char * const lang       = savepv(PerlEnv_getenv("LANG"));
    bool setlocale_failure = FALSE;
    unsigned int i;

    /* A later getenv() could zap this, so only use here */
    const char * const bad_lang_use_once = PerlEnv_getenv("PERL_BADLANG");

    const bool locwarn = (printwarn > 1
                          || (          printwarn
                              && (    ! bad_lang_use_once
                                  || (
                                    /* disallow with "" or "0" */
                                    *bad_lang_use_once
                                    && strNEc(bad_lang_use_once, "0")))));
    bool done = FALSE;
    static char * sl_result[NOMINAL_LC_ALL_INDEX + 1]; /* setlocale() return vals;
                                                     not copied so must be
                                                     looked at immediately */
    static char * curlocales[NOMINAL_LC_ALL_INDEX + 1]; /* current locale for given
                                                     category; should have been
                                                     copied so aren't volatile.
                                                     Needs to be initialized via static,
                                                     See Coverity CID #180984
                                                     Uninitialized pointer read
                                                   */
    char * locale_param;

#  ifdef WIN32

    /* In some systems you can find out the system default locale
     * and use that as the fallback locale. */
#    define SYSTEM_DEFAULT_LOCALE
#  endif
#  ifdef SYSTEM_DEFAULT_LOCALE

    const char *system_default_locale = NULL;

#  endif

#  ifndef DEBUGGING
#    define DEBUG_LOCALE_INIT(a,b,c)
#  else

    DEBUG_INITIALIZATION_set(cBOOL(PerlEnv_getenv("PERL_DEBUG_LOCALE_INIT")));

#    define DEBUG_LOCALE_INIT(category, locale, result)                     \
	STMT_START {                                                        \
		if (debug_initialization) {                                 \
                    PerlIO_printf(Perl_debug_log,                           \
                                  "%s:%d: %s\n",                            \
                                  __FILE__, __LINE__,                       \
                                  setlocale_debug_string(category,          \
                                                          locale,           \
                                                          result));         \
                }                                                           \
	} STMT_END

/* Make sure the parallel arrays are properly set up */
#    ifdef USE_LOCALE_NUMERIC
    assert(categories[LC_NUMERIC_INDEX] == LC_NUMERIC);
    assert(strEQ(category_names[LC_NUMERIC_INDEX], "LC_NUMERIC"));
#    endif
#    ifdef USE_LOCALE_CTYPE
    assert(categories[LC_CTYPE_INDEX] == LC_CTYPE);
    assert(strEQ(category_names[LC_CTYPE_INDEX], "LC_CTYPE"));
#    endif
#    ifdef USE_LOCALE_COLLATE
    assert(categories[LC_COLLATE_INDEX] == LC_COLLATE);
    assert(strEQ(category_names[LC_COLLATE_INDEX], "LC_COLLATE"));
#    endif
#    ifdef USE_LOCALE_TIME
    assert(categories[LC_TIME_INDEX] == LC_TIME);
    assert(strEQ(category_names[LC_TIME_INDEX], "LC_TIME"));
#    endif
#    ifdef USE_LOCALE_MESSAGES
    assert(categories[LC_MESSAGES_INDEX] == LC_MESSAGES);
    assert(strEQ(category_names[LC_MESSAGES_INDEX], "LC_MESSAGES"));
#    endif
#    ifdef USE_LOCALE_MONETARY
    assert(categories[LC_MONETARY_INDEX] == LC_MONETARY);
    assert(strEQ(category_names[LC_MONETARY_INDEX], "LC_MONETARY"));
#    endif
#    ifdef LC_ALL
    assert(categories[LC_ALL_INDEX] == LC_ALL);
    assert(strEQ(category_names[LC_ALL_INDEX], "LC_ALL"));
    assert(NOMINAL_LC_ALL_INDEX == LC_ALL_INDEX);
#    endif
#  endif    /* DEBUGGING */
#  ifndef LOCALE_ENVIRON_REQUIRED

    PERL_UNUSED_VAR(done);
    PERL_UNUSED_VAR(locale_param);

#  else

    /*
     * Ultrix setlocale(..., "") fails if there are no environment
     * variables from which to get a locale name.
     */

#    ifdef LC_ALL

    if (lang) {
	sl_result[LC_ALL_INDEX] = do_setlocale_c(LC_ALL, setlocale_init);
        DEBUG_LOCALE_INIT(LC_ALL, setlocale_init, sl_result[LC_ALL_INDEX]);
	if (sl_result[LC_ALL_INDEX])
	    done = TRUE;
	else
	    setlocale_failure = TRUE;
    }
    if (! setlocale_failure) {
        for (i = 0; i < LC_ALL_INDEX; i++) {
            locale_param = (! done && (lang || PerlEnv_getenv(category_names[i])))
                           ? setlocale_init
                           : NULL;
            sl_result[i] = do_setlocale_r(categories[i], locale_param);
            if (! sl_result[i]) {
                setlocale_failure = TRUE;
            }
            DEBUG_LOCALE_INIT(categories[i], locale_param, sl_result[i]);
        }
    }

#    endif /* LC_ALL */
#  endif /* LOCALE_ENVIRON_REQUIRED */

    /* We try each locale in the list until we get one that works, or exhaust
     * the list.  Normally the loop is executed just once.  But if setting the
     * locale fails, inside the loop we add fallback trials to the array and so
     * will execute the loop multiple times */
    trial_locales[0] = setlocale_init;
    trial_locales_count = 1;

    for (i= 0; i < trial_locales_count; i++) {
        const char * trial_locale = trial_locales[i];

        if (i > 0) {

            /* XXX This is to preserve old behavior for LOCALE_ENVIRON_REQUIRED
             * when i==0, but I (khw) don't think that behavior makes much
             * sense */
            setlocale_failure = FALSE;

#  ifdef SYSTEM_DEFAULT_LOCALE
#    ifdef WIN32

            /* On Windows machines, an entry of "" after the 0th means to use
             * the system default locale, which we now proceed to get. */
            if (strEQc(trial_locale, "")) {
                unsigned int j;

                /* Note that this may change the locale, but we are going to do
                 * that anyway just below */
                system_default_locale = do_setlocale_c(LC_ALL, "");
                DEBUG_LOCALE_INIT(LC_ALL, "", system_default_locale);

                /* Skip if invalid or if it's already on the list of locales to
                 * try */
                if (! system_default_locale) {
                    goto next_iteration;
                }
                for (j = 0; j < trial_locales_count; j++) {
                    if (strEQ(system_default_locale, trial_locales[j])) {
                        goto next_iteration;
                    }
                }

                trial_locale = system_default_locale;
            }
#    endif /* WIN32 */
#  endif /* SYSTEM_DEFAULT_LOCALE */
        }

#  ifdef LC_ALL

        sl_result[LC_ALL_INDEX] = do_setlocale_c(LC_ALL, trial_locale);
        DEBUG_LOCALE_INIT(LC_ALL, trial_locale, sl_result[LC_ALL_INDEX]);
        if (! sl_result[LC_ALL_INDEX]) {
            /* On darwin/osx we might want to free this return value or
               suppress the valgrind warning, but not elsewhere. POSIX
               standard forbids it, valgrind detects this upstream
               problem.  See
               e.g. https://stackoverflow.com/questions/29116354/should-i-free-the-pointer-returned-by-setlocale */            
            setlocale_failure = TRUE;
        }
        else {
            /* Since LC_ALL succeeded, it should have changed all the other
             * categories it can to its value; so we massage things so that the
             * setlocales below just return their category's current values.
             * This adequately handles the case in NetBSD where LC_COLLATE may
             * not be defined for a locale, and setting it individually will
             * fail, whereas setting LC_ALL succeeds, leaving LC_COLLATE set to
             * the POSIX locale. */
            trial_locale = NULL;
        }

#  endif /* LC_ALL */

        if (! setlocale_failure) {
            unsigned int j;
            for (j = 0; j < NOMINAL_LC_ALL_INDEX; j++) {
                curlocales[j]
                        = savepv(do_setlocale_r(categories[j], trial_locale));
                if (! curlocales[j]) {
                    setlocale_failure = TRUE;
                }
                DEBUG_LOCALE_INIT(categories[j], trial_locale, curlocales[j]);
            }

            if (! setlocale_failure) {  /* All succeeded */
                break;  /* Exit trial_locales loop */
            }
        }

        /* Here, something failed; will need to try a fallback. */
        ok = 0;

        if (i == 0) {
            unsigned int j;

            if (locwarn) { /* Output failure info only on the first one */

#  ifdef LC_ALL

                PerlIO_printf(Perl_error_log,
                "perl: warning: Setting locale failed.\n");

#  else /* !LC_ALL */

                PerlIO_printf(Perl_error_log,
                "perl: warning: Setting locale failed for the categories:\n\t");

                for (j = 0; j < NOMINAL_LC_ALL_INDEX; j++) {
                    if (! curlocales[j]) {
                        PerlIO_printf(Perl_error_log, category_names[j]);
                    }
                    else {
                        Safefree(curlocales[j]);
                    }
                }

                PerlIO_printf(Perl_error_log, "and possibly others\n");

#  endif /* LC_ALL */

                PerlIO_printf(Perl_error_log,
                    "perl: warning: Please check that your locale settings:\n");

#  ifdef __GLIBC__

                PerlIO_printf(Perl_error_log,
                            "\tLANGUAGE = %c%s%c,\n",
                            language ? '"' : '(',
                            language ? language : "unset",
                            language ? '"' : ')');
#  endif

                PerlIO_printf(Perl_error_log,
                            "\tLC_ALL = %c%s%c,\n",
                            lc_all ? '"' : '(',
                            lc_all ? lc_all : "unset",
                            lc_all ? '"' : ')');

#  if defined(USE_ENVIRON_ARRAY)

                {
                    char **e;

                    /* Look through the environment for any variables of the
                     * form qr/ ^ LC_ [A-Z]+ = /x, except LC_ALL which was
                     * already handled above.  These are assumed to be locale
                     * settings.  Output them and their values. */
                    for (e = environ; *e; e++) {
                        const STRLEN prefix_len = sizeof("LC_") - 1;
                        STRLEN uppers_len;

                        if (     strBEGINs(*e, "LC_")
                            && ! strBEGINs(*e, "LC_ALL=")
                            && (uppers_len = strspn(*e + prefix_len,
                                             "ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
                            && ((*e)[prefix_len + uppers_len] == '='))
                        {
                            PerlIO_printf(Perl_error_log, "\t%.*s = \"%s\",\n",
                                (int) (prefix_len + uppers_len), *e,
                                *e + prefix_len + uppers_len + 1);
                        }
                    }
                }

#  else

                PerlIO_printf(Perl_error_log,
                            "\t(possibly more locale environment variables)\n");

#  endif

                PerlIO_printf(Perl_error_log,
                            "\tLANG = %c%s%c\n",
                            lang ? '"' : '(',
                            lang ? lang : "unset",
                            lang ? '"' : ')');

                PerlIO_printf(Perl_error_log,
                            "    are supported and installed on your system.\n");
            }

            /* Calculate what fallback locales to try.  We have avoided this
             * until we have to, because failure is quite unlikely.  This will
             * usually change the upper bound of the loop we are in.
             *
             * Since the system's default way of setting the locale has not
             * found one that works, We use Perl's defined ordering: LC_ALL,
             * LANG, and the C locale.  We don't try the same locale twice, so
             * don't add to the list if already there.  (On POSIX systems, the
             * LC_ALL element will likely be a repeat of the 0th element "",
             * but there's no harm done by doing it explicitly.
             *
             * Note that this tries the LC_ALL environment variable even on
             * systems which have no LC_ALL locale setting.  This may or may
             * not have been originally intentional, but there's no real need
             * to change the behavior. */
            if (lc_all) {
                for (j = 0; j < trial_locales_count; j++) {
                    if (strEQ(lc_all, trial_locales[j])) {
                        goto done_lc_all;
                    }
                }
                trial_locales[trial_locales_count++] = lc_all;
            }
          done_lc_all:

            if (lang) {
                for (j = 0; j < trial_locales_count; j++) {
                    if (strEQ(lang, trial_locales[j])) {
                        goto done_lang;
                    }
                }
                trial_locales[trial_locales_count++] = lang;
            }
          done_lang:

#  if defined(WIN32) && defined(LC_ALL)

            /* For Windows, we also try the system default locale before "C".
             * (If there exists a Windows without LC_ALL we skip this because
             * it gets too complicated.  For those, the "C" is the next
             * fallback possibility).  The "" is the same as the 0th element of
             * the array, but the code at the loop above knows to treat it
             * differently when not the 0th */
            trial_locales[trial_locales_count++] = "";

#  endif

            for (j = 0; j < trial_locales_count; j++) {
                if (strEQc(trial_locales[j], "C")) {
                    goto done_C;
                }
            }
            trial_locales[trial_locales_count++] = "C";

          done_C: ;
        }   /* end of first time through the loop */

#  ifdef WIN32

      next_iteration: ;

#  endif

    }   /* end of looping through the trial locales */

    if (ok < 1) {   /* If we tried to fallback */
        const char* msg;
        if (! setlocale_failure) {  /* fallback succeeded */
           msg = "Falling back to";
        }
        else {  /* fallback failed */
            unsigned int j;

            /* We dropped off the end of the loop, so have to decrement i to
             * get back to the value the last time through */
            i--;

            ok = -1;
            msg = "Failed to fall back to";

            /* To continue, we should use whatever values we've got */

            for (j = 0; j < NOMINAL_LC_ALL_INDEX; j++) {
                Safefree(curlocales[j]);
                curlocales[j] = savepv(do_setlocale_r(categories[j], NULL));
                DEBUG_LOCALE_INIT(categories[j], NULL, curlocales[j]);
            }
        }

        if (locwarn) {
            const char * description;
            const char * name = "";
            if (strEQc(trial_locales[i], "C")) {
                description = "the standard locale";
                name = "C";
            }

#  ifdef SYSTEM_DEFAULT_LOCALE

            else if (strEQc(trial_locales[i], "")) {
                description = "the system default locale";
                if (system_default_locale) {
                    name = system_default_locale;
                }
            }

#  endif /* SYSTEM_DEFAULT_LOCALE */

            else {
                description = "a fallback locale";
                name = trial_locales[i];
            }
            if (name && *name) {
                PerlIO_printf(Perl_error_log,
                    "perl: warning: %s %s (\"%s\").\n", msg, description, name);
            }
            else {
                PerlIO_printf(Perl_error_log,
                                   "perl: warning: %s %s.\n", msg, description);
            }
        }
    } /* End of tried to fallback */

    /* Done with finding the locales; update our records */

#  ifdef USE_LOCALE_CTYPE

    new_ctype(curlocales[LC_CTYPE_INDEX]);

#  endif
#  ifdef USE_LOCALE_COLLATE

    new_collate(curlocales[LC_COLLATE_INDEX]);

#  endif
#  ifdef USE_LOCALE_NUMERIC

    new_numeric(curlocales[LC_NUMERIC_INDEX]);

#  endif


    for (i = 0; i < NOMINAL_LC_ALL_INDEX; i++) {
        Safefree(curlocales[i]);
    }

#  if defined(USE_PERLIO) && defined(USE_LOCALE_CTYPE)

    /* Set PL_utf8locale to TRUE if using PerlIO _and_ the current LC_CTYPE
     * locale is UTF-8.  If PL_utf8locale and PL_unicode (set by -C or by
     * $ENV{PERL_UNICODE}) are true, perl.c:S_parse_body() will turn on the
     * PerlIO :utf8 layer on STDIN, STDOUT, STDERR, _and_ the default open
     * discipline.  */
    PL_utf8locale = _is_cur_LC_category_utf8(LC_CTYPE);

    /* Set PL_unicode to $ENV{PERL_UNICODE} if using PerlIO.
       This is an alternative to using the -C command line switch
       (the -C if present will override this). */
    {
	 const char *p = PerlEnv_getenv("PERL_UNICODE");
	 PL_unicode = p ? parse_unicode_opts(&p) : 0;
	 if (PL_unicode & PERL_UNICODE_UTF8CACHEASSERT_FLAG)
	     PL_utf8cache = -1;
    }

#  endif
#  ifdef __GLIBC__

    Safefree(language);

#  endif

    Safefree(lc_all);
    Safefree(lang);

#endif /* USE_LOCALE */
#ifdef DEBUGGING

    /* So won't continue to output stuff */
    DEBUG_INITIALIZATION_set(FALSE);

#endif

    return ok;
}

#ifdef USE_LOCALE_COLLATE

char *
Perl__mem_collxfrm(pTHX_ const char *input_string,
                         STRLEN len,    /* Length of 'input_string' */
                         STRLEN *xlen,  /* Set to length of returned string
                                           (not including the collation index
                                           prefix) */
                         bool utf8      /* Is the input in UTF-8? */
                   )
{

    /* _mem_collxfrm() is a bit like strxfrm() but with two important
     * differences. First, it handles embedded NULs. Second, it allocates a bit
     * more memory than needed for the transformed data itself.  The real
     * transformed data begins at offset COLLXFRM_HDR_LEN.  *xlen is set to
     * the length of that, and doesn't include the collation index size.
     * Please see sv_collxfrm() to see how this is used. */

#define COLLXFRM_HDR_LEN    sizeof(PL_collation_ix)

    char * s = (char *) input_string;
    STRLEN s_strlen = strlen(input_string);
    char *xbuf = NULL;
    STRLEN xAlloc;          /* xalloc is a reserved word in VC */
    STRLEN length_in_chars;
    bool first_time = TRUE; /* Cleared after first loop iteration */

    PERL_ARGS_ASSERT__MEM_COLLXFRM;

    /* Must be NUL-terminated */
    assert(*(input_string + len) == '\0');

    /* If this locale has defective collation, skip */
    if (PL_collxfrm_base == 0 && PL_collxfrm_mult == 0) {
        DEBUG_L(PerlIO_printf(Perl_debug_log,
                      "_mem_collxfrm: locale's collation is defective\n"));
        goto bad;
    }

    /* Replace any embedded NULs with the control that sorts before any others.
     * This will give as good as possible results on strings that don't
     * otherwise contain that character, but otherwise there may be
     * less-than-perfect results with that character and NUL.  This is
     * unavoidable unless we replace strxfrm with our own implementation. */
    if (UNLIKELY(s_strlen < len)) {   /* Only execute if there is an embedded
                                         NUL */
        char * e = s + len;
        char * sans_nuls;
        STRLEN sans_nuls_len;
        int try_non_controls;
        char this_replacement_char[] = "?\0";   /* Room for a two-byte string,
                                                   making sure 2nd byte is NUL.
                                                 */
        STRLEN this_replacement_len;

        /* If we don't know what non-NUL control character sorts lowest for
         * this locale, find it */
        if (PL_strxfrm_NUL_replacement == '\0') {
            int j;
            char * cur_min_x = NULL;    /* The min_char's xfrm, (except it also
                                           includes the collation index
                                           prefixed. */

            DEBUG_Lv(PerlIO_printf(Perl_debug_log, "Looking to replace NUL\n"));

            /* Unlikely, but it may be that no control will work to replace
             * NUL, in which case we instead look for any character.  Controls
             * are preferred because collation order is, in general, context
             * sensitive, with adjoining characters affecting the order, and
             * controls are less likely to have such interactions, allowing the
             * NUL-replacement to stand on its own.  (Another way to look at it
             * is to imagine what would happen if the NUL were replaced by a
             * combining character; it wouldn't work out all that well.) */
            for (try_non_controls = 0;
                 try_non_controls < 2;
                 try_non_controls++)
            {
                /* Look through all legal code points (NUL isn't) */
                for (j = 1; j < 256; j++) {
                    char * x;       /* j's xfrm plus collation index */
                    STRLEN x_len;   /* length of 'x' */
                    STRLEN trial_len = 1;
                    char cur_source[] = { '\0', '\0' };

                    /* Skip non-controls the first time through the loop.  The
                     * controls in a UTF-8 locale are the L1 ones */
                    if (! try_non_controls && (PL_in_utf8_COLLATE_locale)
                                               ? ! isCNTRL_L1(j)
                                               : ! isCNTRL_LC(j))
                    {
                        continue;
                    }

                    /* Create a 1-char string of the current code point */
                    cur_source[0] = (char) j;

                    /* Then transform it */
                    x = _mem_collxfrm(cur_source, trial_len, &x_len,
                                      0 /* The string is not in UTF-8 */);

                    /* Ignore any character that didn't successfully transform.
                     * */
                    if (! x) {
                        continue;
                    }

                    /* If this character's transformation is lower than
                     * the current lowest, this one becomes the lowest */
                    if (   cur_min_x == NULL
                        || strLT(x         + COLLXFRM_HDR_LEN,
                                 cur_min_x + COLLXFRM_HDR_LEN))
                    {
                        PL_strxfrm_NUL_replacement = j;
                        cur_min_x = x;
                    }
                    else {
                        Safefree(x);
                    }
                } /* end of loop through all 255 characters */

                /* Stop looking if found */
                if (cur_min_x) {
                    break;
                }

                /* Unlikely, but possible, if there aren't any controls that
                 * work in the locale, repeat the loop, looking for any
                 * character that works */
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                "_mem_collxfrm: No control worked.  Trying non-controls\n"));
            } /* End of loop to try first the controls, then any char */

            if (! cur_min_x) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                    "_mem_collxfrm: Couldn't find any character to replace"
                    " embedded NULs in locale %s with", PL_collation_name));
                goto bad;
            }

            DEBUG_L(PerlIO_printf(Perl_debug_log,
                    "_mem_collxfrm: Replacing embedded NULs in locale %s with "
                    "0x%02X\n", PL_collation_name, PL_strxfrm_NUL_replacement));

            Safefree(cur_min_x);
        } /* End of determining the character that is to replace NULs */

        /* If the replacement is variant under UTF-8, it must match the
         * UTF8-ness as the original */
        if ( ! UVCHR_IS_INVARIANT(PL_strxfrm_NUL_replacement) && utf8) {
            this_replacement_char[0] =
                                UTF8_EIGHT_BIT_HI(PL_strxfrm_NUL_replacement);
            this_replacement_char[1] =
                                UTF8_EIGHT_BIT_LO(PL_strxfrm_NUL_replacement);
            this_replacement_len = 2;
        }
        else {
            this_replacement_char[0] = PL_strxfrm_NUL_replacement;
            /* this_replacement_char[1] = '\0' was done at initialization */
            this_replacement_len = 1;
        }

        /* The worst case length for the replaced string would be if every
         * character in it is NUL.  Multiply that by the length of each
         * replacement, and allow for a trailing NUL */
        sans_nuls_len = (len * this_replacement_len) + 1;
        Newx(sans_nuls, sans_nuls_len, char);
        *sans_nuls = '\0';

        /* Replace each NUL with the lowest collating control.  Loop until have
         * exhausted all the NULs */
        while (s + s_strlen < e) {
            my_strlcat(sans_nuls, s, sans_nuls_len);

            /* Do the actual replacement */
            my_strlcat(sans_nuls, this_replacement_char, sans_nuls_len);

            /* Move past the input NUL */
            s += s_strlen + 1;
            s_strlen = strlen(s);
        }

        /* And add anything that trails the final NUL */
        my_strlcat(sans_nuls, s, sans_nuls_len);

        /* Switch so below we transform this modified string */
        s = sans_nuls;
        len = strlen(s);
    } /* End of replacing NULs */

    /* Make sure the UTF8ness of the string and locale match */
    if (utf8 != PL_in_utf8_COLLATE_locale) {
        const char * const t = s;   /* Temporary so we can later find where the
                                       input was */

        /* Here they don't match.  Change the string's to be what the locale is
         * expecting */

        if (! utf8) { /* locale is UTF-8, but input isn't; upgrade the input */
            s = (char *) bytes_to_utf8((const U8 *) s, &len);
            utf8 = TRUE;
        }
        else {   /* locale is not UTF-8; but input is; downgrade the input */

            s = (char *) bytes_from_utf8((const U8 *) s, &len, &utf8);

            /* If the downgrade was successful we are done, but if the input
             * contains things that require UTF-8 to represent, have to do
             * damage control ... */
            if (UNLIKELY(utf8)) {

                /* What we do is construct a non-UTF-8 string with
                 *  1) the characters representable by a single byte converted
                 *     to be so (if necessary);
                 *  2) and the rest converted to collate the same as the
                 *     highest collating representable character.  That makes
                 *     them collate at the end.  This is similar to how we
                 *     handle embedded NULs, but we use the highest collating
                 *     code point instead of the smallest.  Like the NUL case,
                 *     this isn't perfect, but is the best we can reasonably
                 *     do.  Every above-255 code point will sort the same as
                 *     the highest-sorting 0-255 code point.  If that code
                 *     point can combine in a sequence with some other code
                 *     points for weight calculations, us changing something to
                 *     be it can adversely affect the results.  But in most
                 *     cases, it should work reasonably.  And note that this is
                 *     really an illegal situation: using code points above 255
                 *     on a locale where only 0-255 are valid.  If two strings
                 *     sort entirely equal, then the sort order for the
                 *     above-255 code points will be in code point order. */

                utf8 = FALSE;

                /* If we haven't calculated the code point with the maximum
                 * collating order for this locale, do so now */
                if (! PL_strxfrm_max_cp) {
                    int j;

                    /* The current transformed string that collates the
                     * highest (except it also includes the prefixed collation
                     * index. */
                    char * cur_max_x = NULL;

                    /* Look through all legal code points (NUL isn't) */
                    for (j = 1; j < 256; j++) {
                        char * x;
                        STRLEN x_len;
                        char cur_source[] = { '\0', '\0' };

                        /* Create a 1-char string of the current code point */
                        cur_source[0] = (char) j;

                        /* Then transform it */
                        x = _mem_collxfrm(cur_source, 1, &x_len, FALSE);

                        /* If something went wrong (which it shouldn't), just
                         * ignore this code point */
                        if (! x) {
                            continue;
                        }

                        /* If this character's transformation is higher than
                         * the current highest, this one becomes the highest */
                        if (   cur_max_x == NULL
                            || strGT(x         + COLLXFRM_HDR_LEN,
                                     cur_max_x + COLLXFRM_HDR_LEN))
                        {
                            PL_strxfrm_max_cp = j;
                            cur_max_x = x;
                        }
                        else {
                            Safefree(x);
                        }
                    }

                    if (! cur_max_x) {
                        DEBUG_L(PerlIO_printf(Perl_debug_log,
                            "_mem_collxfrm: Couldn't find any character to"
                            " replace above-Latin1 chars in locale %s with",
                            PL_collation_name));
                        goto bad;
                    }

                    DEBUG_L(PerlIO_printf(Perl_debug_log,
                            "_mem_collxfrm: highest 1-byte collating character"
                            " in locale %s is 0x%02X\n",
                            PL_collation_name,
                            PL_strxfrm_max_cp));

                    Safefree(cur_max_x);
                }

                /* Here we know which legal code point collates the highest.
                 * We are ready to construct the non-UTF-8 string.  The length
                 * will be at least 1 byte smaller than the input string
                 * (because we changed at least one 2-byte character into a
                 * single byte), but that is eaten up by the trailing NUL */
                Newx(s, len, char);

                {
                    STRLEN i;
                    STRLEN d= 0;
                    char * e = (char *) t + len;

                    for (i = 0; i < len; i+= UTF8SKIP(t + i)) {
                        U8 cur_char = t[i];
                        if (UTF8_IS_INVARIANT(cur_char)) {
                            s[d++] = cur_char;
                        }
                        else if (UTF8_IS_NEXT_CHAR_DOWNGRADEABLE(t + i, e)) {
                            s[d++] = EIGHT_BIT_UTF8_TO_NATIVE(cur_char, t[i+1]);
                        }
                        else {  /* Replace illegal cp with highest collating
                                   one */
                            s[d++] = PL_strxfrm_max_cp;
                        }
                    }
                    s[d++] = '\0';
                    Renew(s, d, char);   /* Free up unused space */
                }
            }
        }

        /* Here, we have constructed a modified version of the input.  It could
         * be that we already had a modified copy before we did this version.
         * If so, that copy is no longer needed */
        if (t != input_string) {
            Safefree(t);
        }
    }

    length_in_chars = (utf8)
                      ? utf8_length((U8 *) s, (U8 *) s + len)
                      : len;

    /* The first element in the output is the collation id, used by
     * sv_collxfrm(); then comes the space for the transformed string.  The
     * equation should give us a good estimate as to how much is needed */
    xAlloc = COLLXFRM_HDR_LEN
           + PL_collxfrm_base
           + (PL_collxfrm_mult * length_in_chars);
    Newx(xbuf, xAlloc, char);
    if (UNLIKELY(! xbuf)) {
        DEBUG_L(PerlIO_printf(Perl_debug_log,
                      "_mem_collxfrm: Couldn't malloc %zu bytes\n", xAlloc));
	goto bad;
    }

    /* Store the collation id */
    *(U32*)xbuf = PL_collation_ix;

    /* Then the transformation of the input.  We loop until successful, or we
     * give up */
    for (;;) {

        *xlen = strxfrm(xbuf + COLLXFRM_HDR_LEN, s, xAlloc - COLLXFRM_HDR_LEN);

        /* If the transformed string occupies less space than we told strxfrm()
         * was available, it means it successfully transformed the whole
         * string. */
        if (*xlen < xAlloc - COLLXFRM_HDR_LEN) {

            /* Some systems include a trailing NUL in the returned length.
             * Ignore it, using a loop in case multiple trailing NULs are
             * returned. */
            while (   (*xlen) > 0
                   && *(xbuf + COLLXFRM_HDR_LEN + (*xlen) - 1) == '\0')
            {
                (*xlen)--;
            }

            /* If the first try didn't get it, it means our prediction was low.
             * Modify the coefficients so that we predict a larger value in any
             * future transformations */
            if (! first_time) {
                STRLEN needed = *xlen + 1;   /* +1 For trailing NUL */
                STRLEN computed_guess = PL_collxfrm_base
                                      + (PL_collxfrm_mult * length_in_chars);

                /* On zero-length input, just keep current slope instead of
                 * dividing by 0 */
                const STRLEN new_m = (length_in_chars != 0)
                                     ? needed / length_in_chars
                                     : PL_collxfrm_mult;

                DEBUG_Lv(PerlIO_printf(Perl_debug_log,
                    "%s: %d: initial size of %zu bytes for a length "
                    "%zu string was insufficient, %zu needed\n",
                    __FILE__, __LINE__,
                    computed_guess, length_in_chars, needed));

                /* If slope increased, use it, but discard this result for
                 * length 1 strings, as we can't be sure that it's a real slope
                 * change */
                if (length_in_chars > 1 && new_m  > PL_collxfrm_mult) {

#  ifdef DEBUGGING

                    STRLEN old_m = PL_collxfrm_mult;
                    STRLEN old_b = PL_collxfrm_base;

#  endif

                    PL_collxfrm_mult = new_m;
                    PL_collxfrm_base = 1;   /* +1 For trailing NUL */
                    computed_guess = PL_collxfrm_base
                                    + (PL_collxfrm_mult * length_in_chars);
                    if (computed_guess < needed) {
                        PL_collxfrm_base += needed - computed_guess;
                    }

                    DEBUG_Lv(PerlIO_printf(Perl_debug_log,
                        "%s: %d: slope is now %zu; was %zu, base "
                        "is now %zu; was %zu\n",
                        __FILE__, __LINE__,
                        PL_collxfrm_mult, old_m,
                        PL_collxfrm_base, old_b));
                }
                else {  /* Slope didn't change, but 'b' did */
                    const STRLEN new_b = needed
                                        - computed_guess
                                        + PL_collxfrm_base;
                    DEBUG_Lv(PerlIO_printf(Perl_debug_log,
                        "%s: %d: base is now %zu; was %zu\n",
                        __FILE__, __LINE__,
                        new_b, PL_collxfrm_base));
                    PL_collxfrm_base = new_b;
                }
            }

            break;
        }

        if (UNLIKELY(*xlen >= PERL_INT_MAX)) {
            DEBUG_L(PerlIO_printf(Perl_debug_log,
                  "_mem_collxfrm: Needed %zu bytes, max permissible is %u\n",
                  *xlen, PERL_INT_MAX));
            goto bad;
        }

        /* A well-behaved strxfrm() returns exactly how much space it needs
         * (usually not including the trailing NUL) when it fails due to not
         * enough space being provided.  Assume that this is the case unless
         * it's been proven otherwise */
        if (LIKELY(PL_strxfrm_is_behaved) && first_time) {
            xAlloc = *xlen + COLLXFRM_HDR_LEN + 1;
        }
        else { /* Here, either:
                *  1)  The strxfrm() has previously shown bad behavior; or
                *  2)  It isn't the first time through the loop, which means
                *      that the strxfrm() is now showing bad behavior, because
                *      we gave it what it said was needed in the previous
                *      iteration, and it came back saying it needed still more.
                *      (Many versions of cygwin fit this.  When the buffer size
                *      isn't sufficient, they return the input size instead of
                *      how much is needed.)
                * Increase the buffer size by a fixed percentage and try again.
                * */
            xAlloc += (xAlloc / 4) + 1;
            PL_strxfrm_is_behaved = FALSE;

#  ifdef DEBUGGING

            if (DEBUG_Lv_TEST || debug_initialization) {
                PerlIO_printf(Perl_debug_log,
                "_mem_collxfrm required more space than previously calculated"
                " for locale %s, trying again with new guess=%d+%zu\n",
                PL_collation_name, (int) COLLXFRM_HDR_LEN,
                xAlloc - COLLXFRM_HDR_LEN);
            }

#  endif

        }

        Renew(xbuf, xAlloc, char);
        if (UNLIKELY(! xbuf)) {
            DEBUG_L(PerlIO_printf(Perl_debug_log,
                      "_mem_collxfrm: Couldn't realloc %zu bytes\n", xAlloc));
            goto bad;
        }

        first_time = FALSE;
    }


#  ifdef DEBUGGING

    if (DEBUG_Lv_TEST || debug_initialization) {

        print_collxfrm_input_and_return(s, s + len, xlen, utf8);
        PerlIO_printf(Perl_debug_log, "Its xfrm is:");
        PerlIO_printf(Perl_debug_log, "%s\n",
                      _byte_dump_string((U8 *) xbuf + COLLXFRM_HDR_LEN,
                       *xlen, 1));
    }

#  endif

    /* Free up unneeded space; retain ehough for trailing NUL */
    Renew(xbuf, COLLXFRM_HDR_LEN + *xlen + 1, char);

    if (s != input_string) {
        Safefree(s);
    }

    return xbuf;

  bad:
    Safefree(xbuf);
    if (s != input_string) {
        Safefree(s);
    }
    *xlen = 0;

#  ifdef DEBUGGING

    if (DEBUG_Lv_TEST || debug_initialization) {
        print_collxfrm_input_and_return(s, s + len, NULL, utf8);
    }

#  endif

    return NULL;
}

#  ifdef DEBUGGING

STATIC void
S_print_collxfrm_input_and_return(pTHX_
                                  const char * const s,
                                  const char * const e,
                                  const STRLEN * const xlen,
                                  const bool is_utf8)
{

    PERL_ARGS_ASSERT_PRINT_COLLXFRM_INPUT_AND_RETURN;

    PerlIO_printf(Perl_debug_log, "_mem_collxfrm[%" UVuf "]: returning ",
                  (UV)PL_collation_ix);
    if (xlen) {
        PerlIO_printf(Perl_debug_log, "%zu", *xlen);
    }
    else {
        PerlIO_printf(Perl_debug_log, "NULL");
    }
    PerlIO_printf(Perl_debug_log, " for locale '%s', string='",
                  PL_collation_name);
    print_bytes_for_locale(s, e, is_utf8);

    PerlIO_printf(Perl_debug_log, "'\n");
}

STATIC void
S_print_bytes_for_locale(pTHX_
                    const char * const s,
                    const char * const e,
                    const bool is_utf8)
{
    const char * t = s;
    bool prev_was_printable = TRUE;
    bool first_time = TRUE;

    PERL_ARGS_ASSERT_PRINT_BYTES_FOR_LOCALE;

    while (t < e) {
        UV cp = (is_utf8)
                ?  utf8_to_uvchr_buf((U8 *) t, e, NULL)
                : * (U8 *) t;
        if (isPRINT(cp)) {
            if (! prev_was_printable) {
                PerlIO_printf(Perl_debug_log, " ");
            }
            PerlIO_printf(Perl_debug_log, "%c", (U8) cp);
            prev_was_printable = TRUE;
        }
        else {
            if (! first_time) {
                PerlIO_printf(Perl_debug_log, " ");
            }
            PerlIO_printf(Perl_debug_log, "%02" UVXf, cp);
            prev_was_printable = FALSE;
        }
        t += (is_utf8) ? UTF8SKIP(t) : 1;
        first_time = FALSE;
    }
}

#  endif   /* #ifdef DEBUGGING */
#endif /* USE_LOCALE_COLLATE */

#ifdef USE_LOCALE

bool
Perl__is_cur_LC_category_utf8(pTHX_ int category)
{
    /* Returns TRUE if the current locale for 'category' is UTF-8; FALSE
     * otherwise. 'category' may not be LC_ALL.  If the platform doesn't have
     * nl_langinfo(), nor MB_CUR_MAX, this employs a heuristic, which hence
     * could give the wrong result.  The result will very likely be correct for
     * languages that have commonly used non-ASCII characters, but for notably
     * English, it comes down to if the locale's name ends in something like
     * "UTF-8".  It errs on the side of not being a UTF-8 locale. */

    char *save_input_locale = NULL;
    STRLEN final_pos;

#  ifdef LC_ALL

    assert(category != LC_ALL);

#  endif

    /* First dispose of the trivial cases */
    save_input_locale = do_setlocale_r(category, NULL);
    if (! save_input_locale) {
        DEBUG_L(PerlIO_printf(Perl_debug_log,
                              "Could not find current locale for category %d\n",
                              category));
        return FALSE;   /* XXX maybe should croak */
    }
    save_input_locale = stdize_locale(savepv(save_input_locale));
    if (isNAME_C_OR_POSIX(save_input_locale)) {
        DEBUG_L(PerlIO_printf(Perl_debug_log,
                              "Current locale for category %d is %s\n",
                              category, save_input_locale));
        Safefree(save_input_locale);
        return FALSE;
    }

#  if defined(USE_LOCALE_CTYPE)    \
    && (defined(MB_CUR_MAX) || (defined(HAS_NL_LANGINFO) && defined(CODESET)))

    { /* Next try nl_langinfo or MB_CUR_MAX if available */

        char *save_ctype_locale = NULL;
        bool is_utf8;

        if (category != LC_CTYPE) { /* These work only on LC_CTYPE */

            /* Get the current LC_CTYPE locale */
            save_ctype_locale = do_setlocale_c(LC_CTYPE, NULL);
            if (! save_ctype_locale) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                               "Could not find current locale for LC_CTYPE\n"));
                goto cant_use_nllanginfo;
            }
            save_ctype_locale = stdize_locale(savepv(save_ctype_locale));

            /* If LC_CTYPE and the desired category use the same locale, this
             * means that finding the value for LC_CTYPE is the same as finding
             * the value for the desired category.  Otherwise, switch LC_CTYPE
             * to the desired category's locale */
            if (strEQ(save_ctype_locale, save_input_locale)) {
                Safefree(save_ctype_locale);
                save_ctype_locale = NULL;
            }
            else if (! do_setlocale_c(LC_CTYPE, save_input_locale)) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                                    "Could not change LC_CTYPE locale to %s\n",
                                    save_input_locale));
                Safefree(save_ctype_locale);
                goto cant_use_nllanginfo;
            }
        }

        DEBUG_L(PerlIO_printf(Perl_debug_log, "Current LC_CTYPE locale=%s\n",
                                              save_input_locale));

        /* Here the current LC_CTYPE is set to the locale of the category whose
         * information is desired.  This means that nl_langinfo() and MB_CUR_MAX
         * should give the correct results */

#    if defined(HAS_NL_LANGINFO) && defined(CODESET)
     /* The task is easiest if has this POSIX 2001 function */

        {
            const char *codeset = my_nl_langinfo(PERL_CODESET, FALSE);
                                          /* FALSE => already in dest locale */

            DEBUG_L(PerlIO_printf(Perl_debug_log,
                            "\tnllanginfo returned CODESET '%s'\n", codeset));

            if (codeset && *codeset) {
                /* If we switched LC_CTYPE, switch back */
                if (save_ctype_locale) {
                    do_setlocale_c(LC_CTYPE, save_ctype_locale);
                    Safefree(save_ctype_locale);
                }

                is_utf8 = (   (   strlen(codeset) == STRLENs("UTF-8")
                               && foldEQ(codeset, STR_WITH_LEN("UTF-8")))
                           || (   strlen(codeset) == STRLENs("UTF8")
                               && foldEQ(codeset, STR_WITH_LEN("UTF8"))));

                DEBUG_L(PerlIO_printf(Perl_debug_log,
                       "\tnllanginfo returned CODESET '%s'; ?UTF8 locale=%d\n",
                                                     codeset,         is_utf8));
                Safefree(save_input_locale);
                return is_utf8;
            }
        }

#    endif
#    ifdef MB_CUR_MAX

        /* Here, either we don't have nl_langinfo, or it didn't return a
         * codeset.  Try MB_CUR_MAX */

        /* Standard UTF-8 needs at least 4 bytes to represent the maximum
         * Unicode code point.  Since UTF-8 is the only non-single byte
         * encoding we handle, we just say any such encoding is UTF-8, and if
         * turns out to be wrong, other things will fail */
        is_utf8 = MB_CUR_MAX >= 4;

        DEBUG_L(PerlIO_printf(Perl_debug_log,
                              "\tMB_CUR_MAX=%d; ?UTF8 locale=%d\n",
                                   (int) MB_CUR_MAX,      is_utf8));

        Safefree(save_input_locale);

#      ifdef HAS_MBTOWC

        /* ... But, most system that have MB_CUR_MAX will also have mbtowc(),
         * since they are both in the C99 standard.  We can feed a known byte
         * string to the latter function, and check that it gives the expected
         * result */
        if (is_utf8) {
            wchar_t wc;
            int len;

            PERL_UNUSED_RESULT(mbtowc(&wc, NULL, 0));/* Reset any shift state */
            errno = 0;
            len = mbtowc(&wc, STR_WITH_LEN(REPLACEMENT_CHARACTER_UTF8));


            if (   len != STRLENs(REPLACEMENT_CHARACTER_UTF8)
                || wc != (wchar_t) UNICODE_REPLACEMENT)
            {
                is_utf8 = FALSE;
                DEBUG_L(PerlIO_printf(Perl_debug_log, "\replacement=U+%x\n",
                                                            (unsigned int)wc));
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                        "\treturn from mbtowc=%d; errno=%d; ?UTF8 locale=0\n",
                                               len,      errno));
            }
        }

#      endif

        /* If we switched LC_CTYPE, switch back */
        if (save_ctype_locale) {
            do_setlocale_c(LC_CTYPE, save_ctype_locale);
            Safefree(save_ctype_locale);
        }

        return is_utf8;

#    endif

    }

  cant_use_nllanginfo:

#  else   /* nl_langinfo should work if available, so don't bother compiling this
           fallback code.  The final fallback of looking at the name is
           compiled, and will be executed if nl_langinfo fails */

    /* nl_langinfo not available or failed somehow.  Next try looking at the
     * currency symbol to see if it disambiguates things.  Often that will be
     * in the native script, and if the symbol isn't in UTF-8, we know that the
     * locale isn't.  If it is non-ASCII UTF-8, we infer that the locale is
     * too, as the odds of a non-UTF8 string being valid UTF-8 are quite small
     * */

#    ifdef HAS_LOCALECONV
#      ifdef USE_LOCALE_MONETARY

    {
        char *save_monetary_locale = NULL;
        bool only_ascii = FALSE;
        bool is_utf8 = FALSE;
        struct lconv* lc;

        /* Like above for LC_CTYPE, we first set LC_MONETARY to the locale of
         * the desired category, if it isn't that locale already */

        if (category != LC_MONETARY) {

            save_monetary_locale = do_setlocale_c(LC_MONETARY, NULL);
            if (! save_monetary_locale) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                            "Could not find current locale for LC_MONETARY\n"));
                goto cant_use_monetary;
            }
            save_monetary_locale = stdize_locale(savepv(save_monetary_locale));

            if (strEQ(save_monetary_locale, save_input_locale)) {
                Safefree(save_monetary_locale);
                save_monetary_locale = NULL;
            }
            else if (! do_setlocale_c(LC_MONETARY, save_input_locale)) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                            "Could not change LC_MONETARY locale to %s\n",
                                                        save_input_locale));
                Safefree(save_monetary_locale);
                goto cant_use_monetary;
            }
        }

        /* Here the current LC_MONETARY is set to the locale of the category
         * whose information is desired. */

        lc = localeconv();
        if (! lc
            || ! lc->currency_symbol
            || is_utf8_invariant_string((U8 *) lc->currency_symbol, 0))
        {
            DEBUG_L(PerlIO_printf(Perl_debug_log, "Couldn't get currency symbol for %s, or contains only ASCII; can't use for determining if UTF-8 locale\n", save_input_locale));
            only_ascii = TRUE;
        }
        else {
            is_utf8 = is_utf8_string((U8 *) lc->currency_symbol, 0);
        }

        /* If we changed it, restore LC_MONETARY to its original locale */
        if (save_monetary_locale) {
            do_setlocale_c(LC_MONETARY, save_monetary_locale);
            Safefree(save_monetary_locale);
        }

        if (! only_ascii) {

            /* It isn't a UTF-8 locale if the symbol is not legal UTF-8;
             * otherwise assume the locale is UTF-8 if and only if the symbol
             * is non-ascii UTF-8. */
            DEBUG_L(PerlIO_printf(Perl_debug_log, "\t?Currency symbol for %s is UTF-8=%d\n",
                                    save_input_locale, is_utf8));
            Safefree(save_input_locale);
            return is_utf8;
        }
    }
  cant_use_monetary:

#      endif /* USE_LOCALE_MONETARY */
#    endif /* HAS_LOCALECONV */

#    if defined(HAS_STRFTIME) && defined(USE_LOCALE_TIME)

/* Still haven't found a non-ASCII string to disambiguate UTF-8 or not.  Try
 * the names of the months and weekdays, timezone, and am/pm indicator */
    {
        char *save_time_locale = NULL;
        int hour = 10;
        bool is_dst = FALSE;
        int dom = 1;
        int month = 0;
        int i;
        char * formatted_time;


        /* Like above for LC_MONETARY, we set LC_TIME to the locale of the
         * desired category, if it isn't that locale already */

        if (category != LC_TIME) {

            save_time_locale = do_setlocale_c(LC_TIME, NULL);
            if (! save_time_locale) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                            "Could not find current locale for LC_TIME\n"));
                goto cant_use_time;
            }
            save_time_locale = stdize_locale(savepv(save_time_locale));

            if (strEQ(save_time_locale, save_input_locale)) {
                Safefree(save_time_locale);
                save_time_locale = NULL;
            }
            else if (! do_setlocale_c(LC_TIME, save_input_locale)) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                            "Could not change LC_TIME locale to %s\n",
                                                        save_input_locale));
                Safefree(save_time_locale);
                goto cant_use_time;
            }
        }

        /* Here the current LC_TIME is set to the locale of the category
         * whose information is desired.  Look at all the days of the week and
         * month names, and the timezone and am/pm indicator for UTF-8 variant
         * characters.  The first such a one found will tell us if the locale
         * is UTF-8 or not */

        for (i = 0; i < 7 + 12; i++) {  /* 7 days; 12 months */
            formatted_time = my_strftime("%A %B %Z %p",
                            0, 0, hour, dom, month, 2012 - 1900, 0, 0, is_dst);
            if ( ! formatted_time
                || is_utf8_invariant_string((U8 *) formatted_time, 0))
            {

                /* Here, we didn't find a non-ASCII.  Try the next time through
                 * with the complemented dst and am/pm, and try with the next
                 * weekday.  After we have gotten all weekdays, try the next
                 * month */
                is_dst = ! is_dst;
                hour = (hour + 12) % 24;
                dom++;
                if (i > 6) {
                    month++;
                }
                continue;
            }

            /* Here, we have a non-ASCII.  Return TRUE is it is valid UTF8;
             * false otherwise.  But first, restore LC_TIME to its original
             * locale if we changed it */
            if (save_time_locale) {
                do_setlocale_c(LC_TIME, save_time_locale);
                Safefree(save_time_locale);
            }

            DEBUG_L(PerlIO_printf(Perl_debug_log, "\t?time-related strings for %s are UTF-8=%d\n",
                                save_input_locale,
                                is_utf8_string((U8 *) formatted_time, 0)));
            Safefree(save_input_locale);
            return is_utf8_string((U8 *) formatted_time, 0);
        }

        /* Falling off the end of the loop indicates all the names were just
         * ASCII.  Go on to the next test.  If we changed it, restore LC_TIME
         * to its original locale */
        if (save_time_locale) {
            do_setlocale_c(LC_TIME, save_time_locale);
            Safefree(save_time_locale);
        }
        DEBUG_L(PerlIO_printf(Perl_debug_log, "All time-related words for %s contain only ASCII; can't use for determining if UTF-8 locale\n", save_input_locale));
    }
  cant_use_time:

#    endif

#    if 0 && defined(USE_LOCALE_MESSAGES) && defined(HAS_SYS_ERRLIST)

/* This code is ifdefd out because it was found to not be necessary in testing
 * on our dromedary test machine, which has over 700 locales.  There, this
 * added no value to looking at the currency symbol and the time strings.  I
 * left it in so as to avoid rewriting it if real-world experience indicates
 * that dromedary is an outlier.  Essentially, instead of returning abpve if we
 * haven't found illegal utf8, we continue on and examine all the strerror()
 * messages on the platform for utf8ness.  If all are ASCII, we still don't
 * know the answer; but otherwise we have a pretty good indication of the
 * utf8ness.  The reason this doesn't help much is that the messages may not
 * have been translated into the locale.  The currency symbol and time strings
 * are much more likely to have been translated.  */
    {
        int e;
        bool is_utf8 = FALSE;
        bool non_ascii = FALSE;
        char *save_messages_locale = NULL;
        const char * errmsg = NULL;

        /* Like above, we set LC_MESSAGES to the locale of the desired
         * category, if it isn't that locale already */

        if (category != LC_MESSAGES) {

            save_messages_locale = do_setlocale_c(LC_MESSAGES, NULL);
            if (! save_messages_locale) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                            "Could not find current locale for LC_MESSAGES\n"));
                goto cant_use_messages;
            }
            save_messages_locale = stdize_locale(savepv(save_messages_locale));

            if (strEQ(save_messages_locale, save_input_locale)) {
                Safefree(save_messages_locale);
                save_messages_locale = NULL;
            }
            else if (! do_setlocale_c(LC_MESSAGES, save_input_locale)) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                            "Could not change LC_MESSAGES locale to %s\n",
                                                        save_input_locale));
                Safefree(save_messages_locale);
                goto cant_use_messages;
            }
        }

        /* Here the current LC_MESSAGES is set to the locale of the category
         * whose information is desired.  Look through all the messages.  We
         * can't use Strerror() here because it may expand to code that
         * segfaults in miniperl */

        for (e = 0; e <= sys_nerr; e++) {
            errno = 0;
            errmsg = sys_errlist[e];
            if (errno || !errmsg) {
                break;
            }
            errmsg = savepv(errmsg);
            if (! is_utf8_invariant_string((U8 *) errmsg, 0)) {
                non_ascii = TRUE;
                is_utf8 = is_utf8_string((U8 *) errmsg, 0);
                break;
            }
        }
        Safefree(errmsg);

        /* And, if we changed it, restore LC_MESSAGES to its original locale */
        if (save_messages_locale) {
            do_setlocale_c(LC_MESSAGES, save_messages_locale);
            Safefree(save_messages_locale);
        }

        if (non_ascii) {

            /* Any non-UTF-8 message means not a UTF-8 locale; if all are valid,
             * any non-ascii means it is one; otherwise we assume it isn't */
            DEBUG_L(PerlIO_printf(Perl_debug_log, "\t?error messages for %s are UTF-8=%d\n",
                                save_input_locale,
                                is_utf8));
            Safefree(save_input_locale);
            return is_utf8;
        }

        DEBUG_L(PerlIO_printf(Perl_debug_log, "All error messages for %s contain only ASCII; can't use for determining if UTF-8 locale\n", save_input_locale));
    }
  cant_use_messages:

#    endif
#  endif /* the code that is compiled when no nl_langinfo */

#  ifndef EBCDIC  /* On os390, even if the name ends with "UTF-8', it isn't a
                   UTF-8 locale */

    /* As a last resort, look at the locale name to see if it matches
     * qr/UTF -?  * 8 /ix, or some other common locale names.  This "name", the
     * return of setlocale(), is actually defined to be opaque, so we can't
     * really rely on the absence of various substrings in the name to indicate
     * its UTF-8ness, but if it has UTF8 in the name, it is extremely likely to
     * be a UTF-8 locale.  Similarly for the other common names */

    final_pos = strlen(save_input_locale) - 1;
    if (final_pos >= 3) {
        char *name = save_input_locale;

        /* Find next 'U' or 'u' and look from there */
        while ((name += strcspn(name, "Uu") + 1)
                                            <= save_input_locale + final_pos - 2)
        {
            if (   isALPHA_FOLD_NE(*name, 't')
                || isALPHA_FOLD_NE(*(name + 1), 'f'))
            {
                continue;
            }
            name += 2;
            if (*(name) == '-') {
                if ((name > save_input_locale + final_pos - 1)) {
                    break;
                }
                name++;
            }
            if (*(name) == '8') {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                                      "Locale %s ends with UTF-8 in name\n",
                                      save_input_locale));
                Safefree(save_input_locale);
                return TRUE;
            }
        }
        DEBUG_L(PerlIO_printf(Perl_debug_log,
                              "Locale %s doesn't end with UTF-8 in name\n",
                                save_input_locale));
    }

#  endif
#  ifdef WIN32

    /* http://msdn.microsoft.com/en-us/library/windows/desktop/dd317756.aspx */
    if (memENDs(save_input_locale, final_pos, "65001")) {
        DEBUG_L(PerlIO_printf(Perl_debug_log,
                        "Locale %s ends with 65001 in name, is UTF-8 locale\n",
                        save_input_locale));
        Safefree(save_input_locale);
        return TRUE;
    }

#  endif

    /* Other common encodings are the ISO 8859 series, which aren't UTF-8.  But
     * since we are about to return FALSE anyway, there is no point in doing
     * this extra work */

#  if 0
    if (instr(save_input_locale, "8859")) {
        DEBUG_L(PerlIO_printf(Perl_debug_log,
                             "Locale %s has 8859 in name, not UTF-8 locale\n",
                             save_input_locale));
        Safefree(save_input_locale);
        return FALSE;
    }
#  endif

    DEBUG_L(PerlIO_printf(Perl_debug_log,
                          "Assuming locale %s is not a UTF-8 locale\n",
                                    save_input_locale));
    Safefree(save_input_locale);
    return FALSE;
}

#endif


bool
Perl__is_in_locale_category(pTHX_ const bool compiling, const int category)
{
    dVAR;
    /* Internal function which returns if we are in the scope of a pragma that
     * enables the locale category 'category'.  'compiling' should indicate if
     * this is during the compilation phase (TRUE) or not (FALSE). */

    const COP * const cop = (compiling) ? &PL_compiling : PL_curcop;

    SV *categories = cop_hints_fetch_pvs(cop, "locale", 0);
    if (! categories || categories == PLACEHOLDER) {
        return FALSE;
    }

    /* The pseudo-category 'not_characters' is -1, so just add 1 to each to get
     * a valid unsigned */
    assert(category >= -1);
    return cBOOL(SvUV(categories) & (1U << (category + 1)));
}

char *
Perl_my_strerror(pTHX_ const int errnum)
{
    /* Returns a mortalized copy of the text of the error message associated
     * with 'errnum'.  It uses the current locale's text unless the platform
     * doesn't have the LC_MESSAGES category or we are not being called from
     * within the scope of 'use locale'.  In the former case, it uses whatever
     * strerror returns; in the latter case it uses the text from the C locale.
     *
     * The function just calls strerror(), but temporarily switches, if needed,
     * to the C locale */

    char *errstr;
    dVAR;

#ifndef USE_LOCALE_MESSAGES

    /* If platform doesn't have messages category, we don't do any switching to
     * the C locale; we just use whatever strerror() returns */

    errstr = savepv(Strerror(errnum));

#else   /* Has locale messages */

    const bool within_locale_scope = IN_LC(LC_MESSAGES);

#  if defined(HAS_POSIX_2008_LOCALE) && defined(HAS_STRERROR_L)

    /* This function is trivial if we don't have to worry about thread safety
     * and have strerror_l(), as it handles the switch of locales so we don't
     * have to deal with that.  We don't have to worry about thread safety if
     * this is an unthreaded build, or if strerror_r() is also available.  Both
     * it and strerror_l() are thread-safe.  Plain strerror() isn't thread
     * safe.  But on threaded builds when strerror_r() is available, the
     * apparent call to strerror() below is actually a macro that
     * behind-the-scenes calls strerror_r().
     */

#    if ! defined(USE_ITHREADS) || defined(HAS_STRERROR_R)

    if (within_locale_scope) {
        errstr = savepv(strerror(errnum));
    }
    else {
        errstr = savepv(strerror_l(errnum, PL_C_locale_obj));
    }

#    else

    /* Here we have strerror_l(), but not strerror_r() and we are on a
     * threaded-build.  We use strerror_l() for everything, constructing a
     * locale to pass to it if necessary */

    bool do_free = FALSE;
    locale_t locale_to_use;

    if (within_locale_scope) {
        locale_to_use = uselocale((locale_t) 0);
        if (locale_to_use == LC_GLOBAL_LOCALE) {
            locale_to_use = duplocale(LC_GLOBAL_LOCALE);
            do_free = TRUE;
        }
    }
    else {  /* Use C locale if not within 'use locale' scope */
        locale_to_use = PL_C_locale_obj;
    }

    errstr = savepv(strerror_l(errnum, locale_to_use));

    if (do_free) {
        freelocale(locale_to_use);
    }

#    endif
#  else /* Doesn't have strerror_l() */

#    ifdef USE_POSIX_2008_LOCALE

    locale_t save_locale = NULL;

#    else

    char * save_locale = NULL;
    bool locale_is_C = FALSE;

    /* We have a critical section to prevent another thread from changing the
     * locale out from under us (or zapping the buffer returned from
     * setlocale() ) */
    LOCALE_LOCK;

#    endif

    DEBUG_Lv(PerlIO_printf(Perl_debug_log,
                            "my_strerror called with errnum %d\n", errnum));
    if (! within_locale_scope) {
        errno = 0;

#  ifdef USE_POSIX_2008_LOCALE /* Use the thread-safe locale functions */

        DEBUG_Lv(PerlIO_printf(Perl_debug_log,
                                    "Not within locale scope, about to call"
                                    " uselocale(0x%p)\n", PL_C_locale_obj));
        save_locale = uselocale(PL_C_locale_obj);
        if (! save_locale) {
            DEBUG_L(PerlIO_printf(Perl_debug_log,
                                    "uselocale failed, errno=%d\n", errno));
        }
        else {
            DEBUG_Lv(PerlIO_printf(Perl_debug_log,
                                    "uselocale returned 0x%p\n", save_locale));
        }

#    else    /* Not thread-safe build */

        save_locale = do_setlocale_c(LC_MESSAGES, NULL);
        if (! save_locale) {
            DEBUG_L(PerlIO_printf(Perl_debug_log,
                                  "setlocale failed, errno=%d\n", errno));
        }
        else {
            locale_is_C = isNAME_C_OR_POSIX(save_locale);

            /* Switch to the C locale if not already in it */
            if (! locale_is_C) {

                /* The setlocale() just below likely will zap 'save_locale', so
                 * create a copy.  */
                save_locale = savepv(save_locale);
                do_setlocale_c(LC_MESSAGES, "C");
            }
        }

#    endif

    }   /* end of ! within_locale_scope */
    else {
        DEBUG_Lv(PerlIO_printf(Perl_debug_log, "%s: %d: WITHIN locale scope\n",
                                               __FILE__, __LINE__));
    }

    DEBUG_Lv(PerlIO_printf(Perl_debug_log,
             "Any locale change has been done; about to call Strerror\n"));
    errstr = savepv(Strerror(errnum));

    if (! within_locale_scope) {
        errno = 0;

#    ifdef USE_POSIX_2008_LOCALE

        DEBUG_Lv(PerlIO_printf(Perl_debug_log,
                    "%s: %d: not within locale scope, restoring the locale\n",
                    __FILE__, __LINE__));
        if (save_locale) {
            UV thr_run = 0;
            /* Dont restore the global locale in threads on darwin */
#if defined(__APPLE__) && defined(USE_ITHREADS)
            if (save_locale == LC_GLOBAL_LOCALE) {
                SV** require = hv_fetchs(GvHVn(PL_incgv), "threads.pm", 0);
                if ( require && *require != UNDEF ) {
                    SV* thr;
                    UV tid;
                    dSP;
                    ENTER; PUSHMARK(SP);
                    EXTEND(SP, 1);
                    mPUSHp("threads", 7);
                    PUTBACK;
                    call_sv(MUTABLE_SV(get_cvs("threads::self",0)), G_SCALAR);
                    thr = *PL_stack_sp; /* avoid the local SP <-> global copying */
                    if (thr && thr != UNDEF) {
                        INCMARK;
                        call_sv(MUTABLE_SV(get_cvs("threads::tid",0)), G_SCALAR);
                        tid = SvIVx(*PL_stack_sp);
                    }
                    LEAVE;
                    if (tid) thr_run++;
                }
            }
#endif
            if (!thr_run && !uselocale(save_locale)) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                                      "uselocale restore failed, errno=%d\n", errno));
            }
        }
    }

#    else

        if (save_locale && ! locale_is_C) {
            if (! do_setlocale_c(LC_MESSAGES, save_locale)) {
                DEBUG_L(PerlIO_printf(Perl_debug_log,
                      "setlocale restore failed, errno=%d\n", errno));
            }
            Safefree(save_locale);
            save_locale = NULL;
        }
    }

    LOCALE_UNLOCK;

#    endif
#  endif /* End of doesn't have strerror_l */
#endif   /* End of does have locale messages */

#ifdef DEBUGGING

    if (DEBUG_Lv_TEST) {
        PerlIO_printf(Perl_debug_log, "Strerror returned; saving a copy: '");
        print_bytes_for_locale(errstr, errstr + strlen(errstr), 0);
        PerlIO_printf(Perl_debug_log, "'\n");
    }

#endif

    SAVEFREEPV(errstr);
    return errstr;
}

/*

=for apidoc sync_locale

Changing the program's locale should be avoided by XS code.  Nevertheless,
certain non-Perl libraries called from XS, such as C<Gtk> do so.  When this
happens, Perl needs to be told that the locale has changed.  Use this function
to do so, before returning to Perl.

=cut
*/

void
Perl_sync_locale(pTHX)
{
    char * newlocale;

#ifdef USE_LOCALE_CTYPE

    newlocale = do_setlocale_c(LC_CTYPE, NULL);
    DEBUG_Lv(PerlIO_printf(Perl_debug_log,
        "%s:%d: %s\n", __FILE__, __LINE__,
        setlocale_debug_string(LC_CTYPE, NULL, newlocale)));
    new_ctype(newlocale);

#endif /* USE_LOCALE_CTYPE */
#ifdef USE_LOCALE_COLLATE

    newlocale = do_setlocale_c(LC_COLLATE, NULL);
    DEBUG_Lv(PerlIO_printf(Perl_debug_log,
        "%s:%d: %s\n", __FILE__, __LINE__,
        setlocale_debug_string(LC_COLLATE, NULL, newlocale)));
    new_collate(newlocale);

#endif
#ifdef USE_LOCALE_NUMERIC

    newlocale = do_setlocale_c(LC_NUMERIC, NULL);
    DEBUG_Lv(PerlIO_printf(Perl_debug_log,
        "%s:%d: %s\n", __FILE__, __LINE__,
        setlocale_debug_string(LC_NUMERIC, NULL, newlocale)));
    new_numeric(newlocale);

#endif /* USE_LOCALE_NUMERIC */

}

#if defined(DEBUGGING) && defined(USE_LOCALE)

STATIC char *
S_setlocale_debug_string(const int category,        /* category number,
                                                           like LC_ALL */
                            const char* const locale,   /* locale name */

                            /* return value from setlocale() when attempting to
                             * set 'category' to 'locale' */
                            const char* const retval)
{
    /* Returns a pointer to a NUL-terminated string in static storage with
     * added text about the info passed in.  This is not thread safe and will
     * be overwritten by the next call, so this should be used just to
     * formulate a string to immediately print or savepv() on. */

    /* initialise to a non-null value to keep it out of BSS and so keep
     * -DPERL_GLOBAL_STRUCT_PRIVATE happy */
    static char ret[128] = "If you can read this, thank your buggy C"
                           " library strlcpy(), and change your hints file"
                           " to undef it";
    unsigned int i;

#  ifdef LC_ALL

    const unsigned int highest_index = LC_ALL_INDEX;

#  else

    const unsigned int highest_index = NOMINAL_LC_ALL_INDEX - 1;

#endif


    my_strlcpy(ret, "setlocale(", sizeof(ret));

    /* Look for category in our list, and if found, add its name */
    for (i = 0; i <= highest_index; i++) {
        if (category == categories[i]) {
            my_strlcat(ret, category_names[i], sizeof(ret));
            goto found_category;
        }
    }

    /* Unknown category to us */
    my_snprintf(ret, sizeof(ret), "%s? %d", ret, category);

  found_category:

    my_strlcat(ret, ", ", sizeof(ret));

    if (locale) {
        my_strlcat(ret, "\"", sizeof(ret));
        my_strlcat(ret, locale, sizeof(ret));
        my_strlcat(ret, "\"", sizeof(ret));
    }
    else {
        my_strlcat(ret, "NULL", sizeof(ret));
    }

    my_strlcat(ret, ") returned ", sizeof(ret));

    if (retval) {
        my_strlcat(ret, "\"", sizeof(ret));
        my_strlcat(ret, retval, sizeof(ret));
        my_strlcat(ret, "\"", sizeof(ret));
    }
    else {
        my_strlcat(ret, "NULL", sizeof(ret));
    }

    assert(strlen(ret) < sizeof(ret));

    return ret;
}

#endif


/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
