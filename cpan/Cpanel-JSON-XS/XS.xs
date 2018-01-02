#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_grok_number
#define NEED_grok_numeric_radix
#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"

#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <limits.h>
#include <float.h>

#if defined(__BORLANDC__) || defined(_MSC_VER)
# define snprintf _snprintf // C compilers have this in stdio.h
#endif

#if defined(_AIX) && (!defined(HAS_LONG_DOUBLE) || AIX_WORKAROUND)
#define HAVE_NO_POWL
#endif

/* Freebsd 10: It has powl, but it is too bad. strtold is good. RT #101265 */
#if defined(__FreeBSD__) && defined(__clang__) && defined(USE_LONG_DOUBLE)
#define HAVE_BAD_POWL
#endif

#if PERL_VERSION < 22 && defined(HAS_SETLOCALE)
#define NEED_NUMERIC_LOCALE_C
#endif

/* FIXME: still a refcount error */
#define HAVE_DECODE_BOM
#define UTF8BOM     "\357\273\277"      /* EF BB BF */
#define UTF16BOM    "\377\376"          /* FF FE or +UFEFF */
#define UTF16BOM_BE "\376\377"          /* FE FF */
#define UTF32BOM    "\377\376\000\000"  /* FF FE 00 00 or +UFEFF */
#define UTF32BOM_BE "\000\000\376\377"  /* 00 00 FE FF */

/* mingw with USE_LONG_DOUBLE (and implied USE_MINGW_ANSI_STDIO) do use the
   non-msvcrt inf/nan stringification in sprintf(). */
#if defined(WIN32) && !defined(__USE_MINGW_ANSI_STDIO) && !defined(USE_LONG_DOUBLE)
/* new ucrtd.dll runtime? We do not probe the runtime or variants in the Makefile.PL yet. */
#define STR_INF "inf"
#define STR_INF2 "inf.0"
#define STR_NAN "nan"
#define STR_QNAN "nan(ind)"
/* old standard msvcrt.dll */
#define STR_INF3 "1.#INF"
#define STR_INF4 "1.#INF.0"
#define STR_NAN2 "1.#IND"
#define STR_QNAN2 "1.#QNAN"
#define HAVE_QNAN
#elif defined(sun) || defined(__sun)
#define STR_INF "Infinity"
#define STR_NAN "NaN"
#elif defined(__hpux)
#define STR_INF "++"
#define STR_NAN "-?"
#define HAVE_NEG_NAN
#define STR_NEG_INF "---"
#define STR_NEG_NAN "?"
#else
#define STR_INF "inf"
#define STR_NAN "nan"
#endif

/* modfl() segfaults for -Duselongdouble && 64-bit mingw64 && mingw
   runtime version 4.0 [perl #125924] */
#if defined(USE_LONG_DOUBLE) && defined(__MINGW64__) \
    && __MINGW64_VERSION_MAJOR == 4 && __MINGW64_VERSION_MINOR == 0
#undef HAS_MODFL
#undef Perl_modf
#define Perl_modf(nv, ip) mingw_modfl(nv, ip)
long double
mingw_modfl(long double x, long double *ip)
{
    *ip = truncl(x);
    return (x == *ip ? copysignl(0.0L, x) : x - *ip);
}
#endif

#if defined(_AIX)
#define HAVE_QNAN
#undef STR_QNAN
#define STR_QNAN "NANQ"
#endif

/* some old perls do not have this, try to make it work, no */
/* guarantees, though. if it breaks, you get to keep the pieces. */
#ifndef UTF8_MAXBYTES
# define UTF8_MAXBYTES 13
#endif

/* 5.6: */
#ifndef IS_NUMBER_IN_UV
#define IS_NUMBER_IN_UV		      0x01 /* number within UV range (maybe not
					      int).  value returned in pointed-
					      to UV */
#define IS_NUMBER_GREATER_THAN_UV_MAX 0x02 /* pointed to UV undefined */
#define IS_NUMBER_NOT_INT	      0x04 /* saw . or E notation */
#define IS_NUMBER_NEG		      0x08 /* leading minus sign */
#define IS_NUMBER_INFINITY	      0x10 /* this is big */
#define IS_NUMBER_NAN                 0x20 /* this is not */
#endif
#ifndef UNI_DISPLAY_QQ
#define UNI_DISPLAY_ISPRINT	0x0001
#define UNI_DISPLAY_BACKSLASH	0x0002
#define UNI_DISPLAY_QQ		(UNI_DISPLAY_ISPRINT|UNI_DISPLAY_BACKSLASH)
#define UNI_DISPLAY_REGEX	(UNI_DISPLAY_ISPRINT|UNI_DISPLAY_BACKSLASH)
#endif
/* with 5.6 hek can only be non-utf8 */
#ifndef HeKUTF8
#define HeKUTF8(he) 0
#endif
#ifndef GV_NOADD_NOINIT
#define GV_NOADD_NOINIT 0
#endif
/* since 5.8.1 */
#ifndef SvIsCOW_shared_hash
#define SvIsCOW_shared_hash(pv) 0
#endif
/* 5.8.1 has a broken assert_not_ROK */
#if PERL_VERSION == 8 && PERL_SUBVERSION == 1
# undef assert_not_ROK
# if defined(__GNUC__) && !defined(PERL_GCC_BRACE_GROUPS_FORBIDDEN)
#  define assert_not_ROK(sv)	({assert(!SvROK(sv) || !SvRV(sv));}),
# else
#  define assert_not_ROK(sv)
# endif
#endif
/* compatibility with perl <5.14 */
#ifndef PERL_UNICODE_MAX
#define PERL_UNICODE_MAX 0x10FFFF
#endif
#ifndef HvNAMELEN_get
# define HvNAMELEN_get(hv) strlen (HvNAME (hv))
#endif
#ifndef HvNAMELEN
# define HvNAMELEN(hv) HvNAMELEN_get (hv)
#endif
#ifndef HvNAMEUTF8
# define HvNAMEUTF8(hv) 0
#endif
/* since 5.14 check use warnings 'nonchar' */
#ifdef WARN_NONCHAR
#define WARNER_NONCHAR(hi)                                      \
  Perl_ck_warner_d(aTHX_ packWARN(WARN_NONCHAR),                \
                   "Unicode non-character U+%04" UVXf " is not "  \
                   "recommended for open interchange", hi)
/* before check use warnings 'utf8' */
#elif PERL_VERSION > 10
#define WARNER_NONCHAR(hi)                                         \
  Perl_ck_warner_d(aTHX_ packWARN(WARN_UTF8),                      \
                   "Unicode non-character U+%04" UVXf " is illegal " \
                   "for interchange", hi)
#else
#define WARNER_NONCHAR(hi)                                         \
  Perl_warner(aTHX_ packWARN(WARN_UTF8),                           \
              "Unicode non-character U+%04lX is illegal", (unsigned long)hi)
#endif

/* since 5.16 */
#ifndef GV_NO_SVGMAGIC
#define GV_NO_SVGMAGIC 0
#endif
/* since 5.18 */
#ifndef SvREFCNT_dec_NN
#define SvREFCNT_dec_NN(sv) SvREFCNT_dec(sv)
#endif
/* from cperl */
#ifndef strEQc
/* the buffer ends with \0, includes comparison of the \0.
   better than strEQ as it uses memcmp, word-wise comparison. */
# define strEQc(s, c) memEQ(s, ("" c ""), sizeof(c))
#endif
#ifndef memEQc
/* excluding the final \0, so the string s may continue */
# define memEQc(s, c) memEQ(s, ("" c ""), sizeof(c)-1)
#endif

/* av_len has 2 different possible types */
#ifndef HVMAX_T
# if PERL_VERSION >= 20
#  define HVMAX_T SSize_t
# else
#  define HVMAX_T I32
# endif
#endif
/* and riter 3 */
#ifndef RITER_T
# ifdef USE_CPERL
#  if PERL_VERSION >= 25
#   define RITER_T U32
#  else
#   define RITER_T SSize_t
#  endif
# else
#   define RITER_T I32
# endif
#endif

/* three extra for rounding, sign, and end of string */
#define IVUV_MAXCHARS (sizeof (UV) * CHAR_BIT * 28 / 93 + 3)

#define F_ASCII           0x00000001UL
#define F_LATIN1          0x00000002UL
#define F_UTF8            0x00000004UL
#define F_INDENT          0x00000008UL
#define F_CANONICAL       0x00000010UL
#define F_SPACE_BEFORE    0x00000020UL
#define F_SPACE_AFTER     0x00000040UL
#define F_ALLOW_NONREF    0x00000100UL
#define F_SHRINK          0x00000200UL
#define F_ALLOW_BLESSED   0x00000400UL
#define F_CONV_BLESSED    0x00000800UL
#define F_RELAXED         0x00001000UL
#define F_ALLOW_UNKNOWN   0x00002000UL
#define F_ALLOW_TAGS      0x00004000UL
#define F_BINARY          0x00008000UL
#define F_ALLOW_BAREKEY   0x00010000UL
#define F_ALLOW_SQUOTE    0x00020000UL
#define F_ALLOW_BIGNUM    0x00040000UL
#define F_ESCAPE_SLASH    0x00080000UL
#define F_SORT_BY         0x00100000UL
#define F_ALLOW_STRINGIFY 0x00200000UL
#define F_HOOK            0x80000000UL // some hooks exist, so slow-path processing

#define F_PRETTY    F_INDENT | F_SPACE_BEFORE | F_SPACE_AFTER
#define SET_RELAXED (F_RELAXED | F_ALLOW_BAREKEY | F_ALLOW_SQUOTE)

#define INIT_SIZE   32 // initial scalar size to be allocated
#define INDENT_STEP 3  // spaces per indentation level

#define SHORT_STRING_LEN 16384 // special-case strings of up to this size

#define DECODE_WANTS_OCTETS(json) ((json)->flags & F_UTF8)

#define SB do {
#define SE } while (0)

#if __GNUC__ >= 3
# define _expect(expr,value)        __builtin_expect ((expr), (value))
# define INLINE                     static inline
#else
# define _expect(expr,value)        (expr)
# define INLINE                     static
#endif
#ifndef LIKELY
#define LIKELY(expr)   _expect ((long)(expr) != 0, 1)
#define UNLIKELY(expr) _expect ((long)(expr) != 0, 0)
#endif

#define IN_RANGE_INC(type,val,beg,end) \
  ((unsigned type)((unsigned type)(val) - (unsigned type)(beg)) \
  <= (unsigned type)((unsigned type)(end) - (unsigned type)(beg)))

#define ERR_NESTING_EXCEEDED "json text or perl structure exceeds maximum nesting level (max_depth set too low?)"

# define JSON_STASH MY_CXT.json_stash

#define MY_CXT_KEY "Cpanel::JSON::XS::_guts"

typedef struct {
  HV *json_stash;             /* Cpanel::JSON::XS:: */
  HV *json_boolean_stash;     /* JSON::PP::Boolean::  */
  HV *jsonold_boolean_stash;  /* JSON::XS::Boolean:: if empty will be (HV*)1 */
  HV *mojo_boolean_stash;     /* Mojo::JSON::_Bool:: if empty will be (HV*)1 */
  SV *json_true, *json_false;
  SV *sv_json;
} my_cxt_t;

// the amount of HEs to allocate on the stack, when sorting keys
#define STACK_HES 64

START_MY_CXT

INLINE SV * get_bool (pTHX_ const char *name);

enum {
  INCR_M_WS = 0, /* initial whitespace skipping, must be 0 */
  INCR_M_STR,    /* inside string */
  INCR_M_BS,     /* inside backslash */
  INCR_M_C0,     /* inside comment in initial whitespace sequence */
  INCR_M_C1,     /* inside comment in other places */
  INCR_M_JSON    /* outside anything, count nesting */
};

#define INCR_DONE(json) ((json)->incr_nest <= 0 && (json)->incr_mode == INCR_M_JSON)

typedef struct {
  U32 flags;
  U32 max_depth;
  STRLEN max_size;

  SV *cb_object;
  HV *cb_sk_object;
  SV *cb_sort_by;

  /* for the incremental parser */
  SV *incr_text;   /* the source text so far */
  STRLEN incr_pos; /* the current offset into the text */
  int incr_nest;   /* {[]}-nesting level */
  unsigned char incr_mode;
  unsigned char infnan_mode;
} JSON;

INLINE void
json_init (JSON *json)
{
  Zero (json, 1, JSON);
  json->max_depth = 512;
}

/* dTHX/threads TODO*/
/* END dtor call not needed, all of these *s refcnts are owned by the stash
  treem not C code */
static void
init_MY_CXT(pTHX_ my_cxt_t * cxt)
{
  cxt->json_stash            = gv_stashpvn ("Cpanel::JSON::XS",  sizeof("Cpanel::JSON::XS")-1, 1);
  cxt->json_boolean_stash    = gv_stashpvn ("JSON::PP::Boolean", sizeof("JSON::PP::Boolean")-1, 1);
  cxt->jsonold_boolean_stash = gv_stashpvn ("JSON::XS::Boolean", sizeof("JSON::XS::Boolean")-1, 0);
  cxt->mojo_boolean_stash    = gv_stashpvn ("Mojo::JSON::_Bool", sizeof("Mojo::JSON::_Bool")-1, 0);
  if ( !cxt->mojo_boolean_stash )
    cxt->mojo_boolean_stash = (HV*)1; /* invalid ptr to compare against, better than a NULL stash */
  if ( !cxt->jsonold_boolean_stash )
    cxt->jsonold_boolean_stash = (HV*)1;

  cxt->json_true  = get_bool (aTHX_ "Cpanel::JSON::XS::true");
  cxt->json_false = get_bool (aTHX_ "Cpanel::JSON::XS::false");

  cxt->sv_json = newSVpv ("JSON", 0);
  SvREADONLY_on (cxt->sv_json);
}


/*/////////////////////////////////////////////////////////////////////////// */
/* utility functions */

/* Unpacks the 2 boolean objects from the global references */
INLINE SV *
get_bool (pTHX_ const char *name)
{
  dMY_CXT;
#if PERL_VERSION > 7
  SV *sv = get_sv (name, 1);
#else
  SV *sv = GvSV(gv_fetchpv(name, 1, SVt_PV));
#endif
  SV* rv = SvRV(sv);
  if (!SvOBJECT(sv) || !SvSTASH(sv)) {
    SvREADONLY_off (sv);
    SvREADONLY_off (rv);
    (void)sv_bless(sv, MY_CXT.json_boolean_stash); /* bless the ref */
  }
  SvREADONLY_on (rv);
  SvREADONLY_on (sv);
  return sv;
}

INLINE void
shrink (pTHX_ SV *sv)
{
  /* ignore errors */
  (void)sv_utf8_downgrade (sv, 1);

  if (SvLEN (sv) > SvCUR (sv) + 1)
    {
#ifdef SvPV_shrink_to_cur
      SvPV_shrink_to_cur (sv);
#elif defined (SvPV_renew)
      SvPV_renew (sv, SvCUR (sv) + 1);
#endif
    }
}

/* decode an utf-8 character and return it, or (UV)-1 in */
/* case of an error. */
/* we special-case "safe" characters from U+80 .. U+7FF, */
/* but use the very good perl function to parse anything else. */
/* note that we never call this function for a ascii codepoints */
INLINE UV
decode_utf8 (pTHX_ unsigned char *s, STRLEN len, int relaxed, STRLEN *clen)
{
  if (LIKELY(len >= 2
             && IN_RANGE_INC (char, s[0], 0xc2, 0xdf)
             && IN_RANGE_INC (char, s[1], 0x80, 0xbf)))
    {
      *clen = 2;
      return ((s[0] & 0x1f) << 6) | (s[1] & 0x3f);
    }
  else {
/* Since perl 5.14 we can disallow illegal unicode above U+10FFFF.
   Before we could only warn with warnings 'utf8'.
   We accept only valid unicode, unless we are in the relaxed mode. */
#if PERL_VERSION > 12
    UV c = utf8n_to_uvuni (s, len, clen,
                           UTF8_CHECK_ONLY | (relaxed ? 0 : UTF8_DISALLOW_SUPER));
#elif PERL_VERSION >= 8
    UV c = utf8n_to_uvuni (s, len, clen, UTF8_CHECK_ONLY);
#endif
#if PERL_VERSION >= 8 && PERL_VERSION <= 12
    if (c > PERL_UNICODE_MAX && !relaxed)
      *clen = -1;
#endif
#if PERL_VERSION >= 8
    return c;
#else
    /* 5.6 does not detect certain ill-formed sequences, esp. overflows,
       which are security relevant. so we add code to detect these. */
    UV c = utf8_to_uv(s, len, clen, UTF8_CHECK_ONLY);
    if (!relaxed) {
      if (!c || c > PERL_UNICODE_MAX)
        *clen = -1;
      /* need to check manually for some overflows. 5.6 unicode bug */
      else if (len >= 2
               && IN_RANGE_INC (char, s[0], 0xc0, 0xfe)
               && !IN_RANGE_INC (char, s[0], 0xc2, 0xdf)) {
        U8 *s0, *send;
        UV uv = *s;
        UV expectlen = UTF8SKIP(s);

#define UTF_CONTINUATION_MASK           ((U8) ((1U << 6) - 1))
#define UTF_ACCUMULATION_OVERFLOW_MASK                          \
        (((UV) UTF_CONTINUATION_MASK) << ((sizeof(UV) * 8) - 6))

        s0 = s;
        /*printf ("maybe overlong <%.*s> %d/%d %x %x\n", len, s, c,
                  *clen, s[0], s[1]);*/
        if (*clen > 4) {
          *clen = -1;
          return c;
        }
        send = (U8*) s0 + ((expectlen <= len) ? len : len);
        for (s = s0 + 1; s < send; s++) {
          if (LIKELY(UTF8_IS_CONTINUATION(*s))) {
            if (uv & UTF_ACCUMULATION_OVERFLOW_MASK) {
              /*printf ("overflow\n");*/
              *clen = -1;
              return c;
	    }
	    uv = UTF8_ACCUMULATE(uv, *s);
          }
	  else {
            /*printf ("unexpected non continuation\n");*/
            *clen = -1;
            return c;
          }
	}
      }
    }
    return c;
#endif
  }
}

/* Likewise for encoding, also never called for ascii codepoints. */
/* This function takes advantage of this fact, although current gcc's */
/* seem to optimise the check for >= 0x80 away anyways. */
INLINE unsigned char *
encode_utf8 (unsigned char *s, UV ch)
{
  if    (UNLIKELY(ch < 0x000080))
    *s++ = ch;
  else if (LIKELY(ch < 0x000800))
    *s++ = 0xc0 | ( ch >>  6),
    *s++ = 0x80 | ( ch        & 0x3f);
  else if        (ch < 0x010000)
    *s++ = 0xe0 | ( ch >> 12),
    *s++ = 0x80 | ((ch >>  6) & 0x3f),
    *s++ = 0x80 | ( ch        & 0x3f);
  else if        (ch < 0x110000)
    *s++ = 0xf0 | ( ch >> 18),
    *s++ = 0x80 | ((ch >> 12) & 0x3f),
    *s++ = 0x80 | ((ch >>  6) & 0x3f),
    *s++ = 0x80 | ( ch        & 0x3f);

  return s;
}

/* convert offset to character index, sv must be string */
static STRLEN
ptr_to_index (pTHX_ SV *sv, const STRLEN offset)
{
  return SvUTF8 (sv)
    ? (STRLEN)utf8_distance ((U8*)(SvPVX(sv)+offset), (U8*)SvPVX (sv))
    : offset;
}

/*/////////////////////////////////////////////////////////////////////////// */
/* fp hell */

#ifdef HAVE_NO_POWL
/* Ulisse Monari: this is a patch for AIX 5.3, perl 5.8.8 without HAS_LONG_DOUBLE
  There Perl_pow maps to pow(...) - NOT TO powl(...), core dumps at Perl_pow(...)

  Base code is from http://bytes.com/topic/c/answers/748317-replacement-pow-function
  This is my change to fs_pow that goes into libc/libm for calling fmod/exp/log.
  NEED TO MODIFY Makefile, after perl Makefile.PL by adding "-lm" onto the LDDLFLAGS line */
static double fs_powEx(double x, double y)
{
    double p = 0;

    if (0 > x && fmod(y, 1) == 0) {
        if (fmod(y, 2) == 0) {
            p =  exp(log(-x) * y);
        } else {
            p = -exp(log(-x) * y);
        }
    } else {
        if (x != 0 || 0 >= y) {
            p =  exp(log( x) * y);
        }
    }
    return p;
}
#endif

/* scan a group of digits, and a trailing exponent */
static void
json_atof_scan1 (const char *s, NV *accum, int *expo, int postdp, int maxdepth)
{
  UV  uaccum = 0;
  int eaccum = 0;

#if defined(HAVE_BAD_POWL)
  *accum = strtold(s, NULL);
#else
  /* if we recurse too deep, skip all remaining digits */
  /* to avoid a stack overflow attack */
  if (UNLIKELY(--maxdepth <= 0))
    while (((U8)*s - '0') < 10)
      ++s;

  for (;;)
    {
      U8 dig = (U8)*s - '0';

      if (UNLIKELY(dig >= 10))
        {
          if (dig == (U8)((U8)'.' - (U8)'0'))
            {
              ++s;
              json_atof_scan1 (s, accum, expo, 1, maxdepth);
            }
          else if ((dig | ' ') == 'e' - '0')
            {
              int exp2 = 0;
              int neg  = 0;

              ++s;

              if (*s == '-')
                {
                  ++s;
                  neg = 1;
                }
              else if (*s == '+')
                ++s;

              while ((dig = (U8)*s - '0') < 10)
                exp2 = exp2 * 10 + *s++ - '0';

              *expo += neg ? -exp2 : exp2;
            }

          break;
        }

      ++s;

      uaccum = uaccum * 10 + dig;
      ++eaccum;

      /* if we have too many digits, then recurse for more */
      /* we actually do this for rather few digits */
      if (uaccum >= (UV_MAX - 9) / 10)
        {
          if (postdp) *expo -= eaccum;
          json_atof_scan1 (s, accum, expo, postdp, maxdepth);
          if (postdp) *expo += eaccum;

          break;
        }
    }

  /* this relies greatly on the quality of the pow () */
  /* implementation of the platform, but a good */
  /* implementation is hard to beat. */
  /* (IEEE 754 conformant ones are required to be exact) */
  if (postdp) *expo -= eaccum;
#ifdef HAVE_NO_POWL
  /* powf() unfortunately is not accurate enough */
  *accum += uaccum * fs_powEx(10., *expo );
#else
  *accum += uaccum * Perl_pow (10., *expo);
#endif
  *expo += eaccum;
#endif
}

