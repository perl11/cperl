use FindBin '$Bin';
use lib $Bin;
use TestYAML tests => 1;

use YAML::Safe;

sub libyaml {
   YAML::Safe::Dump( $_[0] );
}

my @x = (256, 'xxx', libyaml({foo => 'bar'}));

isnt "@x", '256 xxx 256 xxx 256',
    "YAML::Safe doesn't mess up the call stack";
