use lib '.';
use t::TestYAMLTests tests => 6;

my $a = Load(<<'...');
---
- !foo [1]
- !Bar::Bar {fa: la}
- !only lonely
...

is ref($a), 'ARRAY', 'Load worked';
is ref($a->[0]), 'foo', 'Private tag works for array';
is ref($a->[1]), 'Bar::Bar', 'Private tag works for hash';
is ref($a->[2]), 'only', 'Private tag works for scalar';
is ${$a->[2]}, 'lonely', 'Scalar is correct';
like $a->[2], qr/^only=SCALAR/, 'Ref is SCALAR';
