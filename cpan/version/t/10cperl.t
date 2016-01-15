#! /usr/local/perl -w
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################
use Test::More;
eval 'use cperl';
plan skip_all => 'requires cperl' if $@;
plan tests => 13;

use version;

my $n = version->new("0.2");
my $c = version->new("0.2c");

cmp_ok($n, '==', $c, "0.2 == 0.2c numeric");
ok    ($n <= $c,     "0.2 <= 0.2c numeric");

ok($c eq '0.2c', "eq 0.2c string");
ok($n ne $c,     "0.2 ne 0.2c string");
ok(!($n < $c),   "!(0.2 < 0.2c) numeric");

my $vc = version->new("v0.2c");
is($vc, 'v0.2c');

my $vn = version->new("v0.2");
cmp_ok($vn, '==', 0.002, "v0.2  == 0.002");
cmp_ok($vc, '==', 0.002, "v0.2c == 0.002");
cmp_ok($n, '==', 0.2, " 0.2  == 0.2");
cmp_ok($c, '==', 0.2, "0.2c == 0.2");

is($vc, 'v0.2c');
is($vn, 'v0.2');
ok(!($vc ne $vn), "v0.2c ne v0.2");
