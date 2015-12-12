#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=45
# dorassign //= failed until B::CC 1.09 (B-C-1.30)
BEGIN {
  unless (-d ".git" and !$ENV{NO_AUTHOR}) {
    print "1..0 #SKIP Only if -d .git\n"; exit;
  }
}
use Test::More tests => 4;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

use B::CC;
SKIP: {
  skip "dorassign was added with perl 5.10.0", 4 if $] < 5.010;
  # other: define it
  ctestok(1, "CC", "ccode45i", 'my $x; $x//=1; print q(ok) if $x;',
	  ($B::CC::VERSION < 1.09 ? "TODO " : ""). "dorassign other fixed with B-C-1.30");
  # next: already defined
  ctestok(2, "CC", "ccode45i", 'my $x=1; $x//=0; print q(ok) if $x;',
	  ($B::CC::VERSION < 1.09 ? "TODO " : ""). "dorassign next fixed with B-C-1.30");

  # dor never failed but test it here for regressions
  ctestok(3, "CC", "ccode45i", 'my ($x,$y); $x=$y//1;print "ok" if $x;');
  ctestok(4, "CC", "ccode45i", 'my $y=1; my $x=$y//0;print "ok" if $x;');
}
