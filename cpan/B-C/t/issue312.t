#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=312
# --staticxs: dynamic loading not available in this perl -DNO_DYNAMIC_LOADING
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $perlcc = "$X -Iblib/arch -Iblib/lib blib/script/perlcc";

is(`$perlcc -O3 --staticxs -o ccode312i -r -e 'require Scalar::Util; eval "require List::Util"; print "ok"'`, "ok", 
   "#312 dynamic loading not available in this perl");
is(`$perlcc -O3 --staticxs -o ccode312i -r -e 'require IO; eval "require List::Util"; print "ok"'`, "ok", 
   "#312");
