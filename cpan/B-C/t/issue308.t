#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=308
# run-time load of some packages - missing DynaLoader::bootstrap
# DynaLoader and AutoLoader
#   core: IPC::SysV DB_File
#   cpan: Net::LibIDN Net::SSLeay BSD::Resource
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;

my $script = 'print (eval q{require BSD::Resource;} ? qq{ok\n} : $@);';
my $exp = "ok";
if (eval "require BSD::Resource;") {
  ctest(1, $exp, 'C,-O3', 'ccode308i', $script, 'C #308 run-time load BSD::Resource - missing DynaLoader::bootstrap');
} else {
  ok(1, "skip BSD::Resource not installed");
}

$script = 'print (eval q{require Net::SSLeay;} ? qq{ok\n} : $@);';
if (eval "require Net::SSLeay;") {
  # works with -O3
  ctest(2, $exp, 'C', 'ccode308i', $script, 'C run-time load Net::SSLeay - missing %Config in Errno.pm');
} else {
  ok(1, "skip Net::SSLeay not installed");
}

# 'print $_,": ",(eval q{require }.$_.q{;} ? qq{ok\n} : $@) for qw(BSD::Resource IPC::SysV DB_File Net::LibIDN Net::SSLeay);'
