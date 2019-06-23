use FindBin '$Bin';
use lib $Bin;
use TestYAML tests => 1;
use YAML::Safe;

my $string = "foo %s bar";

my $string2 = Load Dump $string;

is $string2, $string,
    "Don't be using newSVpvf for strings, cuz it does a sprintf action";
