/*
 * SMART: string matching algorithms research tool.
 * Copyright (C) 2012  Simone Faro and Thierry Lecroq
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>
 * 
 * contact the authors at: faro@dmi.unict.it, thierry.lecroq@univ-rouen.fr
 * download the tool at: http://www.dmi.unict.it/~faro/smart/
 *
 * This is an implementation of the EPSM algorithm in S. Faro and O. M. Kulekci. 
 * It includes corrections to the original implementations gently provided by
 * Jorma Tarhio and Jan Holub 
 */

#define BEGIN_PREPROCESSING
#define END_PREPROCESSING
#define BEGIN_SEARCHING
#define END_SEARCHING

/* #include "include/define.h"
   #include "include/main.h"
*/
#include <memory.h>
#include <smmintrin.h>
#include <inttypes.h>

/* used implicitly for the LIST size in search16
#define HASHSIZE 11
*/

typedef union{
         __m128i* symbol16;
   unsigned char* symbol;
} TEXT;

typedef union{
              __m128i  v;
        unsigned  int  ui[4];
   unsigned short int  us[8];
        unsigned char  uc[16];
} VectorUnion;

typedef struct list
{
    struct list *next;
    unsigned int pos;
} LIST;

static int search1(unsigned char* pattern,
                   const int patlen __attribute__((unused)),
                   unsigned char* x,
                   int textlen)
{  /* we exactly know patlen=1 */
    __m128i* text = (__m128i*)x;
    __m128i* tend  = (__m128i*)(x+16*(textlen/16));
    __m128i t0,a;
    VectorUnion template0;
    unsigned int j;
    int cnt=0;

    BEGIN_PREPROCESSING
    for (j=0; j<16; j++)
    {
        template0.uc[j]=pattern[0];
    }
    t0 = template0.v;
    END_PREPROCESSING

    BEGIN_SEARCHING
    while(text<tend){
        a     = _mm_cmpeq_epi8(t0,*text);
        j     = _mm_movemask_epi8(a);
        cnt  += _mm_popcnt_u32( j );
        text++;
    }
    /* now we are at the beginning of the last 16-byte block, perform naive check */
    for (j=16*(textlen/16); j<(unsigned int)textlen; j++)
        cnt += (x[j] == pattern[0]);
    END_SEARCHING
    return cnt;
}

static int search2(unsigned char* pattern,
                   const int patlen __attribute__((unused)),
                   unsigned char* x,
                   int textlen)
{  /* we exactly know patlen=2 */
    __m128i* text = (__m128i*)x;
    __m128i* tend  = (__m128i*)(x+16*(textlen/16));
    __m128i t0,t1,a,b;
    VectorUnion template0,template1;
    unsigned int j,k,carry=0;
    int cnt=0;
    unsigned char firstch = pattern[0], lastch = pattern[1];
    
    BEGIN_PREPROCESSING
    for(j=0; j<16; j++)
    {
        template0.uc[j]=firstch;       /* template0.uc[i+1]=lastch; */
        template1.uc[j]=lastch;        /* template1.uc[i+1]=firstch; */
    }
    t0 = template0.v;
    t1 = template1.v;
    END_PREPROCESSING
    
    BEGIN_SEARCHING
    while(text<tend){
        a     = _mm_cmpeq_epi8(t0,*text);
        j     = _mm_movemask_epi8(a);
        b     = _mm_cmpeq_epi8(t1,*text);
        k     = _mm_movemask_epi8(b);
        cnt  += _mm_popcnt_u32( ((j<<1)|(carry>>15)) & k );
        carry = j & 0x00008000;
        text++;
    }
    /* now we are at the beginning of the last 16-byte block, perform naive check */
    for(j=16*(textlen/16); j<(unsigned int)textlen; j++)
        cnt += ((x[j-1]==firstch) && (x[j]==lastch));
    END_SEARCHING
    return cnt;
}

