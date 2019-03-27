#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=245
# unicode value not preserved when passed to a function with -O3
# lc("\x{1E9E}") and "\x{df}" were hashed as the same string in const %strtable
use strict;
use Config;
my @plan;
BEGIN {
  if ($ENV{PERL_CORE}) {
    unshift @INC, ('t', '../../lib');
  } else {
    unshift @INC, 't', "blib/arch", "blib/lib";
  }
  require TestBC;

  $ENV{SKIP_SLOW_TESTS} = 1 if $Config{ccflags} =~ /-flto/;
  $ENV{SKIP_SLOW_TESTS} = 1 if $^O =~ /MSWin32|cygwin/ and is_CI();

  if ($ENV{SKIP_SLOW_TESTS}) {
    @plan = (skip_all => 'SKIP_SLOW_TESTS, timeout on CI');
  } else {
    @plan = (tests => 1);
  }
}
use Test::More @plan;

use B::C;
# passes threaded and <5.10
my $fixed_with = "1.42_70";
my $TODO = "TODO " if $B::C::VERSION lt $fixed_with;
$TODO = "" if $Config{useithreads};
$TODO = "" if $] < 5.010;
my $todomsg = '#245 2nd static unicode char';
# this is now with 5.24.0.c also a test for FAKE_SIGNATURES
ctest(1,"b: 223", 'C,-O3','ccode245i', <<'EOF', $TODO.$todomsg);
sub foo {
    my ( $a, $b ) = @_;
    print "b: ".ord($b);
}
foo(lc("\x{1E9E}"), "\x{df}");
EOF
