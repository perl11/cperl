#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=159
# wrong ISA with empty packages, and wrong dumping of unfound methods
use Test::More tests => 2;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

use B::C;
my $when = "1.42_61";
ctestok(1, "C,-O3", 'ccode159i_c',
        'BEGIN{@X::ISA="Y";sub Y::z{"Y::z"}} print "ok\n" if X->z eq "Y::z";delete $X::{z};exit',
        ($B::C::VERSION lt $when ? "TODO " : "").
        "wrong ISA with empty packages fixed with B-C-$when");
ctestok(2, "C,-O3", 'ccode159i_r',
        '@X::ISA="Y";sub Y::z{"Y::z"} print "ok\n" if X->z eq "Y::z";delete $X::{z};exit',
        ($B::C::VERSION lt $when ? "TODO " : "").
        "wrong method dispatch by dumping unfound methods fixed with B-C-$when");
