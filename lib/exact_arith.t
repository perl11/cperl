#!./perl -- -*- mode: cperl; cperl-indent-level: 4 -*-

BEGIN {
    chdir 't' if -d 't';
    @INC = ( '.', '../lib' );
}

use strict;
require '../t/test.pl';
plan(8);

$|=1;
my $a = 18446744073709551614;

# test it at compile-time in constant folding
use exact_arith;
my $n = 18446744073709551614 * 2; # => 36893488147419103228, Math::BigInt or *::GMP
like(ref $n, qr/^Math::BigInt/,  '* type (c)');
ok($n eq '36893488147419103228', '* val (c)') or
  is($n, '36893488147419103228');

{
    no exact_arith;
    my $m = 18446744073709551614 * 2;
    is(ref $m, '', '* no type (c)');
    is($m, 3.68934881474191e+19, '* no val (c)');
}

my $two = 2;
$n = 18446744073709551614 * $two; # run-time
like(ref $n, qr/^Math::BigInt/,  '* type (r)');
ok($n eq '36893488147419103228', '* val (r)') or
  is($n, '36893488147419103228');

{
    no exact_arith;
    my $m = 18446744073709551614 * $two;
    is(ref $m, '', '* no type (r)');
    is($m, 3.68934881474191e+19, '* no val (r)');
}

my $c = 18446744073709551614 + 10000;
like(ref $c, qr/^Math::BigInt/,  '+ type (c)');
my $r = $a + 10000;
like(ref $r, qr/^Math::BigInt/,  '+ type (r)');

$c = 18446744073709551624 - 2;
like(ref $c, qr/^Math::BigInt/,  '- type (c)');
$r = $c  - 1;
like(ref $r, qr/^Math::BigInt/,  '- type (r)');

$c = 1844674407370955162400 / 0.3;
like(ref $c, qr/^Math::BigInt/,  '/ type (c)');
$r = 1844674407370955162400 / 0.3;
like(ref $r, qr/^Math::BigInt/,  '/ type (r)');

$c = 18446744073709551614 ** 2;
like(ref $c, qr/^Math::BigInt/,  '** type (c)');
$r = $a ** 2;
like(ref $r, qr/^Math::BigInt/,  '** type (r)');

$r = $a++;
like(ref $r, qr/^Math::BigInt/,  '++ type (r)');