static NV
json_atof (const char *s)
{
  NV accum = 0.;
  int expo = 0;
  int neg  = 0;

  if (*s == '-')
    {
      ++s;
      neg = 1;
    }

  /* a recursion depth of ten gives us >>500 bits */
  json_atof_scan1 (s, &accum, &expo, 0, 10);

  return neg ? -accum : accum;
}


/* target of scalar reference is bool?  -1 == nope, 0 == false, 1 == true */
static int
ref_bool_type (pTHX_ SV *sv)
{
  svtype svt = SvTYPE (sv);

  if (svt < SVt_PVAV)
    {
      STRLEN len = 0;
      char *pv = svt ? SvPV (sv, len) : 0;

      if (len == 1) {
        if (*pv == '1')
          return 1;
        else if (*pv == '0')
          return 0;
      }

    }

  return -1;
}

/* returns whether scalar is not a reference in the sense of allow_nonref */
static int
json_nonref (pTHX_ SV *scalar)
{
  if (!SvROK (scalar))
    return 1;

  scalar = SvRV (scalar);

  if (!SvOBJECT (scalar) && ref_bool_type (aTHX_ scalar) >= 0)
    return 1;

  if (SvOBJECT (scalar)) {
    dMY_CXT;
    HV *bstash   = MY_CXT.json_boolean_stash;
    HV *oldstash = MY_CXT.jsonold_boolean_stash;
    HV *mstash   = MY_CXT.mojo_boolean_stash;
    HV *stash    = SvSTASH (scalar);

    if (stash == bstash || stash == mstash || stash == oldstash)
      return 1;
  }
  
  return 0;
}

/*/////////////////////////////////////////////////////////////////////////// */
/* encoder */

/* structure used for encoding JSON */
typedef struct
{
  char *cur;  /* SvPVX (sv) + current output position */
  char *end;  /* SvEND (sv) */
  SV *sv;     /* result scalar */
  JSON json;
  U32 indent; /* indentation level */
  UV limit;   /* escape character values >= this value when encoding */
} enc_t;

INLINE void
need (pTHX_ enc_t *enc, STRLEN len)
{
#if PERL_VERSION > 6
  DEBUG_v(Perl_deb(aTHX_ "need enc: %p %p %4ld, want: %lu\n", enc->cur, enc->end,
                   (long)(enc->end - enc->cur), (unsigned long)len));
#endif
  assert(enc->cur <= enc->end);
  if (UNLIKELY(enc->cur + len >= enc->end))
    {
      STRLEN cur = enc->cur - (char *)SvPVX (enc->sv);
      SvGROW (enc->sv, cur + (len < (cur >> 2) ? cur >> 2 : len) + 1);
      enc->cur = SvPVX (enc->sv) + cur;
      enc->end = SvPVX (enc->sv) + SvLEN (enc->sv) - 1;
    }
}

INLINE void
encode_ch (pTHX_ enc_t *enc, char ch)
{
  need (aTHX_ enc, 1);
  *enc->cur++ = ch;
}

static void
encode_str (pTHX_ enc_t *enc, char *str, STRLEN len, int is_utf8)
{
  char *end = str + len;

#if PERL_VERSION < 8
  /* perl5.6 encodes to utf8 automatically, reverse it */
  if (is_utf8 && (enc->json.flags & F_BINARY))
    {
      str = (char *)utf8_to_bytes((U8*)str, &len);
      if (!str)
	croak ("illegal unicode character in binary string", str);
      end = str + len;
    }
#endif
  need (aTHX_ enc, len);

  while (str < end)
    {
      unsigned char ch = *(unsigned char *)str;
#if PERL_VERSION > 6
      DEBUG_v(Perl_deb(aTHX_ "str  enc: %p %p %4ld, want: %lu\n", enc->cur, enc->end,
                       (long)(enc->end - enc->cur), (long unsigned)len));
#endif
      if (LIKELY(ch >= 0x20 && ch < 0x80)) /* most common case */
        {
          assert(enc->cur <= enc->end);
          if (UNLIKELY(ch == '"')) /* but with slow exceptions */
            {
              need (aTHX_ enc, 2);
              *enc->cur++ = '\\';
              *enc->cur++ = '"';
              ++len;
            }
          else if (UNLIKELY(ch == '\\'))
            {
              need (aTHX_ enc, 2);
              *enc->cur++ = '\\';
              *enc->cur++ = '\\';
              ++len;
            }
          else if (UNLIKELY(ch == '/' && (enc->json.flags & F_ESCAPE_SLASH)))
            {
              need (aTHX_ enc, 2);
              *enc->cur++ = '\\';
              *enc->cur++ = '/';
              ++len;
            }
          else {
            need (aTHX_ enc, 1);
            *enc->cur++ = ch;
          }

          ++str;
        }
      else
        {
          assert(enc->cur <= enc->end);
          switch (ch)
            {
            case '\010': need (aTHX_ enc, 2);
              *enc->cur++ = '\\'; *enc->cur++ = 'b'; ++len; ++str; break;
            case '\011': need (aTHX_ enc, 2);
              *enc->cur++ = '\\'; *enc->cur++ = 't'; ++len; ++str; break;
            case '\012': need (aTHX_ enc, 2);
              *enc->cur++ = '\\'; *enc->cur++ = 'n'; ++len; ++str; break;
            case '\014': need (aTHX_ enc, 2);
              *enc->cur++ = '\\'; *enc->cur++ = 'f'; ++len; ++str; break;
            case '\015': need (aTHX_ enc, 2);
              *enc->cur++ = '\\'; *enc->cur++ = 'r'; ++len; ++str; break;

            default:
              {
                  STRLEN clen;
                  UV uch;

                  if (is_utf8 && !(enc->json.flags & F_BINARY))
                    {
                      uch = decode_utf8 (aTHX_ (unsigned char *)str, end - str,
                                         enc->json.flags & F_RELAXED, &clen);
                      if (clen == (STRLEN)-1)
                        croak ("malformed or illegal unicode character in string [%.11s], cannot convert to JSON", str);
                    }
                  else
                    {
                      uch = ch;
                      clen = 1;
                    }

                  if (uch < 0x80/*0x20*/ || uch >= enc->limit)
                    {
		      if (enc->json.flags & F_BINARY)
			{
                          /* MB cannot arrive here */
                          need (aTHX_ enc, 4);
                          *enc->cur++ = '\\';
                          *enc->cur++ = 'x';
                          *enc->cur++ = PL_hexdigit [(uch >>  4) & 15];
                          *enc->cur++ = PL_hexdigit [ uch & 15];
                          len += 3;
			}
                      else if (uch >= 0x10000UL)
                        {
                          if (uch >= 0x110000UL)
                            croak ("out of range codepoint (0x%lx) encountered, unrepresentable in JSON", (unsigned long)uch);

                          need (aTHX_ enc, 12);
                          sprintf (enc->cur, "\\u%04x\\u%04x",
                                   (int)((uch - 0x10000) / 0x400 + 0xD800),
                                   (int)((uch - 0x10000) % 0x400 + 0xDC00));
                          enc->cur += 12;
                          len += 11;
                        }
		      else
                        {
                          need (aTHX_ enc, 6);
                          *enc->cur++ = '\\';
                          *enc->cur++ = 'u';
                          *enc->cur++ = PL_hexdigit [ uch >> 12      ];
                          *enc->cur++ = PL_hexdigit [(uch >>  8) & 15];
                          *enc->cur++ = PL_hexdigit [(uch >>  4) & 15];
                          *enc->cur++ = PL_hexdigit [ uch & 15];
                          len += 5;
                        }

                      str += clen;
                    }
                  else if (enc->json.flags & F_LATIN1)
                    {
                      need (aTHX_ enc, 1);
                      *enc->cur++ = uch;
                      str += clen;
                    }
                  else if (enc->json.flags & F_BINARY)
                    {
                      need (aTHX_ enc, 1);
                      *enc->cur++ = uch;
                      str += clen;
                    }
                  else if (is_utf8)
                    {
                      need (aTHX_ enc, clen);
                      len += clen;
                      do
                        {
                          *enc->cur++ = *str++;
                        }
                      while (--clen);
                    }
                  else
                    { /* never more than 11 bytes needed */
                      need (aTHX_ enc, UTF8_MAXBYTES);
                      enc->cur = (char*)encode_utf8 ((U8*)enc->cur, uch);
                      ++str;
                      len += UTF8_MAXBYTES - 1;
                    }
                }
            }
        }

      --len;
    }
}

INLINE void
encode_const_str (pTHX_ enc_t *enc, const char *str, STRLEN len, int is_utf8)
{
  encode_str (aTHX_ enc, (char *)str, len, is_utf8);
}

INLINE void
encode_indent (pTHX_ enc_t *enc)
{
  if (enc->json.flags & F_INDENT)
    {
      int spaces = enc->indent * INDENT_STEP;

      need (aTHX_ enc, spaces);
      memset (enc->cur, ' ', spaces);
      enc->cur += spaces;
    }
}

INLINE void
encode_space (pTHX_ enc_t *enc)
{
  encode_ch (aTHX_ enc, ' ');
}

INLINE void
encode_nl (pTHX_ enc_t *enc)
{
  if (enc->json.flags & F_INDENT)
    {
      encode_ch (aTHX_ enc, '\n');
    }
}

INLINE void
encode_comma (pTHX_ enc_t *enc)
{
  encode_ch (aTHX_ enc, ',');

  if (enc->json.flags & F_INDENT)
    encode_nl (aTHX_ enc);
  else if (enc->json.flags & F_SPACE_AFTER)
    encode_space (aTHX_ enc);
}

static void encode_sv (pTHX_ enc_t *enc, SV *sv);

static void
encode_av (pTHX_ enc_t *enc, AV *av)
{
  HVMAX_T i, len = av_len (av);

  if (enc->indent >= enc->json.max_depth)
    croak (ERR_NESTING_EXCEEDED);

  encode_ch (aTHX_ enc, '[');
  
  if (len >= 0)
    {
      encode_nl (aTHX_ enc); ++enc->indent;

      for (i = 0; i <= len; ++i)
        {
          SV **svp = av_fetch (av, i, 0);

          encode_indent (aTHX_ enc);

          if (svp)
            encode_sv (aTHX_ enc, *svp);
          else
            encode_const_str (aTHX_ enc, "null", 4, 0);

          if (i < len)
            encode_comma (aTHX_ enc);
        }

      encode_nl (aTHX_ enc); --enc->indent; encode_indent (aTHX_ enc);
    }
  
  encode_ch (aTHX_ enc, ']');
}

static void
encode_hk (pTHX_ enc_t *enc, HE *he)
{
  encode_ch (aTHX_ enc, '"');

  if (HeKLEN (he) == HEf_SVKEY)
    {
      SV *sv = HeSVKEY (he);
      STRLEN len;
      char *str;
      
      SvGETMAGIC (sv);
      str = SvPV (sv, len);

      encode_str (aTHX_ enc, str, len, SvUTF8 (sv));
    }
  else
    encode_str (aTHX_ enc, HeKEY (he), (STRLEN)HeKLEN (he), HeKUTF8 (he));

  encode_ch (aTHX_ enc, '"');

  if (enc->json.flags & F_SPACE_BEFORE) encode_space (aTHX_ enc);
  encode_ch (aTHX_ enc, ':');
  if (enc->json.flags & F_SPACE_AFTER ) encode_space (aTHX_ enc);
}

/* compare hash entries, used when all keys are bytestrings */
static int
he_cmp_fast (const void *a_, const void *b_)
{
  int cmp;

  HE *a = *(HE **)a_;
  HE *b = *(HE **)b_;

  STRLEN la = HeKLEN (a);
  STRLEN lb = HeKLEN (b);

  if (!(cmp = memcmp (HeKEY (b), HeKEY (a), lb < la ? lb : la)))
    cmp = lb - la;

  return cmp;
}

/* compare hash entries, used when some keys are sv's or utf-x */
static int
he_cmp_slow (const void *a, const void *b)
{
  dTHX;
  return sv_cmp (HeSVKEY_force (*(HE **)b), HeSVKEY_force (*(HE **)a));
}

static void
encode_hv (pTHX_ enc_t *enc, HV *hv)
{
  HE *he;

  if (enc->indent >= enc->json.max_depth)
    croak (ERR_NESTING_EXCEEDED);

  encode_ch (aTHX_ enc, '{');

  /* for canonical output we have to sort by keys first */
  /* caused by randomised hash orderings */
  if (enc->json.flags & F_CANONICAL && !SvTIED_mg((SV*)hv, PERL_MAGIC_tied))
    {
      RITER_T i, count = hv_iterinit (hv);

      if (SvMAGICAL (hv))
        {
          /* need to count by iterating. could improve by dynamically building the vector below */
          /* but I don't care for the speed of this special case. */
          /* note also that we will run into undefined behaviour when the two iterations */
          /* do not result in the same count, something I might care for in some later release. */

          count = 0;
          while (hv_iternext (hv))
            ++count;

          hv_iterinit (hv);
        }

      if (count)
        {
          int fast = 1;
          HE *hes_stack [STACK_HES];
          HE **hes = hes_stack;

          // allocate larger arrays on the heap
          if (count > STACK_HES)
            {
              SV *sv = sv_2mortal (NEWSV (0, count * sizeof (*hes)));
              hes = (HE **)SvPVX (sv);
            }

          i = 0;
          while ((he = hv_iternext (hv)))
            {
              hes [i++] = he;
              if (HeKLEN (he) < 0 || HeKUTF8 (he))
                fast = 0;
            }

          assert (i == count);

          if (fast)
            qsort (hes, count, sizeof (HE *), he_cmp_fast);
          else
            {
              /* hack to forcefully disable "use bytes" */
              COP cop = *PL_curcop;
              cop.op_private = 0;

              ENTER;
              SAVETMPS;

              SAVEVPTR (PL_curcop);
              PL_curcop = &cop;

              qsort (hes, count, sizeof (HE *), he_cmp_slow);

              FREETMPS;
              LEAVE;
            }

          encode_nl (aTHX_ enc); ++enc->indent;

          while (count--)
            {
              encode_indent (aTHX_ enc);
              he = hes [count];
              encode_hk (aTHX_ enc, he);
              encode_sv (aTHX_ enc, UNLIKELY(SvMAGICAL (hv)) ? hv_iterval (hv, he) : HeVAL (he));

              if (count)
                encode_comma (aTHX_ enc);
            }

          encode_nl (aTHX_ enc); --enc->indent; encode_indent (aTHX_ enc);
        }
    }
  else
    {
      if (hv_iterinit (hv) || SvMAGICAL (hv))
        if ((he = hv_iternext (hv)))
          {
            encode_nl (aTHX_ enc); ++enc->indent;

            for (;;)
              {
                encode_indent (aTHX_ enc);
                encode_hk (aTHX_ enc, he);
                encode_sv (aTHX_ enc, UNLIKELY(SvMAGICAL (hv)) ? hv_iterval (hv, he) : HeVAL (he));

                if (!(he = hv_iternext (hv)))
                  break;

                encode_comma (aTHX_ enc);
              }

            encode_nl (aTHX_ enc); --enc->indent; encode_indent (aTHX_ enc);
          }
    }

  encode_ch (aTHX_ enc, '}');
}

/* implement convert_blessed, sv is already unref'ed here */
static void
encode_stringify(pTHX_ enc_t *enc, SV *sv, int isref)
{
  char *str = NULL;
  STRLEN len;
  SV *pv = NULL;
  svtype type = SvTYPE(sv);
#if PERL_VERSION <= 8
  MAGIC *mg;
#endif

/* SvAMAGIC without the ref */
#if PERL_VERSION > 17
#define MyAMG(sv) (SvOBJECT(sv) && HvAMAGIC(SvSTASH(sv)))
#else
#if PERL_VERSION > 8
#define MyAMG(sv) (SvOBJECT(sv) && (SvFLAGS(sv) & SVf_AMAGIC))
#else
#define MyAMG(sv) (SvOBJECT(sv) && ((SvFLAGS(sv) & SVf_AMAGIC) \
        || ((mg = mg_find((SV*)SvSTASH(sv), PERL_MAGIC_overload_table)) \
            && mg->mg_ptr && AMT_AMAGIC((AMT*)mg->mg_ptr))))
#endif
#endif

  if (isref && SvAMAGIC(sv))
    ;
  /* if no string overload found, check allow_stringify */
  else if (!MyAMG(sv) && !(enc->json.flags & F_ALLOW_STRINGIFY)) {
    if (isref && !(enc->json.flags & F_ALLOW_UNKNOWN))
      croak ("cannot encode reference to scalar '%s' unless the scalar is 0 or 1",
             SvPV_nolen (sv_2mortal (newRV_inc (sv))));
    encode_const_str (aTHX_ enc, "null", 4, 0);
    return;
  }
  /* sv_2pv_flags does not accept those types: */
  if (type != SVt_PVAV && type != SVt_PVHV && type != SVt_PVFM) {
    /* the essential of pp_stringify */
#if PERL_VERSION > 7
    pv = newSVpvs("");
    sv_copypv(pv, sv);
    SvSETMAGIC(pv);
    str = SvPVutf8_force(pv, len);
#else
    char *s;
    if (isref) {
      pv = AMG_CALLun(sv,string);
      len = SvCUR(pv);
      str = SvPVX(pv);
      SvREFCNT_inc(pv);
    }
    else {
      pv = newSVpvs("");
      s = SvPV(sv,len);
      sv_setpvn(pv,s,len);
      if (SvUTF8(sv))
	SvUTF8_on(pv);
      else
	SvUTF8_off(pv);
      SvSETMAGIC(pv);
      str = SvPVutf8_force(pv, len);
    }
#endif
    if (!len) {
      encode_const_str (aTHX_ enc, "null", 4, 0);
      SvREFCNT_dec(pv);
      return;
    }
  } else {
    /* manually call all possible magic on AV, HV, FM */
    if (SvGMAGICAL(sv)) mg_get(sv);
    if (MyAMG(sv)) { /* force a RV here */
      SV* rv = newRV(SvREFCNT_inc(sv));
#if PERL_VERSION <= 8
      HV *stash = SvSTASH(sv);
      if (!SvSTASH(rv) || !(SvFLAGS(sv) & SVf_AMAGIC)) {
        sv_bless(rv, stash);
        Gv_AMupdate(stash);
        SvFLAGS(sv) |= SVf_AMAGIC;
      }
#endif
#if PERL_VERSION > 13
      pv = AMG_CALLunary(rv, string_amg);
#else
      pv = AMG_CALLun(rv, string);
#endif
      TAINT_IF(pv && SvTAINTED(pv));
      if (pv && SvPOK(pv)) {
        str = SvPVutf8_force(pv, len);
        encode_ch (aTHX_ enc, '"');
        encode_str (aTHX_ enc, str, len, 0);
        encode_ch (aTHX_ enc, '"');
        SvREFCNT_dec(rv);
        return;
      }
      SvREFCNT_dec(rv);
    }
  }
  if (!str)
    encode_const_str (aTHX_ enc, "null", 4, 0);
  else {
    if (isref != 1)
      encode_ch (aTHX_ enc, '"');
    encode_str (aTHX_ enc, str, len, 0);
    if (isref != 1)
      encode_ch (aTHX_ enc, '"');
  }
  if (pv) SvREFCNT_dec(pv);

#undef MyAMG

}

/* encode objects, arrays and special \0=false and \1=true values
   and other representations of booleans: JSON::PP::Boolean, Mojo::JSON::_Bool
 */
