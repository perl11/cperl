#      Stackobj.pm
#
#      Copyright (c) 1996 Malcolm Beattie
#      Copyright (c) 2010 Reini Urban
#      Copyright (c) 2012, 2013, 2014, 2015 cPanel Inc
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#
package B::Stackobj;

our $VERSION = '1.12_01';

use Exporter ();
@ISA       = qw(Exporter);
our @EXPORT_OK = qw(set_callback T_UNKNOWN T_NUM T_INT T_STR VALID_UNSIGNED
  VALID_INT VALID_NUM VALID_STR VALID_SV REGISTER TEMPORARY);
our %EXPORT_TAGS = (
  types => [qw(T_UNKNOWN T_NUM T_INT T_STR)],
  flags => [
    qw(VALID_INT VALID_NUM VALID_STR VALID_SV
      VALID_UNSIGNED REGISTER TEMPORARY)
  ]
);

use strict;
use B qw(SVf_IOK SVf_NOK SVf_IVisUV SVf_ROK SVf_POK);
use B::C qw(ivx nvx);
use Config;

# Types
sub T_UNKNOWN () { 0 }
sub T_INT ()     { 1 }
sub T_NUM ()     { 2 }
sub T_STR ()     { 3 }
sub T_SPECIAL () { 4 }

# Flags
sub VALID_INT ()      { 0x01 }
sub VALID_UNSIGNED () { 0x02 }
sub VALID_NUM ()      { 0x04 }
sub VALID_STR ()      { 0x08 }
sub VALID_SV ()       { 0x10 }
sub REGISTER ()       { 0x20 }    # no implicit write-back when calling subs
sub TEMPORARY ()      { 0x40 }    # no implicit write-back needed at all
sub SAVE_INT ()       { 0x80 }    # if int part needs to be saved at all
sub SAVE_NUM ()       { 0x100 }   # if num part needs to be saved at all
sub SAVE_STR ()       { 0x200 }   # if str part needs to be saved at all

# no backtraces to avoid compiler pollution
#use Carp qw(confess);
sub confess {
  if (exists &Carp::confess) {
    goto &Carp::confess;
  } else {
    die @_."\n";
  }
}

#
# Callback for runtime code generation
#

my $runtime_callback = sub { confess "set_callback not yet called" };
sub set_callback (&) { $runtime_callback = shift }
sub runtime { &$runtime_callback(@_) }

#
# Methods
#

# The stack holds generally only the string ($sv->save) representation of the B object,
# for the types sv, int, double, numeric and sometimes bool.
# Special subclasses keep the B obj, like Const

sub write_back { confess "stack object does not implement write_back" }

sub invalidate {
  shift->{flags} &= ~( VALID_INT | VALID_UNSIGNED | VALID_NUM | VALID_STR );
}

sub invalidate_int {
  shift->{flags} &= ~( VALID_INT | VALID_UNSIGNED );
}

sub invalidate_double {
  shift->{flags} &= ~( VALID_NUM );
}

sub invalidate_str {
  shift->{flags} &= ~( VALID_STR );
}

sub as_sv {
  my $obj = shift;
  if ( !( $obj->{flags} & VALID_SV ) ) {
    $obj->write_back;
    $obj->{flags} |= VALID_SV;
  }
  return $obj->{sv};
}

sub as_obj {
  return shift->{obj};
}

sub as_int {
  my $obj = shift;
  if ( !( $obj->{flags} & VALID_INT ) ) {
    $obj->load_int;
    $obj->{flags} |= VALID_INT | SAVE_INT;
  }
  return $obj->{iv};
}

sub as_double {
  my $obj = shift;
  if ( !( $obj->{flags} & VALID_NUM ) ) {
    $obj->load_double;
    $obj->{flags} |= VALID_NUM | SAVE_NUM;
  }
  return $obj->{nv};
}

sub as_str {
  my $obj = shift;
  if ( !( $obj->{flags} & VALID_STR ) ) {
    $obj->load_str;
    $obj->{flags} |= VALID_STR | SAVE_STR;
  }
  return $obj->{sv};
}

sub as_numeric {
  my $obj = shift;
  return $obj->{type} == T_INT ? $obj->as_int : $obj->as_double;
}

sub as_bool {
  my $obj = shift;
  if ( $obj->{flags} & VALID_INT ) {
    return $obj->{iv};
  }
  if ( $obj->{flags} & VALID_NUM ) {
    return $obj->{nv};
  }
  return sprintf( "(SvTRUE(%s))", $obj->as_sv );
}

