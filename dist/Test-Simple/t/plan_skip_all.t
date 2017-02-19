BEGIN {
    if( $ENV{PERL_CORE} ) {
        @INC = '../../lib';
    }
}

use Test::More;

plan skip_all => 'Just testing plan & skip_all';

fail('We should never get here');
