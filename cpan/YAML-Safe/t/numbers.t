use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 6;

my ($a, $b, $c, $d) = (42, "42", 42, "42");
my $e = ">$c<"; # make IV $c a dualvar PVIV
my $f = $d + 3; # make PV $d a dualvar PVIV

is Dump($a, $b, $c, $d), <<'...', "Dumping Integers and Strings";
--- 42
--- '42'
--- 42
--- 42
...

my ($num, $float, $str) = Load(<<'...');
--- 42
--- 0.333
--- '02134'
...

is Dump($num, $float, $str), <<'...', "Round tripping integers and strings";
--- 42
--- 0.333
--- '02134'
...

{
my $obj = YAML::Safe->new->quotenum;

is $obj->Dump($a, $b, $c, $d), <<'...', "Dumping Integers and Strings with quotenum";
--- 42
--- '42'
--- 42
--- 42
...

my ($num, $float, $str) = $obj->Load(<<'...');
--- 42
--- 0.333
--- '02134'
...

is $obj->Dump($num, $float, $str), <<'...', "Round tripping integers and strings with quotenum";
--- 42
--- 0.333
--- '02134'
...

}

{
my $obj = YAML::Safe->new->quotenum(0);

is $obj->Dump($a, $b, $c, $d), <<'...', "Dumping Integers and Strings w/o quotenum";
--- 42
--- 42
--- 42
--- 42
...

my ($num, $float, $str) = $obj->Load(<<'...');
--- 42
--- 0.333
--- '02134'
...

is $obj->Dump($num, $float, $str), <<'...', "Round tripping integers and strings w/o quotenum";
--- 42
--- 0.333
--- 02134
...

}
