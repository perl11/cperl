#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=273
# PVMG RV should not overwrite PV slot

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;
use B::C ();

my $todo = ($B::C::VERSION ge '1.43_07') ? "" : "TODO ";
# $todo = "TODO 5.22 " if $] > 5.021; # fixed with 1.52_09

ctest(1,'11','C,-O3','ccode273i',<<'EOF',$todo.'#273 PVMG RV vs PV');
package Foo;
use overload;
sub import { overload::constant "integer" => sub { return shift }};
package main;
BEGIN { $INC{"Foo.pm"} = "/lib/Foo.pm" };
use Foo;
my $result = eval "5+6";
print "$result\n";
EOF