#
# Debugging methods
#
sub peek {
  my $obj   = shift;
  my $type  = $obj->{type};
  my $flags = $obj->{flags};
  my @flags;
  if ( $type == T_UNKNOWN ) {
    $type = "T_UNKNOWN";
  }
  elsif ( $type == T_INT ) {
    $type = "T_INT";
  }
  elsif ( $type == T_NUM ) {
    $type = "T_NUM";
  }
  elsif ( $type == T_STR ) {
    $type = "T_STR";
  }
  else {
    $type = "(illegal type $type)";
  }
  push( @flags, "VALID_INT" )    if $flags & VALID_INT;
  push( @flags, "VALID_NUM" )    if $flags & VALID_NUM;
  push( @flags, "VALID_STR" )    if $flags & VALID_STR;
  push( @flags, "VALID_SV" )     if $flags & VALID_SV;
  push( @flags, "REGISTER" )     if $flags & REGISTER;
  push( @flags, "TEMPORARY" )    if $flags & TEMPORARY;
  @flags = ("none") unless @flags;
  return sprintf( "%s type=$type flags=%s sv=$obj->{sv} iv=$obj->{iv} nv=$obj->{nv}",
    B::class($obj), join( "|", @flags ) );
}

sub minipeek {
  my $obj   = shift;
  my $type  = $obj->{type};
  my $flags = $obj->{flags};
  if ( $type == T_INT || $flags & VALID_INT ) {
    return $obj->{iv};
  }
  elsif ( $type == T_NUM || $flags & VALID_NUM ) {
    return $obj->{nv};
  }
  else {
    return $obj->{sv};
  }
}

#
# Caller needs to ensure that set_int, set_double,
# set_numeric and set_sv are only invoked on legal lvalues.
#
sub set_int {
  my ( $obj, $expr, $unsigned ) = @_;
  my $sval;
  # bullshit detector for non numeric expr, expr 'lnv0 + rnv0'
  if ($expr =~ /[ a-dfzA-DF-Z]/) { # looks not like number
    $sval = $expr;
  } else {
    $sval = B::C::ivx($expr);
    $sval = $expr if $sval eq '0' and $expr;
  }

  runtime("$obj->{iv} = $sval;");
  $obj->{flags} &= ~( VALID_SV | VALID_NUM );
  $obj->{flags} |= VALID_INT | SAVE_INT;
  $obj->{flags} |= VALID_UNSIGNED if $unsigned;
}

sub set_double {
  my ( $obj, $expr ) = @_;
  my $sval;
  if ($expr =~ /^-?(Inf|NaN)$/i) {
    $sval = B::C::nvx($expr);
    $sval = $expr if $sval eq '0' and $expr;
  # bullshit detector for non numeric expr, expr 'lnv0 + rnv0'
  } elsif ($expr =~ /[ a-dfzA-DF-Z]/) { # looks not like number
    $sval = $expr;
  } else {
    $sval = B::C::nvx($expr);
    $sval = $expr if $sval eq '0' and $expr;
  }

  runtime("$obj->{nv} = $sval;");
  $obj->{flags} &= ~( VALID_SV | VALID_INT );
  $obj->{flags} |= VALID_NUM | SAVE_NUM;
}

sub set_numeric {
  my ( $obj, $expr ) = @_;
  if ( $obj->{type} == T_INT ) {
    $obj->set_int($expr);
  }
  else {
    $obj->set_double($expr);
  }
}

sub set_sv {
  my ( $obj, $expr ) = @_;
  runtime("SvSetSV($obj->{sv}, $expr);");
  $obj->invalidate;
  $obj->{flags} |= VALID_SV;
}

#
# Stackobj::Padsv
#

@B::Stackobj::Padsv::ISA = 'B::Stackobj';

sub B::Stackobj::Padsv::new {
  my ( $class, $type, $extra_flags, $ix, $iname, $dname ) = @_;
  $extra_flags |= SAVE_INT    if $extra_flags & VALID_INT;
  $extra_flags |= SAVE_NUM if $extra_flags & VALID_NUM;
  bless {
    type  => $type,
    flags => VALID_SV | $extra_flags,
    targ  => $ix,
    sv    => "PL_curpad[$ix]",
    iv    => "$iname",
    nv    => "$dname",
  }, $class;
}

sub B::Stackobj::Padsv::as_obj {
  my $obj = shift;
  my @c = comppadlist->ARRAY;
  my @p = $c[1]->ARRAY;
  return $p[ $obj->{targ} ];
}

