use lib '.';
use t::TestYAMLTests tests => 25;

filters {
    error => ['lines', 'chomp'],
};

run {
    my $test = shift;
    eval {
        Load($test->yaml);
    };
    for my $error ($test->error) {
        if ($error =~ s/^!//) {
            my $re = qr/$error/;
            unlike $@, $re, $test->name . " (!~ /$error/)";
        }
        else {
            my $re = qr/$error/;
            like $@, $re, $test->name . " (=~ /$error/)";
        }
    }
};

__DATA__
=== Bad hash indentation
+++ yaml
foo: 2
 bar: 4
+++ error
mapping values are not allowed in this context
document: 1
line: 2
column: 5

=== Unquoted * as hash key
+++ yaml
*: foo
+++ error
did not find expected alphabetic or numeric character
document: 1
column: 2
while scanning an alias

=== Unquoted * as hash value
+++ yaml
---
foo bar: *
+++ error
did not find expected alphabetic or numeric character
document: 1
line: 2
column: 11
while scanning an alias

=== Unquoted * as scalar
+++ yaml
--- xxx
--- * * *
+++ error
did not find expected alphabetic or numeric character
document: 2
line: 2
column: 6
while scanning an alias

=== Bad tag for array
+++ yaml
--- !!foo []
+++ error
bad tag found for array: 'tag:yaml.org,2002:foo'
document: 1

=== Bad tag for hash
+++ yaml
--- !!!foo {}
+++ error
bad tag found for hash: 'tag:yaml.org,2002:!foo'
document: 1
!line:
!column:

=== https://bitbucket.org/xi/libyaml/issue/10/wrapped-strings-cause-assert-failure
+++ yaml
  x: "
" y: z
+++ error
did not find expected key
