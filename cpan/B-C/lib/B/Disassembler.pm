#      Disassembler.pm
#
#      Copyright (c) 1996 Malcolm Beattie
#      Copyright (c) 2008,2009,2010,2011,2012 Reini Urban
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.

$B::Disassembler::VERSION = '1.13';

package B::Disassembler::BytecodeStream;

use FileHandle;
use Carp;
use Config qw(%Config);
use B qw(cstring cast_I32);
@ISA = qw(FileHandle);

sub readn {
  my ( $fh, $len ) = @_;
  my $data;
  read( $fh, $data, $len );
  croak "reached EOF while reading $len bytes" unless length($data) == $len;
  return $data;
}

sub GET_U8 {
  my $fh = shift;
  my $c  = $fh->getc;
  croak "reached EOF while reading U8" unless defined($c);
  return ord($c);
}

sub GET_U16 {
  my $fh  = shift;
  my $str = $fh->readn(2);
  croak "reached EOF while reading U16" unless length($str) == 2;

  # Todo: check byteorder
  return unpack( "S", $str );
}

sub GET_NV {
  my $fh = shift;
  my ( $str, $c );
  while ( defined( $c = $fh->getc ) && $c ne "\0" ) {
    $str .= $c;
  }
  croak "reached EOF while reading double" unless defined($c);
  return $str;
}

sub GET_U32 {
  my $fh  = shift;
  my $str = $fh->readn(4);
  croak "reached EOF while reading U32" unless length($str) == 4;

  # Todo: check byteorder
  return unpack( "L", $str );
}

sub GET_I32 {
  my $fh  = shift;
  my $str = $fh->readn(4);
  croak "reached EOF while reading I32" unless length($str) == 4;

  # Todo: check byteorder
  return unpack( "l", $str );
}

sub GET_objindex {
  my $fh  = shift;
  my $str = $fh->readn(4);
  croak "reached EOF while reading objindex" unless length($str) == 4;

  # Todo: check byteorder
  return unpack( "L", $str );
}

sub GET_opindex {
  my $fh  = shift;
  my $str = $fh->readn(4);
  croak "reached EOF while reading opindex" unless length($str) == 4;

  # Todo: check byteorder
  return unpack( "L", $str );
}

sub GET_svindex {
  my $fh  = shift;
  my $str = $fh->readn(4);
  croak "reached EOF while reading svindex" unless length($str) == 4;

  # Todo: check byteorder
  return unpack( "L", $str );
}

sub GET_pvindex {
  my $fh  = shift;
  my $str = $fh->readn(4);
  croak "reached EOF while reading pvindex" unless length($str) == 4;

  # Todo: check byteorder
  return unpack( "L", $str );
}

sub GET_hekindex {
  my $fh  = shift;
  my $str = $fh->readn(4);
  croak "reached EOF while reading hekindex" unless length($str) == 4;

  # Todo: check byteorder
  return unpack( "L", $str );
}

sub GET_strconst {
  my $fh = shift;
  my ( $str, $c );
  $str = '';
  while ( defined( $c = $fh->getc ) && $c ne "\0" ) {
    $str .= $c;
  }
  croak "reached EOF while reading strconst" unless defined($c);
  return cstring($str);
}

sub GET_pvcontents { }

sub GET_PV {
  my $fh = shift;
  my $str;
  my $len = $fh->GET_U32;
  if ($len) {
    read( $fh, $str, $len );
    croak "reached EOF while reading PV" unless length($str) == $len;
    return cstring($str);
  }
  else {
    return '""';
  }
}

sub GET_comment_t {
  my $fh = shift;
  my ( $str, $c );
  while ( defined( $c = $fh->getc ) && $c ne "\n" ) {
    $str .= $c;
  }
  croak "reached EOF while reading comment" unless defined($c);
  return cstring($str);
}

sub GET_double {
  my $fh = shift;
  my ( $str, $c );
  while ( defined( $c = $fh->getc ) && $c ne "\0" ) {
    $str .= $c;
  }
  croak "reached EOF while reading double" unless defined($c);
  return $str;
}

sub GET_none { }

sub GET_op_tr_array {
  my $fh  = shift;
  my $len = unpack "S", $fh->readn(2);
  my @ary = unpack "S*", $fh->readn( $len * 2 );
  return join( ",", $len, @ary );
}

sub GET_IV64 {
  my $fh  = shift;
  my $str = $fh->readn(8);
  croak "reached EOF while reading I32" unless length($str) == 8;

  # Todo: check byteorder
  my $i = unpack( "q", $str );
  return $i > 8 ? sprintf "0x%09llx", $i : $i;
}

