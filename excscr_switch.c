#include "excscr.h"
#include <string.h>

long excscr_lookup(const char* s) {
    const unsigned int l = strlen(s);
    const unsigned char* su = (const unsigned char*)s;
    switch (l) {
      case 3: 
        switch (su[0]) { /* Nko, Mro, Vai */
          case 'M':
            if (*(short*)su == (short)0x724d /* Mro */
		&& *(&su[2]) == 'o') return 56;
            break;
          case 'N':
            if (*(short*)su == (short)0x6b4e /* Nko */
		&& *(&su[2]) == 'o') return 60;
            break;
          case 'V':
            if (*(short*)su == (short)0x6156 /* Vai */
		&& *(&su[2]) == 'i') return 101;
          default:
            return -1;
        }
        return -1;
      case 4: 
        switch (su[0]) { /* Cham, Modi, Lisu, Ahom */
          case 'A':
            if (*(int*)su == (int)0x6d6f6841 /* Ahom */) return 2;
            break;
          case 'C':
            if (*(int*)su == (int)0x6d616843 /* Cham */) return 16;
            break;
          case 'L':
            if (*(int*)su == (int)0x7573694c /* Lisu */) return 45;
            break;
          case 'M':
            if (*(int*)su == (int)0x69646f4d /* Modi */) return 55;
          default:
            return -1;
        }
        return -1;
      case 5: 
        switch (su[0]) { /* Runic, Limbu, Greek, Ogham, Bamum, Batak, Takri, Buhid */
          case 'B':
            if (*(int*)su == (int)0x756d6142 /* Bamum */
		&& *(&su[4]) == 'm') return 6;
            if (*(int*)su == (int)0x61746142 /* Batak */
		&& *(&su[4]) == 'k') return 8;
            if (*(int*)su == (int)0x69687542 /* Buhid */
		&& *(&su[4]) == 'd') return 12;
            break;
          case 'G':
            if (*(int*)su == (int)0x65657247 /* Greek */
		&& *(&su[4]) == 'k') return 1;
            break;
          case 'L':
            if (*(int*)su == (int)0x626d694c /* Limbu */
		&& *(&su[4]) == 'u') return 42;
            break;
          case 'O':
            if (*(int*)su == (int)0x6168674f /* Ogham */
		&& *(&su[4]) == 'm') return 61;
            break;
          case 'R':
            if (*(int*)su == (int)0x696e7552 /* Runic */
		&& *(&su[4]) == 'c') return 82;
            break;
          case 'T':
            if (*(int*)su == (int)0x726b6154 /* Takri */
		&& *(&su[4]) == 'i') return 98;
          default:
            return -1;
        }
        return -1;
      case 6: 
        switch (su[2]) { /* Chakma, Lydian, Carian, Brahmi, Rejang, Gothic, Khojki, Hatran, Tai_Le, Coptic, Kaithi, Common, Lycian, Lepcha, Syriac */
          case 'a':
            if (*(int*)su == (int)0x6b616843 /* Chakma */
		&& *(short*)&su[4] == (short)0x616d /* ma */) return 15;
            if (*(int*)su == (int)0x68617242 /* Brahmi */
		&& *(short*)&su[4] == (short)0x696d /* mi */) return 9;
            break;
          case 'c':
            if (*(int*)su == (int)0x6963794c /* Lycian */
		&& *(short*)&su[4] == (short)0x6e61 /* an */) return 46;
            break;
          case 'd':
            if (*(int*)su == (int)0x6964794c /* Lydian */
		&& *(short*)&su[4] == (short)0x6e61 /* an */) return 47;
            break;
          case 'i':
            if (*(int*)su == (int)0x5f696154 /* Tai_Le */
		&& *(short*)&su[4] == (short)0x654c /* Le */) return 95;
            if (*(int*)su == (int)0x7469614b /* Kaithi */
		&& *(short*)&su[4] == (short)0x6968 /* hi */) return 36;
            break;
          case 'j':
            if (*(int*)su == (int)0x616a6552 /* Rejang */
		&& *(short*)&su[4] == (short)0x676e /* ng */) return 81;
            break;
          case 'm':
            if (*(int*)su == (int)0x6d6d6f43 /* Common */
		&& *(short*)&su[4] == (short)0x6e6f /* on */) return 18;
            break;
          case 'o':
            if (*(int*)su == (int)0x6a6f684b /* Khojki */
		&& *(short*)&su[4] == (short)0x696b /* ki */) return 39;
            break;
          case 'p':
            if (*(int*)su == (int)0x74706f43 /* Coptic */
		&& *(short*)&su[4] == (short)0x6369 /* ic */) return 19;
            if (*(int*)su == (int)0x6370654c /* Lepcha */
		&& *(short*)&su[4] == (short)0x6168 /* ha */) return 41;
            break;
          case 'r':
            if (*(int*)su == (int)0x69726143 /* Carian */
		&& *(short*)&su[4] == (short)0x6e61 /* an */) return 13;
            if (*(int*)su == (int)0x69727953 /* Syriac */
		&& *(short*)&su[4] == (short)0x6361 /* ac */) return 92;
            break;
          case 't':
            if (*(int*)su == (int)0x68746f47 /* Gothic */
		&& *(short*)&su[4] == (short)0x6369 /* ic */) return 27;
            if (*(int*)su == (int)0x72746148 /* Hatran */
		&& *(short*)&su[4] == (short)0x6e61 /* an */) return 30;
          default:
            return -1;
        }
        return -1;
      case 7: 
        switch (su[0]) { /* Sharada, Multani, Grantha, Elbasan, Tirhuta, Mandaic, Shavian, Deseret, Braille, Cypriot, Tagalog, Siddham, Avestan, Osmanya, Hanunoo */
          case 'A':
            if (*(int*)su == (int)0x73657641 /* Avestan */
		&& *(short*)&su[4] == (short)0x6174 /* tan */
		&& *(&su[6]) == 'n') return 4;
            break;
          case 'B':
            if (*(int*)su == (int)0x69617242 /* Braille */
		&& *(short*)&su[4] == (short)0x6c6c /* lle */
		&& *(&su[6]) == 'e') return 10;
            break;
          case 'C':
            if (*(int*)su == (int)0x72707943 /* Cypriot */
		&& *(short*)&su[4] == (short)0x6f69 /* iot */
		&& *(&su[6]) == 't') return 21;
            break;
          case 'D':
            if (*(int*)su == (int)0x65736544 /* Deseret */
		&& *(short*)&su[4] == (short)0x6572 /* ret */
		&& *(&su[6]) == 't') return 22;
            break;
          case 'E':
            if (*(int*)su == (int)0x61626c45 /* Elbasan */
		&& *(short*)&su[4] == (short)0x6173 /* san */
		&& *(&su[6]) == 'n') return 25;
            break;
          case 'G':
            if (*(int*)su == (int)0x6e617247 /* Grantha */
		&& *(short*)&su[4] == (short)0x6874 /* tha */
		&& *(&su[6]) == 'a') return 28;
            break;
          case 'H':
            if (*(int*)su == (int)0x756e6148 /* Hanunoo */
		&& *(short*)&su[4] == (short)0x6f6e /* noo */
		&& *(&su[6]) == 'o') return 29;
            break;
          case 'M':
            if (*(int*)su == (int)0x746c754d /* Multani */
		&& *(short*)&su[4] == (short)0x6e61 /* ani */
		&& *(&su[6]) == 'i') return 57;
            if (*(int*)su == (int)0x646e614d /* Mandaic */
		&& *(short*)&su[4] == (short)0x6961 /* aic */
		&& *(&su[6]) == 'c') return 49;
            break;
          case 'O':
            if (*(int*)su == (int)0x616d734f /* Osmanya */
		&& *(short*)&su[4] == (short)0x796e /* nya */
		&& *(&su[6]) == 'a') return 70;
            break;
          case 'S':
            if (*(int*)su == (int)0x72616853 /* Sharada */
		&& *(short*)&su[4] == (short)0x6461 /* ada */
		&& *(&su[6]) == 'a') return 85;
            if (*(int*)su == (int)0x76616853 /* Shavian */
		&& *(short*)&su[4] == (short)0x6169 /* ian */
		&& *(&su[6]) == 'n') return 86;
            if (*(int*)su == (int)0x64646953 /* Siddham */
		&& *(short*)&su[4] == (short)0x6168 /* ham */
		&& *(&su[6]) == 'm') return 87;
            break;
          case 'T':
            if (*(int*)su == (int)0x68726954 /* Tirhuta */
		&& *(short*)&su[4] == (short)0x7475 /* uta */
		&& *(&su[6]) == 'a') return 99;
            if (*(int*)su == (int)0x61676154 /* Tagalog */
		&& *(short*)&su[4] == (short)0x6f6c /* log */
		&& *(&su[6]) == 'g') return 93;
          default:
            return -1;
        }
        return -1;
      case 8: 
        switch (su[2]) { /* Balinese, Linear_B, Tai_Viet, Linear_A, Cyrillic, Mahajani, Javanese, Tai_Tham, Cherokee, Tagbanwa, Ugaritic, Phags_Pa, Buginese, Ol_Chiki, Duployan, Kayah_Li */
          case '_':
            if (*(unsigned long *)su == (unsigned long)0x696b6968435f6c4fULL /* Ol_Chiki */) return 62;
            break;
          case 'a':
            if (*(unsigned long *)su == (unsigned long)0x6369746972616755ULL /* Ugaritic */) return 100;
            if (*(unsigned long *)su == (unsigned long)0x61505f7367616850ULL /* Phags_Pa */) return 78;
            break;
          case 'e':
            if (*(unsigned long *)su == (unsigned long)0x65656b6f72656843ULL /* Cherokee */) return 17;
            break;
          case 'g':
            if (*(unsigned long *)su == (unsigned long)0x61776e6162676154ULL /* Tagbanwa */) return 94;
            if (*(unsigned long *)su == (unsigned long)0x6573656e69677542ULL /* Buginese */) return 11;
            break;
          case 'h':
            if (*(unsigned long *)su == (unsigned long)0x696e616a6168614dULL /* Mahajani */) return 48;
            break;
          case 'i':
            if (*(unsigned long *)su == (unsigned long)0x746569565f696154ULL /* Tai_Viet */) return 97;
            if (*(unsigned long *)su == (unsigned long)0x6d6168545f696154ULL /* Tai_Tham */) return 96;
            break;
          case 'l':
            if (*(unsigned long *)su == (unsigned long)0x6573656e696c6142ULL /* Balinese */) return 5;
            break;
          case 'n':
            if (*(unsigned long *)su == (unsigned long)0x425f7261656e694cULL /* Linear_B */) return 44;
            if (*(unsigned long *)su == (unsigned long)0x415f7261656e694cULL /* Linear_A */) return 43;
            break;
          case 'p':
            if (*(unsigned long *)su == (unsigned long)0x6e61796f6c707544ULL /* Duployan */) return 23;
            break;
          case 'r':
            if (*(unsigned long *)su == (unsigned long)0x63696c6c69727943ULL /* Cyrillic */) return 0;
            break;
          case 'v':
            if (*(unsigned long *)su == (unsigned long)0x6573656e6176614aULL /* Javanese */) return 35;
            break;
          case 'y':
            if (*(unsigned long *)su == (unsigned long)0x694c5f686179614bULL /* Kayah_Li */) return 37;
          default:
            return -1;
        }
        return -1;
      case 9: 
        switch (su[0]) { /* Nabataean, Bassa_Vah, Inherited, Palmyrene, Khudawadi, Cuneiform, Sundanese, Samaritan */
          case 'B':
            if (*(unsigned long *)su == (unsigned long)0x61565f6173736142ULL /* Bassa_Vah */
		&& *(&su[8]) == 'h') return 7;
            break;
          case 'C':
            if (*(unsigned long *)su == (unsigned long)0x726f6669656e7543ULL /* Cuneiform */
		&& *(&su[8]) == 'm') return 20;
            break;
          case 'I':
            if (*(unsigned long *)su == (unsigned long)0x6574697265686e49ULL /* Inherited */
		&& *(&su[8]) == 'd') return 32;
            break;
          case 'K':
            if (*(unsigned long *)su == (unsigned long)0x646177616475684bULL /* Khudawadi */
		&& *(&su[8]) == 'i') return 40;
            break;
          case 'N':
            if (*(unsigned long *)su == (unsigned long)0x616561746162614eULL /* Nabataean */
		&& *(&su[8]) == 'n') return 58;
            break;
          case 'P':
            if (*(unsigned long *)su == (unsigned long)0x6e6572796d6c6150ULL /* Palmyrene */
		&& *(&su[8]) == 'e') return 72;
            break;
          case 'S':
            if (*(unsigned long *)su == (unsigned long)0x73656e61646e7553ULL /* Sundanese */
		&& *(&su[8]) == 'e') return 90;
            if (*(unsigned long *)su == (unsigned long)0x61746972616d6153ULL /* Samaritan */
		&& *(&su[8]) == 'n') return 83;
          default:
            return -1;
        }
        return -1;
      case 10: 
        switch (su[4]) { /* Old_Permic, Manichaean, Old_Turkic, Phoenician, Kharoshthi, Old_Italic, Glagolitic, Saurashtra */
          case 'I':
            if (*(unsigned long *)su == (unsigned long)0x6c6174495f646c4fULL /* Old_Italic */
		&& *(short*)&su[8] == (short)0x6369 /* ic */) return 64;
            break;
          case 'P':
            if (*(unsigned long *)su == (unsigned long)0x6d7265505f646c4fULL /* Old_Permic */
		&& *(short*)&su[8] == (short)0x6369 /* ic */) return 66;
            break;
          case 'T':
            if (*(unsigned long *)su == (unsigned long)0x6b7275545f646c4fULL /* Old_Turkic */
		&& *(short*)&su[8] == (short)0x6369 /* ic */) return 69;
            break;
          case 'a':
            if (*(unsigned long *)su == (unsigned long)0x7468736172756153ULL /* Saurashtra */
		&& *(short*)&su[8] == (short)0x6172 /* ra */) return 84;
            break;
          case 'c':
            if (*(unsigned long *)su == (unsigned long)0x65616863696e614dULL /* Manichaean */
		&& *(short*)&su[8] == (short)0x6e61 /* an */) return 50;
            break;
          case 'n':
            if (*(unsigned long *)su == (unsigned long)0x6963696e656f6850ULL /* Phoenician */
		&& *(short*)&su[8] == (short)0x6e61 /* an */) return 79;
            break;
          case 'o':
            if (*(unsigned long *)su == (unsigned long)0x7468736f7261684bULL /* Kharoshthi */
		&& *(short*)&su[8] == (short)0x6968 /* hi */) return 38;
            if (*(unsigned long *)su == (unsigned long)0x74696c6f67616c47ULL /* Glagolitic */
		&& *(short*)&su[8] == (short)0x6369 /* ic */) return 26;
          default:
            return -1;
        }
        return -1;
      case 11: 
        switch (su[0]) { /* New_Tai_Lue, Warang_Citi, SignWriting, Pau_Cin_Hau, Old_Persian */
          case 'N':
            if (*(unsigned long *)su == (unsigned long)0x5f6961545f77654eULL /* New_Tai_Lue */
		&& *(short*)&su[8] == (short)0x754c /* Lue */
		&& *(&su[10]) == 'e') return 59;
            break;
          case 'O':
            if (*(unsigned long *)su == (unsigned long)0x737265505f646c4fULL /* Old_Persian */
		&& *(short*)&su[8] == (short)0x6169 /* ian */
		&& *(&su[10]) == 'n') return 67;
            break;
          case 'P':
            if (*(unsigned long *)su == (unsigned long)0x5f6e69435f756150ULL /* Pau_Cin_Hau */
		&& *(short*)&su[8] == (short)0x6148 /* Hau */
		&& *(&su[10]) == 'u') return 77;
            break;
          case 'S':
            if (*(unsigned long *)su == (unsigned long)0x746972576e676953ULL /* SignWriting */
		&& *(short*)&su[8] == (short)0x6e69 /* ing */
		&& *(&su[10]) == 'g') return 88;
            break;
          case 'W':
            if (*(unsigned long *)su == (unsigned long)0x435f676e61726157ULL /* Warang_Citi */
		&& *(short*)&su[8] == (short)0x7469 /* iti */
		&& *(&su[10]) == 'i') return 102;
          default:
            return -1;
        }
        return -1;
      case 12: 
        switch (su[1]) { /* Pahawh_Hmong, Sora_Sompeng, Syloti_Nagri, Meetei_Mayek */
          case 'a':
            if (*(unsigned long *)su == (unsigned long)0x485f687761686150ULL /* Pahawh_Hmong */
		&& *(int*)&su[8] == (int)0x676e6f6d /* mong */) return 71;
            break;
          case 'e':
            if (*(unsigned long *)su == (unsigned long)0x4d5f69657465654dULL /* Meetei_Mayek */
		&& *(int*)&su[8] == (int)0x6b657961 /* ayek */) return 51;
            break;
          case 'o':
            if (*(unsigned long *)su == (unsigned long)0x6d6f535f61726f53ULL /* Sora_Sompeng */
		&& *(int*)&su[8] == (int)0x676e6570 /* peng */) return 89;
            break;
          case 'y':
            if (*(unsigned long *)su == (unsigned long)0x4e5f69746f6c7953ULL /* Syloti_Nagri */
		&& *(int*)&su[8] == (int)0x69726761 /* agri */) return 91;
          default:
            return -1;
        }
        return -1;
      case 13: 
        switch (su[0]) { /* Old_Hungarian, Mende_Kikakui */
          case 'M':
            if (*(unsigned long *)su == (unsigned long)0x694b5f65646e654dULL /* Mende_Kikakui */
		&& *(int*)&su[8] == (int)0x756b616b /* kakui */
		&& *(&su[12]) == 'i') return 52;
            break;
          case 'O':
            if (*(unsigned long *)su == (unsigned long)0x676e75485f646c4fULL /* Old_Hungarian */
		&& *(int*)&su[8] == (int)0x61697261 /* arian */
		&& *(&su[12]) == 'n') return 63;
          default:
            return -1;
        }
        return -1;
      case 15: 
        return *(unsigned long *)su == (unsigned long)0x5f7265746c617350ULL /* Psalter_Pahlavi */
		&& *(int*)&su[8] == (int)0x6c686150 /* Pahlavi */
		&& *(short*)&su[12] == (short)0x7661 /* avi */
		&& *(&su[14]) == 'i' ? 80 : -1;
      case 16: 
        switch (su[0]) { /* Meroitic_Cursive, Imperial_Aramaic */
          case 'I':
            if (!memcmp(su, "Imperial_Aramaic", 16)) return 31;
            break;
          case 'M':
            if (!memcmp(su, "Meroitic_Cursive", 16)) return 53;
          default:
            return -1;
        }
        return -1;
      case 17: 
        switch (su[4]) { /* Old_North_Arabian, Old_South_Arabian */
          case 'N':
            if (!memcmp(su, "Old_North_Arabian", 16)
		&& *(&su[16]) == 'n') return 65;
            break;
          case 'S':
            if (!memcmp(su, "Old_South_Arabian", 16)
		&& *(&su[16]) == 'n') return 68;
          default:
            return -1;
        }
        return -1;
      case 18: 
        return !memcmp(su, "Caucasian_Albanian", 16)
		&& *(short*)&su[16] == (short)0x6e61 /* an */ ? 14 : -1;
      case 20: 
        switch (su[0]) { /* Egyptian_Hieroglyphs, Meroitic_Hieroglyphs */
          case 'E':
            if (!memcmp(su, "Egyptian_Hieroglyphs", 16)
		&& *(int*)&su[16] == (int)0x73687079 /* yphs */) return 24;
            break;
          case 'M':
            if (!memcmp(su, "Meroitic_Hieroglyphs", 16)
		&& *(int*)&su[16] == (int)0x73687079 /* yphs */) return 54;
          default:
            return -1;
        }
        return -1;
      case 21: 
        switch (su[0]) { /* Inscriptional_Pahlavi, Anatolian_Hieroglyphs */
          case 'A':
            if (!memcmp(su, "Anatolian_Hieroglyphs", 16)
		&& *(int*)&su[16] == (int)0x6870796c /* lyphs */
		&& *(&su[20]) == 's') return 3;
            break;
          case 'I':
            if (!memcmp(su, "Inscriptional_Pahlavi", 16)
		&& *(int*)&su[16] == (int)0x76616c68 /* hlavi */
		&& *(&su[20]) == 'i') return 33;
          default:
            return -1;
        }
        return -1;
      case 22: 
        return !memcmp(su, "Inscriptional_Parthian", 16)
		&& *(int*)&su[16] == (int)0x69687472 /* rthian */
		&& *(short*)&su[20] == (short)0x6e61 /* an */ ? 34 : -1;
    }
    return -1;
}
