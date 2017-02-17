#      Assembler.pm
#
#      Copyright (c) 1996 Malcolm Beattie
#      Copyright (c) 2008,2009,2010,2011,2012 Reini Urban
#      Copyright (c) 2014 cPanel Inc
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.

package B::Assembler;
use Exporter;
use B qw(ppname);
use B::Asmdata qw(%insn_data @insn_name);
use Config qw(%Config);
require ByteLoader;    # we just need its $VERSION

no warnings;           # XXX

@ISA       = qw(Exporter);
our @EXPORT_OK = qw(assemble_fh newasm endasm assemble asm maxopix maxsvix);
our $VERSION   = '1.13';

use strict;
my %opnumber;
my ( $i, $opname );
for ( $i = 0 ; defined( $opname = ppname($i) ) ; $i++ ) {
  $opnumber{$opname} = $i;
}

my ( $linenum, $errors, $out );    #	global state, set up by newasm

sub error {
  my $str = shift;
  warn "$linenum: $str\n";
  $errors++;
}

my $debug = 0;
sub debug { $debug = shift }
my $quiet = 0;
sub quiet { $quiet = shift }
my ( $maxopix, $maxsvix ) = ( 0xffffffff, 0xffffffff );
sub maxopix { $maxopix = shift }
sub maxsvix { $maxsvix = shift }

sub limcheck($$$$) {
  my ( $val, $lo, $hi, $loc ) = @_;
  if ( $val < $lo || $hi < $val ) {
    error "argument for $loc outside [$lo, $hi]: $val";
    $val = $hi;
  }
  return $val;
}

#
# First define all the data conversion subs to which Asmdata will refer
#

sub B::Asmdata::PUT_U8 {
  error "Missing argument to PUT_U8" if @_ < 1;
  my $arg = shift;
  my $c   = uncstring($arg);
  if ( defined($c) ) {
    if ( length($c) != 1 ) {
      error "argument for U8 is too long: $c";
      $c = substr( $c, 0, 1 );
    }
  }
  else {
    $arg = limcheck( $arg, 0, 0xff, 'U8' );
    $c = chr($arg);
  }
  return $c;
}

sub B::Asmdata::PUT_U16 {
  error "Missing argument to PUT_U16" if @_ < 1;
  my $arg = limcheck( $_[0], 0, 0xffff, 'U16' );
  pack( "S", $arg );
}

sub B::Asmdata::PUT_U32 {
  error "Missing argument to PUT_U32" if @_ < 1;
  my $arg = limcheck( $_[0], 0, 0xffffffff, 'U32' );
  pack( "L", $arg );
}

sub B::Asmdata::PUT_I32 {
  error "Missing argument to PUT_I32" if @_ < 1;
  my $arg = limcheck( $_[0], -0x80000000, 0x7fffffff, 'I32' );
  pack( "l", $arg );
}

sub B::Asmdata::PUT_NV {
  error "Missing argument to PUT_NV" if @_ < 1;
  sprintf( "%s\0", $_[0] );
}    # "%lf" looses precision and pack('d',...)
     # may not even be portable between compilers

sub B::Asmdata::PUT_objindex {    # could allow names here
  error "Missing argument to PUT_objindex" if @_ < 1;
  my $maxidx = $_[1] || 0xffffffff;
  my $what = $_[2] || 'ix';
  my $arg = limcheck( $_[0], 0, $maxidx, $what );
  pack( "L", $arg );
}
sub B::Asmdata::PUT_svindex { B::Asmdata::PUT_objindex( @_, $maxsvix, 'svix' ) }
sub B::Asmdata::PUT_opindex { B::Asmdata::PUT_objindex( @_, $maxopix, 'opix' ) }
sub B::Asmdata::PUT_pvindex { B::Asmdata::PUT_objindex( @_, $maxsvix, 'pvix' ) }
sub B::Asmdata::PUT_hekindex { B::Asmdata::PUT_objindex( @_ ) }

sub B::Asmdata::PUT_strconst {
  error "Missing argument to PUT_strconst" if @_ < 1;
  my $arg = shift;
  my $str = uncstring($arg);
  if ( !defined($str) ) {
    my @callstack = caller(3);
    error "bad string constant: '$arg', called from ".$callstack[3]
      ." line:".$callstack[2] unless $callstack[3] eq 'B::PADNAME::ix'; # empty newpadnx
    $str = '';
  }
  if ( $str =~ s/\0//g ) {
    error "string constant argument contains NUL: $arg";
    $str = '';
  }
  return $str . "\0";
}

