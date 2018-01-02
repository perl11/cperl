use lib '.';
use t::TestYAMLTests tests => 6;

my ($a, $b, $c, $d) = (42, "42", 42, "42");
my $e = ">$c<";
my $f = $d + 3;

{
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

}

{
local $YAML::XS::QuoteNumericStrings = 1;

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

}

{
local $YAML::XS::QuoteNumericStrings = 0;

is Dump($a, $b, $c, $d), <<'...', "Dumping Integers and Strings";
--- 42
--- 42
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
--- 02134
...

}

