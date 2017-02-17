# B::Bytecode.pm - The bytecode compiler (.plc), loaded by ByteLoader
#
# Copyright (c) 1994-1999 Malcolm Beattie. All rights reserved.
# Copyright (c) 2003 Enache Adrian. All rights reserved.
# Copyright (c) 2008-2011 Reini Urban <rurban@cpan.org>. All rights reserved.
# Copyright (c) 2011-2015 cPanel Inc. All rights reserved.
# This module is free software; you can redistribute and/or modify
# it under the same terms as Perl itself.

# Reviving 5.6 support here is work in progress, and not yet enabled.
# So far the original is used instead, even if the list of failed tests
# with the old 5.6. compiler is impressive: 3,6,8..10,12,15,16,18,25..28.

package B::Bytecode;

our $VERSION = '1.17';

use 5.008;
use B qw( main_cv main_root main_start
	  begin_av init_av end_av cstring comppadlist
	  OPf_SPECIAL OPf_STACKED OPf_MOD
	  OPpLVAL_INTRO SVf_READONLY SVf_ROK );
use B::Assembler qw(asm newasm endasm);

BEGIN {
  if ( $] < 5.009 ) {
    require B::Asmdata;
    B::Asmdata->import(qw(@specialsv_name @optype));
    eval q[
      sub SVp_NOK() {}; # unused
      sub SVf_NOK() {}; # unused
     ];
  }
  else {
    B->import(qw(SVp_NOK SVf_NOK @specialsv_name @optype));
  }
  if ( $] > 5.007 ) {
    B->import(qw(defstash curstash inc_gv dowarn
		 warnhook diehook SVt_PVGV
		 SVf_FAKE));
  } else {
    B->import(qw(walkoptree));
  }
  if ($] > 5.017) {
    B->import('SVf_IsCOW');
  } else {
    eval q[sub SVf_IsCOW() {};]; # unused
  }
  if ($] > 5.021006) {
    B->import('SVf_PROTECT');
  } else {
    eval q[sub SVf_PROTECT() {};]; # unused
  }
  if ( $] >= 5.017005 ) {
    @B::PAD::ISA = ('B::AV');
  }
}
use strict;
use Config;
use B::Concise;

#################################################

my $PERL56  = ( $] <  5.008001 );
my $PERL510 = ( $] >= 5.009005 );
my $PERL512 = ( $] >= 5.011 );
#my $PERL514 = ( $] >= 5.013002 );
my $PERL518 = ( $] >= 5.017006 );
my $PERL520 = ( $] >= 5.019002 );
my $PERL522 = ( $] >= 5.021005 );
my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
our ($quiet, $includeall, $savebegins, $T_inhinc);
my ( $varix, $opix, %debug, %walked, %files, @cloop );
my %strtab  = ( 0, 0 );
my %svtab   = ( 0, 0 );
my %optab   = ( 0, 0 );
my %spectab = $PERL56 ? () : ( 0, 0 ); # we need the special Nullsv on 5.6 (?)
my $tix     = $PERL56 ? 0 : 1;
my %ops     = ( 0, 0 );
my @packages;    # list of packages to compile. 5.6 only
our $curcv;

# sub asm ($;$$) { }
sub nice ($) { }
sub nice1 ($) { }

my %optype_enum;
my ($SVt_PVGV, $SVf_FAKE, $POK);
if ($PERL56) {
  *dowarn = sub {};
  $SVt_PVGV = 13;
  $SVf_FAKE = 0x00100000;
  $POK = 0x00040000 | 0x04000000;
  sub MAGICAL56 { $_[0]->FLAGS & 0x000E000 } #(SVs_GMG|SVs_SMG|SVs_RMG)
} else {
  no strict 'subs';
  $SVt_PVGV = SVt_PVGV;
  $SVf_FAKE = SVf_FAKE;
}

{ # block necessary for caller to work
  my $caller = caller;
  if ( $] > 5.017 and $] < 5.019004 and ($caller eq 'O' or $caller eq 'Od' )) {
    require XSLoader;
    XSLoader::load('B::C'); # for op->slabbed... workarounds
  }
  if ( $] > 5.021) { # for op_aux
    require XSLoader;
    XSLoader::load('B::C');
  }
}

for ( my $i = 0 ; $i < @optype ; $i++ ) {
  $optype_enum{ $optype[$i] } = $i;
}

BEGIN {
  my $ithreads = defined $Config::Config{'useithreads'} && $Config::Config{'useithreads'} eq 'define';
  eval qq{
	sub ITHREADS() { $ithreads }
	sub VERSION() { $] }
    };
  die $@ if $@;
}

sub as_hex($) {$quiet ? undef : sprintf("0x%x",shift)}

# Fixes bug #307: use foreach, not each
# each is not safe to use (at all). walksymtable is called recursively which might add
# symbols to the stash, which might cause re-ordered rehashes, which will fool the hash
# iterator, leading to missing symbols.
# Old perl5 bug: The iterator should really be stored in the op, not the hash.
sub walksymtable {
  my ($symref, $method, $recurse, $prefix) = @_;
  my ($sym, $ref, $fullname);
  $prefix = '' unless defined $prefix;
  foreach my $sym ( sort keys %$symref ) {
    no strict 'refs';
    $ref = $symref->{$sym};
    $fullname = "*main::".$prefix.$sym;
    if ($sym =~ /::$/) {
      $sym = $prefix . $sym;
      if (svref_2object(\*$sym)->NAME ne "main::" && $sym ne "<none>::" && &$recurse($sym)) {
        walksymtable(\%$fullname, $method, $recurse, $sym);
      }
    } else {
      svref_2object(\*$fullname)->$method();
    }
  }
}

#################################################

# This is for -S commented assembler output
sub op_flags($) {
  return '' if $quiet;
  # B::Concise::op_flags($_[0]); # too terse
  # common flags (see BASOP.op_flags in op.h)
  my $x = shift;
  my (@v);
  push @v, "WANT_VOID"   if ( $x & 3 ) == 1;
  push @v, "WANT_SCALAR" if ( $x & 3 ) == 2;
  push @v, "WANT_LIST"   if ( $x & 3 ) == 3;
  push @v, "KIDS"        if $x & 4;
  push @v, "PARENS"      if $x & 8;
  push @v, "REF"         if $x & 16;
  push @v, "MOD"         if $x & 32;
  push @v, "STACKED"     if $x & 64;
  push @v, "SPECIAL"     if $x & 128;
  return join( ",", @v );
}

# This is also for -S commented assembler output
sub sv_flags($;$) {
  return '' if $quiet or $B::Concise::VERSION < 0.74;    # or ($] == 5.010);
  return '' unless $debug{Comment};
  return 'B::SPECIAL' if $_[0]->isa('B::SPECIAL');
  return 'B::PADLIST' if $_[0]->isa('B::PADLIST');
  return 'B::PADNAMELIST' if $_[0]->isa('B::PADNAMELIST');
  return 'B::NULL'    if $_[0]->isa('B::NULL');
  my ($sv) = @_;
  my %h;

  # TODO: Check with which Concise and B versions this works. 5.10.0 fails.
  # B::Concise 0.66 fails also
  *B::Concise::fmt_line = sub { return shift };
  my $op = $ops{ $tix - 1 };
  if (ref $op and !$op->targ) { # targ assumes a valid curcv
    %h = B::Concise::concise_op( $op );
  }
  B::Concise::concise_sv( $_[0], \%h, 0 );
}

sub pvstring($) {
  my $pv = shift;
  defined($pv) ? cstring( $pv . "\0" ) : "\"\"";
}

sub pvix($) {
  my $str = pvstring shift;
  my $ix  = $strtab{$str};
  defined($ix) ? $ix : do {
    nice1 "-PV- $tix";
    B::Assembler::maxsvix($tix) if $debug{A};
    asm "newpv", $str;
    asm "stpv", $strtab{$str} = $tix;
    $tix++;
  }
}

