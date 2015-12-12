#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=32
# use open and @ARGV
use strict;
BEGIN {
  if ($] < 5.006) {
    print "1..1\nok 1 #skip $] has no IO discipline\n"; exit;
  }
}
use Test::More tests => 1;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
my $name = 'ccode32i.pl';
open my $fh, '>', $name or die;
print $fh 'use open ":encoding(utf8)";my $x;print @ARGV';
close $fh;

my $X = $^X =~ m/\s/ ? qq{"$^X" -Iblib/arch -Iblib/lib} : "$^X -Iblib/arch -Iblib/lib";
is(`$X blib/script/perlcc -O3 -occode32i -r $name 1 2 3`,
   '123', "use open and \@ARGV");

