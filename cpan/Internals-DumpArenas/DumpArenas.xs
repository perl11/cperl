/* This code uses several internal APIs. I'm declaring PERL_CORE
 * purely so this is visible to anyone grepping CPAN for code that
 * does this sort of thing.
 *
 *   Copied and pasted structure of S_visit from sv.c
 *   Used PL_sv_arenaroot
 *   Used do_sv_dump (instead of sv_dump)
 *   Used pv_display
 */
#define PERL_CORE

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

/* need workaround broken dump of !SvOBJECT with SvSTASH in dump.c */
/* fixed in cperl5.22.2 and perl5.23.8  */
#if PERL_VERSION >= 18 && (!defined(USE_CPERL) && PERL_VERSION < 24)
#define NEED_SAFE_SVSTASH
#endif

void DumpPointer( pTHX_ PerlIO *f, SV *sv ) {
  dVAR;
  if ( &PL_sv_undef == sv ) {
    PerlIO_puts(f, "sv_undef");
  }
  else if (&PL_sv_yes == sv) {
    PerlIO_puts(f, "sv_yes");
  }
  else if (&PL_sv_no == sv) {
    PerlIO_puts(f, "sv_no");
  }
#if PERL_VERSION > 6
  else if (&PL_sv_placeholder == sv) { /* deleted hash entry */
    PerlIO_printf(f, "sv_placeholder");
  }
#endif
  else {
    PerlIO_printf(f, "0x%" UVxf, PTR2UV(sv));
  }
}

void
DumpAvARRAY( pTHX_ PerlIO *f, SV *sv) {
  I32 key = 0;

  PerlIO_printf(f,"AvARRAY(0x%" UVxf ") = {",PTR2UV(AvARRAY(sv)));
  if (!AvARRAY(sv)) return;
  if ( AvMAX(sv) != AvFILL(sv) ) {
    PerlIO_puts(f,"{");
  }
  
  for ( key = 0; key <= AvMAX(sv); ++key ) {
    DumpPointer(aTHX_ f, AvARRAY(sv)[key]);
    
    /* Join with something */
    if ( AvMAX(sv) == AvFILL(sv) ) {
      if (key != AvMAX(sv)) {
        PerlIO_puts(f, ",");
      }
    }
    else {
      PerlIO_puts(
        f,
        AvFILL(sv) == key ? "}{" :
        AvMAX(sv) == key  ? "}" :
        ","
      );
    }
  }
  PerlIO_puts(f,"}\n\n");
}

void
DumpHvARRAY( pTHX_ PerlIO *f, SV *sv) {
  U32 key = 0;
  HE *entry;
  SV *tmp = newSVpv("",0);

  PerlIO_printf(f,"HvARRAY(0x%" UVxf ")\n",PTR2UV(HvARRAY(sv)));
  if (!HvARRAY(sv)) goto hvend;

  for ( key = 0; key <= HvMAX(sv); ++key ) {
    for ( entry = HvARRAY(sv)[key]; entry; entry = HeNEXT(entry) ) {
      if ( HEf_SVKEY == HeKLEN(entry) ) {
        PerlIO_printf(
          f, "  [SV 0x%" UVxf "] => ",
          PTR2UV(HeKEY(entry)));
        DumpPointer(aTHX_ f, (SV*)(HeKEY(entry)));
      }
      else {
        PerlIO_printf(
          f, "  [0x%" UVxf " %s] => ",
          PTR2UV(HeKEY(entry)),
          pv_display(
            tmp,
            HeKEY(entry), HeKLEN(entry), HeKLEN(entry),
            0 ));
      }
      DumpPointer(aTHX_ f, HeVAL(entry));
      PerlIO_puts(f, "\n");
    }
  }
 hvend:
  PerlIO_puts(f,"\n");

  SvREFCNT_dec(tmp);
}
#if 0
void
DumpHashKeys( pTHX_ PerlIO *f, SV *sv) {
  U32 key = 0;
  HE *entry;
  SV *tmp = newSVpv("",0);

  PerlIO_printf(f,"SHARED HASH KEYS at 0x%" UVxf "\n", PTR2UV(sv));
  if (!HvARRAY(sv)) goto hkend;
  
  for ( key = 0; key <= HvMAX(sv); ++key ) {
    for ( entry = HvARRAY(sv)[key]; entry; entry = HeNEXT(entry) ) {
      if ( HEf_SVKEY == HeKLEN(entry) ) {
        PerlIO_printf(f, "    SV 0x%" UVxf "\n", PTR2UV(HeKEY(entry)) );
        DumpPointer(aTHX_ f, (SV*)(HeKEY(entry)));
      }
      else {
        PerlIO_printf(f, "    0x%" UVxf " %s\n", PTR2UV(HeKEY(entry)),
                      pv_display( (SV*)tmp, (const char*)HeKEY(entry),
                                  HeKLEN(entry), HeKLEN(entry), 0 ) );
      } 
    }
  }
 hkend:
  PerlIO_puts(f,"\n\n");
  SvREFCNT_dec(tmp);
}
#endif

