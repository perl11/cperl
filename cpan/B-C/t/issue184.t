#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=184
# sub overload, no warnings redefine
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;

ctestok(1,'C,-O3','ccode184i',<<'EOF','#184 no warnings redefine');
use warnings;
sub xyz { no warnings 'redefine'; *xyz = sub { $a <=> $b }; &xyz }
eval { @b = sort xyz 4,1,3,2 };
print defined $b[0] && $b[0] == 1 && $b[1] == 2 && $b[2] == 3 && $b[3] == 4 ? "ok\n" : "fail\n";
EOF
