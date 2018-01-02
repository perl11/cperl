use lib '.';
use t::TestYAMLTests tests => 2;

my $yaml = Dump "foo\0bar";

is $yaml, <<'...', 'Strings with nulls can Dump';
--- "foo\0bar"
...

my $str = Load $yaml;
is $str, "foo\0bar", 'Strings with nulls can Load';

