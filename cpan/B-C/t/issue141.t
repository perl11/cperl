#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=141
# C,-O3 stativ pv fails with conversion to IV: char* "1" => 0   < 5.17.5, branch new-cog
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

use B::C;
my $todo = ($B::C::VERSION lt '1.42_57' ? "TODO " : "");
$todo = "" if $] > 5.017005;
ctestok(1, "C,-O3", 'ccode141i', '@x=(0..1);print "ok" if $#x == "1"', "${todo}C,-O3 pv2iv conversion with static strings");
