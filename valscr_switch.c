#include "valscr.h"
#include <string.h>

long valscr_lookup(const char* s) {
    const unsigned int l = strlen(s);
    const unsigned char* su = (const unsigned char*)s;
    switch (l) {
      case 2: 
        return *(short*)su == (short)0x6959 /* Yi */ ? 136 : -1;
      case 3: 
        switch (su[0]) { /* Lao, Vai, Mro, Han, Nko */
          case 'H':
            if (*(short*)su == (short)0x6148 /* Han */
		&& *(&su[2]) == 'n') return 41;
            break;
          case 'L':
            if (*(short*)su == (short)0x614c /* Lao */
		&& *(&su[2]) == 'o') return 60;
            break;
          case 'M':
            if (*(short*)su == (short)0x724d /* Mro */
		&& *(&su[2]) == 'o') return 81;
            break;
          case 'N':
            if (*(short*)su == (short)0x6b4e /* Nko */
		&& *(&su[2]) == 'o') return 87;
            break;
          case 'V':
            if (*(short*)su == (short)0x6156 /* Vai */
		&& *(&su[2]) == 'i') return 134;
          default:
            return -1;
        }
        return -1;
      case 4: 
        switch (su[0]) { /* Modi, Lisu, Miao, Newa, Ahom, Thai, Cham */
          case 'A':
            if (*(int*)su == (int)0x6d6f6841 /* Ahom */) return 1;
            break;
          case 'C':
            if (*(int*)su == (int)0x6d616843 /* Cham */) return 21;
            break;
          case 'L':
            if (*(int*)su == (int)0x7573694c /* Lisu */) return 66;
            break;
          case 'M':
            if (*(int*)su == (int)0x69646f4d /* Modi */) return 79;
            if (*(int*)su == (int)0x6f61694d /* Miao */) return 78;
            break;
          case 'N':
            if (*(int*)su == (int)0x6177654e /* Newa */) return 86;
            break;
          case 'T':
            if (*(int*)su == (int)0x69616854 /* Thai */) return 129;
          default:
            return -1;
        }
        return -1;
      case 5: 
        switch (su[4]) { /* Khmer, Limbu, Osage, Adlam, Greek, Oriya, Runic, Batak, Latin, Ogham, Bamum, Buhid, Takri, Tamil */
          case 'a':
            if (*(int*)su == (int)0x7969724f /* Oriya */
		&& *(&su[4]) == 'a') return 97;
            break;
          case 'c':
            if (*(int*)su == (int)0x696e7552 /* Runic */
		&& *(&su[4]) == 'c') return 107;
            break;
          case 'd':
            if (*(int*)su == (int)0x69687542 /* Buhid */
		&& *(&su[4]) == 'd') return 16;
            break;
          case 'e':
            if (*(int*)su == (int)0x6761734f /* Osage */
		&& *(&su[4]) == 'e') return 98;
            break;
          case 'i':
            if (*(int*)su == (int)0x726b6154 /* Takri */
		&& *(&su[4]) == 'i') return 124;
            break;
          case 'k':
            if (*(int*)su == (int)0x65657247 /* Greek */
		&& *(&su[4]) == 'k') return 38;
            if (*(int*)su == (int)0x61746142 /* Batak */
		&& *(&su[4]) == 'k') return 9;
            break;
          case 'l':
            if (*(int*)su == (int)0x696d6154 /* Tamil */
		&& *(&su[4]) == 'l') return 125;
            break;
          case 'm':
            if (*(int*)su == (int)0x616c6441 /* Adlam */
		&& *(&su[4]) == 'm') return 0;
            if (*(int*)su == (int)0x6168674f /* Ogham */
		&& *(&su[4]) == 'm') return 88;
            if (*(int*)su == (int)0x756d6142 /* Bamum */
		&& *(&su[4]) == 'm') return 7;
            break;
          case 'n':
            if (*(int*)su == (int)0x6974614c /* Latin */
		&& *(&su[4]) == 'n') return 61;
            break;
          case 'r':
            if (*(int*)su == (int)0x656d684b /* Khmer */
		&& *(&su[4]) == 'r') return 57;
            break;
          case 'u':
            if (*(int*)su == (int)0x626d694c /* Limbu */
		&& *(&su[4]) == 'u') return 63;
          default:
            return -1;
        }
        return -1;
      case 6: 
        switch (su[2]) { /* Lycian, Hangul, Lydian, Brahmi, Common, Hebrew, Kaithi, Telugu, Rejang, Carian, Coptic, Lepcha, Tai_Le, Chakma, Gothic, Khojki, Thaana, Syriac, Tangut, Arabic, Hatran */
          default: /* split into 2 switches */
            switch (su[0]) { /* Brahmi, Chakma, Thaana, Arabic */
              case 'A':
                if (*(int*)su == (int)0x62617241 /* Arabic */
		&& *(short*)&su[4] == (short)0x6369 /* ic */) return 3;
                break;
              case 'B':
                if (*(int*)su == (int)0x68617242 /* Brahmi */
		&& *(short*)&su[4] == (short)0x696d /* mi */) return 13;
                break;
              case 'C':
                if (*(int*)su == (int)0x6b616843 /* Chakma */
		&& *(short*)&su[4] == (short)0x616d /* ma */) return 20;
                break;
              case 'T':
                if (*(int*)su == (int)0x61616854 /* Thaana */
		&& *(short*)&su[4] == (short)0x616e /* na */) return 128;
            }
            /* fallthru to other half */
            switch (su[2]) { /* Lycian, Hangul, Lydian, Common, Hebrew, Kaithi, Telugu, Rejang, Carian, Coptic, Lepcha, Tai_Le, Gothic, Khojki, Syriac, Tangut, Hatran */
              case 'b':
                if (*(int*)su == (int)0x72626548 /* Hebrew */
		&& *(short*)&su[4] == (short)0x7765 /* ew */) return 45;
                break;
              case 'c':
                if (*(int*)su == (int)0x6963794c /* Lycian */
		&& *(short*)&su[4] == (short)0x6e61 /* an */) return 67;
                break;
              case 'd':
                if (*(int*)su == (int)0x6964794c /* Lydian */
		&& *(short*)&su[4] == (short)0x6e61 /* an */) return 68;
                break;
              case 'i':
                if (*(int*)su == (int)0x7469614b /* Kaithi */
		&& *(short*)&su[4] == (short)0x6968 /* hi */) return 52;
                if (*(int*)su == (int)0x5f696154 /* Tai_Le */
		&& *(short*)&su[4] == (short)0x654c /* Le */) return 121;
                break;
              case 'j':
                if (*(int*)su == (int)0x616a6552 /* Rejang */
		&& *(short*)&su[4] == (short)0x676e /* ng */) return 106;
                break;
              case 'l':
                if (*(int*)su == (int)0x756c6554 /* Telugu */
		&& *(short*)&su[4] == (short)0x7567 /* gu */) return 127;
                break;
              case 'm':
                if (*(int*)su == (int)0x6d6d6f43 /* Common */
		&& *(short*)&su[4] == (short)0x6e6f /* on */) return 23;
                break;
              case 'n':
                if (*(int*)su == (int)0x676e6148 /* Hangul */
		&& *(short*)&su[4] == (short)0x6c75 /* ul */) return 42;
                if (*(int*)su == (int)0x676e6154 /* Tangut */
		&& *(short*)&su[4] == (short)0x7475 /* ut */) return 126;
                break;
              case 'o':
                if (*(int*)su == (int)0x6a6f684b /* Khojki */
		&& *(short*)&su[4] == (short)0x696b /* ki */) return 58;
                break;
              case 'p':
                if (*(int*)su == (int)0x74706f43 /* Coptic */
		&& *(short*)&su[4] == (short)0x6369 /* ic */) return 24;
                if (*(int*)su == (int)0x6370654c /* Lepcha */
		&& *(short*)&su[4] == (short)0x6168 /* ha */) return 62;
                break;
              case 'r':
                if (*(int*)su == (int)0x69726143 /* Carian */
		&& *(short*)&su[4] == (short)0x6e61 /* an */) return 18;
                if (*(int*)su == (int)0x69727953 /* Syriac */
		&& *(short*)&su[4] == (short)0x6361 /* ac */) return 118;
                break;
              case 't':
                if (*(int*)su == (int)0x68746f47 /* Gothic */
		&& *(short*)&su[4] == (short)0x6369 /* ic */) return 36;
                if (*(int*)su == (int)0x72746148 /* Hatran */
		&& *(short*)&su[4] == (short)0x6e61 /* an */) return 44;
              default:
                return -1;
            }
        }
        return -1;
      case 7: 
        switch (su[3]) { /* Deseret, Grantha, Multani, Myanmar, Sinhala, Braille, Cypriot, Bengali, Elbasan, Shavian, Marchen, Avestan, Osmanya, Tirhuta, Siddham, Tibetan, Hanunoo, Mandaic, Tagalog, Kannada, Sharada */
          case 'a':
            if (*(int*)su == (int)0x61626c45 /* Elbasan */
		&& *(short*)&su[4] == (short)0x6173 /* san */
		&& *(&su[6]) == 'n') return 32;
            if (*(int*)su == (int)0x616d734f /* Osmanya */
		&& *(short*)&su[4] == (short)0x796e /* nya */
		&& *(&su[6]) == 'a') return 99;
            if (*(int*)su == (int)0x61676154 /* Tagalog */
		&& *(short*)&su[4] == (short)0x6f6c /* log */
		&& *(&su[6]) == 'g') return 119;
            break;
          case 'c':
            if (*(int*)su == (int)0x6372614d /* Marchen */
		&& *(short*)&su[4] == (short)0x6568 /* hen */
		&& *(&su[6]) == 'n') return 73;
            break;
          case 'd':
            if (*(int*)su == (int)0x64646953 /* Siddham */
		&& *(short*)&su[4] == (short)0x6168 /* ham */
		&& *(&su[6]) == 'm') return 112;
            if (*(int*)su == (int)0x646e614d /* Mandaic */
		&& *(short*)&su[4] == (short)0x6961 /* aic */
		&& *(&su[6]) == 'c') return 71;
            break;
          case 'e':
            if (*(int*)su == (int)0x65736544 /* Deseret */
		&& *(short*)&su[4] == (short)0x6572 /* ret */
		&& *(&su[6]) == 't') return 28;
            if (*(int*)su == (int)0x65626954 /* Tibetan */
		&& *(short*)&su[4] == (short)0x6174 /* tan */
		&& *(&su[6]) == 'n') return 130;
            break;
          case 'g':
            if (*(int*)su == (int)0x676e6542 /* Bengali */
		&& *(short*)&su[4] == (short)0x6c61 /* ali */
		&& *(&su[6]) == 'i') return 10;
            break;
          case 'h':
            if (*(int*)su == (int)0x686e6953 /* Sinhala */
		&& *(short*)&su[4] == (short)0x6c61 /* ala */
		&& *(&su[6]) == 'a') return 114;
            if (*(int*)su == (int)0x68726954 /* Tirhuta */
		&& *(short*)&su[4] == (short)0x7475 /* uta */
		&& *(&su[6]) == 'a') return 132;
            break;
          case 'i':
            if (*(int*)su == (int)0x69617242 /* Braille */
		&& *(short*)&su[4] == (short)0x6c6c /* lle */
		&& *(&su[6]) == 'e') return 14;
            break;
          case 'n':
            if (*(int*)su == (int)0x6e617247 /* Grantha */
		&& *(short*)&su[4] == (short)0x6874 /* tha */
		&& *(&su[6]) == 'a') return 37;
            if (*(int*)su == (int)0x6e61794d /* Myanmar */
		&& *(short*)&su[4] == (short)0x616d /* mar */
		&& *(&su[6]) == 'r') return 83;
            if (*(int*)su == (int)0x6e6e614b /* Kannada */
		&& *(short*)&su[4] == (short)0x6461 /* ada */
		&& *(&su[6]) == 'a') return 53;
            break;
          case 'r':
            if (*(int*)su == (int)0x72707943 /* Cypriot */
		&& *(short*)&su[4] == (short)0x6f69 /* iot */
		&& *(&su[6]) == 't') return 26;
            if (*(int*)su == (int)0x72616853 /* Sharada */
		&& *(short*)&su[4] == (short)0x6461 /* ada */
		&& *(&su[6]) == 'a') return 110;
            break;
          case 's':
            if (*(int*)su == (int)0x73657641 /* Avestan */
		&& *(short*)&su[4] == (short)0x6174 /* tan */
		&& *(&su[6]) == 'n') return 5;
            break;
          case 't':
            if (*(int*)su == (int)0x746c754d /* Multani */
		&& *(short*)&su[4] == (short)0x6e61 /* ani */
		&& *(&su[6]) == 'i') return 82;
            break;
          case 'u':
            if (*(int*)su == (int)0x756e6148 /* Hanunoo */
		&& *(short*)&su[4] == (short)0x6f6e /* noo */
		&& *(&su[6]) == 'o') return 43;
            break;
          case 'v':
            if (*(int*)su == (int)0x76616853 /* Shavian */
		&& *(short*)&su[4] == (short)0x6169 /* ian */
		&& *(&su[6]) == 'n') return 111;
          default:
            return -1;
        }
        return -1;
      case 8: 
        switch (su[2]) { /* Ethiopic, Tifinagh, Armenian, Tai_Tham, Tagbanwa, Phags_Pa, Javanese, Bopomofo, Ol_Chiki, Hiragana, Balinese, Linear_B, Ugaritic, Cyrillic, Gujarati, Kayah_Li, Katakana, Buginese, Linear_A, Duployan, Tai_Viet, Georgian, Mahajani, Cherokee, Gurmukhi */
          case '_':
            if (*(unsigned long *)su == (unsigned long)0x696b6968435f6c4fULL /* Ol_Chiki */) return 89;
            break;
          case 'a':
            if (*(unsigned long *)su == (unsigned long)0x61505f7367616850ULL /* Phags_Pa */) return 103;
            if (*(unsigned long *)su == (unsigned long)0x6369746972616755ULL /* Ugaritic */) return 133;
            break;
          case 'e':
            if (*(unsigned long *)su == (unsigned long)0x65656b6f72656843ULL /* Cherokee */) return 22;
            break;
          case 'f':
            if (*(unsigned long *)su == (unsigned long)0x6867616e69666954ULL /* Tifinagh */) return 131;
            break;
          case 'g':
            if (*(unsigned long *)su == (unsigned long)0x61776e6162676154ULL /* Tagbanwa */) return 120;
            if (*(unsigned long *)su == (unsigned long)0x6573656e69677542ULL /* Buginese */) return 15;
            break;
          case 'h':
            if (*(unsigned long *)su == (unsigned long)0x6369706f69687445ULL /* Ethiopic */) return 33;
            if (*(unsigned long *)su == (unsigned long)0x696e616a6168614dULL /* Mahajani */) return 69;
            break;
          case 'i':
            if (*(unsigned long *)su == (unsigned long)0x6d6168545f696154ULL /* Tai_Tham */) return 122;
            if (*(unsigned long *)su == (unsigned long)0x746569565f696154ULL /* Tai_Viet */) return 123;
            break;
          case 'j':
            if (*(unsigned long *)su == (unsigned long)0x69746172616a7547ULL /* Gujarati */) return 39;
            break;
          case 'l':
            if (*(unsigned long *)su == (unsigned long)0x6573656e696c6142ULL /* Balinese */) return 6;
            break;
          case 'm':
            if (*(unsigned long *)su == (unsigned long)0x6e61696e656d7241ULL /* Armenian */) return 4;
            break;
          case 'n':
            if (*(unsigned long *)su == (unsigned long)0x425f7261656e694cULL /* Linear_B */) return 65;
            if (*(unsigned long *)su == (unsigned long)0x415f7261656e694cULL /* Linear_A */) return 64;
            break;
          case 'o':
            if (*(unsigned long *)su == (unsigned long)0x6e616967726f6547ULL /* Georgian */) return 34;
            break;
          case 'p':
            if (*(unsigned long *)su == (unsigned long)0x6f666f6d6f706f42ULL /* Bopomofo */) return 12;
            if (*(unsigned long *)su == (unsigned long)0x6e61796f6c707544ULL /* Duployan */) return 30;
            break;
          case 'r':
            if (*(unsigned long *)su == (unsigned long)0x616e616761726948ULL /* Hiragana */) return 46;
            if (*(unsigned long *)su == (unsigned long)0x63696c6c69727943ULL /* Cyrillic */) return 27;
            if (*(unsigned long *)su == (unsigned long)0x69686b756d727547ULL /* Gurmukhi */) return 40;
            break;
          case 't':
            if (*(unsigned long *)su == (unsigned long)0x616e616b6174614bULL /* Katakana */) return 54;
            break;
          case 'v':
            if (*(unsigned long *)su == (unsigned long)0x6573656e6176614aULL /* Javanese */) return 51;
            break;
          case 'y':
            if (*(unsigned long *)su == (unsigned long)0x694c5f686179614bULL /* Kayah_Li */) return 55;
          default:
            return -1;
        }
        return -1;
      case 9: 
        switch (su[5]) { /* Khudawadi, Malayalam, Inherited, Samaritan, Bhaiksuki, Cuneiform, Nabataean, Mongolian, Palmyrene, Bassa_Vah, Sundanese */
          case '_':
            if (*(unsigned long *)su == (unsigned long)0x61565f6173736142ULL /* Bassa_Vah */
		&& *(&su[8]) == 'h') return 8;
            break;
          case 'a':
            if (*(unsigned long *)su == (unsigned long)0x616c6179616c614dULL /* Malayalam */
		&& *(&su[8]) == 'm') return 70;
            if (*(unsigned long *)su == (unsigned long)0x616561746162614eULL /* Nabataean */
		&& *(&su[8]) == 'n') return 84;
            break;
          case 'f':
            if (*(unsigned long *)su == (unsigned long)0x726f6669656e7543ULL /* Cuneiform */
		&& *(&su[8]) == 'm') return 25;
            break;
          case 'i':
            if (*(unsigned long *)su == (unsigned long)0x6574697265686e49ULL /* Inherited */
		&& *(&su[8]) == 'd') return 48;
            if (*(unsigned long *)su == (unsigned long)0x61746972616d6153ULL /* Samaritan */
		&& *(&su[8]) == 'n') return 108;
            break;
          case 'l':
            if (*(unsigned long *)su == (unsigned long)0x61696c6f676e6f4dULL /* Mongolian */
		&& *(&su[8]) == 'n') return 80;
            break;
          case 'n':
            if (*(unsigned long *)su == (unsigned long)0x73656e61646e7553ULL /* Sundanese */
		&& *(&su[8]) == 'e') return 116;
            break;
          case 'r':
            if (*(unsigned long *)su == (unsigned long)0x6e6572796d6c6150ULL /* Palmyrene */
		&& *(&su[8]) == 'e') return 101;
            break;
          case 's':
            if (*(unsigned long *)su == (unsigned long)0x6b75736b69616842ULL /* Bhaiksuki */
		&& *(&su[8]) == 'i') return 11;
            break;
          case 'w':
            if (*(unsigned long *)su == (unsigned long)0x646177616475684bULL /* Khudawadi */
		&& *(&su[8]) == 'i') return 59;
          default:
            return -1;
        }
        return -1;
      case 10: 
        switch (su[5]) { /* Glagolitic, Manichaean, Old_Italic, Kharoshthi, Saurashtra, Devanagari, Phoenician, Old_Permic, Old_Turkic */
          case 'a':
            if (*(unsigned long *)su == (unsigned long)0x6167616e61766544ULL /* Devanagari */
		&& *(short*)&su[8] == (short)0x6972 /* ri */) return 29;
            break;
          case 'e':
            if (*(unsigned long *)su == (unsigned long)0x6d7265505f646c4fULL /* Old_Permic */
		&& *(short*)&su[8] == (short)0x6369 /* ic */) return 93;
            break;
          case 'h':
            if (*(unsigned long *)su == (unsigned long)0x65616863696e614dULL /* Manichaean */
		&& *(short*)&su[8] == (short)0x6e61 /* an */) return 72;
            break;
          case 'i':
            if (*(unsigned long *)su == (unsigned long)0x6963696e656f6850ULL /* Phoenician */
		&& *(short*)&su[8] == (short)0x6e61 /* an */) return 104;
            break;
          case 'l':
            if (*(unsigned long *)su == (unsigned long)0x74696c6f67616c47ULL /* Glagolitic */
		&& *(short*)&su[8] == (short)0x6369 /* ic */) return 35;
            break;
          case 's':
            if (*(unsigned long *)su == (unsigned long)0x7468736f7261684bULL /* Kharoshthi */
		&& *(short*)&su[8] == (short)0x6968 /* hi */) return 56;
            if (*(unsigned long *)su == (unsigned long)0x7468736172756153ULL /* Saurashtra */
		&& *(short*)&su[8] == (short)0x6172 /* ra */) return 109;
            break;
          case 't':
            if (*(unsigned long *)su == (unsigned long)0x6c6174495f646c4fULL /* Old_Italic */
		&& *(short*)&su[8] == (short)0x6369 /* ic */) return 91;
            break;
          case 'u':
            if (*(unsigned long *)su == (unsigned long)0x6b7275545f646c4fULL /* Old_Turkic */
		&& *(short*)&su[8] == (short)0x6369 /* ic */) return 96;
          default:
            return -1;
        }
        return -1;
      case 11: 
        switch (su[0]) { /* New_Tai_Lue, Pau_Cin_Hau, Old_Persian, SignWriting, Warang_Citi */
          case 'N':
            if (*(unsigned long *)su == (unsigned long)0x5f6961545f77654eULL /* New_Tai_Lue */
		&& *(short*)&su[8] == (short)0x754c /* Lue */
		&& *(&su[10]) == 'e') return 85;
            break;
          case 'O':
            if (*(unsigned long *)su == (unsigned long)0x737265505f646c4fULL /* Old_Persian */
		&& *(short*)&su[8] == (short)0x6169 /* ian */
		&& *(&su[10]) == 'n') return 94;
            break;
          case 'P':
            if (*(unsigned long *)su == (unsigned long)0x5f6e69435f756150ULL /* Pau_Cin_Hau */
		&& *(short*)&su[8] == (short)0x6148 /* Hau */
		&& *(&su[10]) == 'u') return 102;
            break;
          case 'S':
            if (*(unsigned long *)su == (unsigned long)0x746972576e676953ULL /* SignWriting */
		&& *(short*)&su[8] == (short)0x6e69 /* ing */
		&& *(&su[10]) == 'g') return 113;
            break;
          case 'W':
            if (*(unsigned long *)su == (unsigned long)0x435f676e61726157ULL /* Warang_Citi */
		&& *(short*)&su[8] == (short)0x7469 /* iti */
		&& *(&su[10]) == 'i') return 135;
          default:
            return -1;
        }
        return -1;
      case 12: 
        switch (su[1]) { /* Pahawh_Hmong, Sora_Sompeng, Meetei_Mayek, Syloti_Nagri */
          case 'a':
            if (*(unsigned long *)su == (unsigned long)0x485f687761686150ULL /* Pahawh_Hmong */
		&& *(int*)&su[8] == (int)0x676e6f6d /* mong */) return 100;
            break;
          case 'e':
            if (*(unsigned long *)su == (unsigned long)0x4d5f69657465654dULL /* Meetei_Mayek */
		&& *(int*)&su[8] == (int)0x6b657961 /* ayek */) return 74;
            break;
          case 'o':
            if (*(unsigned long *)su == (unsigned long)0x6d6f535f61726f53ULL /* Sora_Sompeng */
		&& *(int*)&su[8] == (int)0x676e6570 /* peng */) return 115;
            break;
          case 'y':
            if (*(unsigned long *)su == (unsigned long)0x4e5f69746f6c7953ULL /* Syloti_Nagri */
		&& *(int*)&su[8] == (int)0x69726761 /* agri */) return 117;
          default:
            return -1;
        }
        return -1;
      case 13: 
        switch (su[0]) { /* Old_Hungarian, Mende_Kikakui */
          case 'M':
            if (*(unsigned long *)su == (unsigned long)0x694b5f65646e654dULL /* Mende_Kikakui */
		&& *(int*)&su[8] == (int)0x756b616b /* kakui */
		&& *(&su[12]) == 'i') return 75;
            break;
          case 'O':
            if (*(unsigned long *)su == (unsigned long)0x676e75485f646c4fULL /* Old_Hungarian */
		&& *(int*)&su[8] == (int)0x61697261 /* arian */
		&& *(&su[12]) == 'n') return 90;
          default:
            return -1;
        }
        return -1;
      case 15: 
        return *(unsigned long *)su == (unsigned long)0x5f7265746c617350ULL /* Psalter_Pahlavi */
		&& *(int*)&su[8] == (int)0x6c686150 /* Pahlavi */
		&& *(short*)&su[12] == (short)0x7661 /* avi */
		&& *(&su[14]) == 'i' ? 105 : -1;
      case 16: 
        switch (su[0]) { /* Meroitic_Cursive, Imperial_Aramaic */
          case 'I':
            if (!memcmp(su, "Imperial_Aramaic", 16)) return 47;
            break;
          case 'M':
            if (!memcmp(su, "Meroitic_Cursive", 16)) return 76;
          default:
            return -1;
        }
        return -1;
      case 17: 
        switch (su[4]) { /* Old_South_Arabian, Old_North_Arabian */
          case 'N':
            if (!memcmp(su, "Old_North_Arabian", 16)
		&& *(&su[16]) == 'n') return 92;
            break;
          case 'S':
            if (!memcmp(su, "Old_South_Arabian", 16)
		&& *(&su[16]) == 'n') return 95;
          default:
            return -1;
        }
        return -1;
      case 18: 
        return !memcmp(su, "Caucasian_Albanian", 16)
		&& *(short*)&su[16] == (short)0x6e61 /* an */ ? 19 : -1;
      case 19: 
        return !memcmp(su, "Canadian_Aboriginal", 16)
		&& *(short*)&su[16] == (short)0x616e /* nal */
		&& *(&su[18]) == 'l' ? 17 : -1;
      case 20: 
        switch (su[0]) { /* Meroitic_Hieroglyphs, Egyptian_Hieroglyphs */
          case 'E':
            if (!memcmp(su, "Egyptian_Hieroglyphs", 16)
		&& *(int*)&su[16] == (int)0x73687079 /* yphs */) return 31;
            break;
          case 'M':
            if (!memcmp(su, "Meroitic_Hieroglyphs", 16)
		&& *(int*)&su[16] == (int)0x73687079 /* yphs */) return 77;
          default:
            return -1;
        }
        return -1;
      case 21: 
        switch (su[0]) { /* Anatolian_Hieroglyphs, Inscriptional_Pahlavi */
          case 'A':
            if (!memcmp(su, "Anatolian_Hieroglyphs", 16)
		&& *(int*)&su[16] == (int)0x6870796c /* lyphs */
		&& *(&su[20]) == 's') return 2;
            break;
          case 'I':
            if (!memcmp(su, "Inscriptional_Pahlavi", 16)
		&& *(int*)&su[16] == (int)0x76616c68 /* hlavi */
		&& *(&su[20]) == 'i') return 49;
          default:
            return -1;
        }
        return -1;
      case 22: 
        return !memcmp(su, "Inscriptional_Parthian", 16)
		&& *(int*)&su[16] == (int)0x69687472 /* rthian */
		&& *(short*)&su[20] == (short)0x6e61 /* an */ ? 50 : -1;
    }
    return -1;
}