sub B::OP::ix($) {
  my $op = shift;
  my $ix = $optab{$$op};
  defined($ix) ? $ix : do {
    nice "[" . $op->name . " $tix]";
    $ops{$tix} = $op;
    # Note: This left-shift 7 encoding of the optype has nothing to do with OCSHIFT
    # in opcode.pl
    # The counterpart is hardcoded in Byteloader/bytecode.h: BSET_newopx
    my $arg = $PERL56 ? $optype_enum{B::class($op)} : $op->size | $op->type << 7;
    my $opsize = $PERL56 ? '?' : $op->size;
    if (ref($op) eq 'B::OP') { # check wrong BASEOPs
      # [perl #80622] Introducing the entrytry hack, needed since 5.12,
      # fixed with 5.13.8 a425677
      #   ck_eval upgrades the UNOP entertry to a LOGOP, but B gets us just a
      #   B::OP (BASEOP).
      #   op->other points to the leavetry op, which is needed for the eval scope.
      if ($op->name eq 'entertry') {
	$opsize = $op->size + (2*$Config{ptrsize});
	$arg = $PERL56 ? $optype_enum{LOGOP} : $opsize | $optype_enum{LOGOP} << 7;
        warn "[perl #80622] Upgrading entertry from BASEOP to LOGOP...\n" unless $quiet;
        bless $op, 'B::LOGOP';
      } elsif ($op->name eq 'aelemfast') {
        if (0) {
          my $class = ITHREADS ? 'PADOP' : 'SVOP';
          my $type  = ITHREADS ? $optype_enum{PADOP} : $optype_enum{SVOP};
          $opsize = $op->size + $Config{ptrsize};
          $arg = $PERL56 ? $type : $opsize | $type << 7;
          warn "Upgrading aelemfast from BASEOP to $class...\n" unless $quiet;
          bless $op, "B::$class";
        }
      } elsif ($DEBUGGING) { # only needed when we want to check for new wrong BASEOP's
	if (eval "require Opcodes;") {
	  my $class = Opcodes::opclass($op->type);
	  if ($class > 0) {
	    my $classname = $optype[$class];
            if ($classname) {
              my $name = $op->name;
              warn "Upgrading $name BASEOP to $classname...\n"  unless $quiet;
              bless $op, "B::".$classname;
            }
	  }
	}
      }
    }
    B::Assembler::maxopix($tix) if $debug{A};
    asm "newopx", $arg, sprintf( "$arg=size:%s,type:%d", $opsize, $op->type );
    asm "stop", $tix if $PERL56;
    $optab{$$op} = $opix = $ix = $tix++;
    $op->bsave($ix);
    $ix;
  }
}

sub B::SPECIAL::ix($) {
  my $spec = shift;
  my $ix   = $spectab{$$spec};
  defined($ix) ? $ix : do {
    B::Assembler::maxsvix($tix) if $debug{A};
    nice "[SPECIAL $tix]";
    asm "ldspecsvx", $$spec, $specialsv_name[$$spec];
    asm "stsv", $tix if $PERL56;
    $spectab{$$spec} = $varix = $tix++;
  }
}

sub B::SV::ix($) {
  my $sv = shift;
  my $ix = $svtab{$$sv};
  defined($ix) ? $ix : do {
    nice '[' . B::class($sv) . " $tix]";
    B::Assembler::maxsvix($tix) if $debug{A};
    my $flags = $sv->FLAGS;
    my $type = $flags & 0xff; # SVTYPEMASK
    # Set TMP_on, MY_off, not to be tidied (test 48),
    # otherwise pad_tidy will set PADSTALE_on and assert. Since 5.16 TMP and STALE share the same bit.
    #if (ref $sv eq 'B::NULL' and $sv->REFCNT > 1 and $] >= 5.016) {
      # $flags |= 0x00020000;  # SvPADTMP_on
      # $flags &= ~0x00040000; # SvPADMY_off
    #}
    asm "newsvx", $flags,
     $debug{Comment} ? sprintf("type=%d,flags=0x%x,%s", $type, $flags, sv_flags($sv)) : '';
    asm "stsv", $tix if $PERL56;
    $svtab{$$sv} = $varix = $ix = $tix++;
    $sv->bsave($ix);
    $ix;
  }
}

#sub B::PAD::ix($) {
#  my $sv = shift;
#  #if ($PERL522) {
#  #  my $ix = $svtab{$$sv};
#  #  defined($ix) ? $ix : do {
#  #    nice '[' . B::class($sv) . " $tix]";
#  #    B::Assembler::maxsvix($tix) if $debug{A};
#  #    asm "newpadx", 0,
#  #      $debug{Comment} ? sprintf("pad_new(flags=0x%x)", 0) : '';
#  #    $svtab{$$sv} = $varix = $ix = $tix++;
#  #    $sv->bsave($ix);
#  #    $ix;
#  #  }
#  #} else {
#  if ($$sv) {
#    bless $sv, 'B::AV';
#    return $sv->B::SV::ix;
#  } else {
#    0
#  }
#}

# since 5.18
sub B::PADLIST::ix($) {
  my $padl = shift;
  my $ix = $svtab{$$padl};
  defined($ix) ? $ix : do {
    nice '[' . B::class($padl) . " $tix]";
    B::Assembler::maxsvix($tix) if $debug{A};
    asm "newpadlx", 0,
     $debug{Comment} ? sprintf("pad_new(flags=0x%x)", 0) : '';
    $svtab{$$padl} = $varix = $ix = $tix++;
    $padl->bsave($ix);
    $ix;
  }
}

sub B::PADNAME::ix {
  my $pn = shift;
  my $ix = $svtab{$$pn};
  defined($ix) ? $ix : do {
    nice '[' . B::class($pn) . " $tix]";
    B::Assembler::maxsvix($tix) if $debug{A};
    my $pv = $pn->PVX;
    asm "newpadnx", $pv ? cstring $pv : "";
    $svtab{$$pn} = $varix = $ix = $tix++;
    $pn->bsave($ix);
    $ix;
  }
}

sub B::PADNAMELIST::ix {
  my $padnl = shift;
  if (!$PERL522) {
    return B::SV::ix(bless $padnl, 'B::AV');
  } else {
    my $ix = $svtab{$$padnl};
    defined($ix) ? $ix : do {
      nice '[' . B::class($padnl) . " $tix]";
      B::Assembler::maxsvix($tix) if $debug{A};
      my $max = $padnl->MAX;
      asm "newpadnlx", $max,
        $debug{Comment} ? sprintf("size=%d, %s", $max+1, sv_flags($padnl)) : '';
      $svtab{$$padnl} = $varix = $ix = $tix++;
      $padnl->bsave($ix);
      $ix;
    }
  }
}

sub B::GV::ix {
  my ( $gv, $desired ) = @_;
  my $ix = $svtab{$$gv};
  defined($ix) ? $ix : do {
    if ( $debug{G} and !$PERL510 ) {
      select *STDERR;
      eval "require B::Debug;";
      $gv->B::GV::debug;
      select *STDOUT;
    }
    if ( ( $PERL510 and $gv->isGV_with_GP )
      or ( !$PERL510 and !$PERL56 and $gv->GP ) )
    {    # only gv with gp
      my ( $svix, $avix, $hvix, $cvix, $ioix, $formix );
      # 510 without debugging misses B::SPECIAL::NAME
      my $name;
      if ( $PERL510
        and ( $gv->STASH->isa('B::SPECIAL') or $gv->isa('B::SPECIAL') ) )
      {
        $name = '_';
        nice '[GV] # "_"';
        return 0;
      }
      else {
        $name = $gv->STASH->NAME . "::"
          . ( B::class($gv) eq 'B::SPECIAL' ? '_' : $gv->NAME );
      }
      nice "[GV $tix]";
      B::Assembler::maxsvix($tix) if $debug{A};
      asm "gv_fetchpvx", cstring $name;
      asm "stsv", $tix if $PERL56;
      $svtab{$$gv} = $varix = $ix = $tix++;
      asm "sv_flags",  $gv->FLAGS, as_hex($gv->FLAGS);
      asm "sv_refcnt", $gv->REFCNT;
      asm "xgv_flags", $gv->GvFLAGS, as_hex($gv->GvFLAGS);

      asm "gp_refcnt", $gv->GvREFCNT;
      asm "load_glob", $ix if $name eq "CORE::GLOBAL::glob";
      return $ix
        unless $desired || desired $gv;
      $svix = $gv->SV->ix;
      $avix = $gv->AV->ix;
      $hvix = $gv->HV->ix;

      # XXX {{{{
      my $cv = $gv->CV;
      $cvix = $$cv && defined $files{ $cv->FILE } ? $cv->ix : 0;
      my $form = $gv->FORM;
      $formix = $$form && defined $files{ $form->FILE } ? $form->ix : 0;

      $ioix = $name !~ /STDOUT$/ ? $gv->IO->ix : 0;

      # }}}} XXX

      nice1 "-GP-", asm "ldsv", $varix = $ix, sv_flags($gv) unless $ix == $varix;
      asm "gp_sv", $svix, sv_flags( $gv->SV ) if $svix;
      asm "gp_av", $avix, sv_flags( $gv->AV ) if $avix;
      asm "gp_hv", $hvix, sv_flags( $gv->HV ) if $hvix;
      asm "gp_cv", $cvix, sv_flags( $gv->CV ) if $cvix;
      asm "gp_io", $ioix if $ioix;
      asm "gp_cvgen", $gv->CVGEN if $gv->CVGEN;
      asm "gp_form",  $formix if $formix;
      asm "gp_file",  pvix $gv->FILE;
      asm "gp_line",  $gv->LINE if $gv->LINE;
      asm "formfeed", $svix if $name eq "main::\cL";
    }
    else {
      nice "[GV $tix]";
      B::Assembler::maxsvix($tix) if $debug{A};
      asm "newsvx", $gv->FLAGS, $debug{Comment} ? sv_flags($gv) : '';
      asm "stsv", $tix if $PERL56;
      $svtab{$$gv} = $varix = $ix = $tix++;
      if ( !$PERL510 ) {
        asm "xgv_flags", $gv->GvFLAGS;  # GV_without_GP has no GvFlags
      }
      if ( !$PERL510 and !$PERL56 and $gv->STASH ) {
        my $stashix = $gv->STASH->ix;
        asm "xgv_stash", $stashix;
      }
      if ($PERL510 and $gv->FLAGS & 0x40000000) { # SVpbm_VALID
        my $bm = bless $gv, "B::BM";
        $bm->bsave($ix); # also saves magic
      } else {
        $gv->B::PVMG::bsave($ix);
      }
    }
    $ix;
  }
}

