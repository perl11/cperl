#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=105
# v5.16 Missing bc imports
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;
use Config ();
my $ITHREADS  = $Config::Config{useithreads};

my $source = 'package A;
use Storable qw/dclone/;

my $a = \"";
dclone $a;
print q(ok)';

my $cmt = "BC missing import 5.16";
my $todo = ($] =~ /^5.016/ and $Config{useithreads}) ? "TODO " : "";
$todo = "TODO " if $] < 5.007;
plctestok(1, "ccode105i", $source, $todo.$cmt);
