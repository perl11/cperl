use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 4;

y2n("Explicit tag on array");
y2n("Very explicit tag on array");

y2n("Explicit tag on hash");
y2n("Very explicit tag on hash");

__DATA__
=== Explicit tag on array
+++ yaml
--- !!perl/array
- 2
- 4
+++ perl
[2, 4];

=== Very explicit tag on array
+++ yaml
--- !<tag:yaml.org,2002:perl/array>
- 2
- 4
+++ perl
[2, 4];

=== Explicit tag on hash
+++ yaml
--- !!perl/hash
2: 4
+++ perl
{2, 4};

=== Very explicit tag on hash
+++ yaml
--- !<tag:yaml.org,2002:perl/hash>
2: 4
+++ perl
{2, 4};

