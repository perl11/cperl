/* ANSI-C code produced by gperf version 3.1 */
/* Command-line: gperf -m 2 --output-file=uniscr.c uniscr_c.in */
/* Computed positions: -k'1,3,5,8' */

#if !((' ' == 32) && ('!' == 33) && ('"' == 34) && ('#' == 35) \
      && ('%' == 37) && ('&' == 38) && ('\'' == 39) && ('(' == 40) \
      && (')' == 41) && ('*' == 42) && ('+' == 43) && (',' == 44) \
      && ('-' == 45) && ('.' == 46) && ('/' == 47) && ('0' == 48) \
      && ('1' == 49) && ('2' == 50) && ('3' == 51) && ('4' == 52) \
      && ('5' == 53) && ('6' == 54) && ('7' == 55) && ('8' == 56) \
      && ('9' == 57) && (':' == 58) && (';' == 59) && ('<' == 60) \
      && ('=' == 61) && ('>' == 62) && ('?' == 63) && ('A' == 65) \
      && ('B' == 66) && ('C' == 67) && ('D' == 68) && ('E' == 69) \
      && ('F' == 70) && ('G' == 71) && ('H' == 72) && ('I' == 73) \
      && ('J' == 74) && ('K' == 75) && ('L' == 76) && ('M' == 77) \
      && ('N' == 78) && ('O' == 79) && ('P' == 80) && ('Q' == 81) \
      && ('R' == 82) && ('S' == 83) && ('T' == 84) && ('U' == 85) \
      && ('V' == 86) && ('W' == 87) && ('X' == 88) && ('Y' == 89) \
      && ('Z' == 90) && ('[' == 91) && ('\\' == 92) && (']' == 93) \
      && ('^' == 94) && ('_' == 95) && ('a' == 97) && ('b' == 98) \
      && ('c' == 99) && ('d' == 100) && ('e' == 101) && ('f' == 102) \
      && ('g' == 103) && ('h' == 104) && ('i' == 105) && ('j' == 106) \
      && ('k' == 107) && ('l' == 108) && ('m' == 109) && ('n' == 110) \
      && ('o' == 111) && ('p' == 112) && ('q' == 113) && ('r' == 114) \
      && ('s' == 115) && ('t' == 116) && ('u' == 117) && ('v' == 118) \
      && ('w' == 119) && ('x' == 120) && ('y' == 121) && ('z' == 122) \
      && ('{' == 123) && ('|' == 124) && ('}' == 125) && ('~' == 126))
/* The character set is not based on ISO-646.  */
#error "gperf generated tables don't work with this execution character set. Please report a bug to <bug-gnu-gperf@gnu.org>."
#endif

#line 1 "uniscr_c.in"
/* -*- mode: c; c-basic-offset: 4; -*-

Copyright (C) 2017 cPanel Inc

Unicode perfect hash for { scripts => sv_yes }
tied to %VALID_SCRIPTS

gperf -m 2 --output-file=uniscr.c uniscr_c.in

=cut

*/

#define PERL_NO_GET_CONTEXT
#define PERL_EXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* Inside of tied XS object is a SVUV which is the iterator for the tied hash.
   The iterator is the offset of next stringpool string to read, unless the
   iterating is finished, then offset is beyond the end of stringpool and should
   not be used to deref (read) the string pool, until the next FIRSTKEY which
   resets the offset back to 0 or offset of 2nd string in string pool */

typedef UV CFGSELF; /* for typemap */
    
struct Perl_scripts_bool { U16 name; U16 len; const char *value; };

static const struct Perl_scripts_bool *
scripts_bool_lookup (register const char *str, register unsigned int len);

#line 41 "uniscr_c.in"
struct Perl_scripts_bool;

#define TOTAL_KEYWORDS 137
#define MIN_WORD_LENGTH 2
#define MAX_WORD_LENGTH 22
#define MIN_HASH_VALUE 2
#define MAX_HASH_VALUE 210
/* maximum key range = 209, duplicates = 0 */

