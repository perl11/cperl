use Test::More; # tests => 1;

use YAML::XS;

plan skip_all => 'Failing test. Not yet implemented';

my $p = {my_key => "When foo or foobar is used, everyone understands that these are just examples, and they dont really exist."};
my $e = <<'...';
---
my_key: When foo or foobar is used, everyone understands that these are just examples, and they dont really exist.
...
is Dump($p), $e, "Long plain scalars don't wrap";
