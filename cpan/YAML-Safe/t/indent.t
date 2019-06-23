use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 2;

my $obj = YAML::Safe->new->indent(4);

is $obj->Dump([{a => 1, b => 2, c => 3}]), <<'...',
---
-   a: 1
    b: 2
    c: 3
...
'Dumped with indent 4';

is $obj->indent(8)->Dump([{a => 1, b => 2, c => 3}]), <<'...',
---
-       a: 1
        b: 2
        c: 3
...
'Dumped with indent 8';