#ifdef __GNUC__
__inline
#else
#ifdef __cplusplus
inline
#endif
#endif
static unsigned int
scripts_bool_hash (register const char *str, register unsigned int len)
{
  static const unsigned char asso_values[] =
    {
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211,   9,   0,  16,  40,  28,
      211,  64,  66,  24,  68,  47,  29,   8,  71,  44,
       16, 211,  61,  26,  19,  46, 102,  23, 211,   0,
      211, 211, 211, 211, 211,  51, 211,   3,  54,  55,
       36,   3,  55,  51,  36,  11,  48,  26,   6,   2,
        0,   1,  70, 211,  16,  64,  11,  18,  46,   3,
      211,  83, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211, 211, 211, 211, 211,
      211, 211, 211, 211, 211, 211
    };
  register int hval = len;

  switch (hval)
    {
      default:
        hval += asso_values[(unsigned char)str[7]];
      /*FALLTHROUGH*/
      case 7:
      case 6:
      case 5:
        hval += asso_values[(unsigned char)str[4]];
      /*FALLTHROUGH*/
      case 4:
      case 3:
        hval += asso_values[(unsigned char)str[2]];
      /*FALLTHROUGH*/
      case 2:
      case 1:
        hval += asso_values[(unsigned char)str[0]];
        break;
    }
  return hval;
}

