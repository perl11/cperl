
use Test::More tests => 2;
use strict;
use Cpanel::JSON::XS;
#########################

my $json = Cpanel::JSON::XS->new->allow_nonref;

my $js = '/';

is($json->encode($js), '"/"');
is($json->escape_slash->encode($js), '"\/"');