void
DumpArenasPerlIO( pTHX_ PerlIO *f) {
  SV *arena;

  for (arena = PL_sv_arenaroot; arena; arena = (SV*)SvANY(arena)) {
    const SV *const arena_end = &arena[SvREFCNT(arena)];
    SV *sv;

    /* See also the static function S_visit in perl's sv.c
     * This is a copied and pasted implementation of that function.
     */
    PerlIO_printf(f,"START ARENA = (0x%" UVxf "-0x%" UVxf ")\n\n",PTR2UV(arena),PTR2UV(arena_end));
    for (sv = arena + 1; sv < arena_end; ++sv) {
      /* not freed */
      if ((SvFLAGS(sv) != SVTYPEMASK) && SvREFCNT(sv)) {

        /* workaround broken dump of !SvOBJECT with SvSTASH in dump.c */
        /* only fixed in cperl so far */
#ifdef NEED_SAFE_SVSTASH
        HV* savestash = NULL;
        if (!SvOBJECT(sv) && SvTYPE(sv) >= SVt_PVMG && SvSTASH(sv)) {
          savestash = SvSTASH(sv);
          SvSTASH(sv) = NULL;
        }
#endif
#if defined(USE_ITHREADS) && defined(DEBUGGING) && defined(SVpbm_VALID)
        /* workaround broken SvTAIL() in dump.c */
        if (SvTYPE(sv) != SVt_PVMG ||
            (!(SvFLAGS(sv) & SVpbm_VALID) &&
             (SvFLAGS(sv) & SVpbm_TAIL)))
#endif
#if PERL_VERSION < 8 && defined(DEBUGGING) && defined(SVpbm_VALID)
          /* workaround broken CvANON() in 5.6 dump.c */
          if (SvTYPE(sv) != SVt_PVCV || !(SvFLAGS(sv) & 0x500))
#endif
            /* Dump the plain SV */
            do_sv_dump(0,f,sv,0,0,0,0);

#ifdef NEED_SAFE_SVSTASH
        if (savestash)
          SvSTASH(sv) = savestash;
#endif
        PerlIO_puts(f,"\n");
        
        /* Dump AvARRAY(0x...) = {{0x...,0x...}{0x...}} */
        switch (SvTYPE(sv)) {
        case SVt_PVAV:
          /* if ( AvARRAY(sv) && AvMAX(sv) > 0 ) */
            DumpAvARRAY( aTHX_ f,sv);
          break;
        case SVt_PVHV:
          /* if ( HvARRAY(sv) && HvMAX(sv) > 0 ) */
            DumpHvARRAY( aTHX_ f,sv);
#if 0
          if ( HvSHAREKEYS(sv) ) {
            DumpHashKeys( aTHX_ f,sv);
          }
#endif
        default:
          break;
        }
      }
      else {
        PerlIO_printf(f,"AVAILABLE(0x%" UVxf ")\n\n",PTR2UV(sv));
      }
    }
    PerlIO_printf(f,"END ARENA = (0x%" UVxf "-0x%" UVxf ")\n\n",PTR2UV(arena),PTR2UV(arena_end));
  }
}

void
DumpArenas( pTHX ) {
  DumpArenasPerlIO( aTHX_ Perl_error_log );
}

void
DumpArenasFd( pTHX_ int fd ) {
  PerlIO *f = (PerlIO*)PerlIO_fdopen( fd, "w" );
  DumpArenasPerlIO( aTHX_ f );
}

MODULE = Internals::DumpArenas  PACKAGE = Internals::DumpArenas
  
PROTOTYPES: DISABLE

void
DumpArenas()
    CODE:
        DumpArenas( aTHX );

void
DumpArenasFd( int fd )
    CODE:
        DumpArenasFd( aTHX_ fd );
