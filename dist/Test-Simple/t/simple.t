BEGIN {
    if( $ENV{PERL_CORE} ) {
        @INC = '../../lib';
    }
}

use strict;

BEGIN { $| = 1; $^W = 1; }

use Test::Simple tests => 3;

ok(1, 'compile');

ok(1);
ok(1, 'foo');
