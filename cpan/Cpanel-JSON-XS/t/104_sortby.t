
use Test::More tests => 3;
use strict;
use Cpanel::JSON::XS;
#########################

my ($js,$obj);
my $pc = Cpanel::JSON::XS->new;

$obj = {a=>1, b=>2, c=>3, d=>4, e=>5, f=>6, g=>7, h=>8, i=>9};

$js = $pc->sort_by(1)->encode($obj);
is($js, q|{"a":1,"b":2,"c":3,"d":4,"e":5,"f":6,"g":7,"h":8,"i":9}|);


$js = $pc->sort_by(sub { $Cpanel::JSON::XS::a cmp $Cpanel::JSON::XS::b })->encode($obj);
is($js, q|{"a":1,"b":2,"c":3,"d":4,"e":5,"f":6,"g":7,"h":8,"i":9}|);

$js = $pc->sort_by('hoge')->encode($obj);
is($js, q|{"a":1,"b":2,"c":3,"d":4,"e":5,"f":6,"g":7,"h":8,"i":9}|);

sub Cpanel::JSON::XS::hoge { $Cpanel::JSON::XS::a cmp $Cpanel::JSON::XS::b }
