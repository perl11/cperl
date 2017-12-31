use lib '.';
use t::TestYAML tests => 1;

use YAML::XS;

sub libyaml {
   YAML::XS::Dump( $_[0] );
}

my @x = (256, 'xxx', libyaml({foo => 'bar'}));

isnt "@x", '256 xxx 256 xxx 256',
    "YAML::XS::LibYAML doesn't mess up the call stack";