sub GET_IV {
  # Check the header settings, not the current settings.
  $B::Disassembler::ivsize == 4 ? &GET_I32 : &GET_IV64;
  # $Config{ivsize} == 4 ? &GET_I32 : &GET_IV64;
}

sub GET_PADOFFSET {
  # Check the header settings, not the current settings.
  $B::Disassembler::ptrsize == 8 ? &GET_IV64 : &GET_U32;
  # $Config{ptrsize} == 8 ? &GET_IV64 : &GET_U32;
}

sub GET_long {
  # Check the header settings, not the current settings.
  # B::Disassembler::ivsize or longsize if ge xxx?
  if ($B::Disassembler::longsize) {
    return $B::Disassembler::longsize == 8 ? &GET_IV64 : &GET_U32;
  } else {
    # return $Config{longsize} == 8 ? &GET_IV64 : &GET_U32;
    return $B::Disassembler::ivsize == 8 ? &GET_IV64 : &GET_U32;
  }
}

sub GET_pmflags {
  my $fh  = shift;
  my $size = 2;
  if ($B::Disassembler::blversion ge '"0.07"') {
    if ($B::Disassembler::perlversion ge '"5.013"') {
      return $fh->GET_U32;
    }
  }
  return $fh->GET_U16;
}

package B::Disassembler;
use Exporter;
@ISA       = qw(Exporter);
our @EXPORT_OK = qw(disassemble_fh get_header print_insn print_insn_bare @opname);
use Carp;
use strict;
use B::Asmdata qw(%insn_data @insn_name);
use Opcode qw(opset_to_ops full_opset);
use Config qw(%Config);
use B::Concise;

BEGIN {
  if ( $] < 5.009 ) {
    B::Asmdata->import(qw(@specialsv_name));
  }
  else {
    B->import(qw(@specialsv_name));
  }
}

my $ix;
my $opname;
our @opname = opset_to_ops(full_opset);
our (
  $magic,   $archname, $blversion, $ivsize,
  $ptrsize, $longsize, $byteorder, $archflag, $perlversion
);
						# >=5.12
our  @svnames = ("NULL");			# 0
push @svnames, "BIND"   if $] >= 5.009 and $] < 5.019002; # 1
push @svnames, ("IV", "NV");			# 2,3
push @svnames, "RV"     if $] < 5.011;		#
push @svnames, "PV";
push @svnames, "INVLIST" if $] >= 5.019002;     # 4
push @svnames, ("PVIV", "PVNV", "PVMG");	# 4-7
push @svnames, "BM"     if $] < 5.009;
push @svnames, "REGEXP" if $] >= 5.011;	# 8
push @svnames, "GV"     if $] >= 5.009;	# 9
push @svnames, ("PVLV", "AV", "HV", "CV");	# 10-13
push @svnames, "GV"     if $] < 5.009;
push @svnames, ("FM", "IO");			# 14,15

sub dis_header($) {
  my ($fh) = @_;
  my $str = $fh->readn(3);
  if ($str eq '#! ')  {
    $str .= $fh->GET_comment_t;
    $str .= $fh->GET_comment_t;
    $magic = $fh->GET_U32;
  } else {
    $str .= $fh->readn(1);
    $magic = unpack( "L", $str );
  }
  warn("bad magic") if $magic != 0x43424c50;
  $archname  = $fh->GET_strconst();
  $blversion = $fh->GET_strconst();
  $ivsize    = $fh->GET_U32();
  $ptrsize   = $fh->GET_U32();
  if ( $blversion ge '"0.06_03"' ) {
    $longsize = $fh->GET_U32();
  }
  if ( $blversion gt '"0.06"' or $blversion eq '"0.04"' ) {
    $byteorder = $fh->GET_strconst();
  }
  if ( $blversion ge '"0.06_05"' ) {
    $archflag = $fh->GET_U16();
  }
  if ( $blversion ge '"0.06_06"' ) {
    $perlversion = $fh->GET_strconst();
  }
}

sub get_header() {
  my @result = (
		$magic,   $archname,  $blversion, $ivsize,
		$ptrsize, $byteorder, $longsize,  $archflag,
		$perlversion
	       );
  if (wantarray) {
    return @result;
  }
  else {
    my $hash = {
		magic       => $magic,
		archname    => $archname,
		blversion   => $blversion,
		ivsize      => $ivsize,
		ptrsize     => $ptrsize,
	       };
    for (qw(magic archname blversion ivsize ptrsize byteorder
	    longsize archflag perlversion))
    {
	$hash->{$_} = $$_ if defined $$_;
    }
    return $hash;
  }
}

