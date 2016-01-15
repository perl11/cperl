#! /usr/local/perl -w
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################
use Test::More;
eval 'use cperl';
plan skip_all => 'requires cperl' if $@;
plan tests => 16;

use version;

my $n = version->new("0.2");
my $c = version->new("0.2c");

cmp_ok($n, '==', $c, "0.2 == 0.2c numeric");
ok    ($n <= $c,     "0.2 <= 0.2c numeric");

ok($n eq '0.2',    "eq 0.2 string");
ok("$c" eq '0.2c', "eq 0.2c string");
ok($c == 0.2,      "== 0.2 num");
ok('0.2c' eq "$c", "eq 0.2c string");
ok("$n" ne "$c",   "0.2 ne 0.2c string");
ok($n eq $c,       "vcmp not scmp");
ok(!($n < $c),   "!(0.2 < 0.2c) numeric");

my $vc = version->new("v0.2c");
ok("$vc" eq 'v0.2c');

my $vn = version->new("v0.2");
cmp_ok($vn, '==', 0.002, "v0.2  == 0.002");
cmp_ok($vc, '==', 0.002, "v0.2c == 0.002");
cmp_ok($n, '==', 0.2, " 0.2  == 0.2");
cmp_ok($c, '==', 0.2, "0.2c == 0.2");

ok($vn eq 'v0.2');
ok("$vc" ne "$vn", "v0.2c ne v0.2");
