#!./perl -- -*- mode: cperl; cperl-indent-level: 4 -*-

BEGIN {
    chdir 't' if -d 't';
    @INC = ( '.', '../lib' );
}

use strict;
require '../t/test.pl';
plan(4);

$|=1;

use exact_arith;
my $n = 18446744073709551614 * 2; # => 36893488147419103228, a bigint object
is(ref $n, 'bigint');
is($n, 36893488147419103228);

{
    no exact_arith;
    my $m = 18446744073709551614 * 2;
    is(ref $n, '');
    is($n, 3.68934881474191e+19);
}