sub print_insn {
  my ( $insn, $arg, $comment ) = @_;
  undef $comment unless $comment;
  if ( defined($arg) ) {
    # threaded or unthreaded
    if ( $insn eq 'newopx' or $insn eq 'ldop' and $] > 5.007) {
      my $type = $arg >> 7;
      my $size = $arg - ( $type << 7 );
      $arg .= sprintf( " \t# size:%d, type:%d %s", $size, $type) if $comment;
      $opname = $opname[$type];
      printf "\n# [%s %d]\n", $opname, $ix++;
    }
    elsif ( !$comment ) {
      ;
    }
    elsif ( $insn eq 'comment' ) {
      $arg .= "comment $arg";
      $arg .= " \t#" . $comment if $comment ne '1';
    }
    elsif ( $insn eq 'stpv' ) {
      $arg .= "\t# " . $comment if $comment ne '1';
      printf "# -%s- %d\n", 'PV', $ix++;
    }
    elsif ( $insn eq 'newsvx' ) {
      my $type = $arg & 0xff; # SVTYPEMASK
      $arg .= sprintf("\t# type=%d,flags=0x%x", $type, $arg);
      $arg .= $comment if $comment ne '1';
      printf "\n# [%s %d]\n", $svnames[$type], $ix++;
    }
    elsif ( $insn eq 'newpadlx' ) {
      $arg .= "\t# " . $comment if $comment ne '1';
      printf "\n# [%s %d]\n", "PADLIST", $ix++;
    }
    elsif ( $insn eq 'newpadnlx' ) {
      $arg .= "\t# " . $comment if $comment ne '1';
      printf "\n# [%s %d]\n", "PADNAMELIST", $ix++;
    }
    elsif ( $insn eq 'newpadnx' ) {
      $arg .= "\t# " . $comment if $comment ne '1';
      printf "\n# [%s %d]\n", "PADNAME", $ix++;
    }
    elsif ( $insn eq 'gv_stashpvx' ) {
      $arg .= "\t# " . $comment if $comment ne '1';
      printf "\n# [%s %d]\n", "STASH", $ix++;
    }
    elsif ( $insn eq 'ldspecsvx' ) {
      $arg .= "\t# $specialsv_name[$arg]";
      $arg .= $comment if $comment ne '1';
      printf "\n# [%s %d]\n", "SPECIAL", $ix++;
    }
    elsif ( $insn eq 'ldsv' ) {
      $arg .= "\t# " . $comment if $comment ne '1';
      printf "# -%s-\n", 'GP/AV/HV/NULL/MG';
    }
    elsif ( $insn eq 'gv_fetchpvx' ) {
      $arg .= "\t# " . $comment if $comment ne '1';
      printf "\n# [%s %d]\n", 'GV', $ix++;
    }
    elsif ( $insn eq 'sv_magic' ) {
      $arg .= sprintf( "\t# '%s'", chr($arg) );
    }
    elsif ( $insn =~ /_flags/ ) {
      my $f = $arg;
      $arg .= sprintf( "\t# 0x%x", $f ) if $comment;
      $arg .= " ".B::Concise::op_flags($f) if $insn eq 'op_flags' and $comment;
    }
    elsif ( $comment and $insn eq 'op_private' ) {
      my $f = $arg;
      $arg .= sprintf( "\t# 0x%x", $f );
      $arg .= " ".B::Concise::private_flags($opname, $f);
    }
    elsif ( $insn eq 'op_type' and $] < 5.007 ) {
      my $type = $arg;
      $arg .= sprintf( "\t# [ %s ]", $opname[$type] );
    }
    else {
      $arg .= "\t# " . $comment if $comment ne '1';
    }
    printf "%s %s\n", $insn, $arg;
  }
  else {
    $insn .= "\t# " . $comment if $comment ne '1';
    print $insn, "\n";
  }
}

sub print_insn_bare {
  my ( $insn, $arg ) = @_;
  if ( defined($arg) ) {
    printf "%s %s\n", $insn, $arg;
  }
  else {
    print $insn, "\n";
  }
}

