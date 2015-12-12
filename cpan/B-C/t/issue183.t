#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=183
# Special case: ->import should fail silently
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;

use B::C ();
my $when = "1.42_61";
ctestok(1,'C,-O3','ccode183i','main->import();print q(ok)',
        ($B::C::VERSION lt $when ? "TODO " : "").'#183 ->import should fail silently');