# expects the string argument already on the "stack" (with depth 1, one sv)
sub B::Asmdata::PUT_pvcontents {
  my $arg = shift;
  error "extraneous argument to pvcontents: $arg" if defined $arg;
  return "";
}

sub B::Asmdata::PUT_PV {
  error "Missing argument to PUT_PV" if @_ < 1;
  my $arg = shift;
  my $str = uncstring($arg);
  if ( !defined($str) ) {
    error "bad string argument: $arg";
    $str = '';
  }
  return pack( "L", length($str) ) . $str;
}

sub B::Asmdata::PUT_comment_t {
  my $arg = shift;
  $arg = uncstring($arg);
  error "bad string argument: $arg" unless defined($arg);
  if ( $arg =~ s/\n//g ) {
    error "comment argument contains linefeed: $arg";
  }
  return $arg . "\n";
}
sub B::Asmdata::PUT_double {
  error "Missing argument to PUT_double" if @_ < 1;
  sprintf( "%s\0", $_[0] )
}    # see PUT_NV above

sub B::Asmdata::PUT_none {
  my $arg = shift;
  error "extraneous argument: $arg" if defined $arg;
  return "";
}

sub B::Asmdata::PUT_op_tr_array {
  error "Missing argument to PUT_tr_array" if @_ < 1;
  my @ary = split /\s*,\s*/, shift;
  return pack "S*", @ary;
}

sub B::Asmdata::PUT_IV64 {
  error "Missing argument to PUT_IV64" if @_ < 1;
  return pack "Q", shift;
}

sub B::Asmdata::PUT_IV {
  $Config{ivsize} == 4 ? &B::Asmdata::PUT_I32 : &B::Asmdata::PUT_IV64;
}

sub B::Asmdata::PUT_PADOFFSET {
  $Config{ptrsize} == 8 ? &B::Asmdata::PUT_IV64 : &B::Asmdata::PUT_U32;
}

sub B::Asmdata::PUT_long {
  $Config{longsize} == 8 ? &B::Asmdata::PUT_IV64 : &B::Asmdata::PUT_U32;
}

sub B::Asmdata::PUT_svtype {
  $Config{longsize} == 8 ? &B::Asmdata::PUT_IV64 : &B::Asmdata::PUT_U32;
}

sub B::Asmdata::PUT_pmflags {
  return ($] < 5.013) ? B::Asmdata::PUT_U16(@_) : B::Asmdata::PUT_U32(@_);
}

my %unesc = (
  n => "\n",
  r => "\r",
  t => "\t",
  a => "\a",
  b => "\b",
  f => "\f",
  v => "\013"
);

sub uncstring {
  my $s = shift;
  $s =~ s/^"// and $s =~ s/"$// or return undef;
  $s =~ s/\\(\d\d\d|.)/length($1) == 3 ? chr(oct($1)) : ($unesc{$1}||$1)/eg;
  return $s;
}