sub B::Stackobj::Padsv::load_int {
  my $obj = shift;
  if ( $obj->{flags} & VALID_NUM ) {
    runtime("$obj->{iv} = $obj->{nv};");
  }
  else {
    runtime("$obj->{iv} = SvIV($obj->{sv});");
  }
  $obj->{flags} |= VALID_INT | SAVE_INT;
}

sub B::Stackobj::Padsv::load_double {
  my $obj = shift;
  $obj->write_back;
  runtime("$obj->{nv} = SvNV($obj->{sv});");
  $obj->{flags} |= VALID_NUM | SAVE_NUM;
}

sub B::Stackobj::Padsv::load_str {
  my $obj = shift;
  $obj->write_back;
  $obj->{flags} |= VALID_STR | SAVE_STR;
}

sub B::Stackobj::Padsv::save_int {
  my $obj = shift;
  return $obj->{flags} & SAVE_INT;
}

sub B::Stackobj::Padsv::save_double {
  my $obj = shift;
  return $obj->{flags} & SAVE_NUM;
}

sub B::Stackobj::Padsv::save_str {
  my $obj = shift;
  return $obj->{flags} & SAVE_STR;
}

sub B::Stackobj::Padsv::write_back {
  my $obj   = shift;
  my $flags = $obj->{flags};
  return if $flags & VALID_SV;
  if ( $flags & VALID_INT ) {
    if ( $flags & VALID_UNSIGNED ) {
      runtime("sv_setuv($obj->{sv}, $obj->{iv});");
    }
    else {
      runtime("sv_setiv($obj->{sv}, $obj->{iv});");
    }
  }
  elsif ( $flags & VALID_NUM ) {
    runtime("sv_setnv($obj->{sv}, $obj->{nv});");
  }
  elsif ( $flags & VALID_STR ) {
    ;
  }
  else {
    confess "write_back failed for lexical @{[$obj->peek]}\n";
  }
  $obj->{flags} |= VALID_SV;
}

#
# Stackobj::Const
#

@B::Stackobj::Const::ISA = 'B::Stackobj';

sub B::Stackobj::Const::new {
  my ( $class, $sv ) = @_;
  my $obj = bless {
    flags => 0,
    sv    => $sv,    # holds the SV object until write_back happens
    obj   => $sv
  }, $class;
  if ( ref($sv) eq "B::SPECIAL" ) {
    $obj->{type} = T_SPECIAL;
  }
  else {
    my $svflags = $sv->FLAGS;
    if ( $svflags & SVf_IOK ) {
      $obj->{flags} = VALID_INT | VALID_NUM;
      $obj->{type}  = T_INT;
      if ( $svflags & SVf_IVisUV ) {
        $obj->{flags} |= VALID_UNSIGNED;
        $obj->{nv} = $obj->{iv} = $sv->UVX;
      }
      else {
        $obj->{nv} = $obj->{iv} = $sv->IV;
      }
    }
    elsif ( $svflags & SVf_NOK ) {
      $obj->{flags} = VALID_INT | VALID_NUM;
      $obj->{type}  = T_NUM;
      $obj->{iv}    = $obj->{nv} = $sv->NV;
    }
    elsif ( $svflags & SVf_POK ) {
      $obj->{flags} = VALID_STR;
      $obj->{type}  = T_STR;
      $obj->{sv}    = $sv;
    }
    else {
      $obj->{type} = T_UNKNOWN;
    }
  }
  return $obj;
}

sub B::Stackobj::Const::write_back {
  my $obj = shift;
  return if $obj->{flags} & VALID_SV;

  # Save the SV object and replace $obj->{sv} by its C source code name
  $obj->{sv} = $obj->{obj}->save;
  $obj->{flags} |= VALID_SV | VALID_INT | VALID_NUM;
}

sub B::Stackobj::Const::load_int {
  my $obj = shift;
  if ( ref( $obj->{obj} ) eq "B::RV" or ($] >= 5.011 and $obj->{obj}->FLAGS & SVf_ROK)) {
    $obj->{iv} = int( $obj->{obj}->RV->PV );
  }
  else {
    $obj->{iv} = int( $obj->{obj}->PV );
  }
  $obj->{flags} |= VALID_INT;
}

sub B::Stackobj::Const::load_double {
  my $obj = shift;
  if ( ref( $obj->{obj} ) eq "B::RV" or ($] >= 5.011 and $obj->{obj}->FLAGS & SVf_ROK)) {
    $obj->{nv} = $obj->{obj}->RV->PV + 0.0;
  }
  else {
    $obj->{nv} = $obj->{obj}->PV + 0.0;
  }
  $obj->{flags} |= VALID_NUM;
}

