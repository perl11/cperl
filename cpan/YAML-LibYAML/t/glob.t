use t::TestYAMLTests tests => 2;
no warnings 'once';

$main::G1 = "Hello";

is Dump(*G1), <<'...', "Dump a scalar glob";
--- !!perl/glob
NAME: G1
PACKAGE: main
SCALAR: Hello
...

eval '@main::G1 = (1..3)';

is Dump(*G1), <<'...', "Add an array to the glob";
--- !!perl/glob
ARRAY:
- 1
- 2
- 3
NAME: G1
PACKAGE: main
SCALAR: Hello
...

exit;

eval '@main::G1 = (1..3)';

my $g = *G1;

is Dump(\$g), <<'...', "Ref to glob";
--- !!perl/ref
=: !!perl/glob
...

my $array = [\$g, \$g, \*G1];
is Dump($array), <<'...', "Globs and aliases";
---
- &1 !!perl/glob
  ARRAY:
  - 1
  - 2
  - 3
  NAME: G1
  PACKAGE: main
  SCALAR: Hello
- *1
...
