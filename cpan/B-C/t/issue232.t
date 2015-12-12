#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=232
# Carp::longmess broken with C,-O0. -O3 is fine
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;
use Config ();
my $ITHREADS = $Config::Config{useithreads};

use B::C ();
my $when = "1.42_61";
ctestok(1,'C,-O0','ccode232i','use Carp (); exit unless Carp::longmess(); print qq{ok\n}',
      (($B::C::VERSION lt $when) ? "TODO " : "").
      '#234 Carp::longmess with C,-O0');
