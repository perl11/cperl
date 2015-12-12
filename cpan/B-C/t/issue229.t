#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=229
# walker misses &main::yyy
BEGIN {
  unless (-d '.git' and !$ENV{NO_AUTHOR} and !$ENV{HARNESS_ACTIVE}) {
    print "1..0 #SKIP Only for author\n";
    exit;
  }
}
use strict;
use Test::More tests => 1;

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $perlcc = "$X -Iblib/arch -Iblib/lib blib/script/perlcc";
is(`$perlcc --no-spawn -O3 -UB -r -occode229i -e 'sub yyy () { "yyy" } print "ok" if( eval q{yyy} eq "yyy");'`,
   "ok", "walker misses &main::yyy");
