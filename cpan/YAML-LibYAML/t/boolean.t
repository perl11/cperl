use lib '.';
use t::TestYAMLTests tests => 5;

my $yaml = <<'...';
---
a: true
b: 1
c: false
d: ''
...

my $hash = Load $yaml;

cmp_ok $hash->{a}, '==', $hash->{b},
    "true is loaded as a scalar whose numeric value is 1";
is "$hash->{a}", "$hash->{b}",
    "true is loaded as a scalar whose string value is '1'";
is "$hash->{c}", "$hash->{d}",
    "false is loaded as a scalar whose string value is ''";

my $yaml2 = Dump($hash);

is $yaml2, $yaml,
    "Booleans YNY roundtrip";

my $yaml3 = <<'...';
---
- true
- false
- 'true'
- 'false'
- 1
- 0
- ''
...

my $yaml4 = Dump Load $yaml3;

is $yaml4, $yaml3,
    "Everything related to boolean YNY roundtrips";