static int search3(unsigned char* pattern,
                   const int patlen __attribute__((unused)),
                   unsigned char* x,
                   int textlen)
{
    /* we exactly know patlen=3 */
    __m128i* text = (__m128i*)x;
    __m128i* tend  = (__m128i*)(x+16*(textlen/16));
    __m128i t0,t1,t2,a,b,c;
    VectorUnion template0,template1,template2;
    unsigned int j,k,l,carry0=0,carry1=0;
    int cnt=0;
    
    BEGIN_PREPROCESSING
    for (j=0; j<16; j++)
    {
        template0.uc[j]=pattern[0];
        template1.uc[j]=pattern[1];
        template2.uc[j]=pattern[2];
    }
    t0 = template0.v;
    t1 = template1.v;
    t2 = template2.v;
    END_PREPROCESSING
    
    BEGIN_SEARCHING
    while(text<tend){
        a     = _mm_cmpeq_epi8(t0,*text);
        j     = _mm_movemask_epi8(a);

        b     = _mm_cmpeq_epi8(t1,*text);
        k     = _mm_movemask_epi8(b);

        c     = _mm_cmpeq_epi8(t2,*text);
        l     = _mm_movemask_epi8(c);

        cnt  += _mm_popcnt_u32( ((j<<2)|(carry0>>14)) & ((k<<1)|(carry1>>15)) & l );
        carry0 = j & 0x0000C000;
        carry1 = k & 0x00008000;
        text++;
    }
    /* now we are at the beginning of the last 16-byte block, perform naive check */
    for (j=16*(textlen/16); j<(unsigned int)textlen; j++)
        cnt += ((x[j-2]==pattern[0]) && (x[j-1]==pattern[1]) && (x[j]==pattern[2]));
    END_SEARCHING
    
    return cnt;
}

static int search4(unsigned char* pattern,
                   const int patlen __attribute__((unused)),
                   unsigned char* x,
                   int textlen)
{
    __m128i* text = (__m128i*)x;
    __m128i* tend  = (__m128i*)(x+16*(textlen/16));
    int i,count=0;
    VectorUnion P,Z;
    __m128i a,b,p,z;

    BEGIN_PREPROCESSING
    if ((textlen%16)<7) tend--;
    Z.ui[0] = Z.ui[1] = Z.ui[2] = Z.ui[3] = 0;
    z= Z.v;
    P.uc[0] = pattern[0];
    P.uc[1] = pattern[1];
    P.uc[2] = pattern[2];
    P.uc[3] = pattern[3];
    p = P.v;
    END_PREPROCESSING

    text++;  /* leave the naive check of the first block to the end */

    BEGIN_SEARCHING
    while(text<tend)
    {
        /* check if P[(m-4) ... (m-1)] matches with
           T[i*16 ... i*16+3], T[i*16+1 ... i*16+4], .... , T[i*16+7 ... i*16+10]
        */
        a      = _mm_mpsadbw_epu8(*text, p, 0x00);
        b      = _mm_cmpeq_epi16(a,z);
        i      = _mm_movemask_epi8(b);
        count += _mm_popcnt_u32(i);

        a      = _mm_blend_epi16(*text,*(text+1),0x0f);
        b      = _mm_shuffle_epi32(a, _MM_SHUFFLE(1,0,3,2));

        /* check if P[(m-4) ... (m-1)] matches with
           T[i*16+8 ... i*16+11], T[i*16+9 ... i*16+12], .... , T[i*16+15 ... i*16+18]
        */
        a      = _mm_mpsadbw_epu8(b, p, 0x00);
        b      = _mm_cmpeq_epi16(a,z);
        i      = _mm_movemask_epi8(b);
        count += _mm_popcnt_u32(i);
        text++;
    }
    count = count / 2;

    /* The ending position of the pattern from the first appropriate position
       T[patlen-1] to the third position of the next 16-byte block is performed naive
    */
    for (i=3; (i<19) && (i<textlen); i++) /* j presents possible end points of the pattern */
        if (0==memcmp(pattern,&x[i-3],patlen)) count++;

    /* Note that at the last iteration of the while loop, we have checked if P
       ends at positions 0,1,and 2 of the last 16-byte block however, what if
       the last position of the text is beyond 2? for the possibilities that T
       ends at positions 3,4,5,6,7,8,9,10,11,12,13,14,and 15, we perform naive
       checks.
    */
    for (i = ((unsigned char*) text)+3-x ; i < textlen ; i++)
    {
        if ( 0 == memcmp(pattern,&x[i-3],4) ) count++;
    }
    END_SEARCHING
    
    return count;
}

