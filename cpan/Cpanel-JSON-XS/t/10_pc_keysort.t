# copied over from JSON::PC and modified to use Cpanel::JSON::XS

use Test::More;
use strict;
BEGIN { plan tests => 1 };
use Cpanel::JSON::XS;
#########################

my ($js,$obj);
my $pc = Cpanel::JSON::XS->new->canonical(1);

$obj = {a=>1, b=>2, c=>3, d=>4, e=>5, f=>6, g=>7, h=>8, i=>9};

$js = $pc->encode($obj);
is($js, q|{"a":1,"b":2,"c":3,"d":4,"e":5,"f":6,"g":7,"h":8,"i":9}|);