sub B::HV::ix {
  my $hv = shift;
  my $ix = $svtab{$$hv};
  defined($ix) ? $ix : do {
    my ( $ix, $i, @array );
    my $name = $hv->NAME;
    my $flags = $hv->FLAGS & ~SVf_READONLY;
    $flags &= ~SVf_PROTECT if $PERL522;
    if ($name) {
      nice "[STASH $tix]";
      B::Assembler::maxsvix($tix) if $debug{A};
      asm "gv_stashpvx", cstring $name;
      asm "ldsv", $tix if $PERL56;
      asm "sv_flags", $flags, as_hex($flags);
      $svtab{$$hv} = $varix = $ix = $tix++;
      asm "xhv_name", pvix $name;

      # my $pmrootix = $hv->PMROOT->ix;	# XXX
      asm "ldsv", $varix = $ix unless $ix == $varix;
      # asm "xhv_pmroot", $pmrootix;	# XXX
    }
    else {
      nice "[HV $tix]";
      B::Assembler::maxsvix($tix) if $debug{A};
      asm "newsvx", $flags, $debug{Comment} ? sv_flags($hv) : '';
      asm "stsv", $tix if $PERL56;
      $svtab{$$hv} = $varix = $ix = $tix++;
      my $stash = $hv->SvSTASH;
      my $stashix = $stash ? $hv->SvSTASH->ix : 0;
      for ( @array = $hv->ARRAY ) {
        next if $i = not $i;
        $_ = $_->ix;
      }
      nice1 "-HV-", asm "ldsv", $varix = $ix unless $ix == $varix;
      ( $i = not $i ) ? asm( "newpv", pvstring $_) : asm( "hv_store", $_ )
        for @array;
      if ( VERSION < 5.009 ) {
        asm "xnv", $hv->NVX;
      }
      asm "xmg_stash", $stashix if $stashix;
      asm( "xhv_riter", $hv->RITER ) if VERSION < 5.009;
    }
    asm "sv_refcnt", $hv->REFCNT if $hv->REFCNT != 1;
    asm "sv_flags", $hv->FLAGS, as_hex($hv->FLAGS) if $hv->FLAGS & SVf_READONLY;
    $ix;
  }
}

sub B::NULL::ix {
  my $sv = shift;
  $$sv ? $sv->B::SV::ix : 0;
}

sub B::NULL::opwalk { 0 }

#################################################

sub B::NULL::bsave {
  my ( $sv, $ix ) = @_;

  nice '-' . B::class($sv) . '-', asm "ldsv", $varix = $ix, sv_flags($sv)
    unless $ix == $varix;
  if ($PERL56) {
    asm "stsv", $ix;
  } else {
    asm "sv_refcnt", $sv->REFCNT if $sv->REFCNT != 1;
  }
}

sub B::SV::bsave;
*B::SV::bsave = *B::NULL::bsave;

sub B::RV::bsave($$) {
  my ( $sv, $ix ) = @_;
  my $rvix = $sv->RV->ix;
  $sv->B::NULL::bsave($ix);
  # RV with DEBUGGING already requires sv_flags before SvRV_set
  my $flags = $sv->FLAGS;
  $flags &= ~0x8000 if $flags & $SVt_PVGV and $PERL522; # no SVpgv_GP
  asm "sv_flags", $flags, as_hex($flags);
  asm "xrv", $rvix;
}

sub B::PV::bsave($$) {
  my ( $sv, $ix ) = @_;
  $sv->B::NULL::bsave($ix);
  return unless $sv;
  if ($PERL56) {
    #$sv->B::SV::bsave;
    if ($sv->FLAGS & $POK) {
      asm  "newpv", pvstring $sv->PV;
      asm  "xpv";
    }
  } elsif ($PERL518 and (($sv->FLAGS & SVf_IsCOW) == SVf_IsCOW)) { # COW
    asm "newpv", pvstring $sv->PV;
    asm "xpvshared";
  } elsif ($PERL510 and (($sv->FLAGS & 0x09000000) == 0x09000000)) { # SHARED
    if ($sv->FLAGS & 0x40000000 and !($sv->FLAGS & 0x00008000)) { # pbm_VALID, !SCREAM
      asm "newpv", pvstring $sv->PVBM;
    } else {
      asm "newpv", pvstring $sv->PV;
    }
    asm "xpvshared";
  } elsif ($PERL510 and $sv->FLAGS & 0x40000000 and !($sv->FLAGS & 0x00008000)) { # pbm_VALID, !SCREAM
    asm "newpv", pvstring $sv->PVBM;
    asm "xpv";
  } else {
    asm "newpv", pvstring $sv->PV;
    asm "xpv";
  }
}

sub B::IV::bsave($$) {
  my ( $sv, $ix ) = @_;
  return $sv->B::RV::bsave($ix)
    if $PERL512 and $sv->FLAGS & B::SVf_ROK;
  $sv->B::NULL::bsave($ix);
  if ($PERL56) {
    asm $sv->needs64bits ? "xiv64" : "xiv32", $sv->IVX;
  } else {
    asm "xiv", $sv->IVX;
  }
}

sub B::NV::bsave($$) {
  my ( $sv, $ix ) = @_;
  $sv->B::NULL::bsave($ix);
  asm "xnv", sprintf "%.40g", $sv->NVX;
}

sub B::PVIV::bsave($$) {
  my ( $sv, $ix ) = @_;
  if ($PERL56) {
    $sv->B::PV::bsave($ix);
  } else {
      $sv->POK ? $sv->B::PV::bsave($ix)
    : $sv->ROK ? $sv->B::RV::bsave($ix)
    :            $sv->B::NULL::bsave($ix);
  }
  if ($PERL510) { # See note below in B::PVNV::bsave
    return if $sv->isa('B::AV');
    return if $sv->isa('B::HV');
    return if $sv->isa('B::CV');
    return if $sv->isa('B::GV');
    return if $sv->isa('B::IO');
    return if $sv->isa('B::FM');
  }
  bwarn( sprintf( "PVIV sv:%s flags:0x%x", B::class($sv), $sv->FLAGS ) )
    if $debug{M};

  if ($PERL56) {
    my $iv = $sv->IVX;
    asm $sv->needs64bits ? "xiv64" : "xiv32", $iv;
  } else {
    # PVIV GV 8009, GV flags & (4000|8000) illegal (SVpgv_GP|SVp_POK)
    asm "xiv", !ITHREADS
      && (($sv->FLAGS & ($SVf_FAKE|SVf_READONLY)) == ($SVf_FAKE|SVf_READONLY))
         ? "0 # but true" : $sv->IVX;
  }
}