sub disassemble_fh {
  my $fh      = shift;
  my $out     = shift;
  my $verbose = shift;
  my ( $c, $getmeth, $insn, $arg );
  $ix = 1;
  bless $fh, "B::Disassembler::BytecodeStream";
  dis_header($fh);
  if ($verbose) {
    printf "#magic       0x%x\n", $magic; #0x43424c50
    printf "#archname    %s\n", $archname;
    printf "#blversion   %s\n", $blversion;
    printf "#ivsize      %d\n", $ivsize;
    printf "#ptrsize     %d\n", $ptrsize;
    printf "#byteorder   %s\n", $byteorder if $byteorder;
    printf "#longsize    %d\n", $longsize  if $longsize;
    printf "#archflag    %d\n", $archflag  if defined $archflag;
    printf "#perlversion %s\n", $perlversion if $perlversion;
    print "\n";
  }
  while ( defined( $c = $fh->getc ) ) {
    $c    = ord($c);
    $insn = $insn_name[$c];
    if ( !defined($insn) || $insn eq "unused" ) {
      my $pos = $fh->tell - 1;
      warn "Illegal instruction code $c at stream offset $pos.\n";
    }
    $getmeth = $insn_data{$insn}->[2];
    #warn "EOF at $insn $getmeth" if $fh->eof();
    $arg     = $fh->$getmeth();
    if ( defined($arg) ) {
      &$out( $insn, $arg, $verbose );
    }
    else {
      &$out( $insn, undef, $verbose );
    }
  }
}

1;

__END__

=head1 NAME

B::Disassembler - Disassemble Perl bytecode

=head1 SYNOPSIS

	use Disassembler qw(print_insn);
        my $fh = new FileHandle "<$ARGV[0]";
	disassemble_fh($fh, \&print_insn);

=head1 DESCRIPTION

disassemble_fh takes an filehandle with bytecode and a printer function.
The printer function gets three arguments: insn, arg (optional) and the comment.

See F<lib/B/Disassembler.pm> and F<scripts/disassemble>.

=head1 disassemble_fh (filehandle, printer_coderef, [ verbose ])

disassemble_fh takes an filehandle with bytecode and a printer coderef.

Two default printer functions are provided:

  print_insn print_insn_bare

=head1 print_insn

Callback function for disassemble_fh, which gets three arguments from
the disassembler.  insn (a string), arg (a string or number or undef)
and the comment (an optional string).

This supports the new behaviour in F<scripts/disassemble>.  It prints
each insn and optional argument with some additional comments, which
looks similar to B::Assembler with option -S (commented source).

=head1 print_insn_bare

This is the same as the old behaviour of scripts/disassemble.  It
prints each insn and optional argument without any comments. Line per
line.

=head1 get_header

Returns the .plc header as array of

  ( magic, archname, blversion, ivsize, ptrsize,
    byteorder, longsize, archflag, perlversion )

in ARRAY context, or in SCALAR context the array from above as named hash.

B<magic> is always "PLBC". "PLJC" is reserved for JIT'ted code also
loaded via ByteLoader.

B<archname> is the archname string and is in the ByteLoader up to 0.06
checked strictly. Starting with ByteLoader 0.06_05 platform
compatibility is implemented by checking the $archflag, and doing
byteorder swapping for same length longsize, and adjusting the ivsize
and ptrsize.

B<blversion> is the ByteLoader version from the header as string.
Up to ByteLoader 0.06 this version must have matched exactly, since 0.07
earlier ByteLoader versions are also accepted in the ByteLoader.

B<ivsize> matches $Config{ivsize} of the assembling perl.
A number, 4 or 8 only supported.

B<ptrsize> matches $Config{ptrsize} of the assembling perl.
A number, 4 or 8 only supported.

B<longsize> is $Config{longsize} of the assembling perl.
A number, 4 or 8.
Only since blversion 0.06_03.

B<byteorder> is a string of "0x12345678" on big-endian or "0x78563412" (?)
on little-endian machines. The beginning "0x" is stripped for compatibility
with intermediate ByteLoader versions, i.e. 5.6.1 to 5.8.0,
Added with blversion 0.06_03, and also with blversion 0.04.
See L<BcVersions>

B<archflag> is a bitmask of opcode platform-dependencies.
Currently used:
  bit 1 for USE_ITHREADS
  bit 2 for MULTIPLICITY
Added with  blversion 0.06_05.

B<perlversion> $] of the perl which produced this bytecode as string.
Added with blversion 0.06_06.

=head1 AUTHORS

Malcolm Beattie C<MICB at cpan.org> I<(retired)>,
Reini Urban C<perl-compiler@googlegroups.com> since 2008.

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=2:
