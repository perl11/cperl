#!./perl -- -*- mode: cperl; cperl-indent-level: 4 -*-
# 64bit int on 64bit CPU, or 32bit via -Duse64bitint
# 32bit without -Duse64bitint cannot be tested. requires !d_quad.

BEGIN {
    chdir 't' if -d 't';
    @INC = ( '.', '../lib' );
}

use strict;
use Config ();
my ($ivsize, $can64) = ($Config::Config{ivsize}, $Config::Config{i64size});
require '../t/test.pl';
skip_all("test only with 64bit IV on a 64bit CPU")
  unless $ivsize == 8 and $can64 == 8;
push @INC, 'cpan/Math-BigInt/lib' if is_miniperl();
plan(15);

$|=1;
# make $ta constant foldable (cperl only)
# Note: on 32bit $ta is a NV, bypassing exact_arith
my $ta :const = 18446744073709551614;
# $a needs to be initialized at run-time to bypass constant folding.
my $a = 18446744073709551614;
my $r1 :const = '36893488147419103228';
my $r2 :const = 3.68934881474191e+19;

# test it at compile-time via constant folding
use exact_arith;
my $n = $ta * 2; # constant folded with cperl
like(ref $n, qr/^Math::BigInt/,  '* type (c)');
is($n, $r1, '* val (c)');

{
    no exact_arith;
    my $m = $ta * 2;
    is(ref $m, '', '* no type (c)');
    is($m, $r2, '* no val (c)');
}

# and at run-time
my $two = 2;
$n = $a * $two;
like(ref $n, qr/^Math::BigInt/,  '* type (r)');
is($n, $r1, '* val (r)');

{
    no exact_arith;
    my $m = $a * $two;
    is(ref $m, '', '* no type (r)');
    is($m, $r2, '* no val (r)');
}

my $c = $ta + 10000;
like(ref $c, qr/^Math::BigInt/,  '+ type (c)');
my $r = $a + 10000;
like(ref $r, qr/^Math::BigInt/,  '+ type (r)');

$c = $ta - (- 2);
like(ref $c, qr/^Math::BigInt/,  '- type (c)');
$r = $c  - 1;
like(ref $r, qr/^Math::BigInt/,  '- type (r)');

# gets smaller, not bigger. with 0.3 we switch to NV
#$c = $b / 3;
#like(ref $c, qr/^Math::BigInt/,  '/ type (c)');
#$r = $b / 3;
#like(ref $r, qr/^Math::BigInt/,  '/ type (r)');

$c = $ta ** 2;
like(ref $c, qr/^Math::BigInt/,  '** type (c)');
$r = $a ** 2;
like(ref $r, qr/^Math::BigInt/,  '** type (r)');

$a++;
$r = $a++;
like(ref $r, qr/^Math::BigInt/,  '++ type (r)');