sub B::PVNV::bsave($$) {
  my ( $sv, $ix ) = @_;
  $sv->B::PVIV::bsave($ix);
  if ($PERL510) {
    # getting back to PVMG
    return if $sv->isa('B::AV');
    return if $sv->isa('B::HV');
    return if $sv->isa('B::CV');
    return if $sv->isa('B::FM');
    return if $sv->isa('B::GV');
    return if $sv->isa('B::IO');

    # cop_seq range instead of a double. (IV, NV)
    unless ($PERL522 or $sv->FLAGS & (SVf_NOK|SVp_NOK)) {
      asm "cop_seq_low", $sv->COP_SEQ_RANGE_LOW;
      asm "cop_seq_high", $sv->COP_SEQ_RANGE_HIGH;
      return;
    }
  }
  asm "xnv", sprintf "%.40g", $sv->NVX;
}

sub B::PVMG::domagic($$) {
  my ( $sv, $ix ) = @_;
  nice1 '-MAGICAL-'; # no empty line before
  my @mglist = $sv->MAGIC;
  my ( @mgix, @namix );
  for (@mglist) {
    my $mg = $_;
    push @mgix, $_->OBJ->ix;
    push @namix, $mg->PTR->ix if $mg->LENGTH == B::HEf_SVKEY;
    $_ = $mg;
  }

  nice1 '-' . B::class($sv) . '-', asm "ldsv", $varix = $ix unless $ix == $varix;
  for (@mglist) {
    next unless ord($_->TYPE);
    asm "sv_magic", ord($_->TYPE), cstring $_->TYPE;
    asm "mg_obj",   shift @mgix; # D sets itself, see mg.c:mg_copy
    my $length = $_->LENGTH;
    if ( $length == B::HEf_SVKEY and !$PERL56) {
      asm "mg_namex", shift @namix;
    }
    elsif ($length) {
      asm "newpv", pvstring $_->PTR;
      $PERL56
        ? asm "mg_pv"
        : asm "mg_name";
    }
  }
}

sub B::PVMG::bsave($$) {
  my ( $sv, $ix ) = @_;
  my $stashix = $sv->SvSTASH->ix;
  $sv->B::PVNV::bsave($ix);
  asm "xmg_stash", $stashix if $stashix;
  # XXX added SV->MAGICAL to 5.6 for compat
  $sv->domagic($ix) if $PERL56 ? MAGICAL56($sv) : $sv->MAGICAL;
}

sub B::PVLV::bsave($$) {
  my ( $sv, $ix ) = @_;
  my $targix = $sv->TARG->ix;
  $sv->B::PVMG::bsave($ix);
  asm "xlv_targ",    $targix unless $PERL56; # XXX really? xlv_targ IS defined
  asm "xlv_targoff", $sv->TARGOFF;
  asm "xlv_targlen", $sv->TARGLEN;
  asm "xlv_type",    $sv->TYPE;
}

sub B::BM::bsave($$) {
  my ( $sv, $ix ) = @_;
  $sv->B::PVMG::bsave($ix);
  asm "xpv_cur",      $sv->CUR if $] > 5.008;
  asm "xbm_useful",   $sv->USEFUL;
  asm "xbm_previous", $sv->PREVIOUS;
  asm "xbm_rare",     $sv->RARE;
}

sub B::IO::bsave($$) {
  my ( $io, $ix ) = @_;
  my $topix    = $io->TOP_GV->ix;
  my $fmtix    = $io->FMT_GV->ix;
  my $bottomix = $io->BOTTOM_GV->ix;
  $io->B::PVMG::bsave($ix);
  asm "xio_lines",       $io->LINES;
  asm "xio_page",        $io->PAGE;
  asm "xio_page_len",    $io->PAGE_LEN;
  asm "xio_lines_left",  $io->LINES_LEFT;
  asm "xio_top_name",    pvix $io->TOP_NAME;
  asm "xio_top_gv",      $topix;
  asm "xio_fmt_name",    pvix $io->FMT_NAME;
  asm "xio_fmt_gv",      $fmtix;
  asm "xio_bottom_name", pvix $io->BOTTOM_NAME;
  asm "xio_bottom_gv",   $bottomix;
  asm "xio_subprocess",  $io->SUBPROCESS unless $PERL510;
  asm "xio_type",        ord $io->IoTYPE;
  if ($PERL56) { # do not mess with PerlIO
    asm "xio_flags",       $io->IoFLAGS;
  } else {
    # XXX IOf_NOLINE off was added with 5.8, but not used (?)
    asm "xio_flags", ord($io->IoFLAGS) & ~32;		# XXX IOf_NOLINE 32
  }
  # issue93: restore std handles
  if (!$PERL56) {
    my $o = $io->object_2svref();
    eval "require ".ref($o).";";
    my $fd = $o->fileno();
    # use IO::Handle ();
    # my $fd = IO::Handle::fileno($o);
    bwarn( "io ix=$ix perlio no fileno for ".ref($o) ) if $fd < 0;
    my $i = 0;
    foreach (qw(stdin stdout stderr)) {
      if ($io->IsSTD($_) or $fd == -$i) { # negative stdout = error
	nice1 "-perlio_$_($fd)-";
	# bwarn( "io $ix perlio_$_($fd)" );
	asm "xio_flags",  $io->IoFLAGS;
	asm "xio_ifp",    $i;
      }
      $i++;
    }
  }
}

sub B::CV::bsave($$) {
  my ( $cv, $ix ) = @_;
  $B::Bytecode::curcv = $cv;
  my $stashix   = $cv->STASH->ix;
  my $gvix      = ($cv->GV and ref($cv->GV) ne 'B::SPECIAL') ? $cv->GV->ix : 0;
  my $padlistix = $cv->PADLIST->ix;
  my $outsideix = $cv->OUTSIDE->ix;
  # there's no main_cv->START optree since 5.18
  my $startix   = $cv->START->opwalk if $] < 5.018 or $$cv != ${main_cv()};
  my $rootix    = $cv->ROOT->ix;
  # TODO 5.14 will need CvGV_set to add backref magic
  my $xsubanyix  = ($cv->CONST and !$PERL56) ? $cv->XSUBANY->ix : 0;

  $cv->B::PVMG::bsave($ix);
  asm "xcv_stash",       $stashix if $stashix;
  asm "xcv_start",       $startix if $startix; # e.g. main_cv 5.18
  asm "xcv_root",        $rootix if $rootix;
  asm "xcv_xsubany",     $xsubanyix if !$PERL56 and $xsubanyix;
  asm "xcv_padlist",     $padlistix;
  asm "xcv_outside",     $outsideix if $outsideix;
  asm "xcv_outside_seq", $cv->OUTSIDE_SEQ if !$PERL56 and $cv->OUTSIDE_SEQ;
  asm "xcv_depth",       $cv->DEPTH if $cv->DEPTH;
  # add the RC flag if there's no backref magic. eg END (48)
  my $cvflags = $cv->CvFLAGS;
  $cvflags |= 0x400 if $] >= 5.013 and !$cv->MAGIC;
  asm "xcv_flags",       $cvflags;
  if ($gvix) {
    asm "xcv_gv",        $gvix;
  } elsif ($] >= 5.018001 and $cv->NAME_HEK) { # ignore main_cv
    asm "xcv_name_hek",  pvix $cv->NAME_HEK;   # set name_hek for lexsub (#130)
  #} elsif ($] >= 5.017004) {                   # 5.18.0 empty name, missing B API
  #  asm "xcv_name_hek",  pvix "_";
  }
  asm "xcv_file",        pvix $cv->FILE if $cv->FILE;    # XXX AD
}

sub B::FM::bsave($$) {
  my ( $form, $ix ) = @_;

  $form->B::CV::bsave($ix);
  asm "xfm_lines", $form->LINES;
}

# an AV or padl_sym
sub B::PAD::bsave($$) {
  my ( $av, $ix ) = @_;
  my @array = $av->ARRAY;
  $_ = $_->ix for @array; # save the elements
  $av->B::NULL::bsave($ix);
  my $fill = scalar @array;
  asm "av_extend", $fill if @array;
  if ($fill > 1 or $array[0]) {
    asm "av_pushx", $_ for @array;
  }
}