static void
encode_rv (pTHX_ enc_t *enc, SV *rv)
{
  svtype svt;
  GV *method;
  SV *sv = SvRV(rv);

  SvGETMAGIC (sv);
  svt = SvTYPE (sv);

  if (UNLIKELY(SvOBJECT (sv)))
    {
      dMY_CXT;
      HV *bstash   = MY_CXT.json_boolean_stash; /* JSON-XS-3.x interop (Types::Serialiser/JSON::PP::Boolean) */
      HV *oldstash = MY_CXT.jsonold_boolean_stash; /* JSON-XS-2.x interop (JSON::XS::Boolean) */
      HV *mstash   = MY_CXT.mojo_boolean_stash; /* Mojo::JSON::_Bool interop */
      HV *stash    = SvSTASH (sv);

      if (stash == bstash || stash == mstash || stash == oldstash)
        {
          if (SvIV (sv))
            encode_const_str (aTHX_ enc, "true", 4, 0);
          else
            encode_const_str (aTHX_ enc, "false", 5, 0);
        }
      else if ((enc->json.flags & F_ALLOW_TAGS)
            && (method = gv_fetchmethod_autoload (stash, "FREEZE", 0)))
        {
          dMY_CXT;
          dSP;
          int count, items;

          ENTER; SAVETMPS; SAVESTACK_POS (); PUSHMARK (SP);
          EXTEND (SP, 2);
          PUSHs (rv);
          PUSHs (MY_CXT.sv_json);

          PUTBACK;
          count = call_sv ((SV *)GvCV (method), G_ARRAY);
          items = count;
          SPAGAIN;

          /* catch this surprisingly common error */
          if (SvROK (TOPs) && SvRV (TOPs) == sv)
            croak ("%s::FREEZE method returned same object as was passed instead of a new one",
                   HvNAME (SvSTASH (sv)));

          encode_ch (aTHX_ enc, '(');
          encode_ch (aTHX_ enc, '"');
          encode_str (aTHX_ enc, HvNAME (stash), HvNAMELEN (stash), HvNAMEUTF8 (stash));
          encode_ch (aTHX_ enc, '"');
          encode_ch (aTHX_ enc, ')');
          encode_ch (aTHX_ enc, '[');

          while (count)
            {
              encode_sv (aTHX_ enc, SP[1 - count--]);
              SPAGAIN;

              if (count)
                encode_ch (aTHX_ enc, ',');
            }

          encode_ch (aTHX_ enc, ']');

          SP -= items;
          PUTBACK;

          FREETMPS; LEAVE;
        }
      else if ((enc->json.flags & F_CONV_BLESSED)
            && (method = gv_fetchmethod_autoload (stash, "TO_JSON", 0)))
        {
          dSP;

          ENTER; SAVETMPS; PUSHMARK (SP);

          XPUSHs (rv);

          /* calling with G_SCALAR ensures that we always get a 1 return value */
          PUTBACK;
          call_sv ((SV *)GvCV (method), G_SCALAR);
          SPAGAIN;
          
          /* catch this surprisingly common error */
          if (SvROK (TOPs) && SvRV (TOPs) == sv)
            croak ("%s::TO_JSON method returned same object as was passed instead of a new one", HvNAME (SvSTASH (sv)));

          sv = POPs;
          PUTBACK;

          encode_sv (aTHX_ enc, sv);

          FREETMPS; LEAVE;
        }
      else if ((enc->json.flags & F_ALLOW_BIGNUM)
               && stash
               && ((stash == gv_stashpvn ("Math::BigInt", sizeof("Math::BigInt")-1, 0))
                || (stash == gv_stashpvn ("Math::BigFloat", sizeof("Math::BigFloat")-1, 0))))
        encode_stringify(aTHX_ enc, rv, 1);
      else if (enc->json.flags & F_CONV_BLESSED)
        encode_stringify(aTHX_ enc, sv, 0);
      else if (enc->json.flags & F_ALLOW_BLESSED)
        encode_const_str (aTHX_ enc, "null", 4, 0);
      else
        croak ("encountered object '%s', but neither allow_blessed, convert_blessed nor allow_tags settings are enabled (or TO_JSON/FREEZE method missing)",
               SvPV_nolen (sv_2mortal (newRV_inc (sv))));
    }
  else if (svt == SVt_PVHV)
    encode_hv (aTHX_ enc, (HV *)sv);
  else if (svt == SVt_PVAV)
    encode_av (aTHX_ enc, (AV *)sv);
  else if (svt < SVt_PVAV && svt != SVt_PVGV)
    {
      int bool_type = ref_bool_type (aTHX_ sv);

      if (bool_type == 1)
        encode_const_str (aTHX_ enc, "true", 4, 0);
      else if (bool_type == 0)
        encode_const_str (aTHX_ enc, "false", 5, 0);
      else if (enc->json.flags & F_ALLOW_STRINGIFY)
        encode_stringify(aTHX_ enc, sv, SvROK(sv));
      else if (enc->json.flags & F_ALLOW_UNKNOWN)
        encode_const_str (aTHX_ enc, "null", 4, 0);
      else
        croak ("cannot encode reference to scalar '%s' unless the scalar is 0 or 1",
               SvPV_nolen (sv_2mortal (newRV_inc (sv))));
    }
  else if (enc->json.flags & F_ALLOW_UNKNOWN)
    encode_const_str (aTHX_ enc, "null", 4, 0);
  else
    croak ("encountered %s, but JSON can only represent references to arrays or hashes",
           SvPV_nolen (sv_2mortal (newRV_inc (sv))));
}

static void
encode_sv (pTHX_ enc_t *enc, SV *sv)
{
  SvGETMAGIC (sv);

  if (UNLIKELY(sv == &PL_sv_yes ))
    {
      encode_const_str (aTHX_ enc, "true", 4, 0);
    }
  else if (UNLIKELY(sv == &PL_sv_no ))
    {
      encode_const_str (aTHX_ enc, "false", 5, 0);
    }
  else if (SvNOKp (sv))
    {
      char *savecur, *saveend;
      char inf_or_nan = 0;
#ifdef NEED_NUMERIC_LOCALE_C
      char *locale = NULL;
#endif
      NV nv = SvNVX(sv);
      /* trust that perl will do the right thing w.r.t. JSON syntax. */
      need (aTHX_ enc, NV_DIG + 32);
      savecur = enc->cur;
      saveend = enc->end;

#if defined(HAVE_ISINF) && defined(HAVE_ISNAN)
      /* With no stringify_infnan we can skip the conversion, returning null. */
      if (enc->json.infnan_mode == 0) {
# if defined(USE_QUADMATH) && defined(HAVE_ISINFL) && defined(HAVE_ISNANL)
        if (UNLIKELY(isinfl(nv) || isnanl(nv)))
# else
        if (UNLIKELY(isinf(nv) || isnan(nv)))
# endif
        {
          goto is_inf_or_nan;
        }
      }
#endif
      /* locale insensitive sprintf radix #96 */
#ifdef NEED_NUMERIC_LOCALE_C
      locale = setlocale(LC_NUMERIC, NULL);
      if (!locale || strNE(locale, "C")) {
        setlocale(LC_NUMERIC, "C");
      }
#endif
#ifdef USE_QUADMATH
      quadmath_snprintf(enc->cur, enc->end - enc->cur, "%.*Qg", (int)NV_DIG, nv);
#else
      (void)Gconvert (nv, NV_DIG, 0, enc->cur);
#endif
#ifdef NEED_NUMERIC_LOCALE_C
      if (locale)
        setlocale(LC_NUMERIC, locale);
#endif

#ifdef STR_INF4
      if (UNLIKELY(strEQc(enc->cur, STR_INF)
                   || strEQc(enc->cur, STR_INF2)
                   || strEQc(enc->cur, STR_INF3)
                   || strEQc(enc->cur, STR_INF4)))
#elif defined(STR_INF2)
      if (UNLIKELY(strEQc(enc->cur, STR_INF)
                   || strEQc(enc->cur, STR_INF2)))
#else
      if (UNLIKELY(strEQc(enc->cur, STR_INF)))
#endif
        inf_or_nan = 1;
#if defined(__hpux)
      else if (UNLIKELY(strEQc(enc->cur, STR_NEG_INF)))
        inf_or_nan = 2;
      else if (UNLIKELY(strEQc(enc->cur, STR_NEG_NAN)))
        inf_or_nan = 3;
#endif
      else if
#ifdef HAVE_QNAN
# ifdef STR_QNAN2
        (UNLIKELY(strEQc(enc->cur, STR_NAN)
                  || strEQc(enc->cur, STR_QNAN)
                  || strEQc(enc->cur, STR_NAN2)
                  || strEQc(enc->cur, STR_QNAN2)))
# else
        (UNLIKELY(strEQc(enc->cur, STR_NAN)
                  || strEQc(enc->cur, STR_QNAN)))
# endif
#else
        (UNLIKELY(strEQc(enc->cur, STR_NAN)))
#endif
        inf_or_nan = 3;
      else if (*enc->cur == '-') {
#ifdef STR_INF4
        if (UNLIKELY(strEQc(enc->cur+1, STR_INF)
                     || strEQc(enc->cur+1, STR_INF2)
                     || strEQc(enc->cur+1, STR_INF3)
                     || strEQc(enc->cur+1, STR_INF4)))
#elif defined(STR_INF2)
        if (UNLIKELY(strEQc(enc->cur+1, STR_INF)
                   || strEQc(enc->cur+1, STR_INF2)))
#else
        if (UNLIKELY(strEQc(enc->cur+1, STR_INF)))
#endif
          inf_or_nan = 2;
        else if
#ifdef HAVE_QNAN
# ifdef STR_QNAN2
          (UNLIKELY(strEQc(enc->cur+1, STR_NAN)
                    || strEQc(enc->cur+1, STR_QNAN)
                    || strEQc(enc->cur+1, STR_NAN2)
                    || strEQc(enc->cur+1, STR_QNAN2)))
# else
          (UNLIKELY(strEQc(enc->cur+1, STR_NAN)
                    || strEQc(enc->cur+1, STR_QNAN)))
# endif
#else
          (UNLIKELY(strEQc(enc->cur+1, STR_NAN)))
#endif
            inf_or_nan = 3;
      }
      if (UNLIKELY(inf_or_nan)) {
#if defined(HAVE_ISINF) && defined(HAVE_ISNAN)
      is_inf_or_nan:
#endif
        if (enc->json.infnan_mode == 0) {
          strncpy(enc->cur, "null\0", 5);
        }
        else if (enc->json.infnan_mode == 1) {
          const int l = strlen(enc->cur);
          memmove(enc->cur+1, enc->cur, l);
          *enc->cur = '"';
          *(enc->cur + l+1) = '"';
          *(enc->cur + l+2) = 0;
        }
        else if (enc->json.infnan_mode == 3) {
          if (inf_or_nan == 1)
            strncpy(enc->cur, "\"inf\"\0", 6);
          else if (inf_or_nan == 2)
            strncpy(enc->cur, "\"-inf\"\0", 7);
          else if (inf_or_nan == 3)
            strncpy(enc->cur, "\"nan\"\0", 6);
        }
        else if (enc->json.infnan_mode != 2) {
          croak ("invalid stringify_infnan mode %c. Must be 0, 1, 2 or 3",
                 enc->json.infnan_mode);
        }
      }
      if (SvPOKp (sv) && !strEQ(enc->cur, SvPVX (sv))) {
        STRLEN len;
        char *str = SvPV (sv, len);
        enc->cur = savecur;
        enc->end = saveend;
        encode_ch (aTHX_ enc, '"');
        encode_str (aTHX_ enc, str, len, SvUTF8 (sv));
        encode_ch (aTHX_ enc, '"');
        *enc->cur = 0;
      }
      else {
        NV intpart;
        if (!( inf_or_nan || Perl_modf(SvNVX(sv), &intpart) || SvIOK(sv)
            || strchr(enc->cur,'e') || strchr(enc->cur,'E')
#if PERL_VERSION < 10
               /* !!1 with 5.8 */
               || (SvPOKp(sv) && strEQc(SvPVX(sv), "1")
                   && SvNVX(sv) == 1.0) /* yes */
#endif
               ) )
          {
            char *tempend = enc->cur + strlen(enc->cur);
            strncpy(tempend, ".0\0", 3);
        }
        enc->cur += strlen (enc->cur);
      }
    }
  else if (SvIOKp (sv))
    {
      char *savecur, *saveend;
      /* we assume we can always read an IV as a UV and vice versa */
      /* we assume two's complement */
      /* we assume no aliasing issues in the union */
      if (SvIsUV (sv) ? SvUVX (sv) <= 59000
                      : SvIVX (sv) <= 59000 && SvIVX (sv) >= -59000)
        {
          /* optimise the "small number case" */
          /* code will likely be branchless and use only a single multiplication */
          /* works for numbers up to 59074 */
          I32 i = (I32)SvIVX (sv);
          U32 u;
          char digit, nz = 0;

          need (aTHX_ enc, 6);
          savecur = enc->cur;
          saveend = enc->end;

          *enc->cur = '-'; enc->cur += i < 0 ? 1 : 0;
          u = i < 0 ? -i : i;

          /* convert to 4.28 fixed-point representation */
          u = u * ((0xfffffff + 10000) / 10000); /* 10**5, 5 fractional digits */

          /* now output digit by digit, each time masking out the integer part */
          /* and multiplying by 5 while moving the decimal point one to the right, */
          /* resulting in a net multiplication by 10. */
          /* we always write the digit to memory but conditionally increment */
          /* the pointer, to enable the use of conditional move instructions. */
          digit = u >> 28; *enc->cur = digit + '0'; enc->cur += (nz = nz || digit); u = (u & 0xfffffffUL) * 5;
          digit = u >> 27; *enc->cur = digit + '0'; enc->cur += (nz = nz || digit); u = (u & 0x7ffffffUL) * 5;
          digit = u >> 26; *enc->cur = digit + '0'; enc->cur += (nz = nz || digit); u = (u & 0x3ffffffUL) * 5;
          digit = u >> 25; *enc->cur = digit + '0'; enc->cur += (nz = nz || digit); u = (u & 0x1ffffffUL) * 5;
          digit = u >> 24; *enc->cur = digit + '0'; enc->cur += 1; /* correctly generate '0' */
          *enc->cur = 0;
        }
      else
        {
          /* large integer, use the (rather slow) snprintf way. */
          need (aTHX_ enc, IVUV_MAXCHARS);
          savecur = enc->cur;
          saveend = enc->end;
          enc->cur +=
             SvIsUV(sv)
                ? snprintf (enc->cur, IVUV_MAXCHARS, "%" UVuf, (UV)SvUVX (sv))
                : snprintf (enc->cur, IVUV_MAXCHARS, "%" IVdf, (IV)SvIVX (sv));
        }

      if (SvPOKp (sv) && !strEQ(savecur, SvPVX (sv))) {
        STRLEN len;
        char *str = SvPV (sv, len);
        enc->cur = savecur;
        enc->end = saveend;
        encode_ch (aTHX_ enc, '"');
        encode_str (aTHX_ enc, str, len, SvUTF8 (sv));
        encode_ch (aTHX_ enc, '"');
        *enc->cur = 0;
      }
    }
  else if (SvPOKp (sv))
    {
      STRLEN len;
      char *str = SvPV (sv, len);
      encode_ch (aTHX_ enc, '"');
      encode_str (aTHX_ enc, str, len, SvUTF8 (sv));
      encode_ch (aTHX_ enc, '"');
    }
  else if (SvROK (sv))
    encode_rv (aTHX_ enc, sv);
  else if (!SvOK (sv) || enc->json.flags & F_ALLOW_UNKNOWN)
    encode_const_str (aTHX_ enc, "null", 4, 0);
  else
    croak ("encountered perl type (%s,0x%x) that JSON cannot handle, check your input data",
           SvPV_nolen (sv), (unsigned int)SvFLAGS (sv));
}

static SV *
encode_json (pTHX_ SV *scalar, JSON *json)
{
  enc_t enc;

  if (!(json->flags & F_ALLOW_NONREF) && json_nonref (aTHX_ scalar))
    croak ("hash- or arrayref expected (not a simple scalar, use allow_nonref to allow this)");

  enc.json      = *json;
  enc.sv        = sv_2mortal (NEWSV (0, INIT_SIZE));
  enc.cur       = SvPVX (enc.sv);
  enc.end       = SvEND (enc.sv);
  enc.indent    = 0;
  enc.limit     = enc.json.flags & F_ASCII  ? 0x000080UL
                : enc.json.flags & F_BINARY ? 0x000080UL
                : enc.json.flags & F_LATIN1 ? 0x000100UL
                                            : 0x110000UL;

  SvPOK_only (enc.sv);
  encode_sv (aTHX_ &enc, scalar);
  encode_nl (aTHX_ &enc);

  SvCUR_set (enc.sv, enc.cur - SvPVX (enc.sv));
  *SvEND (enc.sv) = 0; /* many xs functions expect a trailing 0 for text strings */

  if (!(enc.json.flags & (F_ASCII | F_LATIN1 | F_BINARY | F_UTF8)))
    SvUTF8_on (enc.sv);

  if (enc.json.flags & F_SHRINK)
    shrink (aTHX_ enc.sv);

  return enc.sv;
}

/*/////////////////////////////////////////////////////////////////////////// */
/* decoder */

/* structure used for decoding JSON */
typedef struct
{
  char *cur; /* current parser pointer */
  char *end; /* end of input string */
  const char *err; /* parse error, if != 0 */
  JSON json;
  U32 depth; /* recursion depth */
  U32 maxdepth; /* recursion depth limit */
} dec_t;

INLINE void
decode_comment (dec_t *dec)
{
  /* only '#'-style comments allowed a.t.m. */

  while (*dec->cur && *dec->cur != 0x0a && *dec->cur != 0x0d)
    ++dec->cur;
}

INLINE void
decode_ws (dec_t *dec)
{
  for (;;)
    {
      char ch = *dec->cur;

      if (ch > 0x20)
        {
          if (UNLIKELY(ch == '#'))
            {
              if (dec->json.flags & F_RELAXED)
                decode_comment (dec);
              else
                break;
            }
          else
            break;
        }
      else if (ch != 0x20 && ch != 0x0a && ch != 0x0d && ch != 0x09)
        break; /* parse error, but let higher level handle it, gives better error messages */

      ++dec->cur;
    }
}

#define ERR(reason) SB dec->err = reason; goto fail; SE

