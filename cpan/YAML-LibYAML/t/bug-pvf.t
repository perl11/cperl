use lib '.';
use t::TestYAML tests => 1;
use YAML::XS;

my $string = "foo %s bar";

my $string2 = Load Dump $string;

is $string2, $string,
    "Don't be using newSVpvf for strings, cuz it does a sprintf action";
