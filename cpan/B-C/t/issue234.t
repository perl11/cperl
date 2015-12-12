#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=234
# new-cog edge-case: pv2iv conversion with negative numeric strings
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;

use B::C;
my $when = "1.42_61";
ctest(1,'^4$','C,-O3','ccode234i','$c = 0; for ("-3" .. "0") { $c++ } ; print "$c"',
      ($B::C::VERSION lt $when ? "TODO " : "").
      '#234 -O3 pv2iv conversion for negative numeric strings');