sub B::AV::bsave {
  my ( $av, $ix ) = @_;
  if (!$PERL56 and $av->MAGICAL) {
    $av->B::PVMG::bsave($ix);
    for ($av->MAGIC) {
      return if $_->TYPE eq 'P'; # 'P' tied AV has no ARRAY/FETCHSIZE,..., test 16
      # but e.g. 'I' (@ISA) has
    }
  }
  my @array = $av->ARRAY;
  $_ = $_->ix for @array; # hack. walks the ->ix methods to save the elements
  my $stashix = $av->SvSTASH->ix;
  nice "-AV-",
    asm "ldsv", $varix = $ix, sv_flags($av) unless $ix == $varix;

  if ($PERL56) {
    # SvREADONLY_off($av) w PADCONST
    asm "sv_flags", $av->FLAGS & ~SVf_READONLY, as_hex($av->FLAGS);
    $av->domagic($ix) if MAGICAL56($av);
    asm "xav_flags", $av->AvFLAGS, as_hex($av->AvFLAGS);
    asm "xav_max", -1;
    asm "xav_fill", -1;
    if ($av->FILL > -1) {
      asm "av_push", $_ for @array;
    } else {
      asm "av_extend", $av->MAX if $av->MAX >= 0 and $av->{ref} ne 'PAD';
    }
    asm "sv_flags", $av->FLAGS if $av->FLAGS & SVf_READONLY; # restore flags
  } else {
    #$av->domagic($ix) if $av->MAGICAL; # XXX need tests for magic arrays
    asm "av_extend", $av->MAX if $av->MAX >= 0;
    asm "av_pushx", $_ for @array;
    if ( !$PERL510 ) {        # VERSION < 5.009
      asm "xav_flags", $av->AvFLAGS, as_hex($av->AvFLAGS);
    }
    # asm "xav_alloc", $av->AvALLOC if $] > 5.013002; # XXX new but not needed
  }
  asm "sv_refcnt", $av->REFCNT if $av->REFCNT != 1;
  asm "xmg_stash", $stashix if $stashix;
}

# since 5.18
sub B::PADLIST::bsave {
  my ( $padl, $ix ) = @_;
  my @array = $padl->ARRAY;
  my $max = scalar @array;
  bless $array[0], 'B::PADNAMELIST' if ref $array[0] eq 'B::AV';
  bless $array[1], 'B::PAD' if ref $array[1] eq 'B::AV';
  my $pnl = $array[0]->ix; # padnamelist
  my $pad = $array[1]->ix; # pad syms
  nice "-PADLIST-",
    asm "ldsv", $varix = $ix unless $ix == $varix;
  asm "padl_name", $pnl;
  asm "padl_sym",  $pad;
  if ($PERL522) {
    asm "padl_id",    $padl->id if $padl->id;
    # 5.18-20 has no PADLIST->outid API, uses xcv_outside instead
    asm "padl_outid", $padl->outid if $padl->outid;
  }
}

# since 5.22
sub B::PADNAME::bsave {
  my ( $pn, $ix ) = @_;
  my $stashix = $pn->OURSTASH->ix;
  my $typeix = $pn->TYPE->ix;
  nice "-PADNAME-",
    asm "ldsv", $varix = $ix unless $ix == $varix;
  asm "padn_pv", cstring $pn->PV if $pn->LEN;
  my $flags = $pn->FLAGS;
  asm "padn_stash", $stashix if $stashix;
  asm "padn_type", $typeix if $typeix;
  asm "padn_flags", $flags & 0xff if $flags & 0xff; # turn of SVf_FAKE, U8 only
  asm "padn_seq_low", $pn->COP_SEQ_RANGE_LOW;
  asm "padn_seq_high", $pn->COP_SEQ_RANGE_HIGH;
  asm "padn_refcnt", $pn->REFCNT if $pn->REFCNT != 1;
  #asm "padn_len", $pn->LEN if $pn->LEN;
}

# since 5.22
sub B::PADNAMELIST::bsave {
  my ( $padnl, $ix ) = @_;
  my @array = $padnl->ARRAY;
  $_ = $_->ix for @array;
  nice "-PADNAMELIST-",
    asm "ldsv", $varix = $ix unless $ix == $varix;
  asm "padnl_push", $_ for @array;
}

sub B::GV::desired {
  my $gv = shift;
  my ( $cv, $form );
  if ( $debug{Gall} and !$PERL510 ) {
    select *STDERR;
    eval "require B::Debug;";
    $gv->debug;
    select *STDOUT;
  }
  $files{ $gv->FILE } && $gv->LINE
    || ${ $cv   = $gv->CV }   && $files{ $cv->FILE }
    || ${ $form = $gv->FORM } && $files{ $form->FILE };
}

sub B::HV::bwalk {
  my $hv = shift;
  return if $walked{$$hv}++;
  my %stash = $hv->ARRAY;
  #while ( my ( $k, $v ) = each %stash )
  foreach my $k (keys %stash) {
    my $v = $stash{$k};
    if ( !$PERL56 and $v->SvTYPE == $SVt_PVGV ) { # XXX ref $v eq 'B::GV'
      my $hash = $v->HV if $v->can("HV");
      if ( $hash and $$hash && $hash->NAME ) {
        $hash->bwalk;
      }
      # B since 5.13.6 (744aaba0598) pollutes our namespace. Keep it clean
      # XXX This fails if our source really needs any B constant
      unless ($] > 5.013005 and $hv->NAME eq 'B') {
	$v->ix(1) if $v->can("desired") and desired $v;
      }
    }
    else {
      if ($] > 5.013005 and $hv->NAME eq 'B') { # see above. omit B prototypes
	return;
      }
      nice "[prototype $tix]";
      B::Assembler::maxsvix($tix) if $debug{A};
      asm "gv_fetchpvx", cstring ($hv->NAME . "::" . $k);
      $svtab{$$v} = $varix = $tix;
      # we need the sv_flags before, esp. for DEBUGGING asserts
      asm "sv_flags",  $v->FLAGS, as_hex($v->FLAGS);
      $v->bsave( $tix++ );
    }
  }
}

######################################################

sub B::OP::bsave_thin {
  my ( $op, $ix ) = @_;
  bwarn( B::peekop($op), ", ix: $ix" ) if $debug{o};
  my $next   = $op->next;
  my $nextix = $optab{$$next};
  $nextix = 0, push @cloop, $op unless defined $nextix;
  if ( $ix != $opix ) {
    nice '-' . $op->name . '-', asm "ldop", $opix = $ix;
  }
  asm "op_flags",   $op->flags, op_flags( $op->flags ) if $op->flags;
  asm "op_next",    $nextix;
  asm "op_targ",    $op->targ if $op->type and $op->targ;  # tricky
  asm "op_private", $op->private if $op->private;          # private concise flags?
  if ($] >= 5.017 and $op->can('slabbed')) {
    asm "op_slabbed", $op->slabbed if $op->slabbed;
    asm "op_savefree", $op->savefree if $op->savefree;
    asm "op_static", $op->static if $op->static;
    if ($] >= 5.019002 and $op->can('folded')) {
      asm "op_folded", $op->folded if $op->folded;
    }
    if ($] >= 5.021002 and $] < 5.021011 and $op->can('lastsib')) {
      asm "op_lastsib", $op->lastsib if $op->lastsib;
    }
    elsif ($] >= 5.021011 and $op->can('moresib')) {
      asm "op_moresib", $op->moresib if $op->moresib;
    }
  }
}

sub B::OP::bsave;
*B::OP::bsave = *B::OP::bsave_thin;

sub B::UNOP::bsave {
  my ( $op, $ix ) = @_;
  my $name    = $op->name;
  my $flags   = $op->flags;
  my $first   = $op->first;
  my $firstix = $name =~ /fl[io]p/

    # that's just neat
    || ( !ITHREADS && $name eq 'regcomp' )

    # trick for /$a/o in pp_regcomp
    || $name eq 'rv2sv'
    && $op->flags & OPf_MOD
    && $op->private & OPpLVAL_INTRO

    # change #18774 (localref) made my life hard (commit 82d039840b913b4)
    ? $first->ix
    : 0;

  # XXX Are there more new UNOP's with first?
  $firstix = $first->ix if $name eq 'require'; #issue 97
  $op->B::OP::bsave($ix);
  asm "op_first", $firstix;
}

