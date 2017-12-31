use strict;
use warnings;

BEGIN { $^P |= 0x210 }
# $PERLDB sets debugger flags
# 0x10  Keep info about source lines on which a subroutine is defined.
# 0x200 Provide informative names to anonymous subroutines based on
#       the place they were compiled.
use Test::More;
use B 'svref_2object';
my $ISCPERL;
BEGIN { $ISCPERL = $^V =~ /c$/; }

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

    $expected =~ s/'/::/g;

    # this is apparently how things worked before 5.16
    utf8::encode($expected) if $] < 5.016 and $ord > 255;
    # before 5.16 and after v5.25.2c names with NUL are stripped
    if (!$ord and ($] < 5.016 or ($ISCPERL and $] >= 5.025002))) {
      $expected =~ s/\0.*//;
    }

    my $stash_name = join '::', map { $_->STASH->NAME, $_->NAME } svref_2object($sub)->GV;

    is $stash_name, $expected, "stash name for $type is correct $for_what";
    is $sub->(), $expected, "caller() in $type returns correct name $for_what";
}

#######################################################################

my @test_ordinals = ( 1 .. 255 );
# 5.16 is the first perl to allow \0 in identifiers
# 5.25.2c disallowed \0 again.
push @test_ordinals, 0 if $] >= 5.016 and !($] >= 5.025002 and $ISCPERL);
# This is a mess. Yes, the stash supposedly can handle unicode, yet
# on < 5.16 the behavior is literally undefined (with crashes beyond
# the basic plane), and is still unclear post 5.16 with eval_bytes/eval_utf8
# In any case - subname needs to *somehow* work with this, so try to
# do the a heuristic with plain eval (grep for `5.016` below)

# Unicode in 5.6 cannot handle multi-byte characters (crashes)
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

is($x->(), "main::foo", "set name by coderef");

{
  package Blork;

  use Sub::Util qw( set_subname );

  set_subname " Bar!", $x;
  ::is($x->(), "Blork:: Bar!", "leading space");

  set_subname "Foo::Bar::Baz", $x;
  ::is($x->(), "Foo::Bar::Baz", "2 levels");

  set_subname "set_subname (dynamic $_)", \&set_subname  for 1 .. 3;

  for (4 .. 5) {
      set_subname "Dynamic $_", $x;
      ::is($x->(), "Blork::Dynamic $_", "Dynamic $_");
  }

  ::is($DB::sub{"main::foo"}, $anon, "DB::sub foo");

  for (4 .. 5) {
      ::is($DB::sub{"Blork::Dynamic $_"}, $anon, "DB::sub Dynamic $_");
  }

  for ("Blork:: Bar!", "Foo::Bar::Baz") {
      ::is($DB::sub{$_}, $anon, "DB::sub anon $_");
  }
}

# RT42725
{
  my $source = eval {
      B::Deparse->new->coderef2text(set_subname foo => sub{ @_ });
  };

  ok !$@, "Deparse without error";

  like($source, qr/\@\_/, 'Deparse has @_');
}

# subname of set_subname
{
  is(subname(set_subname "my-scary-name-here", sub {}), "main::my-scary-name-here",
    'subname of set_subname');
}

#######################################################################

my $legal_ident_char = "A-Z_a-z0-9'";
$legal_ident_char .= join '', map chr, 0x100, 0x498
    unless $] < 5.008;

for my $ord (@test_ordinals) {
    my $sub;
    my $pkg       = sprintf 'test::SOME_%c_STASH', $ord;
    my $subname   = sprintf 'SOME_%c_NAME', $ord;
    my $fullname = $pkg . '::' . $subname;
    if ($ord == 0x27) { # ' => :: gv.c:S_parse_gv_stash_name
      $fullname = "test::SOME_::_STASH::SOME_::_NAME";
    }
    if (!$ord && ($] >= 5.025002 and $ISCPERL)) {
      $fullname = "test::SOME_::SOME_";
    }

    $sub = set_subname $fullname => sub { (caller(0))[3] };
    caller3_ok $sub, $fullname, 'renamed closure', $ord;

    # test that we can *always* compile at least within the correct package
    my $expected;
    if ( chr($ord) =~ m/^[$legal_ident_char]$/o ) { # compile directly
        $expected = $fullname;
        $sub = compile_named_sub $fullname => '(caller(0))[3]';
    }
    else { # not a legal identifier but at least test the package name by aliasing
        # unicode quirks <5.16
        if (($ord == 0x2122 or $ord == 0x1f4a9) and $] < 5.015) {
            $subname  = "sub";
            $fullname = $pkg . '::' . $subname;
        }
        $expected = "aliased::native::$fullname";
        {
            no strict 'refs';
            *palatable:: = *{"aliased::native::${pkg}::"};
            # now palatable:: literally means aliased::native::${pkg}::
            if ($ISCPERL and $] >= 5.025) {
              warnings->unimport('security');
              BEGIN { strict->unimport('names') if $] >= 5.027; }
              ${"palatable::$subname"} = 1;
              ${"palatable::"}{"sub"} = ${"palatable::"}{$subname};
            } else {
              ${"palatable::$subname"} = 1;
              ${"palatable::"}{"sub"} = ${"palatable::"}{$subname};
            }
            # and palatable::sub means aliased::native::${pkg}::${subname}
        }
        $sub = compile_named_sub 'palatable::sub' => '(caller(0))[3]';
    }
    caller3_ok $sub, $expected, 'natively compiled sub', $ord;
}

# vim: ft=perl