struct stringpool_t
  {
    char stringpool_str2[sizeof("Yi")];
    char stringpool_str9[sizeof("Bamum")];
    char stringpool_str10[sizeof("Bengali")];
    char stringpool_str11[sizeof("Brahmi")];
    char stringpool_str12[sizeof("Mro")];
    char stringpool_str14[sizeof("Ahom")];
    char stringpool_str15[sizeof("Miao")];
    char stringpool_str16[sizeof("Braille")];
    char stringpool_str17[sizeof("Balinese")];
    char stringpool_str18[sizeof("Mandaic")];
    char stringpool_str19[sizeof("Armenian")];
    char stringpool_str20[sizeof("Myanmar")];
    char stringpool_str21[sizeof("Mongolian")];
    char stringpool_str22[sizeof("Adlam")];
    char stringpool_str23[sizeof("Cham")];
    char stringpool_str24[sizeof("Multani")];
    char stringpool_str25[sizeof("Common")];
    char stringpool_str26[sizeof("Thai")];
    char stringpool_str27[sizeof("Chakma")];
    char stringpool_str28[sizeof("Thaana")];
    char stringpool_str29[sizeof("Arabic")];
    char stringpool_str30[sizeof("Avestan")];
    char stringpool_str31[sizeof("Cherokee")];
    char stringpool_str32[sizeof("Tamil")];
    char stringpool_str33[sizeof("Lao")];
    char stringpool_str34[sizeof("Meetei_Mayek")];
    char stringpool_str35[sizeof("Mende_Kikakui")];
    char stringpool_str36[sizeof("Sinhala")];
    char stringpool_str37[sizeof("Anatolian_Hieroglyphs")];
    char stringpool_str38[sizeof("Phoenician")];
    char stringpool_str39[sizeof("Sharada")];
    char stringpool_str40[sizeof("Linear_B")];
    char stringpool_str41[sizeof("Carian")];
    char stringpool_str42[sizeof("Batak")];
    char stringpool_str43[sizeof("Tangut")];
    char stringpool_str45[sizeof("Latin")];
    char stringpool_str47[sizeof("Shavian")];
    char stringpool_str48[sizeof("Modi")];
    char stringpool_str49[sizeof("Linear_A")];
    char stringpool_str51[sizeof("Syriac")];
    char stringpool_str52[sizeof("Cuneiform")];
    char stringpool_str53[sizeof("Osmanya")];
    char stringpool_str54[sizeof("Limbu")];
    char stringpool_str55[sizeof("Osage")];
    char stringpool_str56[sizeof("Samaritan")];
    char stringpool_str57[sizeof("Kannada")];
    char stringpool_str58[sizeof("Caucasian_Albanian")];
    char stringpool_str59[sizeof("Tai_Tham")];
    char stringpool_str60[sizeof("Tirhuta")];
    char stringpool_str61[sizeof("Takri")];
    char stringpool_str62[sizeof("Buginese")];
    char stringpool_str63[sizeof("Oriya")];
    char stringpool_str64[sizeof("Bhaiksuki")];
    char stringpool_str65[sizeof("Tai_Le")];
    char stringpool_str66[sizeof("Warang_Citi")];
    char stringpool_str67[sizeof("Marchen")];
    char stringpool_str68[sizeof("Saurashtra")];
    char stringpool_str69[sizeof("Han")];
    char stringpool_str70[sizeof("Khmer")];
    char stringpool_str71[sizeof("Canadian_Aboriginal")];
    char stringpool_str72[sizeof("Kharoshthi")];
    char stringpool_str73[sizeof("Hanunoo")];
    char stringpool_str74[sizeof("Lydian")];
    char stringpool_str75[sizeof("Nko")];
    char stringpool_str76[sizeof("Manichaean")];
    char stringpool_str77[sizeof("Buhid")];
    char stringpool_str78[sizeof("Newa")];
    char stringpool_str79[sizeof("Bassa_Vah")];
    char stringpool_str80[sizeof("Khojki")];
    char stringpool_str81[sizeof("Bopomofo")];
    char stringpool_str82[sizeof("Telugu")];
    char stringpool_str83[sizeof("Tagalog")];
    char stringpool_str84[sizeof("Tagbanwa")];
    char stringpool_str85[sizeof("Grantha")];
    char stringpool_str86[sizeof("Hatran")];
    char stringpool_str87[sizeof("Ogham")];
    char stringpool_str88[sizeof("Inherited")];
    char stringpool_str89[sizeof("Glagolitic")];
    char stringpool_str90[sizeof("Hangul")];
    char stringpool_str91[sizeof("Tibetan")];
    char stringpool_str92[sizeof("Gothic")];
    char stringpool_str93[sizeof("Lycian")];
    char stringpool_str94[sizeof("Phags_Pa")];
    char stringpool_str95[sizeof("Katakana")];
    char stringpool_str96[sizeof("Psalter_Pahlavi")];
    char stringpool_str97[sizeof("Lisu")];
    char stringpool_str98[sizeof("Greek")];
    char stringpool_str99[sizeof("Devanagari")];
    char stringpool_str100[sizeof("Kaithi")];
    char stringpool_str101[sizeof("Cyrillic")];
    char stringpool_str102[sizeof("Sundanese")];
    char stringpool_str103[sizeof("Coptic")];
    char stringpool_str104[sizeof("Cypriot")];
    char stringpool_str105[sizeof("Siddham")];
    char stringpool_str106[sizeof("Meroitic_Cursive")];
    char stringpool_str107[sizeof("Sora_Sompeng")];
    char stringpool_str108[sizeof("Old_Permic")];
    char stringpool_str109[sizeof("Malayalam")];
    char stringpool_str110[sizeof("Meroitic_Hieroglyphs")];
    char stringpool_str111[sizeof("Mahajani")];
    char stringpool_str112[sizeof("Pau_Cin_Hau")];
    char stringpool_str113[sizeof("Khudawadi")];
    char stringpool_str114[sizeof("Palmyrene")];
    char stringpool_str115[sizeof("Rejang")];
    char stringpool_str116[sizeof("Vai")];
    char stringpool_str117[sizeof("Gurmukhi")];
    char stringpool_str118[sizeof("Tifinagh")];
    char stringpool_str119[sizeof("Duployan")];
    char stringpool_str120[sizeof("Old_Italic")];
    char stringpool_str121[sizeof("Runic")];
    char stringpool_str122[sizeof("SignWriting")];
    char stringpool_str123[sizeof("Ugaritic")];
    char stringpool_str124[sizeof("Georgian")];
    char stringpool_str125[sizeof("Javanese")];
    char stringpool_str126[sizeof("Syloti_Nagri")];
    char stringpool_str127[sizeof("Deseret")];
    char stringpool_str128[sizeof("Ethiopic")];
    char stringpool_str129[sizeof("Hebrew")];
    char stringpool_str132[sizeof("Imperial_Aramaic")];
    char stringpool_str133[sizeof("Pahawh_Hmong")];
    char stringpool_str134[sizeof("Old_South_Arabian")];
    char stringpool_str135[sizeof("Old_Turkic")];
    char stringpool_str136[sizeof("Inscriptional_Pahlavi")];
    char stringpool_str137[sizeof("Inscriptional_Parthian")];
    char stringpool_str141[sizeof("Lepcha")];
    char stringpool_str142[sizeof("Egyptian_Hieroglyphs")];
    char stringpool_str144[sizeof("Hiragana")];
    char stringpool_str147[sizeof("Gujarati")];
    char stringpool_str148[sizeof("Nabataean")];
    char stringpool_str150[sizeof("Ol_Chiki")];
    char stringpool_str151[sizeof("Tai_Viet")];
    char stringpool_str153[sizeof("Elbasan")];
    char stringpool_str155[sizeof("New_Tai_Lue")];
    char stringpool_str171[sizeof("Old_Persian")];
    char stringpool_str179[sizeof("Old_North_Arabian")];
    char stringpool_str185[sizeof("Kayah_Li")];
    char stringpool_str210[sizeof("Old_Hungarian")];
  };