sub B::UNOP_AUX::bsave {
  my ( $op, $ix ) = @_;
  my $name    = $op->name;
  my $flags   = $op->flags;
  my $first   = $op->first;
  my $firstix = $first->ix;
  my $aux     = $op->aux;
  my @aux_list = $op->aux_list($B::Bytecode::curcv);
  for my $item (@aux_list) {
    $item->ix if ref $item;
  }
  $op->B::OP::bsave($ix);
  asm "op_first", $firstix;
  asm "unop_aux", cstring $op->aux;
}

sub B::METHOP::bsave($$) {
  my ( $op, $ix ) = @_;
  my $name    = $op->name;
  my $firstix = $name eq 'method' ? $op->first->ix : $op->meth_sv->ix;
  my $rclass  = $op->rclass->ix;
  $op->B::OP::bsave($ix);
  if ($op->name eq 'method') {
    asm "op_first", $firstix;
  } else {
    asm "methop_methsv", $firstix;
  }
  asm "methop_rclass", $rclass if $rclass or ITHREADS; # padoffset 0 valid threaded
}

sub B::BINOP::bsave($$) {
  my ( $op, $ix ) = @_;
  if ( $op->name eq 'aassign' && $op->private & B::OPpASSIGN_HASH() ) {
    my $last   = $op->last;
    my $lastix = do {
      local *B::OP::bsave   = *B::OP::bsave_fat;
      local *B::UNOP::bsave = *B::UNOP::bsave_fat;
      #local *B::BINOP::bsave = *B::BINOP::bsave_fat;
      $last->ix;
    };
    asm "ldop", $lastix unless $lastix == $opix;
    asm "op_targ", $last->targ;
    $op->B::OP::bsave($ix);
    asm "op_last", $lastix;
  }
  else {
    $op->B::OP::bsave($ix);
  }
}

# not needed if no pseudohashes

*B::BINOP::bsave = *B::OP::bsave if $PERL510;    #VERSION >= 5.009;

# deal with sort / formline

sub B::LISTOP::bsave($$) {
  my ( $op, $ix ) = @_;
  bwarn( B::peekop($op), ", ix: $ix" ) if $debug{o};
  my $name = $op->name;
  sub blocksort() { OPf_SPECIAL | OPf_STACKED }
  if ( $name eq 'sort' && ( $op->flags & blocksort ) == blocksort ) {
    # Note: 5.21.2 PERL_OP_PARENT support work in progress
    my $first    = $op->first;
    my $pushmark = $first->sibling; # XXX may be B::NULL
    my $rvgv     = $pushmark->first;
    my $leave    = $rvgv->first;

    my $leaveix = $leave->ix;
    #asm "comment", "leave" unless $quiet;

    my $rvgvix = $rvgv->ix;
    asm "ldop", $rvgvix unless $rvgvix == $opix;
    #asm "comment", "rvgv" unless $quiet;
    asm "op_first", $leaveix;

    my $pushmarkix = $pushmark->ix;
    asm "ldop", $pushmarkix unless $pushmarkix == $opix;
    #asm "comment", "pushmark" unless $quiet;
    asm "op_first", $rvgvix;

    my $firstix = $first->ix;
    asm "ldop", $firstix unless $firstix == $opix;
    #asm "comment", "first" unless $quiet;
    asm "op_sibling", $pushmarkix if $first->has_sibling;

    $op->B::OP::bsave($ix);
    asm "op_first", $firstix;
  }
  elsif ( $name eq 'formline' ) {
    $op->B::UNOP::bsave_fat($ix);
  }
  elsif ( $name eq 'dbmopen' ) {
    require AnyDBM_File;
    $op->B::OP::bsave($ix);
  }
  else {
    $op->B::OP::bsave($ix);
  }
}

# fat versions

# or parent since 5.22
sub B::OP::has_sibling($) {
  my $op = shift;
  return $op->moresib if $op->can('moresib'); #5.22
  return $op->lastsib if $op->can('lastsib'); #5.21
  return 1;
}

sub B::OP::bsave_fat($$) {
  my ( $op, $ix ) = @_;

  if ($op->has_sibling) {
    my $sibling = $op->sibling; # might be B::NULL with 5.22 and PERL_OP_PARENT
    my $siblix = $sibling->ix;
    $op->B::OP::bsave_thin($ix);
    asm "op_sibling", $siblix;
  } elsif ($] > 5.021011 and ref($op->parent) ne 'B::NULL') {
    my $parent = $op->parent;
    my $pix = $parent->ix;
    $op->B::OP::bsave_thin($ix);
    asm "op_sibling", $pix; # but renamed to op_sibparent
  } else {
    $op->B::OP::bsave_thin($ix);
  }
  # asm "op_seq", -1;			XXX don't allocate OPs piece by piece
}

sub B::UNOP::bsave_fat {
  my ( $op, $ix ) = @_;
  my $firstix = $op->first->ix;

  $op->B::OP::bsave($ix);
  asm "op_first", $firstix;
}

sub B::BINOP::bsave_fat {
  my ( $op, $ix ) = @_;
  my $last   = $op->last;
  my $lastix = $op->last->ix;
  bwarn( B::peekop($op), ", ix: $ix $last: $last, lastix: $lastix" )
    if $debug{o};
  if ( !$PERL510 && $op->name eq 'aassign' && $last->name eq 'null' ) {
    asm "ldop", $lastix unless $lastix == $opix;
    asm "op_targ", $last->targ;
  }

  $op->B::UNOP::bsave($ix);
  asm "op_last", $lastix;
}

sub B::LOGOP::bsave {
  my ( $op, $ix ) = @_;
  my $otherix = $op->other->ix;
  bwarn( B::peekop($op), ", ix: $ix" ) if $debug{o};

  $op->B::UNOP::bsave($ix);
  asm "op_other", $otherix;
}

sub B::PMOP::bsave {
  my ( $op, $ix ) = @_;
  my ( $rrop, $rrarg, $rstart );

  # my $pmnextix = $op->pmnext->ix;	# XXX
  bwarn( B::peekop($op), " ix: $ix" ) if $debug{M} or $debug{o};
  if (ITHREADS) {
    if ( $op->name eq 'subst' ) {
      $rrop   = "op_pmreplroot";
      $rrarg  = $op->pmreplroot->ix;
      $rstart = $op->pmreplstart->ix;
    }
    elsif ( $op->name eq 'pushre' ) {
      $rrarg = $op->pmreplroot;
      $rrop  = "op_pmreplrootpo";
    }
    $op->B::BINOP::bsave($ix);
    if ( !$PERL56 and $op->pmstashpv )
    {    # avoid empty stash? if (table) pre-compiled else re-compile
      if ( !$PERL510 ) {
        asm "op_pmstashpv", pvix $op->pmstashpv;
      }
      else {
        # XXX crash in 5.10, 5.11. Only used in OP_MATCH, with PMf_ONCE set
        if ( $op->name eq 'match' and $op->op_pmflags & 2) {
          asm "op_pmstashpv", pvix $op->pmstashpv;
        } else {
          bwarn("op_pmstashpv ignored") if $debug{M};
        }
      }
    }
    elsif ($PERL56) { # ignored
      ;
    }
    else {
      bwarn("op_pmstashpv main") if $debug{M};
      asm "op_pmstashpv", pvix "main" unless $PERL510;
    }
  } # ithreads
  else {
    $rrop  = "op_pmreplrootgv";
    $rrarg  = $op->pmreplroot->ix;
    $rstart = $op->pmreplstart->ix if $op->name eq 'subst';
    # 5.6 walks down the pmreplrootgv here
    # $op->pmreplroot->save($rrarg) unless $op->name eq 'pushre';
    my $stashix = $op->pmstash->ix unless $PERL56;
    $op->B::BINOP::bsave($ix);
    asm "op_pmstash", $stashix unless $PERL56;
  }

  asm $rrop, $rrarg if $rrop;
  asm "op_pmreplstart", $rstart if $rstart;

  if ( !$PERL510 ) {
    bwarn( "PMOP op_pmflags: ", $op->pmflags ) if $debug{M};
    asm "op_pmflags",     $op->pmflags;
    asm "op_pmpermflags", $op->pmpermflags;
    asm "op_pmdynflags",  $op->pmdynflags unless $PERL56;
    # asm "op_pmnext", $pmnextix;	# XXX broken
    # Special sequence: This is the arg for the next pregcomp
    asm "newpv", pvstring $op->precomp;
    asm "pregcomp";
  }
  elsif ($PERL510) {
    # Since PMf_BASE_SHIFT we need a U32, which is a new bytecode for
    # backwards compat
    asm "op_pmflags", $op->pmflags;
    bwarn("PMOP op_pmflags: ", $op->pmflags) if $debug{M};
    my $pv = $op->precomp;
    asm "newpv", pvstring $pv;
    asm "pregcomp";
    # pregcomp does not set the extflags correctly, just the pmflags
    asm "op_reflags", $op->reflags if $pv; # so overwrite the extflags
  }
}

