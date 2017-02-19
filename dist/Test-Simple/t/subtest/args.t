#!/usr/bin/perl -w

use strict;
use Test::Builder;

BEGIN {
    if( $ENV{PERL_CORE} ) {
        chdir 't';
        @INC = ( '../lib', 'lib' );
    }
    else {
        unshift @INC, 't/lib';
    }
}
use Test::Builder::NoOutput;

my $tb = Test::Builder->new;

$tb->ok( !eval { $tb->subtest() } );
#old error: subtest()'s second argument must be a code ref
#new better error: Not enough arguments for subroutine Test::Builder::subtest. Want: 3, but got: 0

$tb->ok( !eval { $tb->subtest("foo", undef) } );
$tb->like( $@, qr/^\Qsubtest()'s second argument must be a code ref/ );

$tb->subtest('Arg passing', sub {
    my $foo = shift;
    my $child = Test::Builder->new;
    $child->is_eq($foo, 'foo');
    $child->done_testing;
    $child->finalize;
}, 'foo');

$tb->done_testing();
