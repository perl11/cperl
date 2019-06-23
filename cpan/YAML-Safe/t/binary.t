use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 1;

my @data = (
    "~\0\200",
    "null\0\200",
    "true\0\200",
    "false\0\200",
);
my $yaml = <<'...';
---
- "~\0\x80"
- "null\0\x80"
- "true\0\x80"
- "false\0\x80"
...

is Dump(\@data), $yaml, 'Dumping zero bytes works';

# see https://github.com/ingydotnet/yaml-libyaml-pm/issues/91