static int search16(unsigned char* pattern, const int patlen, unsigned char* x, int textlen)
{
    /* 11 bit hash is gives the best result according to our tests, no shorter no longer */
    LIST* flist[2048];
    LIST *t;

    unsigned int i,filter,shift = (patlen/8)-1;
    unsigned long long crc, seed= 123456789, mask;
    unsigned long long* ptr64;
    unsigned long long* lastchunk;
    unsigned char* charPtr;
    int count=0;
    unsigned tmppatlen=(patlen/8)*8;
    mask = 2047;
    
    BEGIN_PREPROCESSING
    memset(flist,0,sizeof(LIST*)*2048);

    for (i=1; i<tmppatlen-7; i++)
    {
        ptr64 = (unsigned long long*)(&pattern[i]);
        crc = _mm_crc32_u64(seed,*ptr64);
        filter = (unsigned int)(crc & mask);

        if (flist[filter]==0)
        {
            flist[filter] = (LIST*)malloc(sizeof(LIST));
            if (flist[filter]){
              flist[filter]->next = 0;
              flist[filter]->pos  = i;
            }
        }
        else
        {
            t = flist[filter];
            while(t->next!=0) t = t->next;
            t->next = (LIST*)malloc(sizeof(LIST));
            if (t->next){
            	t = t->next;
            	t->next=0;
            	t->pos = i;
            }
        }
    }
    END_PREPROCESSING
    
    BEGIN_SEARCHING
    lastchunk = (unsigned long long*)&x[((textlen-tmppatlen)/8)*8+1];
    ptr64     = (unsigned long long*)&x[(shift-1)*8];

    crc = _mm_crc32_u64(seed,*ptr64);
    filter = (unsigned int)(crc & mask);
    if (flist[filter]){
        charPtr = (unsigned char*)ptr64;
        t = flist[filter];
        while(t)
        {
            if (t->pos <= 8*(shift-1)){
                if (memcmp(pattern,charPtr - t->pos,patlen) == 0)
                    count++;
            }
            t=t->next;
        }
    }
    ptr64 += shift;

    crc = _mm_crc32_u64(seed,*ptr64);
    filter = (unsigned int)(crc & mask);
    if (flist[filter]) {
        charPtr = (unsigned char*)ptr64;
        t = flist[filter];
        while(t)
        {
            if (t->pos <= 8*(2*shift-1)){
                if (memcmp(pattern,charPtr - t->pos,patlen) == 0)
                    count++;
            }
            t=t->next;
        }
    }
    ptr64 += shift;

    while(ptr64 < lastchunk)
    {
        crc = _mm_crc32_u64(seed,*ptr64);
        filter = (unsigned int)(crc & mask);

        if (flist[filter])
        {
            charPtr = (unsigned char*)ptr64;
            t = flist[filter];
            while(t)
            {
                if (memcmp(pattern,charPtr - t->pos,patlen) == 0)
                    count++;
                t=t->next;
            }
        }
        ptr64 += shift;
    }

    ptr64 -= shift;
    charPtr = (unsigned char*)ptr64;
    charPtr += tmppatlen-1; /* the first position unchecked where P may end */

    while(charPtr < &x[textlen-1])
    {
        if (0== memcmp(pattern,charPtr-tmppatlen+1,patlen)) count++;
        charPtr++;
    }
    END_SEARCHING

    return count;
}