static const struct stringpool_t stringpool_contents =
  {
    "Yi",
    "Bamum",
    "Bengali",
    "Brahmi",
    "Mro",
    "Ahom",
    "Miao",
    "Braille",
    "Balinese",
    "Mandaic",
    "Armenian",
    "Myanmar",
    "Mongolian",
    "Adlam",
    "Cham",
    "Multani",
    "Common",
    "Thai",
    "Chakma",
    "Thaana",
    "Arabic",
    "Avestan",
    "Cherokee",
    "Tamil",
    "Lao",
    "Meetei_Mayek",
    "Mende_Kikakui",
    "Sinhala",
    "Anatolian_Hieroglyphs",
    "Phoenician",
    "Sharada",
    "Linear_B",
    "Carian",
    "Batak",
    "Tangut",
    "Latin",
    "Shavian",
    "Modi",
    "Linear_A",
    "Syriac",
    "Cuneiform",
    "Osmanya",
    "Limbu",
    "Osage",
    "Samaritan",
    "Kannada",
    "Caucasian_Albanian",
    "Tai_Tham",
    "Tirhuta",
    "Takri",
    "Buginese",
    "Oriya",
    "Bhaiksuki",
    "Tai_Le",
    "Warang_Citi",
    "Marchen",
    "Saurashtra",
    "Han",
    "Khmer",
    "Canadian_Aboriginal",
    "Kharoshthi",
    "Hanunoo",
    "Lydian",
    "Nko",
    "Manichaean",
    "Buhid",
    "Newa",
    "Bassa_Vah",
    "Khojki",
    "Bopomofo",
    "Telugu",
    "Tagalog",
    "Tagbanwa",
    "Grantha",
    "Hatran",
    "Ogham",
    "Inherited",
    "Glagolitic",
    "Hangul",
    "Tibetan",
    "Gothic",
    "Lycian",
    "Phags_Pa",
    "Katakana",
    "Psalter_Pahlavi",
    "Lisu",
    "Greek",
    "Devanagari",
    "Kaithi",
    "Cyrillic",
    "Sundanese",
    "Coptic",
    "Cypriot",
    "Siddham",
    "Meroitic_Cursive",
    "Sora_Sompeng",
    "Old_Permic",
    "Malayalam",
    "Meroitic_Hieroglyphs",
    "Mahajani",
    "Pau_Cin_Hau",
    "Khudawadi",
    "Palmyrene",
    "Rejang",
    "Vai",
    "Gurmukhi",
    "Tifinagh",
    "Duployan",
    "Old_Italic",
    "Runic",
    "SignWriting",
    "Ugaritic",
    "Georgian",
    "Javanese",
    "Syloti_Nagri",
    "Deseret",
    "Ethiopic",
    "Hebrew",
    "Imperial_Aramaic",
    "Pahawh_Hmong",
    "Old_South_Arabian",
    "Old_Turkic",
    "Inscriptional_Pahlavi",
    "Inscriptional_Parthian",
    "Lepcha",
    "Egyptian_Hieroglyphs",
    "Hiragana",
    "Gujarati",
    "Nabataean",
    "Ol_Chiki",
    "Tai_Viet",
    "Elbasan",
    "New_Tai_Lue",
    "Old_Persian",
    "Old_North_Arabian",
    "Kayah_Li",
    "Old_Hungarian"
  };
