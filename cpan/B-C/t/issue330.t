#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=330
# initialize op_ppaddr before init

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;

my $cmt = '#330 m//i SWASHINIT';
my $script = '"\x{101}a" =~ qr/\x{100}/i && print "ok\n"';
ctestok(1, 'C,-O1', 'ccode330i', $script, 'C -fppaddr '.$cmt);
ctestok(2, 'C,-O0', 'ccode330i', $script, 'C -fno-ppaddr '.$cmt);
