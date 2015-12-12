#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=97
# require without op_first in use v5.12
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;

my $source = $] < 5.012 ? "use 5.006; print q(ok);" : "use v5.12; print q(ok);";

plctestok(1, "ccode97i", $source, "BC require v5.12");