sub strip_comments {
  my $stmt = shift;

  # Comments only allowed in instructions which don't take string arguments
  # Treat string as a single line so .* eats \n characters.
  my $line = $stmt;
  $stmt =~ s{
	^\s*	# Ignore leading whitespace
	(
	  [^"]*  # A double quote '"' indicates a string argument. If we
		 # find a double quote, the match fails and we strip nothing.
	)
	\s*\#	# Any amount of whitespace plus the comment marker...
	\s*(.*)$ # ...which carries on to end-of-string.
    }{$1}sx;    # Keep only the instruction and optional argument.
  return ($stmt) if $line eq $stmt;

  $stmt =~ m{
	^\s*
	(
	  [^"]*
	)
	\s*\#
	\s*(.*)$
    }sx;        # Keep only the instruction and optional argument.
  my ( $line, $comment ) = ( $1, $2 );

  # $line =~ s/\t$// if $comment;
  return ( $line, $comment );
}

# create the ByteCode header:
#   magic, archname, ByteLoader $VERSION, ivsize, ptrsize, longsize, byteorder,
#   archflag, perlversion
# byteorder is strconst, not U32 because of varying size issues (?)
# archflag: bit 1: useithreads, bit 2: multiplicity
# perlversion for the bytecode translation.

sub gen_header {
  my $header = gen_header_hash();
  my $string  = "";
  $string .= B::Asmdata::PUT_U32( $header->{magic} );
  $string .= B::Asmdata::PUT_strconst( '"' . $header->{archname} . '"' );
  $string .= B::Asmdata::PUT_strconst( '"' . $header->{blversion} . '"' );
  $string .= B::Asmdata::PUT_U32( $header->{ivsize} );
  $string .= B::Asmdata::PUT_U32( $header->{ptrsize} );
  if ( exists $header->{longsize} ) {
    $string .= B::Asmdata::PUT_U32( $header->{longsize} );
  }
  $string .= B::Asmdata::PUT_strconst(  sprintf(qq["0x%s"], $header->{byteorder} ));
  if ( exists $header->{archflag} ) {
    $string .= B::Asmdata::PUT_U16( $header->{archflag} );
  }
  if ( exists $header->{perlversion} ) {
    $string .= B::Asmdata::PUT_strconst( '"' . $header->{perlversion} . '"');
  }
  $string;
}

# Calculate the ByteCode header values:
#   magic, archname, ByteLoader $VERSION, ivsize, ptrsize, longsize, byteorder
#   archflag, perlversion
# nvtype is irrelevant (floats are stored as strings)
# byteorder is strconst, not U32 because of varying size issues (?)
# archflag: bit 1: useithreads, bit 2: multiplicity
# perlversion for the bytecode translation.

sub gen_header_hash {
  my $header  = {};
  my $blversion = "$ByteLoader::VERSION";
  #if ($] < 5.009 and $blversion eq '0.06_01') {
  #  $blversion = '0.06';# fake the old backwards compatible version
  #}
  $header->{magic}     = 0x43424c50;
  $header->{archname}  = $Config{archname};
  $header->{blversion} = $blversion;
  $header->{ivsize}    = $Config{ivsize};
  $header->{ptrsize}   = $Config{ptrsize};
  if ( $blversion ge "0.06_03" ) {
    $header->{longsize} = $Config{longsize};
  }
  my $byteorder = $Config{byteorder};
  if ($] < 5.007) {
    # until 5.6 the $Config{byteorder} was dependent on ivsize, which was wrong. we need longsize.
    my $t = $Config{ivtype};
    my $s = $Config{longsize};
    my $f = $t eq 'long' ? 'L!' : $s == 8 ? 'Q': 'I';
    if ($s == 4 || $s == 8) {
      my $i = 0;
      foreach my $c (reverse(2..$s)) { $i |= ord($c); $i <<= 8 }
      $i |= ord(1);
      $byteorder = join('', unpack('a'x$s, pack($f, $i)));
    } else {
      $byteorder = '?'x$s;
    }
  }
  $header->{byteorder}   = $byteorder;
  if ( $blversion ge "0.06_05" ) {
    my $archflag = 0;
    $archflag += 1 if $Config{useithreads};
    $archflag += 2 if $Config{usemultiplicity};
    $header->{archflag} = $archflag;
  }
  if ( $blversion ge "0.06_06" ) {
    $header->{perlversion} = $];
  }
  $header;
}

sub parse_statement {
  my $stmt = shift;
  my ( $insn, $arg ) = $stmt =~ m{
	^\s*	# allow (but ignore) leading whitespace
	(.*?) # Ignore -S op groups. Instruction continues up until...
	(?:	# ...an optional whitespace+argument group
	    \s+		# first whitespace.
	    (.*)	# The argument is all the rest (newlines included).
	)?$	# anchor at end-of-line
    }sx;
  if ( defined($arg) ) {
    if ( $arg =~ s/^0x(?=[0-9a-fA-F]+$)// ) {
      $arg = hex($arg);
    }
    elsif ( $arg =~ s/^0(?=[0-7]+$)// ) {
      $arg = oct($arg);
    }
    elsif ( $arg =~ /^pp_/ ) {
      $arg =~ s/\s*$//;    # strip trailing whitespace
      my $opnum = $opnumber{$arg};
      if ( defined($opnum) ) {
        $arg = $opnum;
      }
      else {
        # TODO: ignore [op] from O=Bytecode,-S
        error qq(No such op type "$arg");
        $arg = 0;
      }
    }
  }
  return ( $insn, $arg );
}

