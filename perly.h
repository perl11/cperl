/* ex: set ro ft=c: -*- buffer-read-only: t -*-
   !!!!!!!   DO NOT EDIT THIS FILE   !!!!!!!
   This file is built by regen_perly.pl from perly.y.
   Any changes made here will be lost!
 */

#ifdef PERL_CORE
/* A Bison parser, made by GNU Bison 2.7.12-4996.  */

/* Bison interface for Yacc-like parsers in C
   
      Copyright (C) 1984, 1989-1990, 2000-2013 Free Software Foundation, Inc.
   
   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.
   
   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
   
   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.
   
   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* Enabling traces.  */
#ifndef YYDEBUG
# define YYDEBUG 0
#endif
#if YYDEBUG
extern int yydebug;
#endif

/* Tokens.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
   /* Put the tokens into the symbol table, so that GDB and other debuggers
      know about them.  */
   enum yytokentype {
     GRAMPROG = 258,
     GRAMEXPR = 259,
     GRAMBLOCK = 260,
     GRAMBARESTMT = 261,
     GRAMFULLSTMT = 262,
     GRAMSTMTSEQ = 263,
     WORD = 264,
     METHOD = 265,
     FUNCMETH = 266,
     THING = 267,
     PMFUNC = 268,
     PRIVATEREF = 269,
     QWLIST = 270,
     FUNC0OP = 271,
     FUNC0SUB = 272,
     UNIOPSUB = 273,
     LSTOPSUB = 274,
     PLUGEXPR = 275,
     PLUGSTMT = 276,
     LABEL = 277,
     FORMAT = 278,
     SUB = 279,
     ANONSUB = 280,
     PACKAGE = 281,
     USE = 282,
     WHILE = 283,
     UNTIL = 284,
     IF = 285,
     UNLESS = 286,
     ELSE = 287,
     ELSIF = 288,
     CONTINUE = 289,
     FOR = 290,
     GIVEN = 291,
     WHEN = 292,
     DEFAULT = 293,
     LOOPEX = 294,
     DOTDOT = 295,
     YADAYADA = 296,
     FUNC0 = 297,
     FUNC1 = 298,
     FUNC = 299,
     UNIOP = 300,
     LSTOP = 301,
     RELOP = 302,
     EQOP = 303,
     MULOP = 304,
     ADDOP = 305,
     DOLSHARP = 306,
     DO = 307,
     HASHBRACK = 308,
     NOAMP = 309,
     LOCAL = 310,
     MY = 311,
     REQUIRE = 312,
     COLONATTR = 313,
     FORMLBRACK = 314,
     FORMRBRACK = 315,
     PREC_LOW = 316,
     DOROP = 317,
     OROP = 318,
     ANDOP = 319,
     NOTOP = 320,
     ASSIGNOP = 321,
     DORDOR = 322,
     OROR = 323,
     ANDAND = 324,
     BITOROP = 325,
     BITANDOP = 326,
     SHIFTOP = 327,
     MATCHOP = 328,
     REFGEN = 329,
     UMINUS = 330,
     POWCOP = 331,
     POWOP = 332,
     POSTJOIN = 333,
     POSTDEC = 334,
     POSTINC = 335,
     PREDEC = 336,
     PREINC = 337,
     ARROW = 338
   };
#endif


#ifdef PERL_IN_TOKE_C
static bool
S_is_opval_token(int type) {
    switch (type) {
    case FUNC0OP:
    case FUNC0SUB:
    case FUNCMETH:
    case LSTOPSUB:
    case METHOD:
    case PLUGEXPR:
    case PLUGSTMT:
    case PMFUNC:
    case PRIVATEREF:
    case QWLIST:
    case THING:
    case UNIOPSUB:
    case WORD:
	return 1;
    }
    return 0;
}
#endif /* PERL_IN_TOKE_C */
#endif /* PERL_CORE */
#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
typedef union YYSTYPE
{
/* Line 2053 of yacc.c  */

    I32	ival; /* __DEFAULT__ (marker for regen_perly.pl;
				must always be 1st union member) */
    char *pval;
    OP *opval;
    GV *gvval;


/* Line 2053 of yacc.c  */
} YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define yystype YYSTYPE /* obsolescent; will be withdrawn */
# define YYSTYPE_IS_DECLARED 1
#endif


#ifdef YYPARSE_PARAM
#if defined __STDC__ || defined __cplusplus
int yyparse (void *YYPARSE_PARAM);
#else
int yyparse ();
#endif
#else /* ! YYPARSE_PARAM */
#if defined __STDC__ || defined __cplusplus
int yyparse (void);
#else
int yyparse ();
#endif
#endif /* ! YYPARSE_PARAM */


#if YYDEBUG
#define YYPRINT
#endif

/* Generated from:
 * 4bf092379a8a3ed7711b8c5767e3344e41bec19580d6b0423a0c552a8cf7e5c2 perly.y
 * 82b7d1e1f57d7b73f14717109a0888760b4a61bc4b2e8a487dbab21278180e28 regen_perly.pl
 * ex: set ro: */
