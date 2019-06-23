# YAML 1.2 only
use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 4;
no warnings 'once';

$main::G1 = "Hello";
my $obj = YAML::Safe->new;

is Dump(*G1), <<'...', "Dump a scalar glob";
--- !!perl/glob
NAME: G1
PACKAGE: main
SCALAR: Hello
...

eval '@main::G1 = (1..3)';

is $obj->noindentmap->Dump(*G1), <<'...', "Add an array to the glob";
--- !!perl/glob
ARRAY:
- 1
- 2
- 3
NAME: G1
PACKAGE: main
SCALAR: Hello
...

#exit;

eval '@main::G1 = (1..3)';

my $g = *G1;

is $obj->Dump(\$g), <<'...', "Ref to glob";
--- &1 !!perl/ref
=: *1
...

my $array = [\$g, \$g, \*G1];
is $obj->Dump($array), <<'...', "Globs and aliases";
---
- &1 !!perl/ref
  =: *1
- *1
- &2 !!perl/ref
  =: *2
...
