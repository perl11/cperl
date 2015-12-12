#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=237
# NULL in strings (pv->PVX problem)
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;
my $cmt = '#237 NULL in strings';
my $script = 'print "\000\000\000\000_"';
my $exp = "^\000\000\000\000_\$";
ctest(1, $exp, 'C,-O3', 'ccode237i', $script, 'C '.$cmt);
plctest(2, $exp, 'ccode237i', $script, "BC ".$cmt);
