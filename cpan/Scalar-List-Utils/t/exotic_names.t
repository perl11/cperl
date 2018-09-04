use strict;
use warnings;

use Test::More;
use B 'svref_2object';
BEGIN { $^P |= 0x210 }
my $CPERL;
BEGIN { $CPERL = $^V =~ /c$/; }

# This is a mess. The stash can supposedly handle Unicode but the behavior
# is literally undefined before 5.16 (with crashes beyond the basic plane),
# and remains unclear past 5.16 with evalbytes and feature unicode_eval
# In any case - Sub::Name needs to *somehow* work with this, so we will do
# a heuristic with ambiguous eval and looking for octets in the stash
use if $] >= 5.016, feature => 'unicode_eval';

if ($] >= 5.008) {
	my $builder = Test::More->builder;
	binmode $builder->output,         ":encoding(utf8)";
	binmode $builder->failure_output, ":encoding(utf8)";
	binmode $builder->todo_output,    ":encoding(utf8)";
}

sub compile_named_sub {
    my ( $fullname, $body ) = @_;
    my $sub = eval "sub $fullname { $body }" . '\\&{$fullname}';
    return $sub if $sub;
    my $e = $@;
    require Carp;
    Carp::croak $e;
}

sub caller3_ok {
    my ( $sub, $expected, $type, $ord ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $for_what = sprintf "when it contains \\x%s ( %s )", (
        ( ($ord > 255)
            ? sprintf "{%X}", $ord
            : sprintf "%02X", $ord
        ),
        (
            $ord > 255                    ? unpack('H*', pack 'C0U', $ord )
            : ($ord > 0x1f and $ord < 0x7f) ? sprintf "%c", $ord
            :                                 sprintf '\%o', $ord
        ),
    );

    # this is apparently how things worked before 5.16
    utf8::encode($expected) if $] < 5.016 and $ord > 255;
    # before 5.16 and after v5.25.2c names with NUL are stripped
    if (!$ord and ($] < 5.016 or ($CPERL and $] >= 5.025002))) {
      $expected =~ s/\0.*//;
    }

    my $stash_name = join '::', map { $_->STASH->NAME, $_->NAME } svref_2object($sub)->GV;

    is $stash_name, $expected, "stash name for $type is correct $for_what";
    is $sub->(), $expected, "caller() in $type returns correct name $for_what";
  SKIP: {
      # TODO: CPERL and utf8 flag >5.16
      skip '%DB::sub not populated when enabled at runtime', 1
        if !keys %DB::sub;
      #skip 'missing utf8 flag for %DB::sub', 1 if (!$ord || $ord > 255) && $] >= 5.016;
      my ($prefix) = $expected =~ /^(.*?test::[^:]+::)/;
      my ($db_found) = grep /^$prefix/, keys %DB::sub;
      is $db_found, $expected, "%DB::sub entry for $type is correct $for_what";
    }
}

#######################################################################

use Sub::Util 'set_subname';

# try '/0x27 first
my @ordinal = ( 39, 1..38, 40..255 );

# 5.16 is the first perl to allow \0 in identifiers
# 5.25.2c disallowed \0 again.
unshift @ordinal, 0
    if ($] >= 5.015006 and (!$CPERL or $] < 5.025002));

# 5.6 cannot handle multibyte unicode chars
push @ordinal,
    0x100,    # LATIN CAPITAL LETTER A WITH MACRON
    0x498,    # CYRILLIC CAPITAL LETTER ZE WITH DESCENDER
    0x2122,   # TRADE MARK SIGN
    0x1f4a9,  # PILE OF POO
    unless $] < 5.008;

plan tests => @ordinal * 2 * 3;

my $legal_ident_char = "A-Z_a-z0-9";
$legal_ident_char .= join '', map chr, 0x100, 0x498
    unless $] < 5.008;
# not really legal, but accepted in pkg-seperator position
$legal_ident_char .= "'" if !$CPERL or $] < 5.025002;

my $uniq = 'A000';
for my $ord (@ordinal) {
    my $sub;
    $uniq++;
    my $pkg      = sprintf 'test::%s::SOME_%c_STASH', $uniq, $ord;
    my $subname  = sprintf 'SOME_%s_%c_NAME', $uniq, $ord;
    my $fullname = join '::', $pkg, $subname;
    # since cperl5.28 ' is not expanded to ::
    if ($ord == 0x27 and (!$CPERL or $] < 5.025002)) { # ' => :: parse_gv_stash_name
      #diag "ord=' expand to ::";
      $fullname =~ s/'/::/g;
    }
    # since cperl5.26 \0 is again being cut off and illegal
    if (!$ord && ($] >= 5.025002 and $CPERL)) {
      #diag "ord=0 cut off since cperl 5.25.2";
      $fullname = sprintf 'test::%s::SOME_::SOME_%s_', $uniq, $uniq;
    }
    #diag "ord=$ord $fullname";

    $sub = set_subname $fullname => sub { (caller(0))[3] };
    caller3_ok $sub, $fullname, 'renamed closure', $ord;

    # test that we can *always* compile at least within the correct package
    my $expected;
    # accept ' also here
    if ( chr($ord) =~ m/^[$legal_ident_char]$/o ) { # compile directly
      $expected = "native::$fullname";
      $sub = compile_named_sub $expected => '(caller(0))[3]';
    }
    else { # not a legal identifier but at least test the package name by aliasing
        $expected = "aliased::native::$fullname";
        {
          no strict 'refs';
          *palatable:: = *{"aliased::native::${pkg}::"};
          my $encoded_sub = $subname;
          utf8::encode($encoded_sub) if $] < 5.016 and $ord > 255;
          # now palatable:: literally means aliased::native::${pkg}::
          if ($CPERL and $] >= 5.025) {
            warnings->unimport('security');
            no if $] >= 5.027001 && $CPERL, strict => 'names';
            ${"palatable::$subname"} = 1;
            ${"palatable::"}{"sub"} = ${"palatable::"}{$encoded_sub};
          } else {
            ${"palatable::$encoded_sub"} = 1;
            ${"palatable::"}{"sub"} = ${"palatable::"}{$encoded_sub};
            # and palatable::sub means aliased::native::${pkg}::${subname}
          }
        }
        $sub = compile_named_sub 'palatable::sub' => '(caller(0))[3]';
    }
    caller3_ok $sub, $expected, 'natively compiled sub', $ord;
}