sub B::Stackobj::Const::load_str {
  my $obj = shift;
  if ( ref( $obj->{obj} ) eq "B::RV" or ($] >= 5.011 and $obj->{obj}->FLAGS & SVf_ROK)) {
    $obj->{sv} = $obj->{obj}->RV;
  }
  else {
    $obj->{sv} = $obj->{obj};
  }
  $obj->{flags} |= VALID_STR;
}

sub B::Stackobj::Const::invalidate { }

#
# Stackobj::Bool
#
;
@B::Stackobj::Bool::ISA = 'B::Stackobj';

sub B::Stackobj::Bool::new {
  my ( $class, $preg ) = @_;
  my $obj = bless {
    type  => T_INT,
    flags => VALID_INT | VALID_NUM,
    iv    => $$preg,
    nv    => $$preg,
    obj   => $preg                       # this holds our ref to the pseudo-reg
  }, $class;
  return $obj;
}

sub B::Stackobj::Bool::write_back {
  my $obj = shift;
  return if $obj->{flags} & VALID_SV;
  $obj->{sv} = "($obj->{iv} ? &PL_sv_yes : &PL_sv_no)";
  $obj->{flags} |= VALID_SV;
}

# XXX Might want to handle as_double/set_double/load_double?

sub B::Stackobj::Bool::invalidate { }

#
# Stackobj::Aelem
#

@B::Stackobj::Aelem::ISA = 'B::Stackobj';

sub B::Stackobj::Aelem::new {
  my ( $class, $av, $ix, $lvalue ) = @_;
  my $sv;
  # pop ix before av
  if ($av eq 'POPs' and $ix eq 'POPi') {
    $sv = "({ int _ix = POPi; _ix >= 0 ? AvARRAY(POPs)[_ix] : *av_fetch((AV*)POPs, _ix, $lvalue); })";
  } elsif ($ix =~ /^-?[\d\.]+$/) {
    $sv = "AvARRAY($av)[$ix]";
  } else {
    $sv = "($ix >= 0 ? AvARRAY($av)[$ix] : *av_fetch((AV*)$av, $ix, $lvalue))";
  }
  my $obj = bless {
    type  => T_UNKNOWN,
    flags => VALID_INT | VALID_NUM | VALID_SV,
    iv    => "SvIVX($sv)",
    nv    => "SvNVX($sv)",
    sv    => "$sv",
    lvalue => $lvalue,
  }, $class;
  return $obj;
}

sub B::Stackobj::Aelem::write_back {
  my $obj = shift;
  $obj->{flags} |= VALID_SV | VALID_INT | VALID_NUM | VALID_STR;
}

sub B::Stackobj::Aelem::invalidate { }

1;

__END__

=head1 NAME

B::Stackobj - Stack and type annotation helper module for the CC backend

=head1 SYNOPSIS

	use B::Stackobj;

=head1 DESCRIPTION

A simple representation of pp stacks and lexical pads for the B::CC compiler.
All locals and function arguments get type annotated, for all B::CC ops which
can be optimized.

For lexical pads (i.e. my or better our variables) we currently can force the type of
variables according to a magic naming scheme in L<B::CC/load_pad>.

    my $<name>_i;    IV integer
    my $<name>_ir;   IV integer in a pseudo register
    my $<name>_d;    NV double

Future ideas are B<type qualifiers> as attributes

  B<num>, B<int>, B<register>, B<temp>, B<unsigned>, B<ro>

such as in

	our int $i : unsigned : ro;
        our num $d;

Type attributes for sub definitions are not spec'ed yet.
L<Ctypes> attributes and objects should also be recognized, such as
C<c_int> and C<c_double>.

B<my vs our>: Note that only B<our> attributes are resolved at B<compile-time>,
B<my> attributes are resolved at B<run-time>. So the compiler will only see
type attributes for our variables.

See L<B::CC/load_pad> and L<types>.

TODO: Represent on this stack not only PADs,SV,IV,PV,NV,BOOL,Special
and a SV const, but also GV,CV,RV,AV,HV, esp. AELEM and HELEM.
Use B::Stackobj::Const.

=head1 AUTHOR

Malcolm Beattie C<MICB at cpan.org> I<(retired)>,
Reini Urban C<rurban at cpan.org>

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 78
# End:
# vim: expandtab shiftwidth=2:
