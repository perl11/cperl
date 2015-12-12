#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=185
# bytes_heavy
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;
use B::C ();
my $when = "1.43_03";

ctestok(1,'C,-O3','ccode185i',<<'EOF',($B::C::VERSION lt $when ? "TODO " : "").'#185 bytes_heavy');
my $a = pack("U", 0xFF);
use bytes;
print "not " unless $a eq "\xc3\xbf" && bytes::length($a) == 2;
print "ok\n"
EOF