#define stringpool ((const char *) &stringpool_contents)
#ifdef __GNUC__
__inline
#if defined __GNUC_STDC_INLINE__ || defined __GNUC_GNU_INLINE__
__attribute__ ((__gnu_inline__))
#endif
#endif
const struct Perl_scripts_bool *
scripts_bool_lookup (register const char *str, register unsigned int len)
{
  static const struct Perl_scripts_bool wordlist[] =
    {
      {-1}, {-1},
#line 180 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str2},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
#line 51 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str9},
#line 54 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str10},
#line 57 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str11},
#line 125 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str12},
      {-1},
#line 45 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str14},
#line 122 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str15},
#line 58 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str16},
#line 50 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str17},
#line 115 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str18},
#line 48 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str19},
#line 127 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str20},
#line 124 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str21},
#line 44 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str22},
#line 65 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str23},
#line 126 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str24},
#line 67 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str25},
#line 173 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str26},
#line 64 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str27},
#line 172 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str28},
#line 47 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str29},
#line 49 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str30},
#line 66 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str31},
#line 169 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str32},
#line 104 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str33},
#line 118 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str34},
#line 119 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str35},
#line 158 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str36},
#line 46 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str37},
#line 148 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str38},
#line 154 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str39},
#line 109 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str40},
#line 62 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str41},
#line 53 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str42},
#line 170 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str43},
      {-1},
#line 105 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str45},
      {-1},
#line 155 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str47},
#line 123 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str48},
#line 108 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str49},
      {-1},
#line 162 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str51},
#line 69 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str52},
#line 143 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str53},
#line 107 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str54},
#line 142 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str55},
#line 152 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str56},
#line 97 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str57},
#line 63 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str58},
#line 166 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str59},
#line 176 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str60},
#line 168 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str61},
#line 59 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str62},
#line 141 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str63},
#line 55 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str64},
#line 165 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str65},
#line 179 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str66},
#line 117 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str67},
#line 153 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str68},
#line 85 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str69},
#line 101 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str70},
#line 61 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str71},
#line 100 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str72},
#line 87 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str73},
#line 112 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str74},
#line 131 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str75},
#line 116 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str76},
#line 60 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str77},
#line 130 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str78},
#line 52 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str79},
#line 102 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str80},
#line 56 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str81},
#line 171 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str82},
#line 163 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str83},
#line 164 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str84},
#line 81 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str85},
#line 88 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str86},
#line 132 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str87},
#line 92 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str88},
#line 79 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str89},
#line 86 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str90},
#line 174 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str91},
#line 80 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str92},
#line 111 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str93},
#line 147 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str94},
#line 98 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str95},
#line 149 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str96},
#line 110 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str97},
#line 82 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str98},
#line 73 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str99},
#line 96 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str100},
#line 71 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str101},
#line 160 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str102},
#line 68 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str103},
#line 70 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str104},
#line 156 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str105},
#line 120 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str106},
#line 159 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str107},
#line 137 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str108},
#line 114 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str109},
#line 121 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str110},
#line 113 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str111},
#line 146 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str112},
#line 103 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str113},
#line 145 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str114},
#line 150 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str115},
#line 178 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str116},
#line 84 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str117},
#line 175 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str118},
#line 74 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str119},
#line 135 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str120},
#line 151 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str121},
#line 157 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str122},
#line 177 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str123},
#line 78 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str124},
#line 95 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str125},
#line 161 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str126},
#line 72 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str127},
#line 77 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str128},
#line 89 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str129},
      {-1}, {-1},
#line 91 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str132},
#line 144 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str133},
#line 139 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str134},
#line 140 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str135},
#line 93 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str136},
#line 94 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str137},
      {-1}, {-1}, {-1},
#line 106 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str141},
#line 75 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str142},
      {-1},
#line 90 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str144},
      {-1}, {-1},
#line 83 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str147},
#line 128 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str148},
      {-1},
#line 133 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str150},
#line 167 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str151},
      {-1},
#line 76 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str153},
      {-1},
#line 129 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str155},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
#line 138 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str171},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
#line 136 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str179},
      {-1}, {-1}, {-1}, {-1}, {-1},
#line 99 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str185},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
      {-1}, {-1}, {-1}, {-1}, {-1}, {-1},
#line 134 "uniscr_c.in"
      {(int)(long)&((struct stringpool_t *)0)->stringpool_str210}
    };

  if (len <= MAX_WORD_LENGTH && len >= MIN_WORD_LENGTH)
    {
      register int key = scripts_bool_hash (str, len);

      if (key <= MAX_HASH_VALUE && key >= 0)
        {
          register int o = wordlist[key].name;
          if (o >= 0)
            {
              register const char *s = o + stringpool;

              if (*str == *s && !strcmp (str + 1, s + 1))
                return &wordlist[key];
            }
        }
    }
  return 0;
}
#line 181 "uniscr_c.in"


