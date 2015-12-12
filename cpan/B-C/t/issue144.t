#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=144
# BM search for \0
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

ctestok(1, "C", 'ccode144i', 'print "ok" if 12 == index("long message\0xx","\0")', "BM search for \\0");