#define EXPECT_CH(ch) SB \
  if (*dec->cur != ch)		\
    ERR (# ch " expected");	\
  ++dec->cur;			\
  SE

#define DEC_INC_DEPTH if (++dec->depth > dec->json.max_depth) ERR (ERR_NESTING_EXCEEDED)
#define DEC_DEC_DEPTH --dec->depth

static SV *decode_sv (pTHX_ dec_t *dec);

/* #regen code
 my $i;
for ($i = 0; $i < 256; ++$i){
print
"    $i >= '0' && $i <= '9' ? $i - '0' : $i >= 'a' && $i <= 'f' ? $i - 'a' + 10
    : $i >= 'A' && $i <= 'F' ? $i - 'A' + 10 : -1 ,
";
}
*/
static const signed char decode_hexdigit[256] = {
    0 >= '0' && 0 <= '9' ? 0 - '0' : 0 >= 'a' && 0 <= 'f' ? 0 - 'a' + 10
    : 0 >= 'A' && 0 <= 'F' ? 0 - 'A' + 10 : -1 ,
    1 >= '0' && 1 <= '9' ? 1 - '0' : 1 >= 'a' && 1 <= 'f' ? 1 - 'a' + 10
    : 1 >= 'A' && 1 <= 'F' ? 1 - 'A' + 10 : -1 ,
    2 >= '0' && 2 <= '9' ? 2 - '0' : 2 >= 'a' && 2 <= 'f' ? 2 - 'a' + 10
    : 2 >= 'A' && 2 <= 'F' ? 2 - 'A' + 10 : -1 ,
    3 >= '0' && 3 <= '9' ? 3 - '0' : 3 >= 'a' && 3 <= 'f' ? 3 - 'a' + 10
    : 3 >= 'A' && 3 <= 'F' ? 3 - 'A' + 10 : -1 ,
    4 >= '0' && 4 <= '9' ? 4 - '0' : 4 >= 'a' && 4 <= 'f' ? 4 - 'a' + 10
    : 4 >= 'A' && 4 <= 'F' ? 4 - 'A' + 10 : -1 ,
    5 >= '0' && 5 <= '9' ? 5 - '0' : 5 >= 'a' && 5 <= 'f' ? 5 - 'a' + 10
    : 5 >= 'A' && 5 <= 'F' ? 5 - 'A' + 10 : -1 ,
    6 >= '0' && 6 <= '9' ? 6 - '0' : 6 >= 'a' && 6 <= 'f' ? 6 - 'a' + 10
    : 6 >= 'A' && 6 <= 'F' ? 6 - 'A' + 10 : -1 ,
    7 >= '0' && 7 <= '9' ? 7 - '0' : 7 >= 'a' && 7 <= 'f' ? 7 - 'a' + 10
    : 7 >= 'A' && 7 <= 'F' ? 7 - 'A' + 10 : -1 ,
    8 >= '0' && 8 <= '9' ? 8 - '0' : 8 >= 'a' && 8 <= 'f' ? 8 - 'a' + 10
    : 8 >= 'A' && 8 <= 'F' ? 8 - 'A' + 10 : -1 ,
    9 >= '0' && 9 <= '9' ? 9 - '0' : 9 >= 'a' && 9 <= 'f' ? 9 - 'a' + 10
    : 9 >= 'A' && 9 <= 'F' ? 9 - 'A' + 10 : -1 ,
    10 >= '0' && 10 <= '9' ? 10 - '0' : 10 >= 'a' && 10 <= 'f' ? 10 - 'a' + 10
    : 10 >= 'A' && 10 <= 'F' ? 10 - 'A' + 10 : -1 ,
    11 >= '0' && 11 <= '9' ? 11 - '0' : 11 >= 'a' && 11 <= 'f' ? 11 - 'a' + 10
    : 11 >= 'A' && 11 <= 'F' ? 11 - 'A' + 10 : -1 ,
    12 >= '0' && 12 <= '9' ? 12 - '0' : 12 >= 'a' && 12 <= 'f' ? 12 - 'a' + 10
    : 12 >= 'A' && 12 <= 'F' ? 12 - 'A' + 10 : -1 ,
    13 >= '0' && 13 <= '9' ? 13 - '0' : 13 >= 'a' && 13 <= 'f' ? 13 - 'a' + 10
    : 13 >= 'A' && 13 <= 'F' ? 13 - 'A' + 10 : -1 ,
    14 >= '0' && 14 <= '9' ? 14 - '0' : 14 >= 'a' && 14 <= 'f' ? 14 - 'a' + 10
    : 14 >= 'A' && 14 <= 'F' ? 14 - 'A' + 10 : -1 ,
    15 >= '0' && 15 <= '9' ? 15 - '0' : 15 >= 'a' && 15 <= 'f' ? 15 - 'a' + 10
    : 15 >= 'A' && 15 <= 'F' ? 15 - 'A' + 10 : -1 ,
    16 >= '0' && 16 <= '9' ? 16 - '0' : 16 >= 'a' && 16 <= 'f' ? 16 - 'a' + 10
    : 16 >= 'A' && 16 <= 'F' ? 16 - 'A' + 10 : -1 ,
    17 >= '0' && 17 <= '9' ? 17 - '0' : 17 >= 'a' && 17 <= 'f' ? 17 - 'a' + 10
    : 17 >= 'A' && 17 <= 'F' ? 17 - 'A' + 10 : -1 ,
    18 >= '0' && 18 <= '9' ? 18 - '0' : 18 >= 'a' && 18 <= 'f' ? 18 - 'a' + 10
    : 18 >= 'A' && 18 <= 'F' ? 18 - 'A' + 10 : -1 ,
    19 >= '0' && 19 <= '9' ? 19 - '0' : 19 >= 'a' && 19 <= 'f' ? 19 - 'a' + 10
    : 19 >= 'A' && 19 <= 'F' ? 19 - 'A' + 10 : -1 ,
    20 >= '0' && 20 <= '9' ? 20 - '0' : 20 >= 'a' && 20 <= 'f' ? 20 - 'a' + 10
    : 20 >= 'A' && 20 <= 'F' ? 20 - 'A' + 10 : -1 ,
    21 >= '0' && 21 <= '9' ? 21 - '0' : 21 >= 'a' && 21 <= 'f' ? 21 - 'a' + 10
    : 21 >= 'A' && 21 <= 'F' ? 21 - 'A' + 10 : -1 ,
    22 >= '0' && 22 <= '9' ? 22 - '0' : 22 >= 'a' && 22 <= 'f' ? 22 - 'a' + 10
    : 22 >= 'A' && 22 <= 'F' ? 22 - 'A' + 10 : -1 ,
    23 >= '0' && 23 <= '9' ? 23 - '0' : 23 >= 'a' && 23 <= 'f' ? 23 - 'a' + 10
    : 23 >= 'A' && 23 <= 'F' ? 23 - 'A' + 10 : -1 ,
    24 >= '0' && 24 <= '9' ? 24 - '0' : 24 >= 'a' && 24 <= 'f' ? 24 - 'a' + 10
    : 24 >= 'A' && 24 <= 'F' ? 24 - 'A' + 10 : -1 ,
    25 >= '0' && 25 <= '9' ? 25 - '0' : 25 >= 'a' && 25 <= 'f' ? 25 - 'a' + 10
    : 25 >= 'A' && 25 <= 'F' ? 25 - 'A' + 10 : -1 ,
    26 >= '0' && 26 <= '9' ? 26 - '0' : 26 >= 'a' && 26 <= 'f' ? 26 - 'a' + 10
    : 26 >= 'A' && 26 <= 'F' ? 26 - 'A' + 10 : -1 ,
    27 >= '0' && 27 <= '9' ? 27 - '0' : 27 >= 'a' && 27 <= 'f' ? 27 - 'a' + 10
    : 27 >= 'A' && 27 <= 'F' ? 27 - 'A' + 10 : -1 ,
    28 >= '0' && 28 <= '9' ? 28 - '0' : 28 >= 'a' && 28 <= 'f' ? 28 - 'a' + 10
    : 28 >= 'A' && 28 <= 'F' ? 28 - 'A' + 10 : -1 ,
    29 >= '0' && 29 <= '9' ? 29 - '0' : 29 >= 'a' && 29 <= 'f' ? 29 - 'a' + 10
    : 29 >= 'A' && 29 <= 'F' ? 29 - 'A' + 10 : -1 ,
    30 >= '0' && 30 <= '9' ? 30 - '0' : 30 >= 'a' && 30 <= 'f' ? 30 - 'a' + 10
    : 30 >= 'A' && 30 <= 'F' ? 30 - 'A' + 10 : -1 ,
    31 >= '0' && 31 <= '9' ? 31 - '0' : 31 >= 'a' && 31 <= 'f' ? 31 - 'a' + 10
    : 31 >= 'A' && 31 <= 'F' ? 31 - 'A' + 10 : -1 ,
    32 >= '0' && 32 <= '9' ? 32 - '0' : 32 >= 'a' && 32 <= 'f' ? 32 - 'a' + 10
    : 32 >= 'A' && 32 <= 'F' ? 32 - 'A' + 10 : -1 ,
    33 >= '0' && 33 <= '9' ? 33 - '0' : 33 >= 'a' && 33 <= 'f' ? 33 - 'a' + 10
    : 33 >= 'A' && 33 <= 'F' ? 33 - 'A' + 10 : -1 ,
    34 >= '0' && 34 <= '9' ? 34 - '0' : 34 >= 'a' && 34 <= 'f' ? 34 - 'a' + 10
    : 34 >= 'A' && 34 <= 'F' ? 34 - 'A' + 10 : -1 ,
    35 >= '0' && 35 <= '9' ? 35 - '0' : 35 >= 'a' && 35 <= 'f' ? 35 - 'a' + 10
    : 35 >= 'A' && 35 <= 'F' ? 35 - 'A' + 10 : -1 ,
    36 >= '0' && 36 <= '9' ? 36 - '0' : 36 >= 'a' && 36 <= 'f' ? 36 - 'a' + 10
    : 36 >= 'A' && 36 <= 'F' ? 36 - 'A' + 10 : -1 ,
    37 >= '0' && 37 <= '9' ? 37 - '0' : 37 >= 'a' && 37 <= 'f' ? 37 - 'a' + 10
    : 37 >= 'A' && 37 <= 'F' ? 37 - 'A' + 10 : -1 ,
    38 >= '0' && 38 <= '9' ? 38 - '0' : 38 >= 'a' && 38 <= 'f' ? 38 - 'a' + 10
    : 38 >= 'A' && 38 <= 'F' ? 38 - 'A' + 10 : -1 ,
    39 >= '0' && 39 <= '9' ? 39 - '0' : 39 >= 'a' && 39 <= 'f' ? 39 - 'a' + 10
    : 39 >= 'A' && 39 <= 'F' ? 39 - 'A' + 10 : -1 ,
    40 >= '0' && 40 <= '9' ? 40 - '0' : 40 >= 'a' && 40 <= 'f' ? 40 - 'a' + 10
    : 40 >= 'A' && 40 <= 'F' ? 40 - 'A' + 10 : -1 ,
    41 >= '0' && 41 <= '9' ? 41 - '0' : 41 >= 'a' && 41 <= 'f' ? 41 - 'a' + 10
    : 41 >= 'A' && 41 <= 'F' ? 41 - 'A' + 10 : -1 ,
    42 >= '0' && 42 <= '9' ? 42 - '0' : 42 >= 'a' && 42 <= 'f' ? 42 - 'a' + 10
    : 42 >= 'A' && 42 <= 'F' ? 42 - 'A' + 10 : -1 ,
    43 >= '0' && 43 <= '9' ? 43 - '0' : 43 >= 'a' && 43 <= 'f' ? 43 - 'a' + 10
    : 43 >= 'A' && 43 <= 'F' ? 43 - 'A' + 10 : -1 ,
    44 >= '0' && 44 <= '9' ? 44 - '0' : 44 >= 'a' && 44 <= 'f' ? 44 - 'a' + 10
    : 44 >= 'A' && 44 <= 'F' ? 44 - 'A' + 10 : -1 ,
    45 >= '0' && 45 <= '9' ? 45 - '0' : 45 >= 'a' && 45 <= 'f' ? 45 - 'a' + 10
    : 45 >= 'A' && 45 <= 'F' ? 45 - 'A' + 10 : -1 ,
    46 >= '0' && 46 <= '9' ? 46 - '0' : 46 >= 'a' && 46 <= 'f' ? 46 - 'a' + 10
    : 46 >= 'A' && 46 <= 'F' ? 46 - 'A' + 10 : -1 ,
    47 >= '0' && 47 <= '9' ? 47 - '0' : 47 >= 'a' && 47 <= 'f' ? 47 - 'a' + 10
    : 47 >= 'A' && 47 <= 'F' ? 47 - 'A' + 10 : -1 ,
    48 >= '0' && 48 <= '9' ? 48 - '0' : 48 >= 'a' && 48 <= 'f' ? 48 - 'a' + 10
    : 48 >= 'A' && 48 <= 'F' ? 48 - 'A' + 10 : -1 ,
    49 >= '0' && 49 <= '9' ? 49 - '0' : 49 >= 'a' && 49 <= 'f' ? 49 - 'a' + 10
    : 49 >= 'A' && 49 <= 'F' ? 49 - 'A' + 10 : -1 ,
    50 >= '0' && 50 <= '9' ? 50 - '0' : 50 >= 'a' && 50 <= 'f' ? 50 - 'a' + 10
    : 50 >= 'A' && 50 <= 'F' ? 50 - 'A' + 10 : -1 ,
    51 >= '0' && 51 <= '9' ? 51 - '0' : 51 >= 'a' && 51 <= 'f' ? 51 - 'a' + 10
    : 51 >= 'A' && 51 <= 'F' ? 51 - 'A' + 10 : -1 ,
    52 >= '0' && 52 <= '9' ? 52 - '0' : 52 >= 'a' && 52 <= 'f' ? 52 - 'a' + 10
    : 52 >= 'A' && 52 <= 'F' ? 52 - 'A' + 10 : -1 ,
    53 >= '0' && 53 <= '9' ? 53 - '0' : 53 >= 'a' && 53 <= 'f' ? 53 - 'a' + 10
    : 53 >= 'A' && 53 <= 'F' ? 53 - 'A' + 10 : -1 ,
    54 >= '0' && 54 <= '9' ? 54 - '0' : 54 >= 'a' && 54 <= 'f' ? 54 - 'a' + 10
    : 54 >= 'A' && 54 <= 'F' ? 54 - 'A' + 10 : -1 ,
    55 >= '0' && 55 <= '9' ? 55 - '0' : 55 >= 'a' && 55 <= 'f' ? 55 - 'a' + 10
    : 55 >= 'A' && 55 <= 'F' ? 55 - 'A' + 10 : -1 ,
    56 >= '0' && 56 <= '9' ? 56 - '0' : 56 >= 'a' && 56 <= 'f' ? 56 - 'a' + 10
    : 56 >= 'A' && 56 <= 'F' ? 56 - 'A' + 10 : -1 ,
    57 >= '0' && 57 <= '9' ? 57 - '0' : 57 >= 'a' && 57 <= 'f' ? 57 - 'a' + 10
    : 57 >= 'A' && 57 <= 'F' ? 57 - 'A' + 10 : -1 ,
    58 >= '0' && 58 <= '9' ? 58 - '0' : 58 >= 'a' && 58 <= 'f' ? 58 - 'a' + 10
    : 58 >= 'A' && 58 <= 'F' ? 58 - 'A' + 10 : -1 ,
    59 >= '0' && 59 <= '9' ? 59 - '0' : 59 >= 'a' && 59 <= 'f' ? 59 - 'a' + 10
    : 59 >= 'A' && 59 <= 'F' ? 59 - 'A' + 10 : -1 ,
    60 >= '0' && 60 <= '9' ? 60 - '0' : 60 >= 'a' && 60 <= 'f' ? 60 - 'a' + 10
    : 60 >= 'A' && 60 <= 'F' ? 60 - 'A' + 10 : -1 ,
    61 >= '0' && 61 <= '9' ? 61 - '0' : 61 >= 'a' && 61 <= 'f' ? 61 - 'a' + 10
    : 61 >= 'A' && 61 <= 'F' ? 61 - 'A' + 10 : -1 ,
    62 >= '0' && 62 <= '9' ? 62 - '0' : 62 >= 'a' && 62 <= 'f' ? 62 - 'a' + 10
    : 62 >= 'A' && 62 <= 'F' ? 62 - 'A' + 10 : -1 ,
    63 >= '0' && 63 <= '9' ? 63 - '0' : 63 >= 'a' && 63 <= 'f' ? 63 - 'a' + 10
    : 63 >= 'A' && 63 <= 'F' ? 63 - 'A' + 10 : -1 ,
    64 >= '0' && 64 <= '9' ? 64 - '0' : 64 >= 'a' && 64 <= 'f' ? 64 - 'a' + 10
    : 64 >= 'A' && 64 <= 'F' ? 64 - 'A' + 10 : -1 ,
    65 >= '0' && 65 <= '9' ? 65 - '0' : 65 >= 'a' && 65 <= 'f' ? 65 - 'a' + 10
    : 65 >= 'A' && 65 <= 'F' ? 65 - 'A' + 10 : -1 ,
    66 >= '0' && 66 <= '9' ? 66 - '0' : 66 >= 'a' && 66 <= 'f' ? 66 - 'a' + 10
    : 66 >= 'A' && 66 <= 'F' ? 66 - 'A' + 10 : -1 ,
    67 >= '0' && 67 <= '9' ? 67 - '0' : 67 >= 'a' && 67 <= 'f' ? 67 - 'a' + 10
    : 67 >= 'A' && 67 <= 'F' ? 67 - 'A' + 10 : -1 ,
    68 >= '0' && 68 <= '9' ? 68 - '0' : 68 >= 'a' && 68 <= 'f' ? 68 - 'a' + 10
    : 68 >= 'A' && 68 <= 'F' ? 68 - 'A' + 10 : -1 ,
    69 >= '0' && 69 <= '9' ? 69 - '0' : 69 >= 'a' && 69 <= 'f' ? 69 - 'a' + 10
    : 69 >= 'A' && 69 <= 'F' ? 69 - 'A' + 10 : -1 ,
    70 >= '0' && 70 <= '9' ? 70 - '0' : 70 >= 'a' && 70 <= 'f' ? 70 - 'a' + 10
    : 70 >= 'A' && 70 <= 'F' ? 70 - 'A' + 10 : -1 ,
    71 >= '0' && 71 <= '9' ? 71 - '0' : 71 >= 'a' && 71 <= 'f' ? 71 - 'a' + 10
    : 71 >= 'A' && 71 <= 'F' ? 71 - 'A' + 10 : -1 ,
    72 >= '0' && 72 <= '9' ? 72 - '0' : 72 >= 'a' && 72 <= 'f' ? 72 - 'a' + 10
    : 72 >= 'A' && 72 <= 'F' ? 72 - 'A' + 10 : -1 ,
    73 >= '0' && 73 <= '9' ? 73 - '0' : 73 >= 'a' && 73 <= 'f' ? 73 - 'a' + 10
    : 73 >= 'A' && 73 <= 'F' ? 73 - 'A' + 10 : -1 ,
    74 >= '0' && 74 <= '9' ? 74 - '0' : 74 >= 'a' && 74 <= 'f' ? 74 - 'a' + 10
    : 74 >= 'A' && 74 <= 'F' ? 74 - 'A' + 10 : -1 ,
    75 >= '0' && 75 <= '9' ? 75 - '0' : 75 >= 'a' && 75 <= 'f' ? 75 - 'a' + 10
    : 75 >= 'A' && 75 <= 'F' ? 75 - 'A' + 10 : -1 ,
    76 >= '0' && 76 <= '9' ? 76 - '0' : 76 >= 'a' && 76 <= 'f' ? 76 - 'a' + 10
    : 76 >= 'A' && 76 <= 'F' ? 76 - 'A' + 10 : -1 ,
    77 >= '0' && 77 <= '9' ? 77 - '0' : 77 >= 'a' && 77 <= 'f' ? 77 - 'a' + 10
    : 77 >= 'A' && 77 <= 'F' ? 77 - 'A' + 10 : -1 ,
    78 >= '0' && 78 <= '9' ? 78 - '0' : 78 >= 'a' && 78 <= 'f' ? 78 - 'a' + 10
    : 78 >= 'A' && 78 <= 'F' ? 78 - 'A' + 10 : -1 ,
    79 >= '0' && 79 <= '9' ? 79 - '0' : 79 >= 'a' && 79 <= 'f' ? 79 - 'a' + 10
    : 79 >= 'A' && 79 <= 'F' ? 79 - 'A' + 10 : -1 ,
    80 >= '0' && 80 <= '9' ? 80 - '0' : 80 >= 'a' && 80 <= 'f' ? 80 - 'a' + 10
    : 80 >= 'A' && 80 <= 'F' ? 80 - 'A' + 10 : -1 ,
    81 >= '0' && 81 <= '9' ? 81 - '0' : 81 >= 'a' && 81 <= 'f' ? 81 - 'a' + 10
    : 81 >= 'A' && 81 <= 'F' ? 81 - 'A' + 10 : -1 ,
    82 >= '0' && 82 <= '9' ? 82 - '0' : 82 >= 'a' && 82 <= 'f' ? 82 - 'a' + 10
    : 82 >= 'A' && 82 <= 'F' ? 82 - 'A' + 10 : -1 ,
    83 >= '0' && 83 <= '9' ? 83 - '0' : 83 >= 'a' && 83 <= 'f' ? 83 - 'a' + 10
    : 83 >= 'A' && 83 <= 'F' ? 83 - 'A' + 10 : -1 ,
    84 >= '0' && 84 <= '9' ? 84 - '0' : 84 >= 'a' && 84 <= 'f' ? 84 - 'a' + 10
    : 84 >= 'A' && 84 <= 'F' ? 84 - 'A' + 10 : -1 ,
    85 >= '0' && 85 <= '9' ? 85 - '0' : 85 >= 'a' && 85 <= 'f' ? 85 - 'a' + 10
    : 85 >= 'A' && 85 <= 'F' ? 85 - 'A' + 10 : -1 ,
    86 >= '0' && 86 <= '9' ? 86 - '0' : 86 >= 'a' && 86 <= 'f' ? 86 - 'a' + 10
    : 86 >= 'A' && 86 <= 'F' ? 86 - 'A' + 10 : -1 ,
    87 >= '0' && 87 <= '9' ? 87 - '0' : 87 >= 'a' && 87 <= 'f' ? 87 - 'a' + 10
    : 87 >= 'A' && 87 <= 'F' ? 87 - 'A' + 10 : -1 ,
    88 >= '0' && 88 <= '9' ? 88 - '0' : 88 >= 'a' && 88 <= 'f' ? 88 - 'a' + 10
    : 88 >= 'A' && 88 <= 'F' ? 88 - 'A' + 10 : -1 ,
    89 >= '0' && 89 <= '9' ? 89 - '0' : 89 >= 'a' && 89 <= 'f' ? 89 - 'a' + 10
    : 89 >= 'A' && 89 <= 'F' ? 89 - 'A' + 10 : -1 ,
    90 >= '0' && 90 <= '9' ? 90 - '0' : 90 >= 'a' && 90 <= 'f' ? 90 - 'a' + 10
    : 90 >= 'A' && 90 <= 'F' ? 90 - 'A' + 10 : -1 ,
    91 >= '0' && 91 <= '9' ? 91 - '0' : 91 >= 'a' && 91 <= 'f' ? 91 - 'a' + 10
    : 91 >= 'A' && 91 <= 'F' ? 91 - 'A' + 10 : -1 ,
    92 >= '0' && 92 <= '9' ? 92 - '0' : 92 >= 'a' && 92 <= 'f' ? 92 - 'a' + 10
    : 92 >= 'A' && 92 <= 'F' ? 92 - 'A' + 10 : -1 ,
    93 >= '0' && 93 <= '9' ? 93 - '0' : 93 >= 'a' && 93 <= 'f' ? 93 - 'a' + 10
    : 93 >= 'A' && 93 <= 'F' ? 93 - 'A' + 10 : -1 ,
    94 >= '0' && 94 <= '9' ? 94 - '0' : 94 >= 'a' && 94 <= 'f' ? 94 - 'a' + 10
    : 94 >= 'A' && 94 <= 'F' ? 94 - 'A' + 10 : -1 ,
    95 >= '0' && 95 <= '9' ? 95 - '0' : 95 >= 'a' && 95 <= 'f' ? 95 - 'a' + 10
    : 95 >= 'A' && 95 <= 'F' ? 95 - 'A' + 10 : -1 ,
    96 >= '0' && 96 <= '9' ? 96 - '0' : 96 >= 'a' && 96 <= 'f' ? 96 - 'a' + 10
    : 96 >= 'A' && 96 <= 'F' ? 96 - 'A' + 10 : -1 ,
    97 >= '0' && 97 <= '9' ? 97 - '0' : 97 >= 'a' && 97 <= 'f' ? 97 - 'a' + 10
    : 97 >= 'A' && 97 <= 'F' ? 97 - 'A' + 10 : -1 ,
    98 >= '0' && 98 <= '9' ? 98 - '0' : 98 >= 'a' && 98 <= 'f' ? 98 - 'a' + 10
    : 98 >= 'A' && 98 <= 'F' ? 98 - 'A' + 10 : -1 ,
    99 >= '0' && 99 <= '9' ? 99 - '0' : 99 >= 'a' && 99 <= 'f' ? 99 - 'a' + 10
    : 99 >= 'A' && 99 <= 'F' ? 99 - 'A' + 10 : -1 ,
    100 >= '0' && 100 <= '9' ? 100 - '0' : 100 >= 'a' && 100 <= 'f' ? 100 - 'a' + 10
    : 100 >= 'A' && 100 <= 'F' ? 100 - 'A' + 10 : -1 ,
    101 >= '0' && 101 <= '9' ? 101 - '0' : 101 >= 'a' && 101 <= 'f' ? 101 - 'a' + 10
    : 101 >= 'A' && 101 <= 'F' ? 101 - 'A' + 10 : -1 ,
    102 >= '0' && 102 <= '9' ? 102 - '0' : 102 >= 'a' && 102 <= 'f' ? 102 - 'a' + 10
    : 102 >= 'A' && 102 <= 'F' ? 102 - 'A' + 10 : -1 ,
    103 >= '0' && 103 <= '9' ? 103 - '0' : 103 >= 'a' && 103 <= 'f' ? 103 - 'a' + 10
    : 103 >= 'A' && 103 <= 'F' ? 103 - 'A' + 10 : -1 ,
    104 >= '0' && 104 <= '9' ? 104 - '0' : 104 >= 'a' && 104 <= 'f' ? 104 - 'a' + 10
    : 104 >= 'A' && 104 <= 'F' ? 104 - 'A' + 10 : -1 ,
    105 >= '0' && 105 <= '9' ? 105 - '0' : 105 >= 'a' && 105 <= 'f' ? 105 - 'a' + 10
    : 105 >= 'A' && 105 <= 'F' ? 105 - 'A' + 10 : -1 ,
    106 >= '0' && 106 <= '9' ? 106 - '0' : 106 >= 'a' && 106 <= 'f' ? 106 - 'a' + 10
    : 106 >= 'A' && 106 <= 'F' ? 106 - 'A' + 10 : -1 ,
    107 >= '0' && 107 <= '9' ? 107 - '0' : 107 >= 'a' && 107 <= 'f' ? 107 - 'a' + 10
    : 107 >= 'A' && 107 <= 'F' ? 107 - 'A' + 10 : -1 ,
    108 >= '0' && 108 <= '9' ? 108 - '0' : 108 >= 'a' && 108 <= 'f' ? 108 - 'a' + 10
    : 108 >= 'A' && 108 <= 'F' ? 108 - 'A' + 10 : -1 ,
    109 >= '0' && 109 <= '9' ? 109 - '0' : 109 >= 'a' && 109 <= 'f' ? 109 - 'a' + 10
    : 109 >= 'A' && 109 <= 'F' ? 109 - 'A' + 10 : -1 ,
    110 >= '0' && 110 <= '9' ? 110 - '0' : 110 >= 'a' && 110 <= 'f' ? 110 - 'a' + 10
    : 110 >= 'A' && 110 <= 'F' ? 110 - 'A' + 10 : -1 ,
    111 >= '0' && 111 <= '9' ? 111 - '0' : 111 >= 'a' && 111 <= 'f' ? 111 - 'a' + 10
    : 111 >= 'A' && 111 <= 'F' ? 111 - 'A' + 10 : -1 ,
    112 >= '0' && 112 <= '9' ? 112 - '0' : 112 >= 'a' && 112 <= 'f' ? 112 - 'a' + 10
    : 112 >= 'A' && 112 <= 'F' ? 112 - 'A' + 10 : -1 ,
    113 >= '0' && 113 <= '9' ? 113 - '0' : 113 >= 'a' && 113 <= 'f' ? 113 - 'a' + 10
    : 113 >= 'A' && 113 <= 'F' ? 113 - 'A' + 10 : -1 ,
    114 >= '0' && 114 <= '9' ? 114 - '0' : 114 >= 'a' && 114 <= 'f' ? 114 - 'a' + 10
    : 114 >= 'A' && 114 <= 'F' ? 114 - 'A' + 10 : -1 ,
    115 >= '0' && 115 <= '9' ? 115 - '0' : 115 >= 'a' && 115 <= 'f' ? 115 - 'a' + 10
    : 115 >= 'A' && 115 <= 'F' ? 115 - 'A' + 10 : -1 ,
    116 >= '0' && 116 <= '9' ? 116 - '0' : 116 >= 'a' && 116 <= 'f' ? 116 - 'a' + 10
    : 116 >= 'A' && 116 <= 'F' ? 116 - 'A' + 10 : -1 ,
    117 >= '0' && 117 <= '9' ? 117 - '0' : 117 >= 'a' && 117 <= 'f' ? 117 - 'a' + 10
    : 117 >= 'A' && 117 <= 'F' ? 117 - 'A' + 10 : -1 ,
    118 >= '0' && 118 <= '9' ? 118 - '0' : 118 >= 'a' && 118 <= 'f' ? 118 - 'a' + 10
    : 118 >= 'A' && 118 <= 'F' ? 118 - 'A' + 10 : -1 ,
    119 >= '0' && 119 <= '9' ? 119 - '0' : 119 >= 'a' && 119 <= 'f' ? 119 - 'a' + 10
    : 119 >= 'A' && 119 <= 'F' ? 119 - 'A' + 10 : -1 ,
    120 >= '0' && 120 <= '9' ? 120 - '0' : 120 >= 'a' && 120 <= 'f' ? 120 - 'a' + 10
    : 120 >= 'A' && 120 <= 'F' ? 120 - 'A' + 10 : -1 ,
    121 >= '0' && 121 <= '9' ? 121 - '0' : 121 >= 'a' && 121 <= 'f' ? 121 - 'a' + 10
    : 121 >= 'A' && 121 <= 'F' ? 121 - 'A' + 10 : -1 ,
    122 >= '0' && 122 <= '9' ? 122 - '0' : 122 >= 'a' && 122 <= 'f' ? 122 - 'a' + 10
    : 122 >= 'A' && 122 <= 'F' ? 122 - 'A' + 10 : -1 ,
    123 >= '0' && 123 <= '9' ? 123 - '0' : 123 >= 'a' && 123 <= 'f' ? 123 - 'a' + 10
    : 123 >= 'A' && 123 <= 'F' ? 123 - 'A' + 10 : -1 ,
    124 >= '0' && 124 <= '9' ? 124 - '0' : 124 >= 'a' && 124 <= 'f' ? 124 - 'a' + 10
    : 124 >= 'A' && 124 <= 'F' ? 124 - 'A' + 10 : -1 ,
    125 >= '0' && 125 <= '9' ? 125 - '0' : 125 >= 'a' && 125 <= 'f' ? 125 - 'a' + 10
    : 125 >= 'A' && 125 <= 'F' ? 125 - 'A' + 10 : -1 ,
    126 >= '0' && 126 <= '9' ? 126 - '0' : 126 >= 'a' && 126 <= 'f' ? 126 - 'a' + 10
    : 126 >= 'A' && 126 <= 'F' ? 126 - 'A' + 10 : -1 ,
    127 >= '0' && 127 <= '9' ? 127 - '0' : 127 >= 'a' && 127 <= 'f' ? 127 - 'a' + 10
    : 127 >= 'A' && 127 <= 'F' ? 127 - 'A' + 10 : -1 ,
    128 >= '0' && 128 <= '9' ? 128 - '0' : 128 >= 'a' && 128 <= 'f' ? 128 - 'a' + 10
    : 128 >= 'A' && 128 <= 'F' ? 128 - 'A' + 10 : -1 ,
    129 >= '0' && 129 <= '9' ? 129 - '0' : 129 >= 'a' && 129 <= 'f' ? 129 - 'a' + 10
    : 129 >= 'A' && 129 <= 'F' ? 129 - 'A' + 10 : -1 ,
    130 >= '0' && 130 <= '9' ? 130 - '0' : 130 >= 'a' && 130 <= 'f' ? 130 - 'a' + 10
    : 130 >= 'A' && 130 <= 'F' ? 130 - 'A' + 10 : -1 ,
    131 >= '0' && 131 <= '9' ? 131 - '0' : 131 >= 'a' && 131 <= 'f' ? 131 - 'a' + 10
    : 131 >= 'A' && 131 <= 'F' ? 131 - 'A' + 10 : -1 ,
    132 >= '0' && 132 <= '9' ? 132 - '0' : 132 >= 'a' && 132 <= 'f' ? 132 - 'a' + 10
    : 132 >= 'A' && 132 <= 'F' ? 132 - 'A' + 10 : -1 ,
    133 >= '0' && 133 <= '9' ? 133 - '0' : 133 >= 'a' && 133 <= 'f' ? 133 - 'a' + 10
    : 133 >= 'A' && 133 <= 'F' ? 133 - 'A' + 10 : -1 ,
    134 >= '0' && 134 <= '9' ? 134 - '0' : 134 >= 'a' && 134 <= 'f' ? 134 - 'a' + 10
    : 134 >= 'A' && 134 <= 'F' ? 134 - 'A' + 10 : -1 ,
    135 >= '0' && 135 <= '9' ? 135 - '0' : 135 >= 'a' && 135 <= 'f' ? 135 - 'a' + 10
    : 135 >= 'A' && 135 <= 'F' ? 135 - 'A' + 10 : -1 ,
    136 >= '0' && 136 <= '9' ? 136 - '0' : 136 >= 'a' && 136 <= 'f' ? 136 - 'a' + 10
    : 136 >= 'A' && 136 <= 'F' ? 136 - 'A' + 10 : -1 ,
    137 >= '0' && 137 <= '9' ? 137 - '0' : 137 >= 'a' && 137 <= 'f' ? 137 - 'a' + 10
    : 137 >= 'A' && 137 <= 'F' ? 137 - 'A' + 10 : -1 ,
    138 >= '0' && 138 <= '9' ? 138 - '0' : 138 >= 'a' && 138 <= 'f' ? 138 - 'a' + 10
    : 138 >= 'A' && 138 <= 'F' ? 138 - 'A' + 10 : -1 ,
    139 >= '0' && 139 <= '9' ? 139 - '0' : 139 >= 'a' && 139 <= 'f' ? 139 - 'a' + 10
    : 139 >= 'A' && 139 <= 'F' ? 139 - 'A' + 10 : -1 ,
    140 >= '0' && 140 <= '9' ? 140 - '0' : 140 >= 'a' && 140 <= 'f' ? 140 - 'a' + 10
    : 140 >= 'A' && 140 <= 'F' ? 140 - 'A' + 10 : -1 ,
    141 >= '0' && 141 <= '9' ? 141 - '0' : 141 >= 'a' && 141 <= 'f' ? 141 - 'a' + 10
    : 141 >= 'A' && 141 <= 'F' ? 141 - 'A' + 10 : -1 ,
    142 >= '0' && 142 <= '9' ? 142 - '0' : 142 >= 'a' && 142 <= 'f' ? 142 - 'a' + 10
    : 142 >= 'A' && 142 <= 'F' ? 142 - 'A' + 10 : -1 ,
    143 >= '0' && 143 <= '9' ? 143 - '0' : 143 >= 'a' && 143 <= 'f' ? 143 - 'a' + 10
    : 143 >= 'A' && 143 <= 'F' ? 143 - 'A' + 10 : -1 ,
    144 >= '0' && 144 <= '9' ? 144 - '0' : 144 >= 'a' && 144 <= 'f' ? 144 - 'a' + 10
    : 144 >= 'A' && 144 <= 'F' ? 144 - 'A' + 10 : -1 ,
    145 >= '0' && 145 <= '9' ? 145 - '0' : 145 >= 'a' && 145 <= 'f' ? 145 - 'a' + 10
    : 145 >= 'A' && 145 <= 'F' ? 145 - 'A' + 10 : -1 ,
    146 >= '0' && 146 <= '9' ? 146 - '0' : 146 >= 'a' && 146 <= 'f' ? 146 - 'a' + 10
    : 146 >= 'A' && 146 <= 'F' ? 146 - 'A' + 10 : -1 ,
    147 >= '0' && 147 <= '9' ? 147 - '0' : 147 >= 'a' && 147 <= 'f' ? 147 - 'a' + 10
    : 147 >= 'A' && 147 <= 'F' ? 147 - 'A' + 10 : -1 ,
    148 >= '0' && 148 <= '9' ? 148 - '0' : 148 >= 'a' && 148 <= 'f' ? 148 - 'a' + 10
    : 148 >= 'A' && 148 <= 'F' ? 148 - 'A' + 10 : -1 ,
    149 >= '0' && 149 <= '9' ? 149 - '0' : 149 >= 'a' && 149 <= 'f' ? 149 - 'a' + 10
    : 149 >= 'A' && 149 <= 'F' ? 149 - 'A' + 10 : -1 ,
    150 >= '0' && 150 <= '9' ? 150 - '0' : 150 >= 'a' && 150 <= 'f' ? 150 - 'a' + 10
    : 150 >= 'A' && 150 <= 'F' ? 150 - 'A' + 10 : -1 ,
    151 >= '0' && 151 <= '9' ? 151 - '0' : 151 >= 'a' && 151 <= 'f' ? 151 - 'a' + 10
    : 151 >= 'A' && 151 <= 'F' ? 151 - 'A' + 10 : -1 ,
    152 >= '0' && 152 <= '9' ? 152 - '0' : 152 >= 'a' && 152 <= 'f' ? 152 - 'a' + 10
    : 152 >= 'A' && 152 <= 'F' ? 152 - 'A' + 10 : -1 ,
    153 >= '0' && 153 <= '9' ? 153 - '0' : 153 >= 'a' && 153 <= 'f' ? 153 - 'a' + 10
    : 153 >= 'A' && 153 <= 'F' ? 153 - 'A' + 10 : -1 ,
    154 >= '0' && 154 <= '9' ? 154 - '0' : 154 >= 'a' && 154 <= 'f' ? 154 - 'a' + 10
    : 154 >= 'A' && 154 <= 'F' ? 154 - 'A' + 10 : -1 ,
    155 >= '0' && 155 <= '9' ? 155 - '0' : 155 >= 'a' && 155 <= 'f' ? 155 - 'a' + 10
    : 155 >= 'A' && 155 <= 'F' ? 155 - 'A' + 10 : -1 ,
    156 >= '0' && 156 <= '9' ? 156 - '0' : 156 >= 'a' && 156 <= 'f' ? 156 - 'a' + 10
    : 156 >= 'A' && 156 <= 'F' ? 156 - 'A' + 10 : -1 ,
    157 >= '0' && 157 <= '9' ? 157 - '0' : 157 >= 'a' && 157 <= 'f' ? 157 - 'a' + 10
    : 157 >= 'A' && 157 <= 'F' ? 157 - 'A' + 10 : -1 ,
    158 >= '0' && 158 <= '9' ? 158 - '0' : 158 >= 'a' && 158 <= 'f' ? 158 - 'a' + 10
    : 158 >= 'A' && 158 <= 'F' ? 158 - 'A' + 10 : -1 ,
    159 >= '0' && 159 <= '9' ? 159 - '0' : 159 >= 'a' && 159 <= 'f' ? 159 - 'a' + 10
    : 159 >= 'A' && 159 <= 'F' ? 159 - 'A' + 10 : -1 ,
    160 >= '0' && 160 <= '9' ? 160 - '0' : 160 >= 'a' && 160 <= 'f' ? 160 - 'a' + 10
    : 160 >= 'A' && 160 <= 'F' ? 160 - 'A' + 10 : -1 ,
    161 >= '0' && 161 <= '9' ? 161 - '0' : 161 >= 'a' && 161 <= 'f' ? 161 - 'a' + 10
    : 161 >= 'A' && 161 <= 'F' ? 161 - 'A' + 10 : -1 ,
    162 >= '0' && 162 <= '9' ? 162 - '0' : 162 >= 'a' && 162 <= 'f' ? 162 - 'a' + 10
    : 162 >= 'A' && 162 <= 'F' ? 162 - 'A' + 10 : -1 ,
    163 >= '0' && 163 <= '9' ? 163 - '0' : 163 >= 'a' && 163 <= 'f' ? 163 - 'a' + 10
    : 163 >= 'A' && 163 <= 'F' ? 163 - 'A' + 10 : -1 ,
    164 >= '0' && 164 <= '9' ? 164 - '0' : 164 >= 'a' && 164 <= 'f' ? 164 - 'a' + 10
    : 164 >= 'A' && 164 <= 'F' ? 164 - 'A' + 10 : -1 ,
    165 >= '0' && 165 <= '9' ? 165 - '0' : 165 >= 'a' && 165 <= 'f' ? 165 - 'a' + 10
    : 165 >= 'A' && 165 <= 'F' ? 165 - 'A' + 10 : -1 ,
    166 >= '0' && 166 <= '9' ? 166 - '0' : 166 >= 'a' && 166 <= 'f' ? 166 - 'a' + 10
    : 166 >= 'A' && 166 <= 'F' ? 166 - 'A' + 10 : -1 ,
    167 >= '0' && 167 <= '9' ? 167 - '0' : 167 >= 'a' && 167 <= 'f' ? 167 - 'a' + 10
    : 167 >= 'A' && 167 <= 'F' ? 167 - 'A' + 10 : -1 ,
    168 >= '0' && 168 <= '9' ? 168 - '0' : 168 >= 'a' && 168 <= 'f' ? 168 - 'a' + 10
    : 168 >= 'A' && 168 <= 'F' ? 168 - 'A' + 10 : -1 ,
    169 >= '0' && 169 <= '9' ? 169 - '0' : 169 >= 'a' && 169 <= 'f' ? 169 - 'a' + 10
    : 169 >= 'A' && 169 <= 'F' ? 169 - 'A' + 10 : -1 ,
    170 >= '0' && 170 <= '9' ? 170 - '0' : 170 >= 'a' && 170 <= 'f' ? 170 - 'a' + 10
    : 170 >= 'A' && 170 <= 'F' ? 170 - 'A' + 10 : -1 ,
    171 >= '0' && 171 <= '9' ? 171 - '0' : 171 >= 'a' && 171 <= 'f' ? 171 - 'a' + 10
    : 171 >= 'A' && 171 <= 'F' ? 171 - 'A' + 10 : -1 ,
    172 >= '0' && 172 <= '9' ? 172 - '0' : 172 >= 'a' && 172 <= 'f' ? 172 - 'a' + 10
    : 172 >= 'A' && 172 <= 'F' ? 172 - 'A' + 10 : -1 ,
    173 >= '0' && 173 <= '9' ? 173 - '0' : 173 >= 'a' && 173 <= 'f' ? 173 - 'a' + 10
    : 173 >= 'A' && 173 <= 'F' ? 173 - 'A' + 10 : -1 ,
    174 >= '0' && 174 <= '9' ? 174 - '0' : 174 >= 'a' && 174 <= 'f' ? 174 - 'a' + 10
    : 174 >= 'A' && 174 <= 'F' ? 174 - 'A' + 10 : -1 ,
    175 >= '0' && 175 <= '9' ? 175 - '0' : 175 >= 'a' && 175 <= 'f' ? 175 - 'a' + 10
    : 175 >= 'A' && 175 <= 'F' ? 175 - 'A' + 10 : -1 ,
    176 >= '0' && 176 <= '9' ? 176 - '0' : 176 >= 'a' && 176 <= 'f' ? 176 - 'a' + 10
    : 176 >= 'A' && 176 <= 'F' ? 176 - 'A' + 10 : -1 ,
    177 >= '0' && 177 <= '9' ? 177 - '0' : 177 >= 'a' && 177 <= 'f' ? 177 - 'a' + 10
    : 177 >= 'A' && 177 <= 'F' ? 177 - 'A' + 10 : -1 ,
    178 >= '0' && 178 <= '9' ? 178 - '0' : 178 >= 'a' && 178 <= 'f' ? 178 - 'a' + 10
    : 178 >= 'A' && 178 <= 'F' ? 178 - 'A' + 10 : -1 ,
    179 >= '0' && 179 <= '9' ? 179 - '0' : 179 >= 'a' && 179 <= 'f' ? 179 - 'a' + 10
    : 179 >= 'A' && 179 <= 'F' ? 179 - 'A' + 10 : -1 ,
    180 >= '0' && 180 <= '9' ? 180 - '0' : 180 >= 'a' && 180 <= 'f' ? 180 - 'a' + 10
    : 180 >= 'A' && 180 <= 'F' ? 180 - 'A' + 10 : -1 ,
    181 >= '0' && 181 <= '9' ? 181 - '0' : 181 >= 'a' && 181 <= 'f' ? 181 - 'a' + 10
    : 181 >= 'A' && 181 <= 'F' ? 181 - 'A' + 10 : -1 ,
    182 >= '0' && 182 <= '9' ? 182 - '0' : 182 >= 'a' && 182 <= 'f' ? 182 - 'a' + 10
    : 182 >= 'A' && 182 <= 'F' ? 182 - 'A' + 10 : -1 ,
    183 >= '0' && 183 <= '9' ? 183 - '0' : 183 >= 'a' && 183 <= 'f' ? 183 - 'a' + 10
    : 183 >= 'A' && 183 <= 'F' ? 183 - 'A' + 10 : -1 ,
    184 >= '0' && 184 <= '9' ? 184 - '0' : 184 >= 'a' && 184 <= 'f' ? 184 - 'a' + 10
    : 184 >= 'A' && 184 <= 'F' ? 184 - 'A' + 10 : -1 ,
    185 >= '0' && 185 <= '9' ? 185 - '0' : 185 >= 'a' && 185 <= 'f' ? 185 - 'a' + 10
    : 185 >= 'A' && 185 <= 'F' ? 185 - 'A' + 10 : -1 ,
    186 >= '0' && 186 <= '9' ? 186 - '0' : 186 >= 'a' && 186 <= 'f' ? 186 - 'a' + 10
    : 186 >= 'A' && 186 <= 'F' ? 186 - 'A' + 10 : -1 ,
    187 >= '0' && 187 <= '9' ? 187 - '0' : 187 >= 'a' && 187 <= 'f' ? 187 - 'a' + 10
    : 187 >= 'A' && 187 <= 'F' ? 187 - 'A' + 10 : -1 ,
    188 >= '0' && 188 <= '9' ? 188 - '0' : 188 >= 'a' && 188 <= 'f' ? 188 - 'a' + 10
    : 188 >= 'A' && 188 <= 'F' ? 188 - 'A' + 10 : -1 ,
    189 >= '0' && 189 <= '9' ? 189 - '0' : 189 >= 'a' && 189 <= 'f' ? 189 - 'a' + 10
    : 189 >= 'A' && 189 <= 'F' ? 189 - 'A' + 10 : -1 ,
    190 >= '0' && 190 <= '9' ? 190 - '0' : 190 >= 'a' && 190 <= 'f' ? 190 - 'a' + 10
    : 190 >= 'A' && 190 <= 'F' ? 190 - 'A' + 10 : -1 ,
    191 >= '0' && 191 <= '9' ? 191 - '0' : 191 >= 'a' && 191 <= 'f' ? 191 - 'a' + 10
    : 191 >= 'A' && 191 <= 'F' ? 191 - 'A' + 10 : -1 ,
    192 >= '0' && 192 <= '9' ? 192 - '0' : 192 >= 'a' && 192 <= 'f' ? 192 - 'a' + 10
    : 192 >= 'A' && 192 <= 'F' ? 192 - 'A' + 10 : -1 ,
    193 >= '0' && 193 <= '9' ? 193 - '0' : 193 >= 'a' && 193 <= 'f' ? 193 - 'a' + 10
    : 193 >= 'A' && 193 <= 'F' ? 193 - 'A' + 10 : -1 ,
    194 >= '0' && 194 <= '9' ? 194 - '0' : 194 >= 'a' && 194 <= 'f' ? 194 - 'a' + 10
    : 194 >= 'A' && 194 <= 'F' ? 194 - 'A' + 10 : -1 ,
    195 >= '0' && 195 <= '9' ? 195 - '0' : 195 >= 'a' && 195 <= 'f' ? 195 - 'a' + 10
    : 195 >= 'A' && 195 <= 'F' ? 195 - 'A' + 10 : -1 ,
    196 >= '0' && 196 <= '9' ? 196 - '0' : 196 >= 'a' && 196 <= 'f' ? 196 - 'a' + 10
    : 196 >= 'A' && 196 <= 'F' ? 196 - 'A' + 10 : -1 ,
    197 >= '0' && 197 <= '9' ? 197 - '0' : 197 >= 'a' && 197 <= 'f' ? 197 - 'a' + 10
    : 197 >= 'A' && 197 <= 'F' ? 197 - 'A' + 10 : -1 ,
    198 >= '0' && 198 <= '9' ? 198 - '0' : 198 >= 'a' && 198 <= 'f' ? 198 - 'a' + 10
    : 198 >= 'A' && 198 <= 'F' ? 198 - 'A' + 10 : -1 ,
    199 >= '0' && 199 <= '9' ? 199 - '0' : 199 >= 'a' && 199 <= 'f' ? 199 - 'a' + 10
    : 199 >= 'A' && 199 <= 'F' ? 199 - 'A' + 10 : -1 ,
    200 >= '0' && 200 <= '9' ? 200 - '0' : 200 >= 'a' && 200 <= 'f' ? 200 - 'a' + 10
    : 200 >= 'A' && 200 <= 'F' ? 200 - 'A' + 10 : -1 ,
    201 >= '0' && 201 <= '9' ? 201 - '0' : 201 >= 'a' && 201 <= 'f' ? 201 - 'a' + 10
    : 201 >= 'A' && 201 <= 'F' ? 201 - 'A' + 10 : -1 ,
    202 >= '0' && 202 <= '9' ? 202 - '0' : 202 >= 'a' && 202 <= 'f' ? 202 - 'a' + 10
    : 202 >= 'A' && 202 <= 'F' ? 202 - 'A' + 10 : -1 ,
    203 >= '0' && 203 <= '9' ? 203 - '0' : 203 >= 'a' && 203 <= 'f' ? 203 - 'a' + 10
    : 203 >= 'A' && 203 <= 'F' ? 203 - 'A' + 10 : -1 ,
    204 >= '0' && 204 <= '9' ? 204 - '0' : 204 >= 'a' && 204 <= 'f' ? 204 - 'a' + 10
    : 204 >= 'A' && 204 <= 'F' ? 204 - 'A' + 10 : -1 ,
    205 >= '0' && 205 <= '9' ? 205 - '0' : 205 >= 'a' && 205 <= 'f' ? 205 - 'a' + 10
    : 205 >= 'A' && 205 <= 'F' ? 205 - 'A' + 10 : -1 ,
    206 >= '0' && 206 <= '9' ? 206 - '0' : 206 >= 'a' && 206 <= 'f' ? 206 - 'a' + 10
    : 206 >= 'A' && 206 <= 'F' ? 206 - 'A' + 10 : -1 ,
    207 >= '0' && 207 <= '9' ? 207 - '0' : 207 >= 'a' && 207 <= 'f' ? 207 - 'a' + 10
    : 207 >= 'A' && 207 <= 'F' ? 207 - 'A' + 10 : -1 ,
    208 >= '0' && 208 <= '9' ? 208 - '0' : 208 >= 'a' && 208 <= 'f' ? 208 - 'a' + 10
    : 208 >= 'A' && 208 <= 'F' ? 208 - 'A' + 10 : -1 ,
    209 >= '0' && 209 <= '9' ? 209 - '0' : 209 >= 'a' && 209 <= 'f' ? 209 - 'a' + 10
    : 209 >= 'A' && 209 <= 'F' ? 209 - 'A' + 10 : -1 ,
    210 >= '0' && 210 <= '9' ? 210 - '0' : 210 >= 'a' && 210 <= 'f' ? 210 - 'a' + 10
    : 210 >= 'A' && 210 <= 'F' ? 210 - 'A' + 10 : -1 ,
    211 >= '0' && 211 <= '9' ? 211 - '0' : 211 >= 'a' && 211 <= 'f' ? 211 - 'a' + 10
    : 211 >= 'A' && 211 <= 'F' ? 211 - 'A' + 10 : -1 ,
    212 >= '0' && 212 <= '9' ? 212 - '0' : 212 >= 'a' && 212 <= 'f' ? 212 - 'a' + 10
    : 212 >= 'A' && 212 <= 'F' ? 212 - 'A' + 10 : -1 ,
    213 >= '0' && 213 <= '9' ? 213 - '0' : 213 >= 'a' && 213 <= 'f' ? 213 - 'a' + 10
    : 213 >= 'A' && 213 <= 'F' ? 213 - 'A' + 10 : -1 ,
    214 >= '0' && 214 <= '9' ? 214 - '0' : 214 >= 'a' && 214 <= 'f' ? 214 - 'a' + 10
    : 214 >= 'A' && 214 <= 'F' ? 214 - 'A' + 10 : -1 ,
    215 >= '0' && 215 <= '9' ? 215 - '0' : 215 >= 'a' && 215 <= 'f' ? 215 - 'a' + 10
    : 215 >= 'A' && 215 <= 'F' ? 215 - 'A' + 10 : -1 ,
    216 >= '0' && 216 <= '9' ? 216 - '0' : 216 >= 'a' && 216 <= 'f' ? 216 - 'a' + 10
    : 216 >= 'A' && 216 <= 'F' ? 216 - 'A' + 10 : -1 ,
    217 >= '0' && 217 <= '9' ? 217 - '0' : 217 >= 'a' && 217 <= 'f' ? 217 - 'a' + 10
    : 217 >= 'A' && 217 <= 'F' ? 217 - 'A' + 10 : -1 ,
    218 >= '0' && 218 <= '9' ? 218 - '0' : 218 >= 'a' && 218 <= 'f' ? 218 - 'a' + 10
    : 218 >= 'A' && 218 <= 'F' ? 218 - 'A' + 10 : -1 ,
    219 >= '0' && 219 <= '9' ? 219 - '0' : 219 >= 'a' && 219 <= 'f' ? 219 - 'a' + 10
    : 219 >= 'A' && 219 <= 'F' ? 219 - 'A' + 10 : -1 ,
    220 >= '0' && 220 <= '9' ? 220 - '0' : 220 >= 'a' && 220 <= 'f' ? 220 - 'a' + 10
    : 220 >= 'A' && 220 <= 'F' ? 220 - 'A' + 10 : -1 ,
    221 >= '0' && 221 <= '9' ? 221 - '0' : 221 >= 'a' && 221 <= 'f' ? 221 - 'a' + 10
    : 221 >= 'A' && 221 <= 'F' ? 221 - 'A' + 10 : -1 ,
    222 >= '0' && 222 <= '9' ? 222 - '0' : 222 >= 'a' && 222 <= 'f' ? 222 - 'a' + 10
    : 222 >= 'A' && 222 <= 'F' ? 222 - 'A' + 10 : -1 ,
    223 >= '0' && 223 <= '9' ? 223 - '0' : 223 >= 'a' && 223 <= 'f' ? 223 - 'a' + 10
    : 223 >= 'A' && 223 <= 'F' ? 223 - 'A' + 10 : -1 ,
    224 >= '0' && 224 <= '9' ? 224 - '0' : 224 >= 'a' && 224 <= 'f' ? 224 - 'a' + 10
    : 224 >= 'A' && 224 <= 'F' ? 224 - 'A' + 10 : -1 ,
    225 >= '0' && 225 <= '9' ? 225 - '0' : 225 >= 'a' && 225 <= 'f' ? 225 - 'a' + 10
    : 225 >= 'A' && 225 <= 'F' ? 225 - 'A' + 10 : -1 ,
    226 >= '0' && 226 <= '9' ? 226 - '0' : 226 >= 'a' && 226 <= 'f' ? 226 - 'a' + 10
    : 226 >= 'A' && 226 <= 'F' ? 226 - 'A' + 10 : -1 ,
    227 >= '0' && 227 <= '9' ? 227 - '0' : 227 >= 'a' && 227 <= 'f' ? 227 - 'a' + 10
    : 227 >= 'A' && 227 <= 'F' ? 227 - 'A' + 10 : -1 ,
    228 >= '0' && 228 <= '9' ? 228 - '0' : 228 >= 'a' && 228 <= 'f' ? 228 - 'a' + 10
    : 228 >= 'A' && 228 <= 'F' ? 228 - 'A' + 10 : -1 ,
    229 >= '0' && 229 <= '9' ? 229 - '0' : 229 >= 'a' && 229 <= 'f' ? 229 - 'a' + 10
    : 229 >= 'A' && 229 <= 'F' ? 229 - 'A' + 10 : -1 ,
    230 >= '0' && 230 <= '9' ? 230 - '0' : 230 >= 'a' && 230 <= 'f' ? 230 - 'a' + 10
    : 230 >= 'A' && 230 <= 'F' ? 230 - 'A' + 10 : -1 ,
    231 >= '0' && 231 <= '9' ? 231 - '0' : 231 >= 'a' && 231 <= 'f' ? 231 - 'a' + 10
    : 231 >= 'A' && 231 <= 'F' ? 231 - 'A' + 10 : -1 ,
    232 >= '0' && 232 <= '9' ? 232 - '0' : 232 >= 'a' && 232 <= 'f' ? 232 - 'a' + 10
    : 232 >= 'A' && 232 <= 'F' ? 232 - 'A' + 10 : -1 ,
    233 >= '0' && 233 <= '9' ? 233 - '0' : 233 >= 'a' && 233 <= 'f' ? 233 - 'a' + 10
    : 233 >= 'A' && 233 <= 'F' ? 233 - 'A' + 10 : -1 ,
    234 >= '0' && 234 <= '9' ? 234 - '0' : 234 >= 'a' && 234 <= 'f' ? 234 - 'a' + 10
    : 234 >= 'A' && 234 <= 'F' ? 234 - 'A' + 10 : -1 ,
    235 >= '0' && 235 <= '9' ? 235 - '0' : 235 >= 'a' && 235 <= 'f' ? 235 - 'a' + 10
    : 235 >= 'A' && 235 <= 'F' ? 235 - 'A' + 10 : -1 ,
    236 >= '0' && 236 <= '9' ? 236 - '0' : 236 >= 'a' && 236 <= 'f' ? 236 - 'a' + 10
    : 236 >= 'A' && 236 <= 'F' ? 236 - 'A' + 10 : -1 ,
    237 >= '0' && 237 <= '9' ? 237 - '0' : 237 >= 'a' && 237 <= 'f' ? 237 - 'a' + 10
    : 237 >= 'A' && 237 <= 'F' ? 237 - 'A' + 10 : -1 ,
    238 >= '0' && 238 <= '9' ? 238 - '0' : 238 >= 'a' && 238 <= 'f' ? 238 - 'a' + 10
    : 238 >= 'A' && 238 <= 'F' ? 238 - 'A' + 10 : -1 ,
    239 >= '0' && 239 <= '9' ? 239 - '0' : 239 >= 'a' && 239 <= 'f' ? 239 - 'a' + 10
    : 239 >= 'A' && 239 <= 'F' ? 239 - 'A' + 10 : -1 ,
    240 >= '0' && 240 <= '9' ? 240 - '0' : 240 >= 'a' && 240 <= 'f' ? 240 - 'a' + 10
    : 240 >= 'A' && 240 <= 'F' ? 240 - 'A' + 10 : -1 ,
    241 >= '0' && 241 <= '9' ? 241 - '0' : 241 >= 'a' && 241 <= 'f' ? 241 - 'a' + 10
    : 241 >= 'A' && 241 <= 'F' ? 241 - 'A' + 10 : -1 ,
    242 >= '0' && 242 <= '9' ? 242 - '0' : 242 >= 'a' && 242 <= 'f' ? 242 - 'a' + 10
    : 242 >= 'A' && 242 <= 'F' ? 242 - 'A' + 10 : -1 ,
    243 >= '0' && 243 <= '9' ? 243 - '0' : 243 >= 'a' && 243 <= 'f' ? 243 - 'a' + 10
    : 243 >= 'A' && 243 <= 'F' ? 243 - 'A' + 10 : -1 ,
    244 >= '0' && 244 <= '9' ? 244 - '0' : 244 >= 'a' && 244 <= 'f' ? 244 - 'a' + 10
    : 244 >= 'A' && 244 <= 'F' ? 244 - 'A' + 10 : -1 ,
    245 >= '0' && 245 <= '9' ? 245 - '0' : 245 >= 'a' && 245 <= 'f' ? 245 - 'a' + 10
    : 245 >= 'A' && 245 <= 'F' ? 245 - 'A' + 10 : -1 ,
    246 >= '0' && 246 <= '9' ? 246 - '0' : 246 >= 'a' && 246 <= 'f' ? 246 - 'a' + 10
    : 246 >= 'A' && 246 <= 'F' ? 246 - 'A' + 10 : -1 ,
    247 >= '0' && 247 <= '9' ? 247 - '0' : 247 >= 'a' && 247 <= 'f' ? 247 - 'a' + 10
    : 247 >= 'A' && 247 <= 'F' ? 247 - 'A' + 10 : -1 ,
    248 >= '0' && 248 <= '9' ? 248 - '0' : 248 >= 'a' && 248 <= 'f' ? 248 - 'a' + 10
    : 248 >= 'A' && 248 <= 'F' ? 248 - 'A' + 10 : -1 ,
    249 >= '0' && 249 <= '9' ? 249 - '0' : 249 >= 'a' && 249 <= 'f' ? 249 - 'a' + 10
    : 249 >= 'A' && 249 <= 'F' ? 249 - 'A' + 10 : -1 ,
    250 >= '0' && 250 <= '9' ? 250 - '0' : 250 >= 'a' && 250 <= 'f' ? 250 - 'a' + 10
    : 250 >= 'A' && 250 <= 'F' ? 250 - 'A' + 10 : -1 ,
    251 >= '0' && 251 <= '9' ? 251 - '0' : 251 >= 'a' && 251 <= 'f' ? 251 - 'a' + 10
    : 251 >= 'A' && 251 <= 'F' ? 251 - 'A' + 10 : -1 ,
    252 >= '0' && 252 <= '9' ? 252 - '0' : 252 >= 'a' && 252 <= 'f' ? 252 - 'a' + 10
    : 252 >= 'A' && 252 <= 'F' ? 252 - 'A' + 10 : -1 ,
    253 >= '0' && 253 <= '9' ? 253 - '0' : 253 >= 'a' && 253 <= 'f' ? 253 - 'a' + 10
    : 253 >= 'A' && 253 <= 'F' ? 253 - 'A' + 10 : -1 ,
    254 >= '0' && 254 <= '9' ? 254 - '0' : 254 >= 'a' && 254 <= 'f' ? 254 - 'a' + 10
    : 254 >= 'A' && 254 <= 'F' ? 254 - 'A' + 10 : -1 ,
    255 >= '0' && 255 <= '9' ? 255 - '0' : 255 >= 'a' && 255 <= 'f' ? 255 - 'a' + 10
    : 255 >= 'A' && 255 <= 'F' ? 255 - 'A' + 10 : -1
};

static UV
decode_4hex (dec_t *dec)
{
  signed char d1, d2, d3, d4;
  unsigned char *cur = (unsigned char *)dec->cur;

  d1 = decode_hexdigit [cur [0]]; if (UNLIKELY(d1 < 0)) ERR ("exactly four hexadecimal digits expected");
  d2 = decode_hexdigit [cur [1]]; if (UNLIKELY(d2 < 0)) ERR ("exactly four hexadecimal digits expected");
  d3 = decode_hexdigit [cur [2]]; if (UNLIKELY(d3 < 0)) ERR ("exactly four hexadecimal digits expected");
  d4 = decode_hexdigit [cur [3]]; if (UNLIKELY(d4 < 0)) ERR ("exactly four hexadecimal digits expected");

  dec->cur += 4;

  return ((UV)d1) << 12
       | ((UV)d2) <<  8
       | ((UV)d3) <<  4
       | ((UV)d4);

fail:
  return (UV)-1;
}

static UV
decode_2hex (dec_t *dec)
{
  signed char d1, d2;
  unsigned char *cur = (unsigned char *)dec->cur;

  d1 = decode_hexdigit [cur [0]]; if (UNLIKELY(d1 < 0)) ERR ("exactly two hexadecimal digits expected");
  d2 = decode_hexdigit [cur [1]]; if (UNLIKELY(d2 < 0)) ERR ("exactly two hexadecimal digits expected");
  dec->cur += 2;
  return ((UV)d1) << 4
       | ((UV)d2);
fail:
  return (UV)-1;
}

static UV
decode_3oct (dec_t *dec)
{
  IV d1, d2, d3;
  unsigned char *cur = (unsigned char *)dec->cur;

  d1 = (IV)(cur[0] - '0'); if (d1 < 0 || d1 > 7) ERR ("exactly three octal digits expected");
  d2 = (IV)(cur[1] - '0'); if (d2 < 0 || d2 > 7) ERR ("exactly three octal digits expected");
  d3 = (IV)(cur[2] - '0'); if (d3 < 0 || d3 > 7) ERR ("exactly three octal digits expected");
  dec->cur += 3;
  return (d1 * 64) + (d2 * 8) + d3;
fail:
  return (UV)-1;
}

static SV *
_decode_str (pTHX_ dec_t *dec, char endstr)
{
  SV *sv = 0;
  int utf8 = 0;
  char *dec_cur = dec->cur;
  unsigned char ch;
  assert(endstr == 0x27 || endstr == '"');

  do
    {
      char buf [SHORT_STRING_LEN + UTF8_MAXBYTES];
      char *cur = buf;

      do
        {
          ch = *(unsigned char *)dec_cur++;

          if (UNLIKELY(ch == endstr))
            {
              if (ch == 0x27 && !(dec->json.flags & F_ALLOW_SQUOTE)) {
                ERR("'\"' expected");
              }
              --dec_cur;
              break;
            }
          else if (UNLIKELY(ch == '\\'))
            {
              switch (*dec_cur)
                {
                  case '\\':
                  case '/':
                  case '"': *cur++ = *dec_cur++; break;

                  case 'b': ++dec_cur; *cur++ = '\010'; break;
                  case 't': ++dec_cur; *cur++ = '\011'; break;
                  case 'n': ++dec_cur; *cur++ = '\012'; break;
                  case 'f': ++dec_cur; *cur++ = '\014'; break;
                  case 'r': ++dec_cur; *cur++ = '\015'; break;

                  case 'x':
		    {
		      UV c;
		      if (!(dec->json.flags & F_BINARY))
                        ERR ("illegal hex character in non-binary string");
		      ++dec_cur;
                      dec->cur = dec_cur;
                      c = decode_2hex (dec);
                      if (c == (UV)-1)
                        goto fail;
		      *cur++ = c;
		      dec_cur += 2;
		      break;
		    }
                  case '0': case '1': case '2': case '3':
		  case '4': case '5': case '6': case '7':
		    {
		      UV c;
		      if (!(dec->json.flags & F_BINARY))
                        ERR ("illegal octal character in non-binary string");
                      dec->cur = dec_cur;
                      c = decode_3oct (dec);
                      if (c == (UV)-1)
                        goto fail;
		      *cur++ = c;
		      dec_cur += 3;
		      break;
		    }
                  case 'u':
                    {
                      UV lo, hi;
                      ++dec_cur;

                      dec->cur = dec_cur;
                      hi = decode_4hex (dec);
                      dec_cur = dec->cur;
                      if (hi == (UV)-1)
                        goto fail;
		      if (dec->json.flags & F_BINARY)
                        ERR ("illegal unicode character in binary string");

                      /* possibly a surrogate pair */
                      if (hi >= 0xd800) {
                        if (hi < 0xdc00) {
                          if (dec_cur [0] != '\\' || dec_cur [1] != 'u')
                            ERR ("missing low surrogate character in surrogate pair");

                          dec_cur += 2;

                          dec->cur = dec_cur;
                          lo = decode_4hex (dec);
                          dec_cur = dec->cur;
                          if (lo == (UV)-1)
                            goto fail;

                          if (lo < 0xdc00 || lo >= 0xe000)
                            ERR ("surrogate pair expected");

                          hi = (hi - 0xD800) * 0x400 + (lo - 0xDC00) + 0x10000;
                          if (UNLIKELY(
                                 !(dec->json.flags & F_RELAXED)
                                 && (((hi & 0xfffe) == 0xfffe)
                                  || ((hi & 0xffff) == 0xffff)))) {
                            WARNER_NONCHAR(hi);
                          }
                        }
                        else if (UNLIKELY(hi < 0xe000)) {
                          ERR ("missing high surrogate character in surrogate pair");
                        }
                        else

/* check 66 noncharacters U+FDD0..U+FDEF, U+FFFE, U+FFFF
   and U+1FFFE, U+1FFFF, U+2FFFE, U+2FFFF, ... U+10FFFE, U+10FFFF (issue #74)
   and warn as in core.
   See http://www.unicode.org/versions/corrigendum9.html.

   https://www.rfc-editor.org/errata_search.php?rfc=7159&eid=3984
   The WG's consensus was to leave the full range present
   in the ABNF and add the interoperability guidance about
   values outside the Unicode accepted range.

   http://seriot.ch/parsing_json.html#25 According to the Unicode
   standard, illformed subsequences should be replaced by U+FFFD
   REPLACEMENT CHARACTER. (See Unicode PR #121: Recommended Practice
   for Replacement Characters). Several parsers use replacement
   characters, while other keep the escaped form or produce an
   non-Unicode character (see Section 5 - Parsing Contents).  This
   values are not for interchange, only for application internal use.
   They are different from private use.  Most parsers accept these.
*/
                          if (UNLIKELY(
                                 !(dec->json.flags & F_RELAXED)
                                 && ((hi >= 0xfdd0 && hi <= 0xfdef)
                                  || (hi >= 0xfffe && hi <= 0xffff)))) {
                            WARNER_NONCHAR(hi);
                          }
		      }
                      if (hi >= 0x80)
                        {
                          utf8 = 1;
                          cur = (char*)encode_utf8 ((U8*)cur, hi);
                        }
                      else
                        *cur++ = hi;
                    }
                    break;

                  default:
                    --dec_cur;
                    ERR ("illegal backslash escape sequence in string");
                }
            }
          else if (LIKELY(ch >= 0x20 && ch < 0x80)) {
            *cur++ = ch;
            /* Ending ' already handled above with (ch == endstr) cid #165321 */
          }
          else if (ch >= 0x80)
            {
              STRLEN clen;

              --dec_cur;

              decode_utf8 (aTHX_ (U8*)dec_cur, dec->end - dec_cur,
                           dec->json.flags & F_RELAXED, &clen);
              if (clen == (STRLEN)-1)
                ERR ("malformed UTF-8 character in JSON string");

              do
                *cur++ = *dec_cur++;
              while (--clen);

              utf8 = 1;
            }
          else if (dec->json.flags & F_RELAXED && ch == '\t') {
            *cur++ = ch;
          } else
            {
              --dec_cur;

              if (!ch)
                ERR ("unexpected end of string while parsing JSON string");
              else
                ERR ("invalid character encountered while parsing JSON string");
            }
        }
      while (cur < buf + SHORT_STRING_LEN);

      {
        STRLEN len = cur - buf;

        if (sv)
          {
            STRLEN cur = SvCUR (sv);

            if (SvLEN (sv) <= cur + len)
              SvGROW (sv, cur + (len < (cur >> 2) ? cur >> 2 : len) + 1);

            memcpy (SvPVX (sv) + SvCUR (sv), buf, len);
            SvCUR_set (sv, SvCUR (sv) + len);
          }
        else
          sv = newSVpvn (buf, len);
      }
    }
  while (*dec_cur != endstr);

  ++dec_cur;

  if (sv)
    {
      SvPOK_only (sv);
      *SvEND (sv) = 0;

      if (utf8)
        SvUTF8_on (sv);
    }
  else
    sv = newSVpvn ("", 0);

  dec->cur = dec_cur;
  return sv;

fail:
  dec->cur = dec_cur;
  return 0;
}

INLINE SV *
decode_str (pTHX_ dec_t *dec)
{
  return _decode_str(aTHX_ dec, '"');
}

INLINE SV *
decode_str_sq (pTHX_ dec_t *dec)
{
  return _decode_str(aTHX_ dec, 0x27);
}

static SV *
decode_num (pTHX_ dec_t *dec)
{
  int is_nv = 0;
  char *start = dec->cur;

  /* [minus] */
  if (*dec->cur == '-')
    ++dec->cur;

  if (*dec->cur == '0')
    {
      ++dec->cur;
      if (*dec->cur >= '0' && *dec->cur <= '9')
         ERR ("malformed number (leading zero must not be followed by another digit)");
    }
  else if (*dec->cur < '0' || *dec->cur > '9')
    ERR ("malformed number (no digits after initial minus)");
  else
    do
      {
        ++dec->cur;
      }
    while (*dec->cur >= '0' && *dec->cur <= '9');

  /* [frac] */
  if (*dec->cur == '.')
    {
      ++dec->cur;

      if (*dec->cur < '0' || *dec->cur > '9')
        ERR ("malformed number (no digits after decimal point)");

      do
        {
          ++dec->cur;
        }
      while (*dec->cur >= '0' && *dec->cur <= '9');

      is_nv = 1;
    }

  /* [exp] */
  if (*dec->cur == 'e' || *dec->cur == 'E')
    {
      ++dec->cur;

      if (*dec->cur == '-' || *dec->cur == '+')
        ++dec->cur;

      if (*dec->cur < '0' || *dec->cur > '9')
        ERR ("malformed number (no digits after exp sign)");

      do
        {
          ++dec->cur;
        }
      while (*dec->cur >= '0' && *dec->cur <= '9');

      is_nv = 1;
    }

  if (!is_nv)
    {
      int len = dec->cur - start;

      /* special case the rather common 1..5-digit-int case */
      if (*start == '-')
        switch (len)
          {
            case 2: return newSViv (-(IV)(                                                                          start [1] - '0' *     1));
            case 3: return newSViv (-(IV)(                                                         start [1] * 10 + start [2] - '0' *    11));
            case 4: return newSViv (-(IV)(                                       start [1] * 100 + start [2] * 10 + start [3] - '0' *   111));
            case 5: return newSViv (-(IV)(                    start [1] * 1000 + start [2] * 100 + start [3] * 10 + start [4] - '0' *  1111));
            case 6: return newSViv (-(IV)(start [1] * 10000 + start [2] * 1000 + start [3] * 100 + start [4] * 10 + start [5] - '0' * 11111));
          }
      else
        switch (len)
          {
            case 1: return newSViv (                                                                                start [0] - '0' *     1);
            case 2: return newSViv (                                                               start [0] * 10 + start [1] - '0' *    11);
            case 3: return newSViv (                                             start [0] * 100 + start [1] * 10 + start [2] - '0' *   111);
            case 4: return newSViv (                          start [0] * 1000 + start [1] * 100 + start [2] * 10 + start [3] - '0' *  1111);
            case 5: return newSViv (      start [0] * 10000 + start [1] * 1000 + start [2] * 100 + start [3] * 10 + start [4] - '0' * 11111);
          }

      {
        UV uv;
        int numtype = grok_number (start, len, &uv);
        if (numtype & IS_NUMBER_IN_UV) {
          if (numtype & IS_NUMBER_NEG)
            {
              if (uv <= (UV)(IV_MAX) + 1)
                return newSViv (-(IV)uv);
            }
          else
            return newSVuv (uv);
	}
      }

      len -= *start == '-' ? 1 : 0;

      /* does not fit into IV or UV, try NV */
      if ((sizeof (NV) == sizeof (double) && DBL_DIG >= len)
          #if defined (LDBL_DIG)
          || (sizeof (NV) == sizeof (long double) && LDBL_DIG >= len)
          #endif
         )
        /* fits into NV without loss of precision */
        return newSVnv (json_atof (start));

      if (dec->json.flags & F_ALLOW_BIGNUM) {
        SV* pv = newSVpvs("require Math::BigInt && return Math::BigInt->new(\"");
        sv_catpvn(pv, start, dec->cur - start);
        sv_catpvs(pv, "\");");
        eval_sv(pv, G_SCALAR);
        SvREFCNT_dec(pv);
        {
          dSP;
          SV *retval = SvREFCNT_inc(POPs);
          PUTBACK;
          return retval;
        }
      }

      /* everything else fails, convert it to a string */
      return newSVpvn (start, dec->cur - start);
    }

  if (dec->json.flags & F_ALLOW_BIGNUM) {
    SV* pv = newSVpvs("require Math::BigFloat && return Math::BigFloat->new(\"");
    sv_catpvn(pv, start, dec->cur - start);
    sv_catpvs(pv, "\");");
    eval_sv(pv, G_SCALAR);
    SvREFCNT_dec(pv);
    {
      dSP;
      SV *retval = SvREFCNT_inc(POPs);
      PUTBACK;
      return retval;
    }
  }

  /* loss of precision here */
  return newSVnv (json_atof (start));

fail:
  return 0;
}

static SV *
decode_av (pTHX_ dec_t *dec)
{
  AV *av = newAV ();

  DEC_INC_DEPTH;
  decode_ws (dec);

  if (*dec->cur == ']')
    ++dec->cur;
  else
    for (;;)
      {
        SV *value;

        value = decode_sv (aTHX_ dec);
        if (!value)
          goto fail;

        av_push (av, value);

        decode_ws (dec);

        if (*dec->cur == ']')
          {
            ++dec->cur;
            break;
          }
        
        if (*dec->cur != ',')
          ERR (", or ] expected while parsing array");

        ++dec->cur;

        decode_ws (dec);

        if (*dec->cur == ']' && dec->json.flags & F_RELAXED)
          {
            ++dec->cur;
            break;
          }
      }

  DEC_DEC_DEPTH;
  return newRV_noinc ((SV *)av);

fail:
  SvREFCNT_dec (av);
  DEC_DEC_DEPTH;
  return 0;
}

static SV *
decode_hv (pTHX_ dec_t *dec)
{
  SV *sv;
  HV *hv = newHV ();
  int allow_squote = dec->json.flags & F_ALLOW_SQUOTE;
  int allow_barekey = dec->json.flags & F_ALLOW_BAREKEY;
  int relaxed = dec->json.flags & F_RELAXED;
  char endstr = '"';

  DEC_INC_DEPTH;
  decode_ws (dec);

  if (*dec->cur == '}')
    ++dec->cur;
  else
    for (;;)
      {
        int is_bare = allow_barekey;

        if (UNLIKELY(allow_barekey
                     && *dec->cur >= 'A' && *dec->cur <= 'z'))
          ;
        else if (UNLIKELY(allow_squote)) {
          if (*dec->cur != '"' && *dec->cur != 0x27) {
            ERR ("'\"' or ''' expected");
          }
          else if (*dec->cur == 0x27)
            endstr = 0x27;
          is_bare=0;
          ++dec->cur;
        } else {
          EXPECT_CH ('"');
          is_bare=0;
        }

        /* heuristic: assume that */
        /* a) decode_str + hv_store_ent are abysmally slow. */
        /* b) most hash keys are short, simple ascii text. */
        /* => try to "fast-match" such strings to avoid */
        /* the overhead of decode_str + hv_store_ent. */
        {
          SV *value;
          char *p = dec->cur;
          char *e = p + 24; /* only try up to 24 bytes */

          for (;;)
            {
              /* the >= 0x80 is false on most architectures */
              if (!is_bare &&
                  (p == e || *p < 0x20 || *(U8*)p >= 0x80 || *p == '\\'
                   || allow_squote))
                {
                  /* slow path, back up and use decode_str */
                  /* utf8 hash keys are handled here */
                  SV *key = _decode_str (aTHX_ dec, endstr);
                  if (!key)
                    goto fail;

                  decode_ws (dec); EXPECT_CH (':');

                  decode_ws (dec);
                  value = decode_sv (aTHX_ dec);
                  if (!value)
                    {
                      SvREFCNT_dec (key);
                      goto fail;
                    }

                  hv_store_ent (hv, key, value, 0);
                  SvREFCNT_dec (key);

                  break;
                }
              else if (*p == endstr
                       || (is_bare &&
                           (*p == ':' || *p == ' ' || *p == 0x0a
                            || *p == 0x0d || *p == 0x09)))
                {
                  /* fast path, got a simple key */
                  char *key = dec->cur;
                  U32 len = p - key;
                  assert(p >= key && p - key < I32_MAX);
#if PTRSIZE >= 8
                  /* hv_store can only handle I32 len, which might overflow */
                  /* perl5 just silently truncates it, cperl panics */
                  if (UNLIKELY(p - key > I32_MAX))
                    ERR ("Hash key too large");
#endif
                  if (!relaxed && UNLIKELY(hv_exists (hv, key, len))) {
                    ERR ("Duplicate keys not allowed");
                  }

                  dec->cur = p + 1;

                  decode_ws (dec); if (*p != ':') EXPECT_CH (':');

                  decode_ws (dec);
                  value = decode_sv (aTHX_ dec);
                  if (!value)
                    goto fail;

                  /* Note: not a utf8 hash key */
#if PERL_VERSION > 8 || (PERL_VERSION == 8 && PERL_SUBVERSION >= 9)
                  hv_common (hv, NULL, key, len, 0,
                             HV_FETCH_ISSTORE|HV_FETCH_JUST_SV, value, 0);
#else
                  hv_store (hv, key, len, value, 0);
#endif
                  break;
                }

              ++p;
            }
        }

        decode_ws (dec);

        if (*dec->cur == '}')
          {
            ++dec->cur;
            break;
          }

        if (*dec->cur != ',')
          ERR (", or } expected while parsing object/hash");

        ++dec->cur;

        decode_ws (dec);

        if (*dec->cur == '}' && dec->json.flags & F_RELAXED)
          {
            ++dec->cur;
            break;
          }
      }

  DEC_DEC_DEPTH;
  sv = newRV_noinc ((SV *)hv);

  /* check filter callbacks */
  if (dec->json.flags & F_HOOK)
    {
      if (dec->json.cb_sk_object && HvKEYS (hv) == 1)
        {
          HE *cb = NULL, *he;

          hv_iterinit (hv);
          he = hv_iternext (hv);
          hv_iterinit (hv);

          /* the next line creates a mortal sv each time it's called. */
          /* might want to optimise this for common cases. */
          if (LIKELY((long)he))
            cb = hv_fetch_ent (dec->json.cb_sk_object, hv_iterkeysv (he), 0, 0);

          if (cb)
            {
              dSP;
              I32 count;

              ENTER; SAVETMPS; SAVESTACK_POS (); PUSHMARK (SP);
              XPUSHs (HeVAL (he));
              sv_2mortal (sv);

              PUTBACK; count = call_sv (HeVAL (cb), G_ARRAY); SPAGAIN;

              if (count == 1)
                {
                  sv = newSVsv (POPs);
                  PUTBACK; FREETMPS; LEAVE;
                  return sv;
                }

              SvREFCNT_inc (sv);
              SP -= count;
              PUTBACK; FREETMPS; LEAVE;
            }
        }

      if (dec->json.cb_object)
        {
          dSP;
          I32 count;

          ENTER; SAVETMPS; SAVESTACK_POS (); PUSHMARK (SP);
          XPUSHs (sv_2mortal (sv));

          PUTBACK; count = call_sv (dec->json.cb_object, G_ARRAY); SPAGAIN;

          if (count == 1)
            {
              sv = newSVsv (POPs);
              PUTBACK; FREETMPS; LEAVE;
              return sv;
            }

          SvREFCNT_inc (sv);
          SP -= count;
          PUTBACK; FREETMPS; LEAVE;
        }
    }

  return sv;

fail:
  SvREFCNT_dec (hv);
  DEC_DEC_DEPTH;
  return 0;
}

static SV *
decode_tag (pTHX_ dec_t *dec)
{
  SV *tag = 0;
  SV *val = 0;

  if (!(dec->json.flags & F_ALLOW_TAGS))
    ERR ("malformed JSON string, neither array, object, number, string or atom");

  ++dec->cur;

  decode_ws (dec);

  tag = decode_sv (aTHX_ dec);
  if (!tag)
    goto fail;

  if (!SvPOK (tag))
    ERR ("malformed JSON string, (tag) must be a string");

  decode_ws (dec);

  if (*dec->cur != ')')
    ERR (") expected after tag");

  ++dec->cur;

  decode_ws (dec);

  val = decode_sv (aTHX_ dec);
  if (!val)
    goto fail;

  if (!SvROK (val) || SvTYPE (SvRV (val)) != SVt_PVAV)
    ERR ("malformed JSON string, tag value must be an array");

  {
    dMY_CXT;
    AV *av = (AV *)SvRV (val);
    HVMAX_T i, len = av_len (av) + 1;
    HV *stash = gv_stashsv (tag, 0);
    SV *sv;
    GV *method;
    dSP;

    if (!stash)
      ERR ("cannot decode perl-object (package does not exist)");

    method = gv_fetchmethod_autoload (stash, "THAW", 0);

    if (!method)
      ERR ("cannot decode perl-object (package does not have a THAW method)");

    ENTER; SAVETMPS; SAVESTACK_POS (); PUSHMARK (SP);
    EXTEND (SP, len + 2);
    /* we re-bless the reference to get overload and other niceties right */
    PUSHs (tag);
    PUSHs (MY_CXT.sv_json);

    for (i = 0; i < len; ++i)
      PUSHs (*av_fetch (av, i, 1));

    PUTBACK;
    call_sv ((SV *)GvCV (method), G_SCALAR);
    SPAGAIN;

    SvREFCNT_dec (tag);
    SvREFCNT_dec (val);
    sv = SvREFCNT_inc (POPs);

    PUTBACK;

    FREETMPS; LEAVE;

    return sv;
  }

fail:
  SvREFCNT_dec (tag);
  SvREFCNT_dec (val);
  return 0;
}

static SV *
decode_sv (pTHX_ dec_t *dec)
{
  /* the beauty of JSON: you need exactly one character lookahead */
  /* to parse everything. */
  switch (*dec->cur)
    {
      case '"': ++dec->cur; return decode_str (aTHX_ dec);
      case 0x27:
        if (dec->json.flags & F_ALLOW_SQUOTE) {
          ++dec->cur; return decode_str_sq (aTHX_ dec);
        }
        ERR ("malformed JSON string, neither tag, array, object, number, string or atom");
        break;
      case '[': ++dec->cur; return decode_av  (aTHX_ dec);
      case '{': ++dec->cur; return decode_hv  (aTHX_ dec);
      case '(':             return decode_tag (aTHX_ dec);

      case '-':
      case '0': case '1': case '2': case '3': case '4':
      case '5': case '6': case '7': case '8': case '9':
        return decode_num (aTHX_ dec);

      case 't':
        if (dec->end - dec->cur >= 4 && memEQc(dec->cur, "true"))
          {
            dMY_CXT;
            dec->cur += 4;
            return newSVsv(MY_CXT.json_true);
          }
        else
          ERR ("'true' expected");

        break;

      case 'f':
        if (dec->end - dec->cur >= 5 && memEQc(dec->cur, "false"))
          {
            dMY_CXT;
            dec->cur += 5;
            return newSVsv(MY_CXT.json_false);
          }
        else
          ERR ("'false' expected");

        break;

      case 'n':
        if (dec->end - dec->cur >= 4 && memEQc(dec->cur, "null"))
          {
            dec->cur += 4;
            return newSVsv(&PL_sv_undef);
          }
        else
          ERR ("'null' expected");

        break;

      default:
        ERR ("malformed JSON string, neither tag, array, object, number, string or atom");
        break;
    }

fail:
  return 0;
}

/* decode UTF32-LE/... to UTF-8:
   $utf8 = Encode::decode("UTF-32", $string); */
static SV *
decode_bom(pTHX_ const char* encoding, SV* string, STRLEN offset)
{
  dSP;
  I32 items;
  PERL_UNUSED_ARG(offset);

#ifndef HAVE_DECODE_BOM
  croak ("Cannot handle multibyte BOM yet");
  return string;
#else
  ENTER;
#if PERL_VERSION > 18
  /* on older perls (<5.20) this corrupts ax */
  Perl_load_module(aTHX_ PERL_LOADMOD_NOIMPORT, newSVpvs("Encode"),
                   NULL, NULL, NULL);
#else
  if (!get_cvs("Encode::decode", GV_NOADD_NOINIT|GV_NO_SVGMAGIC))
    croak("Multibyte BOM needs to use Encode before");
#endif
  LEAVE;
  ENTER;
  PUSHMARK(SP);
  XPUSHs(newSVpvn(encoding, strlen(encoding)));
  XPUSHs(string);
  PUTBACK;
  /* Calling Encode::Unicode::decode_xs would be faster, but we'd need the blessed
     enc hash from find_encoding() then. e.g. $Encode::Encoding{'UTF-16LE'}
     bless {Name=>UTF-16,size=>2,endian=>'',ucs2=>undef}, 'Encode::Unicode';
     And currenty we enjoy the simplicity of the BOM offset advance by 
     endianness autodetection.
   */
  items = call_sv(MUTABLE_SV(get_cvs("Encode::decode",
              GV_NOADD_NOINIT|GV_NO_SVGMAGIC)), G_SCALAR);
  SPAGAIN;
  if (items >= 0 && SvPOK(TOPs)) {
    LEAVE;
    SvUTF8_on(TOPs);
    return POPs;
  } else {
    LEAVE;
    return string;
  }
#endif
}

static SV *
decode_json (pTHX_ SV *string, JSON *json, STRLEN *offset_return)
{
  dec_t dec;
  SV *sv;
  STRLEN len, offset = 0;
  int converted = 0;
  /*dMY_CXT;*/

  /* work around bugs in 5.10 where manipulating magic values
   * makes perl ignore the magic in subsequent accesses.
   * also make a copy of non-PV values, to get them into a clean
   * state (SvPV should do that, but it's buggy, see below).
   * But breaks decode_prefix with offset.
   */
  /*SvGETMAGIC (string);*/
  if (SvMAGICAL (string) || !SvPOK (string) || SvIsCOW_shared_hash(string))
    string = sv_2mortal (newSVsv (string));

  SvUPGRADE (string, SVt_PV);

  /* work around a bug in perl 5.10, which causes SvCUR to fail an
   * assertion with -DDEBUGGING, although SvCUR is documented to
   * return the xpv_cur field which certainly exists after upgrading.
   * according to nicholas clark, calling SvPOK fixes this.
   * But it doesn't fix it, so try another workaround, call SvPV_nolen
   * and hope for the best.
   * Damnit, SvPV_nolen still trips over yet another assertion. This
   * assertion business is seriously broken, try yet another workaround
   * for the broken -DDEBUGGING.
   */
  {
#ifdef DEBUGGING
    len = SvOK (string) ? sv_len (string) : 0;
#else
    len = SvCUR (string);
#endif

    if (UNLIKELY(len > json->max_size && json->max_size))
      croak ("attempted decode of JSON text of %lu bytes size, but max_size is set to %lu",
             (unsigned long)len, (unsigned long)json->max_size);
  }

  /* Detect BOM and possibly convert to UTF-8 and set UTF8 flag.

     https://tools.ietf.org/html/rfc7159#section-8.1
     JSON text SHALL be encoded in UTF-8, UTF-16, or UTF-32.
     Byte Order Mark - While section 8.1 states "Implementations MUST
     NOT add a byte order mark to the beginning of a JSON text",
     "implementations (...) MAY ignore the presence of a byte order
     mark rather than treating it as an error". */
  if (UNLIKELY(len > 2 && SvPOK(string))) {
    U8 *s = (U8*)SvPVX (string);
    if (*s >= 0xEF) {
      if (len >= 3 && memEQc(s, UTF8BOM)) {
        json->flags |= F_UTF8;
        converted++;
        offset = 3;
        SvPV_set(string, SvPVX_mutable (string) + 3);
        SvCUR_set(string, len - 3);
        SvUTF8_on(string);
        /* omitting the endian name will skip the BOM in the result */
      } else if (len >= 4 && memEQc(s, UTF32BOM)) {
        string = decode_bom(aTHX_ "UTF-32", string, 4);
        json->flags |= F_UTF8;
        converted++;
      } else if (memEQc(s, UTF16BOM)) {
        string = decode_bom(aTHX_ "UTF-16", string, 2);
        json->flags |= F_UTF8;
        converted++;
      } else if (memEQc(s, UTF16BOM_BE)) {
        string = decode_bom(aTHX_ "UTF-16", string, 2);
        json->flags |= F_UTF8;
        converted++;
      }
    } else if (UNLIKELY(len >= 4 && !*s && memEQc(s, UTF32BOM_BE))) {
        string = decode_bom(aTHX_ "UTF-32", string, 4);
        json->flags |= F_UTF8;
        converted++;
    }
  }

  if (LIKELY(!converted)) {
    if (DECODE_WANTS_OCTETS (json))
      sv_utf8_downgrade (string, 0);
    else
      sv_utf8_upgrade (string);
  }

  /* should basically be a NOP but needed for 5.6 with undef */
  if (!SvPOK(string))
    SvGROW (string, SvCUR (string) + 1);

  dec.json  = *json;
  dec.cur   = SvPVX (string);
  dec.end   = SvEND (string);
  dec.err   = 0;
  dec.depth = 0;

  if (dec.json.cb_object || dec.json.cb_sk_object)
    dec.json.flags |= F_HOOK;

  *dec.end = 0; /* this should basically be a nop, too, but make sure it's there */

  decode_ws (&dec);
  sv = decode_sv (aTHX_ &dec);

  if (offset_return) {
    if (dec.cur < SvPVX (string) || dec.cur > SvEND (string))
      *offset_return = 0;
    else
      *offset_return = dec.cur - SvPVX (string);
  }

  if (!(offset_return || !sv))
    {
      /* check for trailing garbage */
      decode_ws (&dec);

      if ((dec.end - dec.cur) || *dec.cur)
        {
          dec.err = "garbage after JSON object";
          SvREFCNT_dec (sv);
          sv = NULL;
        }
    }
  /* restore old utf8 string with BOM */
  if (UNLIKELY(offset)) {
    SvPV_set(string, SvPVX_mutable (string) - offset);
    SvCUR_set(string, len);
  }

  if (!sv)
    {
      SV *uni = sv_newmortal ();

#if PERL_VERSION >= 8
      /* horrible hack to silence warning inside pv_uni_display */
      /* TODO: Can be omitted with newer perls */
      COP cop = *PL_curcop;
      cop.cop_warnings = pWARN_NONE;
      ENTER;
      SAVEVPTR (PL_curcop);
      PL_curcop = &cop;
      pv_uni_display (uni, (U8*)dec.cur, dec.end - dec.cur, 20, UNI_DISPLAY_QQ);
      LEAVE;
#endif
      croak ("%s, at character offset %d (before \"%s\")",
             dec.err,
             (int)ptr_to_index (aTHX_ string, dec.cur-SvPVX(string)),
             dec.cur != dec.end ? SvPV_nolen (uni) : "(end of string)");
    }

  if (!(dec.json.flags & F_ALLOW_NONREF) && json_nonref(aTHX_ sv))
    croak ("JSON text must be an object or array (but found number, string, true, false or null, use allow_nonref to allow this)");

  return sv_2mortal (sv);
}

/*/////////////////////////////////////////////////////////////////////////// */
/* incremental parser */

static void
incr_parse (JSON *self)
{
  const char *p = SvPVX (self->incr_text) + self->incr_pos;

  /* the state machine here is a bit convoluted and could be simplified a lot */
  /* but this would make it slower, so... */

  for (;;)
    {
      /*printf ("loop pod %d *p<%c><%s>, mode %d nest %d\n", p - SvPVX (self->incr_text), *p, p, self->incr_mode, self->incr_nest);//D */
      switch (self->incr_mode)
        {
          /* only used for initial whitespace skipping */
          case INCR_M_WS:
            for (;;)
              {
                if (*p > 0x20)
                  {
                    if (*p == '#')
                      {
                        self->incr_mode = INCR_M_C0;
                        goto incr_m_c;
                      }
                    else
                      {
                        self->incr_mode = INCR_M_JSON;
                        goto incr_m_json;
                      }
                  }
                else if (!*p)
                  goto interrupt;

                ++p;
              }

          /* skip a single char inside a string (for \\-processing) */
          case INCR_M_BS:
            if (!*p)
              goto interrupt;

            ++p;
            self->incr_mode = INCR_M_STR;
            goto incr_m_str;

          /* inside #-style comments */
          case INCR_M_C0:
          case INCR_M_C1:
          incr_m_c:
            for (;;)
              {
                if (*p == '\n')
                  {
                    self->incr_mode = self->incr_mode == INCR_M_C0 ? INCR_M_WS : INCR_M_JSON;
                    break;
                  }
                else if (!*p)
                  goto interrupt;

                ++p;
              }

            break;

          /* inside a string */
          case INCR_M_STR:
          incr_m_str:
            for (;;)
              {
                if (*p == '"')
                  {
                    ++p;
                    self->incr_mode = INCR_M_JSON;

                    if (!self->incr_nest)
                      goto interrupt;

                    goto incr_m_json;
                  }
                else if (*p == '\\')
                  {
                    ++p; /* "virtually" consumes character after \ */

                    if (!*p) /* if at end of string we have to switch modes */
                      {
                        self->incr_mode = INCR_M_BS;
                        goto interrupt;
                      }
                  }
                else if (!*p)
                  goto interrupt;

                ++p;
              }

          /* after initial ws, outside string */
          case INCR_M_JSON:
          incr_m_json:
            for (;;)
              {
                switch (*p++)
                  {
                    case 0:
                      --p;
                      goto interrupt;

                    case 0x09:
                    case 0x0a:
                    case 0x0d:
                    case 0x20:
                      if (!self->incr_nest)
                        {
                          --p; /* do not eat the whitespace, let the next round do it */
                          goto interrupt;
                        }
                      break;

                    case '"':
                      self->incr_mode = INCR_M_STR;
                      goto incr_m_str;

                    case '[':
                    case '{':
                    case '(':
                      if (++self->incr_nest > (int)self->max_depth)
                        croak (ERR_NESTING_EXCEEDED);
                      break;

                    case ']':
                    case '}':
                      if (--self->incr_nest <= 0)
                        goto interrupt;
                      break;

                    case ')':
                      --self->incr_nest;
                      break;

                    case '#':
                      self->incr_mode = INCR_M_C1;
                      goto incr_m_c;
                  }
              }
        }
    }

interrupt:
  self->incr_pos = p - SvPVX (self->incr_text);
  /*printf ("interrupt<%.*s>\n", self->incr_pos, SvPVX(self->incr_text));//D */
  /*printf ("return pos %d mode %d nest %d\n", self->incr_pos, self->incr_mode, self->incr_nest);//D */
}

/*/////////////////////////////////////////////////////////////////////////// */
/* XS interface functions */

MODULE = Cpanel::JSON::XS		PACKAGE = Cpanel::JSON::XS

#if PERL_VERSION > 7
# define NODEBUG_ON \
        CvNODEBUG_on (get_cv ("Cpanel::JSON::XS::incr_text", 0));
#else
# define NODEBUG_ON
#endif

BOOT:
{
        MY_CXT_INIT;
        init_MY_CXT(aTHX_ &MY_CXT);

        NODEBUG_ON; /* the debugger completely breaks lvalue subs */
}

PROTOTYPES: DISABLE


#_if PERL_IMPLICIT_CONTEXT for embedding, but no ithreads, then CLONE is never
# called

#ifdef USE_ITHREADS

void CLONE (...)
    PPCODE:
        MY_CXT_CLONE; /* possible declaration */
        init_MY_CXT(aTHX_ &MY_CXT);
	/* skip implicit PUTBACK, returning @_ to caller, more efficient*/
        return;

#endif

void END(...)
    PREINIT:
        dMY_CXT;
        SV * sv;
    PPCODE:
        sv = MY_CXT.sv_json;
        MY_CXT.sv_json = NULL;
        SvREFCNT_dec_NN(sv);
	/* skip implicit PUTBACK, returning @_ to caller, more efficient*/
        return;

void new (char *klass)
    PPCODE:
        dMY_CXT;
  	SV *pv = NEWSV (0, sizeof (JSON));
        SvPOK_only (pv);
        json_init ((JSON *)SvPVX (pv));
        XPUSHs (sv_2mortal (sv_bless (
           newRV_noinc (pv),
           strEQc (klass, "Cpanel::JSON::XS") ? JSON_STASH : gv_stashpv (klass, 1)
        )));

void ascii (JSON *self, int enable = 1)
    ALIAS:
        ascii           = F_ASCII
        latin1          = F_LATIN1
        binary          = F_BINARY
        utf8            = F_UTF8
        indent          = F_INDENT
        canonical       = F_CANONICAL
        space_before    = F_SPACE_BEFORE
        space_after     = F_SPACE_AFTER
        pretty          = F_PRETTY
        allow_nonref    = F_ALLOW_NONREF
        shrink          = F_SHRINK
        allow_blessed   = F_ALLOW_BLESSED
        convert_blessed = F_CONV_BLESSED
        relaxed         = SET_RELAXED
        allow_unknown   = F_ALLOW_UNKNOWN
        allow_tags      = F_ALLOW_TAGS
        allow_barekey   = F_ALLOW_BAREKEY
        allow_singlequote = F_ALLOW_SQUOTE
        allow_bignum    = F_ALLOW_BIGNUM
        escape_slash    = F_ESCAPE_SLASH
        allow_stringify = F_ALLOW_STRINGIFY
    PPCODE:
        if (enable)
          self->flags |=  ix;
        else
          self->flags &= ~ix;
        XPUSHs (ST (0));

void get_ascii (JSON *self)
    ALIAS:
        get_ascii           = F_ASCII
        get_latin1          = F_LATIN1
        get_binary          = F_BINARY
        get_utf8            = F_UTF8
        get_indent          = F_INDENT
        get_canonical       = F_CANONICAL
        get_space_before    = F_SPACE_BEFORE
        get_space_after     = F_SPACE_AFTER
        get_allow_nonref    = F_ALLOW_NONREF
        get_shrink          = F_SHRINK
        get_allow_blessed   = F_ALLOW_BLESSED
        get_convert_blessed = F_CONV_BLESSED
        get_relaxed         = F_RELAXED
        get_allow_unknown   = F_ALLOW_UNKNOWN
        get_allow_tags      = F_ALLOW_TAGS
        get_allow_barekey   = F_ALLOW_BAREKEY
        get_allow_singlequote = F_ALLOW_SQUOTE
        get_allow_bignum    = F_ALLOW_BIGNUM
        get_escape_slash    = F_ESCAPE_SLASH
        get_allow_stringify  = F_ALLOW_STRINGIFY
    PPCODE:
        XPUSHs (boolSV (self->flags & ix));

void max_depth (JSON *self, U32 max_depth = 0x80000000UL)
    PPCODE:
        self->max_depth = max_depth;
        XPUSHs (ST (0));

U32 get_max_depth (JSON *self)
    CODE:
        RETVAL = self->max_depth;
    OUTPUT:
        RETVAL

void max_size (JSON *self, U32 max_size = 0)
    PPCODE:
        self->max_size = max_size;
        XPUSHs (ST (0));

int get_max_size (JSON *self)
    CODE:
        RETVAL = self->max_size;
    OUTPUT:
        RETVAL

void stringify_infnan (JSON *self, IV infnan_mode = 1)
    PPCODE:
        if (infnan_mode > 3 || infnan_mode < 0) {
          croak ("invalid stringify_infnan mode %d. Must be 0, 1, 2 or 3", (int)infnan_mode);
        }
        self->infnan_mode = (unsigned char)infnan_mode;
        XPUSHs (ST (0));
        
int get_stringify_infnan (JSON *self)
    CODE:
        RETVAL = (int)self->infnan_mode;
    OUTPUT:
        RETVAL

void sort_by (JSON *self, SV* cb = &PL_sv_yes)
    PPCODE:
{
        SvREFCNT_dec (self->cb_sort_by);
        self->cb_sort_by = SvOK (cb) ? newSVsv (cb) : 0;
        if (self->cb_sort_by)
          self->flags |= F_CANONICAL;

        XPUSHs (ST (0));
}

        
void filter_json_object (JSON *self, SV *cb = &PL_sv_undef)
    PPCODE:
{
        SvREFCNT_dec (self->cb_object);
        self->cb_object = SvOK (cb) ? newSVsv (cb) : 0;

        XPUSHs (ST (0));
}

void filter_json_single_key_object (JSON *self, SV *key, SV *cb = &PL_sv_undef)
    PPCODE:
{
	if (!self->cb_sk_object)
          self->cb_sk_object = newHV ();

        if (SvOK (cb))
          (void)hv_store_ent (self->cb_sk_object, key, newSVsv (cb), 0);
        else
          {
            (void)hv_delete_ent (self->cb_sk_object, key, G_DISCARD, 0);

            if (!HvKEYS (self->cb_sk_object))
              {
                SvREFCNT_dec (self->cb_sk_object);
                self->cb_sk_object = 0;
              }
          }

        XPUSHs (ST (0));
}

void encode (JSON *self, SV *scalar)
    PPCODE:
        PUTBACK; scalar = encode_json (aTHX_ scalar, self); SPAGAIN;
        XPUSHs (scalar);

void decode (JSON *self, SV *jsonstr)
    PPCODE:
        PUTBACK; jsonstr = decode_json (aTHX_ jsonstr, self, 0); SPAGAIN;
        XPUSHs (jsonstr);

void decode_prefix (JSON *self, SV *jsonstr)
    PPCODE:
{
	SV *sv;
        STRLEN offset;
        PUTBACK; sv = decode_json (aTHX_ jsonstr, self, &offset); SPAGAIN;
        EXTEND (SP, 2);
        PUSHs (sv);
        PUSHs (sv_2mortal (newSVuv (ptr_to_index (aTHX_ jsonstr, offset))));
}

void incr_parse (JSON *self, SV *jsonstr = 0)
    PPCODE:
{
	if (!self->incr_text)
          self->incr_text = newSVpvn ("", 0);

        /* if utf8-ness doesn't match the decoder, need to upgrade/downgrade */
        if (!DECODE_WANTS_OCTETS (self) == !SvUTF8 (self->incr_text)) {
          if (DECODE_WANTS_OCTETS (self))
            {
              if (self->incr_pos)
                self->incr_pos = utf8_length ((U8 *)SvPVX (self->incr_text),
                                              (U8 *)SvPVX (self->incr_text) + self->incr_pos);

              sv_utf8_downgrade (self->incr_text, 0);
            }
          else
            {
              sv_utf8_upgrade (self->incr_text);

              if (self->incr_pos)
                self->incr_pos = utf8_hop ((U8 *)SvPVX (self->incr_text), self->incr_pos)
                                 - (U8 *)SvPVX (self->incr_text);
            }
	}

        /* append data, if any */
        if (jsonstr)
          {
            /* make sure both strings have same encoding */
            if (SvUTF8 (jsonstr) != SvUTF8 (self->incr_text)) {
              if (SvUTF8 (jsonstr))
                sv_utf8_downgrade (jsonstr, 0);
              else
                sv_utf8_upgrade (jsonstr);
	    }

            /* and then just blindly append */
            {
              STRLEN len;
              const char *str = SvPV (jsonstr, len);
              STRLEN cur = SvCUR (self->incr_text);

              if (SvLEN (self->incr_text) <= cur + len)
                SvGROW (self->incr_text, cur + (len < (cur >> 2) ? cur >> 2 : len) + 1);

              Move (str, SvEND (self->incr_text), len, char);
              SvCUR_set (self->incr_text, SvCUR (self->incr_text) + len);
              *SvEND (self->incr_text) = 0; /* this should basically be a nop, too, but make sure it's there */
            }
          }

        if (GIMME_V != G_VOID)
          do
            {
              SV *sv;
              STRLEN offset;
              char *endp;

              if (!INCR_DONE (self))
                {
                  incr_parse (self);

                  if (UNLIKELY(self->incr_pos > self->max_size && self->max_size))
                    croak ("attempted decode of JSON text of %lu bytes size, but max_size is set to %lu",
                           (unsigned long)self->incr_pos, (unsigned long)self->max_size);

                  if (!INCR_DONE (self))
                    {
                      /* as an optimisation, do not accumulate white space in the incr buffer */
                      if (self->incr_mode == INCR_M_WS && self->incr_pos)
                        {
                          self->incr_pos = 0;
                          SvCUR_set (self->incr_text, 0);
                        }

                      break;
                    }
                }

              PUTBACK; sv = decode_json (aTHX_ self->incr_text, self, &offset); SPAGAIN;
              XPUSHs (sv);

              endp = SvPVX(self->incr_text) + offset;
              self->incr_pos -= offset;
              self->incr_nest = 0;
              self->incr_mode = 0;
#if PERL_VERSION > 9
              sv_chop (self->incr_text, (const char* const)endp);
#else
              sv_chop (self->incr_text, (char*)endp);
#endif
            }
          while (GIMME_V == G_ARRAY);
}

#if PERL_VERSION > 6

SV *incr_text (JSON *self)
    ATTRS: lvalue
    CODE:
{
        if (UNLIKELY(self->incr_pos))
          croak ("incr_text can not be called when the incremental parser already started parsing");

        RETVAL = self->incr_text ? SvREFCNT_inc (self->incr_text) : &PL_sv_undef;
}
    OUTPUT:
        RETVAL

#else

SV *incr_text (JSON *self)
    CODE:
{
        if (UNLIKELY(self->incr_pos))
          croak ("incr_text can not be called when the incremental parser already started parsing");

        RETVAL = self->incr_text ? SvREFCNT_inc (self->incr_text) : &PL_sv_undef;
}
	OUTPUT:
        RETVAL

#endif

void incr_skip (JSON *self)
	CODE:
{
        if (self->incr_pos)
          {
            sv_chop (self->incr_text, SvPV_nolen (self->incr_text) + self->incr_pos);
            self->incr_pos  = 0;
            self->incr_nest = 0;
            self->incr_mode = 0;
          }
}

void incr_reset (JSON *self)
	CODE:
{
	SvREFCNT_dec (self->incr_text);
        self->incr_text = 0;
        self->incr_pos  = 0;
        self->incr_nest = 0;
        self->incr_mode = 0;
}

void DESTROY (JSON *self)
	CODE:
        SvREFCNT_dec (self->cb_sk_object);
        SvREFCNT_dec (self->cb_object);
        SvREFCNT_dec (self->cb_sort_by);
        SvREFCNT_dec (self->incr_text);

PROTOTYPES: ENABLE

void encode_json (SV *scalar)
	ALIAS:
        _to_json    = 0
        encode_json = F_UTF8
	PPCODE:
{
        JSON json;
        json_init (&json);
        json.flags |= ix;
        PUTBACK; scalar = encode_json (aTHX_ scalar, &json); SPAGAIN;
        XPUSHs (scalar);
}

void decode_json (SV *jsonstr, SV *allow_nonref = NULL)
	ALIAS:
        _from_json  = 0
        decode_json = F_UTF8
	PPCODE:
{
        JSON json;
        json_init (&json);
        json.flags |= ix;
        if (ix && allow_nonref)
          json.flags |= F_ALLOW_NONREF;
        PUTBACK; jsonstr = decode_json (aTHX_ jsonstr, &json, 0); SPAGAIN;
        XPUSHs (jsonstr);
}