int str_search(unsigned char* pattern, int patlen, unsigned char* x, int textlen)
{
    if (patlen<2)         return  search1 (pattern, patlen, x, textlen);
    if (patlen==2)        return  search2 (pattern, 2,      x, textlen);
    if (patlen==3)        return  search3 (pattern, 3,      x, textlen);
    if (patlen==4)        return  search4 (pattern, 4,      x, textlen);
    if (patlen>=16)       return search16 (pattern, patlen, x, textlen);
    {
        unsigned char* y0;
        int i, j, k, count=0;
        VectorUnion P, zero;
        __m128i res, a, b, z, p;
        __m128i* text = (__m128i*)x;
        __m128i* tend  = (__m128i*)(x+16*(textlen/16));
        tend--;

        BEGIN_PREPROCESSING
        zero.ui[0] = zero.ui[1] = zero.ui[2] = zero.ui[3] = 0;
        z = zero.v;
        P.uc[0] = pattern[patlen - 5];
        P.uc[1] = pattern[patlen - 4];
        P.uc[2] = pattern[patlen - 3];
        P.uc[3] = pattern[patlen - 2];
        p = P.v;

        i = (patlen-1) / 16; /* i points the first 16-byte block that P may end in */
        i++;
        text += i;
        for (k=0; k<(i*16+8)-patlen+1; k++)  if (0 == memcmp(pattern,x+k,patlen)) count++;
        END_PREPROCESSING
    
        BEGIN_SEARCHING
        /* the loop checks if pattern ends at the second half of text[i] or at the
           first half of text[i+1] */
        while (text < tend) {
            /* check if P[(m-5) ... (m-2)] matches with T[i*16+4 ... i*16+7], T[i*16+5
              ... i*16+8], .... , T[i*16+11 ... i*16+14]
              note that this corresponds P ends at T[i*16+8],T[i*16+9],...,T[i*16+15]
            */
            res = _mm_mpsadbw_epu8(*text, p, 0x04);
            b = _mm_cmpeq_epi16(res, z);
            j = _mm_movemask_epi8(b);
            if (j) {
                y0 = (unsigned char *)(text) + 9 - patlen;
                if ((j & 3) == 3 && !memcmp(pattern, y0, patlen))
                    count++;
                if ((j & 12) == 12 && !memcmp(pattern, y0 + 1, patlen))
                    count++;
                if ((j & 48) == 48 && !memcmp(pattern, y0 + 2, patlen))
                    count++;
                if ((j & 192) == 192 && !memcmp(pattern, y0 + 3, patlen))
                    count++;
                if ((j & 768) == 768 && !memcmp(pattern, y0 + 4, patlen))
                    count++;
                if ((j & 3072) == 3072 && !memcmp(pattern, y0 + 5, patlen))
                    count++;
                if ((j & 12288) == 12288 && !memcmp(pattern, y0 + 6, patlen))
                    count++;
                if ((j & 49152) == 49152 && !memcmp(pattern, y0 + 7, patlen))
                    count++;
            }

            a   = _mm_blend_epi16(*text,*(text+1),0x0f);
            b   = _mm_shuffle_epi32(a,_MM_SHUFFLE(1,0,3,2));

            /* check if P ends at T[(i+1)*16+8],T[(i+1)*16+9],...,T[(i+1)*16+15] */
            res  = _mm_mpsadbw_epu8(b, p, 0x04);
            b    = _mm_cmpeq_epi16(res,z);
            j    = _mm_movemask_epi8(b);

            if (j)
            {
                y0 = (unsigned char*)(text) + 9 + 8 - patlen;
                if ( (j&3)==3 && !memcmp(pattern,y0,patlen)) count++;
                if ( (j&12)==12 && !memcmp(pattern,y0+1,patlen)) count++;
                if ( (j&48)==48 && !memcmp(pattern,y0+2,patlen)) count++;
                if ( (j&192)==192 && !memcmp(pattern,y0+3,patlen)) count++;
                if ( (j&768)==768 && !memcmp(pattern,y0+4,patlen)) count++;
                if ( (j&3072)==3072 && !memcmp(pattern,y0+5,patlen)) count++;
                if ( (j&12288)==12288 && !memcmp(pattern,y0+6,patlen)) count++;
                if ( (j&49152)==49152 && !memcmp(pattern,y0+7,patlen)) count++;
            }
            text++;
        }

        for (k = ((unsigned char*)text)+8-x ; k < textlen ; k++)
        {
            if ( 0 == memcmp(pattern,&x[k-patlen+1],patlen) ) count++;
        }
        END_SEARCHING
        return count;
    }
}

