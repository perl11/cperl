/* various hash functions
 *--------------------------------------------------------------------------------------
 * The "hash seed" feature was added in Perl 5.8.1 to perturb the results
 * to avoid "algorithmic complexity attacks".
 *
 * On cperl hash randomisation is off, cperl counts collisions instead.
 * Else if USE_HASH_SEED is defined, hash randomisation is done by default.
 * (see also perl.c:perl_parse() and S_init_tls_and_interp() and util.c:get_hash_seed())
 */

#ifndef PERL_SEEN_HV_FUNC_H /* compile once */
#define PERL_SEEN_HV_FUNC_H

#ifdef HAS_QUAD
#define CAN64BITHASH
#endif

/* double hashing with those 2 */
#define PERL_HASH_FUNC_FNV1A
#define PERL_HASH_FUNC_DJB2

#define PERL_HASH_FUNC "FNV1A"
#define PERL_HASH_SEED_BYTES 4
#define PERL_HASH_WITH_SEED(seed,hash,str,len) \
    (hash)= S_perl_hash_fnv1a((seed),(U8*)(str),(len))

#ifndef PERL_HASH_SEED
#   if defined(USE_HASH_SEED)
#       define PERL_HASH_SEED PL_hash_seed
#   elif PERL_HASH_SEED_BYTES == 4
#       define PERL_HASH_SEED ((const U8 *)"PeRl")
#   elif PERL_HASH_SEED_BYTES == 8
#       define PERL_HASH_SEED ((const U8 *)"PeRlHaSh")
#   elif PERL_HASH_SEED_BYTES == 16
#       define PERL_HASH_SEED ((const U8 *)"PeRlHaShhAcKpErl")
#   else
#       error "No PERL_HASH_SEED definition for " PERL_HASH_FUNC
#   endif
#endif

#define PERL_HASH(hash,str,len) PERL_HASH_WITH_SEED(PERL_HASH_SEED,hash,str,len)

#include <assert.h>

/* From khash:
   Use quadratic probing. When the capacity is power of 2, stepping function
   i*(i+1)/2 guarantees to traverse each bucket. It is better than double
   hashing on cache performance and is more robust than linear probing.

   In theory, double hashing should be more robust than quadratic probing.
   However, my implementation is probably not for large hash tables, because
   the second hash function is closely tied to the first hash function,
   which reduce the effectiveness of double hashing.

   Reference: http://research.cs.vt.edu/AVresearch/hashing/quadratic.php
*/

PERL_STATIC_INLINE U32
S_perl_hash_fnv1a(const unsigned char * const seed,
                  const unsigned char *str, const STRLEN len) {
    const unsigned char * const end = (const unsigned char *)str + len;
    U32 hash = 0x811C9DC5 + *((U32*)seed); /* maybe also get rid of seed */
    while (str < end) {
        hash ^= *str++;
        hash *= 16777619;
    }
    return hash;
}

PERL_STATIC_INLINE U32
S_perl_hash_djb2(const unsigned char * const seed, const unsigned char *str, const STRLEN len) {
    const unsigned char * const end = (const unsigned char *)str + len;
    U32 hash = *((const U32*)seed) + (U32)len;
    assert(hash);
    while (str < end) {
        hash = ((hash << 5) + hash) + *str;
        str++;
    }
    return hash;
}

/* legacy - only mod_perl should be doing this. */
#ifdef PERL_HASH_INTERNAL_ACCESS
#define PERL_HASH_INTERNAL(hash,str,len) PERL_HASH(hash,str,len)
#endif

#endif /*compile once*/

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