sub B::SVOP::bsave {
  my ( $op, $ix ) = @_;
  my $svix = $op->sv->ix;

  $op->B::OP::bsave($ix);
  asm "op_sv", $svix;
}

sub B::PADOP::bsave {
  my ( $op, $ix ) = @_;

  $op->B::OP::bsave($ix);

  # XXX crashed in 5.11 (where, why?)
  #if ($PERL512) {
  asm "op_padix", $op->padix;
  #}
}

sub B::PVOP::bsave {
  my ( $op, $ix ) = @_;
  $op->B::OP::bsave($ix);
  return unless my $pv = $op->pv;

  if ( $op->name eq 'trans' ) {
    asm "op_pv_tr", join ',', length($pv) / 2, unpack( "s*", $pv );
  }
  else {
    asm "newpv", pvstring $pv;
    asm "op_pv";
  }
}

sub B::LOOP::bsave {
  my ( $op, $ix ) = @_;
  my $nextix = $op->nextop->ix;
  my $lastix = $op->lastop->ix;
  my $redoix = $op->redoop->ix;

  $op->B::BINOP::bsave($ix);
  asm "op_redoop", $redoix;
  asm "op_nextop", $nextix;
  asm "op_lastop", $lastix;
}

sub B::COP::bsave {
  my ( $cop, $ix ) = @_;
  my $warnix = $cop->warnings->ix;
  if (ITHREADS) {
    $cop->B::OP::bsave($ix);
    asm "cop_stashpv", pvix $cop->stashpv, $cop->stashpv;
    asm "cop_file",    pvix $cop->file,    $cop->file;
  }
  else {
    my $stashix = $cop->stash->ix;
    my $fileix  = $PERL56 ? pvix($cop->file) : $cop->filegv->ix(1);
    $cop->B::OP::bsave($ix);
    asm "cop_stash",  $stashix;
    asm "cop_filegv", $fileix;
  }
  asm "cop_label", pvix $cop->label, $cop->label if $cop->label;    # XXX AD
  asm "cop_seq", $cop->cop_seq;
  asm "cop_arybase", $cop->arybase unless $PERL510;
  asm "cop_line", $cop->line;
  asm "cop_warnings", $warnix;
  if ( !$PERL510 and !$PERL56 ) {
    asm "cop_io", $cop->io->ix;
  }
}

sub B::OP::opwalk {
  my $op = shift;
  my $ix = $optab{$$op};
  defined($ix) ? $ix : do {
    my $ix;
    my @oplist = ($PERL56 and $op->isa("B::COP"))
      ? () : $op->oplist; # 5.6 may be called by a COP
    push @cloop, undef;
    $ix = $_->ix while $_ = pop @oplist;
    #print "\n# rest of cloop\n";
    while ( $_ = pop @cloop ) {
      asm "ldop",    $optab{$$_};
      asm "op_next", $optab{ ${ $_->next } };
    }
    $ix;
  }
}

# Do run-time requires with -b savebegin and without -i includeall.
# Otherwise all side-effects of BEGIN blocks are already in the current
# compiled code.
# -b or !-i will have smaller code, but run-time access of dependent modules
# such as with python, where all modules are byte-compiled.
# With -i the behaviour is similar to the C or CC compiler, where everything
# is packed into one file.
# Redo only certain ops, such as push @INC ""; unshift @INC "" (TODO *INC)
# use/require defs and boot sections are already included.
sub save_begin {
  my $av;
  if ( ( $av = begin_av )->isa("B::AV") and $av->ARRAY) {
    nice '<push_begin>';
    if ($savebegins) {
      for ( $av->ARRAY ) {
        next unless $_->FILE eq $0;
        asm "push_begin", $_->ix;
      }
    }
    else {
      for ( $av->ARRAY ) {
        next unless $_->FILE eq $0;

        # XXX BEGIN { goto A while 1; A: }
        for ( my $op = $_->START ; $$op ; $op = $op->next ) {
	  # 1. push|unshift @INC, "libpath"
	  if ($op->name eq 'gv') {
            my $gv = B::class($op) eq 'SVOP'
                  ? $op->gv
                  : ( ( $_->PADLIST->ARRAY )[1]->ARRAY )[ $op->padix ];
	    nice1 '<gv '.$gv->NAME.'>' if $$gv;
            asm "incav", inc_gv->AV->ix if $$gv and $gv->NAME eq 'INC'; 
	  }
	  # 2. use|require
	  if (!$includeall) {
	    next unless $op->name eq 'require' ||
              # this kludge needed for tests
              $op->name eq 'gv' && do {
                my $gv = B::class($op) eq 'SVOP'
                  ? $op->gv
                  : ( ( $_->PADLIST->ARRAY )[1]->ARRAY )[ $op->padix ];
                $$gv && $gv->NAME =~ /use_ok|plan/;
              };
              nice1 '<require in BEGIN>';
              asm "push_begin", $_->ix if $_;
              last;
	   }
        }
      }
    }
  }
}

sub save_init_end {
  my $av;
  if ( ( $av = init_av )->isa("B::AV") and $av->ARRAY ) {
    nice '<push_init>';
    for ( $av->ARRAY ) {
      next unless $_->FILE eq $0;
      asm "push_init", $_->ix;
    }
  }
  if ( ( $av = end_av )->isa("B::AV") and $av->ARRAY ) {
    nice '<push_end>';
    for ( $av->ARRAY ) {
      next unless $_->FILE eq $0;
      asm "push_end", $_->ix;
    }
  }
}

################### perl 5.6 backport only ###################################

sub B::GV::bytecodecv {
  my $gv = shift;
  my $cv = $gv->CV;
  if ( $$cv && !( $gv->FLAGS & 0x80 ) ) { # GVf_IMPORTED_CV / && !saved($cv)
    if ($debug{cv}) {
      bwarn(sprintf( "saving extra CV &%s::%s (0x%x) from GV 0x%x\n",
        $gv->STASH->NAME, $gv->NAME, $$cv, $$gv ));
    }
    $gv->bsave;
  }
}