MODULE = Unicode		PACKAGE = Unicode
PROTOTYPES: DISABLE

void
FETCH(self, key)
     SV* self
     SV* key
ALIAS:
     EXISTS = 1
PREINIT:
     const struct Perl_scripts_bool *c;
     SV * RETVAL;
PPCODE:
     SP++; /* make space for 1 returned SV* */
     PUTBACK; /* let some vars go out of liveness */
#if Size_t_size > INTSIZE
     if (SvCUR(key) > UINT_MAX)
         REYURN_UNDEF;
#endif
     c = scripts_lookup(SvPVX_const(key), (unsigned int)SvCUR(key));
     PERL_UNUSED_VAR(self);
     RETVAL = c ? PL_sv_yes : &PL_sv_undef;

     *SP = RETVAL;
     return; /* skip implicit PUTBACK, it was done earlier */

#you would think the prototype croak can be removed and replaced with ...
#but the check actually makes sure there is 1 SP slot available since the retval
#SV* winds up ontop of the incoming self arg
void
SCALAR(self)
    SV *self
CODE:
    PERL_UNUSED_VAR(self);
    /* MAX_HASH_VALUE is technically wrong, real array size is MAX_HASH_VALUE +1 */
    *SP = newSVpvn(STRINGIFY(TOTAL_KEYWORDS) "/" STRINGIFY(MAX_HASH_VALUE),
                   sizeof(STRINGIFY(TOTAL_KEYWORDS) "/" STRINGIFY(MAX_HASH_VALUE))-1);
    return; /* skip implicit PUTBACK, SP didnt move, 1 arg in means 1 arg out */

void
FIRSTKEY(self)
         UNISELF *self
PREINIT:
    /* Note: This is highly gperf dependent */
    const char *s = (const char *)stringpool;
    size_t len;
CODE:
    STATIC_ASSERT_STMT(sizeof(stringpool_contents) > 1); /* atleast 1 string */

    len = strlen(s);
    /* self is SVIV with offset (aka iterator) into stringpool */
    *self = len + 1; /* set to next string to read */
    /* overwrite UNISELF *self slot on stack */
    *SP = sv_2mortal(newSVpvn(s, len));
    return; /* skip implicit PUTBACK, 1 arg in, means 1 arg out, SP not moved*/

void
NEXTKEY(self, lastkey)
         UNISELF *self
         SV *lastkey
PREINIT:
    SV * RETVAL;
PPCODE:
    PERL_UNUSED_VAR(lastkey);
    SP++; /* make space for 1 returned SV* */
    PUTBACK; /* let some vars go out of liveness */

    /* bounds check to avoid running off the end of stringpool */
    if (*self < sizeof(stringpool_contents)) {
        const char * key = (const char*)stringpool+*self;
        size_t len = strlen(key);
        *self += len + 1;
        RETVAL = sv_2mortal(newSVpvn(key, len));
    }
    else
        RETVAL = &PL_sv_undef;
    *SP = RETVAL;
    return; /* skip implicit PUTBACK, it was done earlier */
     
BOOT:
{
  STATIC_ASSERT_STMT(sizeof(stringpool_contents) <= 1 << 15);
}
