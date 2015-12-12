
use Test::More tests => 4;
use strict;
use Cpanel::JSON::XS;
#########################

my $json = Cpanel::JSON::XS->new;

eval q| $json->decode('{foo:"bar"}') |;
ok($@); # in XS and PP, the error message differs.

$json->allow_barekey;
is($json->decode('{foo:"bar"}')->{foo}, 'bar');
is($json->decode('{ foo : "bar"}')->{foo}, 'bar', 'with space');
is($json->decode(qq({\tfoo\t:"bar"}))->{foo}, 'bar', 'with tab');