sub symwalk {
  no strict 'refs';
  my $ok = 1
    if grep { ( my $name = $_[0] ) =~ s/::$//; $_ eq $name; } @packages;
  if ( grep { /^$_[0]/; } @packages ) {
    walksymtable( \%{"$_[0]"}, "desired", \&symwalk, $_[0] );
  }
  bwarn("considering $_[0] ... " . ( $ok ? "accepted\n" : "rejected\n" ))
    if $debug{b};
  $ok;
}

################### end perl 5.6 backport ###################################

sub compile {
  my ( $head, $scan, $keep_syn, $module );
  my $cwd = '';
  $files{$0} = 1;
  $DB::single=1 if defined &DB::DB;
  # includeall mode (without require):
  if ($includeall) {
    # add imported symbols => values %INC
    $files{$_} = 1 for values %INC;
  }

  sub keep_syn {
    $keep_syn         = 1;
    *B::OP::bsave     = *B::OP::bsave_fat;
    *B::UNOP::bsave   = *B::UNOP::bsave_fat;
    *B::BINOP::bsave  = *B::BINOP::bsave_fat;
    #*B::LISTOP::bsave = *B::LISTOP::bsave_fat;
    #*B::LOGOP::bsave  = *B::LOGOP::bsave_fat;
    #*B::PMOP::bsave   = *B::PMOP::bsave_fat;
  }
  sub bwarn { print STDERR "Bytecode.pm: @_\n" unless $quiet; }

  for (@_) {
    if (/^-q(q?)/) {
      $quiet = 1;
    }
    elsif (/^-S/) {
      $debug{Comment} = 1;
      $debug{-S} = 1;
      *newasm = *endasm = sub { };
      *asm = sub($;$$) {
        undef $_[2] if defined $_[2] and $quiet;
        ( defined $_[2] )
          ? print $_[0], " ", $_[1], "\t# ", $_[2], "\n"
          : print "@_\n";
      };
      *nice = sub ($) { print "\n# @_\n" unless $quiet; };
      *nice1 = sub ($) { print "# @_\n" unless $quiet; };
    }
    elsif (/^-v/) {
      warn "conflicting -q ignored" if $quiet;
      *nice = sub ($) { print "\n# @_\n"; print STDERR "@_\n" };
      *nice1 = sub ($) { print "# @_\n"; print STDERR "@_\n" };
    }
    elsif (/^-H/) {
      require ByteLoader;
      my $version = $ByteLoader::VERSION;
      $head = "#! $^X
use ByteLoader '$ByteLoader::VERSION';
";

      # Maybe: Fix the plc reader, if 'perl -MByteLoader <.plc>' is called
    }
    elsif (/^-k/) {
      keep_syn() if !$PERL510 or $PERL522;
    }
    elsif (/^-m/) {
      $module = 1;
    }
    elsif (/^-o(.*)$/) {
      open STDOUT, ">$1" or die "open $1: $!";
    }
    elsif (/^-F(.*)$/) {
      $files{$1} = 1;
    }
    elsif (/^-i/) {
      $includeall = 1;
    }
    elsif (/^-D(.*)$/) {
      $debug{$1}++;
    }
    elsif (/^-s(.*)$/) {
      $scan = length($1) ? $1 : $0;
    }
    elsif (/^-b/) {
      $savebegins = 1;
    } # this is here for the testsuite
    elsif (/^-TI/) {
      $T_inhinc = 1;
    }
    elsif (/^-TF(.*)/) {
      my $thatfile = $1;
      *B::COP::file = sub { $thatfile };
    }
    # Use -m instead for modules
    elsif (/^-u(.*)/ and $PERL56) {
      my $arg ||= $1;
      push @packages, $arg;
    }
    else {
      bwarn "Ignoring '$_' option";
    }
  }
  if ($scan) {
    my $f;
    if ( open $f, $scan ) {
      while (<$f>) {
        /^#\s*line\s+\d+\s+("?)(.*)\1/ and $files{$2} = 1;
        /^#/ and next;
        if ( /\bgoto\b\s*[^&]/ && !$keep_syn ) {
          bwarn "keeping the syntax tree: \"goto\" op found";
          keep_syn;
        }
      }
    }
    else {
      bwarn "cannot rescan '$scan'";
    }
    close $f;
  }
  binmode STDOUT;
  return sub {
    if ($debug{-S}) {
      my $header = B::Assembler::gen_header_hash;
      asm sprintf("#%-10s\t","magic").sprintf("0x%x",$header->{magic});
      for (qw(archname blversion ivsize ptrsize byteorder longsize archflag
              perlversion)) {
	asm sprintf("#%-10s\t",$_).$header->{$_};
      }
    }
    print $head if $head;
    newasm sub { print @_ };

    nice '<incav>' if $T_inhinc;
    asm "incav", inc_gv->AV->ix if $T_inhinc;
    save_begin;
    #asm "incav", inc_gv->AV->ix if $T_inhinc;
    nice '<end_begin>';
    if (!$PERL56) {
      defstash->bwalk;
    } else {
      if ( !@packages ) {
        # support modules?
	@packages = qw(main);
      }
      for (@packages) {
	no strict qw(refs);
        #B::svref_2object( \%{"$_\::"} )->bwalk;
	walksymtable( \%{"$_\::"}, "bytecodecv", \&symwalk );
      }
      walkoptree( main_root, "bsave" ) unless ref(main_root) eq "B::NULL";
    }

    asm "signal", cstring "__WARN__"    # XXX
      if !$PERL56 and warnhook->ix;
    save_init_end;

    unless ($module) {
      $B::Bytecode::curcv = main_cv;
      nice '<main_start>';
      asm "main_start", $PERL56 ? main_start->ix : main_start->opwalk;
      #asm "main_start", main_start->opwalk;
      nice '<main_root>';
      asm "main_root",  main_root->ix;
      nice '<main_cv>';
      asm "main_cv",    main_cv->ix;
      nice '<curpad>';
      asm "curpad",     ( comppadlist->ARRAY )[1]->ix;
    }
    asm "dowarn", dowarn unless $PERL56;

    {
      no strict 'refs';
      nice "<DATA>";
      my $dh = $PERL56 ? *main::DATA : *{ defstash->NAME . "::DATA" };
      unless ( eof $dh ) {
        local undef $/;
        asm "data", ord 'D' if !$PERL56;
        print <$dh>;
      }
      else {
        asm "ret";
      }
    }

    endasm;
  }
}

1;

=head1 NAME

B::Bytecode - Perl compiler's bytecode backend

=head1 SYNOPSIS

B<perl -MO=Bytecode>[B<,-H>][B<,-o>I<script.plc>] I<script.pl>

=head1 DESCRIPTION

Compiles a Perl script into a bytecode format that could be loaded
later by the ByteLoader module and executed as a regular Perl script.
This saves time for the optree parsing and compilation and space for
the sourcecode in memory.

=head1 EXAMPLE

    $ perl -MO=Bytecode,-H,-ohi -e 'print "hi!\n"'
    $ perl hi
    hi!

=head1 OPTIONS

=over 4

=item B<-H>

Prepend a C<use ByteLoader VERSION;> line to the produced bytecode.
This way you will not need to add C<-MByteLoader> to your perl command-line.

Beware: This option does not yet work with 5.18 and higher. You need to use
C<-MByteLoader> still.

=item B<-i> includeall

Include all used packages and its symbols. Does no run-time require from
BEGIN blocks (C<use> package).

This creates bigger and more independent code, but is more error prone and
does not support pre-compiled C<.pmc> modules.

It is highly recommended to use C<-i> together with C<-b> I<safebegin>.

=item B<-b> savebegin

Save all the BEGIN blocks.

Normally only BEGIN blocks that C<require>
other files (ex. C<use Foo;>) or push|unshift
to @INC are saved.

=item B<-k>

Keep the syntax tree - it is stripped by default.

=item B<-o>I<outfile>

Put the bytecode in <outfile> instead of dumping it to STDOUT.

=item B<-s>

Scan the script for C<# line ..> directives and for <goto LABEL>
expressions. When gotos are found keep the syntax tree.

=item B<-S>

Output assembler source rather than piping it through the assembler
and outputting bytecode.
Without C<-q> the assembler source is commented.

=item B<-m>

Compile to a F<.pmc> module rather than to a single standalone F<.plc> program.

Currently this just means that the bytecodes for initialising C<main_start>,
C<main_root>, C<main_cv> and C<curpad> are omitted.

=item B<-u>I<package>

"use package." Might be needed of the package is not automatically detected.

=item B<-F>I<file>

Include file. If not C<-i> define all symbols in the given included
source file. C<-i> would all included files,
C<-F> only a certain file - full path needed.

=item B<-q>

Be quiet.

=item B<-v>

Be verbose.

=item B<-TI>

Restore full @INC for running within the CORE testsuite.

=item B<-TF> I<cop file>

Set the COP file - for running within the CORE testsuite.

=item B<-Do>

OPs, prints each OP as it's processed

=item B<-DM>

Debugging flag for more verbose STDERR output.

B<M> for Magic and Matches.

=item B<-DG>

Debug GV's

=item B<-DA>

Set developer B<A>ssertions, to help find possible obj-indices out of range.

=back

=head1 KNOWN BUGS

=over 4

=item *

5.10 threaded fails with setting the wrong MATCH op_pmflags
5.10 non-threaded fails calling anoncode, ...

=item *

C<BEGIN { goto A: while 1; A: }> won't even compile.

=item *

C<?...?> and C<reset> do not work as expected.

=item *

variables in C<(?{ ... })> constructs are not properly scoped.

=item *

Scripts that use source filters will fail miserably.

=item *

Special GV's fail.

=back

=head1 NOTICE

There are also undocumented bugs and options.

=head1 AUTHORS

Originally written by Malcolm Beattie 1996 and
modified by Benjamin Stuhl <sho_pi@hotmail.com>.

Rewritten by Enache Adrian <enache@rdslink.ro>, 2003 a.d.

Enhanced by Reini Urban <rurban@cpan.org>, 2008-2012

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=2:
