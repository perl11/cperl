use strict;
use warnings;

BEGIN { $^P |= 0x210 }
use Test::More;

my @test_ordinals = ( 1 .. 255 );
# 5.16 is the first perl to start properly handling \0 in identifiers
push @test_ordinals, 0
    unless $] < 5.016;
# This is a mess. Yes, the stash supposedly can handle unicode, yet
# on < 5.16 the behavior is literally undefined (with crashes beyond
# the basic plane), and is still unclear post 5.16 with eval_bytes/eval_utf8
# In any case - Sub::Name needs to *somehow* work with this, so try to
# do the a heuristic with plain eval (grep for `5.016` below)
push @test_ordinals,
    0x100,    # LATIN CAPITAL LETTER A WITH MACRON
    0x498,    # CYRILLIC CAPITAL LETTER ZE WITH DESCENDER
    0x2122,   # TRADE MARK SIGN
    0x1f4a9,  # PILE OF POO
    unless $] < 5.008;

plan tests => 18 + (@test_ordinals * 2 * 2);

use B::Deparse;
use Sub::Util qw( subname set_subname );

{
  sub localfunc {}
  sub fully::qualified::func {}

  is(subname(\&subname), "Sub::Util::subname",
    'subname of \&subname');
  is(subname(\&localfunc), "main::localfunc",
    'subname of \&localfunc');
  is(subname(\&fully::qualified::func), "fully::qualified::func",
    'subname of \&fully::qualfied::func');

  # Because of the $^P debug flag, we'll get [file:line] as well
  like(subname(sub {}), qr/^main::__ANON__\[.+:\d+\]$/, 'subname of anon sub');

  ok(!eval { subname([]) }, 'subname [] dies');
}

my $x = set_subname foo => sub { (caller 0)[3] };
my $line = __LINE__ - 1;
my $file = __FILE__;
my $anon = $DB::sub{"main::__ANON__[${file}:${line}]"};

is($x->(), "main::foo");

{
  package Blork;

  use Sub::Util qw( set_subname );

  set_subname " Bar!", $x;
  ::is($x->(), "Blork:: Bar!");

  set_subname "Foo::Bar::Baz", $x;
  ::is($x->(), "Foo::Bar::Baz");

  set_subname "set_subname (dynamic $_)", \&set_subname  for 1 .. 3;

  for (4 .. 5) {
      set_subname "Dynamic $_", $x;
      ::is($x->(), "Blork::Dynamic $_");
  }

  ::is($DB::sub{"main::foo"}, $anon);

  for (4 .. 5) {
      ::is($DB::sub{"Blork::Dynamic $_"}, $anon);
  }

  for ("Blork:: Bar!", "Foo::Bar::Baz") {
      ::is($DB::sub{$_}, $anon);
  }
}

# RT42725
{
  my $source = eval {
      B::Deparse->new->coderef2text(set_subname foo => sub{ @_ });
  };

  ok !$@;

  like $source, qr/\@\_/;
}

# subname of set_subname
{
  is(subname(set_subname "my-scary-name-here", sub {}), "main::my-scary-name-here",
    'subname of set_subname');
}

# binary and unicode names

use B 'svref_2object';

sub caller3_ok {
    my ( $cref, $expected, $ord, $type ) = @_;

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

    my $fullname   = svref_2object($cref)->GV->STASH->NAME
            . "::" . svref_2object($cref)->GV->NAME;

    is $fullname, $expected, "stash name for $type is correct $for_what";
    is $cref->(), $expected, "caller() in $type returns correct name $for_what";
}

#######################################################################

for my $ord (@test_ordinals) {
    my $sub;
    my $pkg       = sprintf 'test::SOME_%c_STASH', $ord;
    my $subname   = sprintf 'SOME_%c_NAME', $ord;
    my $full_name = $pkg . '::' . $subname;
    if ($ord == 0x27) {
        $full_name = "test::SOME_::_STASH::SOME_::_NAME";
    }

    $sub = set_subname $full_name => sub { (caller(0))[3] };
    caller3_ok $sub, $full_name, $ord, 'renamed closure';

    # test that we can *always* compile at least within the correct package
    my $expected;
    if ( chr($ord) =~ /^[A-Z_a-z0-9']$/ ) { # legal identifier char, compile directly
        $expected = $full_name;
        if ( chr($ord) eq "'" ) {  # special-case ' == ::
            $expected =~ s/'/::/g; # gv.c:S_parse_gv_stash_name
            $pkg     .=  "::SOME_";
        }
        $sub = eval( "
            package $pkg;
            sub $full_name { (caller(0))[3] };
            no strict 'refs';
            \\&{\$full_name}
        " ) || die $@;
    }
    else { # not a legal identifier but at least test the package name
        $expected = "${pkg}::foo";
        { no strict 'refs'; *palatable:: = *{"${pkg}::"} }
        $sub = eval( "
            package palatable;
            sub foo { (caller(0))[3] };
            \\&foo;
        " ) || die $@;
    }
    caller3_ok $sub, $expected, $ord, 'natively compiled sub';
}

# vim: ft=perl