sub assemble_insn {
  my ( $insn, $arg ) = @_;
  my $data = $insn_data{$insn};
  if ( defined($data) ) {
    my ( $bytecode, $putsub ) = @{$data}[ 0, 1 ];
    error qq(unsupported instruction "$insn") unless $putsub;
    return "" unless $putsub;
    my $argcode = &$putsub($arg);
    return chr($bytecode) . $argcode;
  }
  else {
    error qq(no such instruction "$insn");
    return "";
  }
}

sub assemble_fh {
  my ( $fh, $out ) = @_;
  my $line;
  my $asm = newasm($out);
  while ( $line = <$fh> ) {
    assemble($line);
  }
  endasm();
}

sub newasm {
  my ($outsub) = @_;

  die "Invalid printing routine for B::Assembler\n"
    unless ref $outsub eq 'CODE';
  die <<EOD if ref $out;
Can't have multiple byteassembly sessions at once!
	(perhaps you forgot an endasm()?)
EOD

  $linenum = $errors = 0;
  $out = $outsub;

  $out->( gen_header() );
}

sub endasm {
  if ($errors) {
    die "There were $errors assembly errors\n";
  }
  $linenum = $errors = $out = 0;
}

### interface via whole line, and optional comments
sub assemble {
  my ($line) = @_;
  my ( $insn, $arg, $comment );
  $linenum++;
  chomp $line;
  $line =~ s/\cM$//;
  if ($debug) {
    my $quotedline = $line;
    $quotedline =~ s/\\/\\\\/g;
    $quotedline =~ s/"/\\"/g;
    $out->( assemble_insn( "comment", qq("$quotedline") ) );
  }
  ( $line, $comment ) = strip_comments($line);
  if ($line) {
    ( $insn, $arg ) = parse_statement($line);
    if ($debug and !$comment and $insn =~ /_flags/) {
      $comment = sprintf("0x%x", $arg);
    }
    $out->( assemble_insn( $insn, $arg, $comment ) );
    if ($debug) {
      $out->( assemble_insn( "nop", undef ) );
    }
  }
  elsif ( $debug and $comment ) {
    $out->( assemble_insn( "nop", undef, $comment ) );
  }
}

### temporary workaround
### interface via 2-3 args

sub asm ($;$$) {
  return if $_[0] =~ /\s*\W/;
  if ( defined $_[1] ) {
    return
      if $_[1] eq "0"
        and $_[0] !~ /^(?:ldsv|stsv|newsvx?|newpad.*|av_pushx?|av_extend|xav_flags)$/;
    return if $_[1] eq "1" and $]>5.007 and $_[0] =~ /^(?:sv_refcnt)$/;
  }
  my ( $insn, $arg, $comment ) = @_;
  if ($] < 5.007) {
    if ($insn eq "newsvx") {
      $arg = $arg & 0xff; # sv not SVt_NULL
      $insn = "newsv";
      # XXX but this needs stsv tix-1 also
    } elsif ($insn eq "newopx") {
      $insn = "newop";
    } elsif ($insn eq "av_pushx") {
      $insn = "av_push";
    } elsif ($insn eq "ldspecsvx") {
      $insn = "ldspecsv";
    } elsif ($insn eq "gv_stashpvx") {
      $insn = "gv_stashpv";
    } elsif ($insn eq "gv_fetchpvx") {
      $insn = "gv_fetchpv";
    } elsif ($insn eq "main_cv") {
      return;
    }
  }
  $out->( assemble_insn( $insn, $arg, $comment ) );
  $linenum++;

  # assemble "@_";
}

1;

__END__

=head1 NAME

B::Assembler - Assemble Perl bytecode

=head1 SYNOPSIS

	perl -MO=Bytecode,-S,-omy.asm my.pl
	assemble my.asm > my.plc

	use B::Assembler qw(newasm endasm assemble);
	newasm(\&printsub);	# sets up for assembly
	assemble($buf); 	# assembles one line
	asm(opcode, arg, [comment]);
	endasm();		# closes down

	use B::Assembler qw(assemble_fh);
	assemble_fh($fh, \&printsub);	# assemble everything in $fh

=head1 DESCRIPTION

B::Bytecode helper module.

=head1 AUTHORS

Malcolm Beattie C<MICB at cpan.org> I<(1996, retired)>,
Per-statement interface by Benjamin Stuhl C<sho_pi@hotmail.com>,
Reini Urban C<perl-compiler@googlegroups.com> I(2008-)

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=2:
