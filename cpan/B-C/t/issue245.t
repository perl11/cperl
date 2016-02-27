#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=245
# unicode value not preserved when passed to a function with -O3
# lc("\x{1E9E}") and "\x{df}" were hashed as the same string in const %strtable
use strict;
BEGIN {
  if ($ENV{PERL_CORE}) {
    unshift @INC, ('t', '../../lib');
  } else {
    unshift @INC, 't', "blib/arch", "blib/lib";
  }
  require TestBC;
}
use Test::More tests => 1;

use B::C;
# passes threaded and <5.10
my $fixed_with = "1.42_70";
my $TODO = "TODO " if $B::C::VERSION lt $fixed_with;
$TODO = "" if $Config{useithreads};
$TODO = "" if $] < 5.010;
my $todomsg = '#245 2nd static unicode char';
ctest(1,"b: 223", 'C,-O3','ccode245i', <<'EOF', $TODO.$todomsg);
sub foo {
    my ( $a, $b ) = @_;
    print "b: ".ord($b);
}
foo(lc("\x{1E9E}"), "\x{df}");
EOF
