use lib '.';
use t::TestYAMLTests tests => 11;
no warnings 'once';
$YAML::XS::IndentlessMap = 1;

filters {
    perl => 'eval',
    yaml => 'load_yaml',
};
my $test = get_block_by_name("Blessed Hashes and Arrays");
my $hash = $test->perl;
my $hash2 = $test->yaml;

# is_deeply is broken and doesn't check blessings
is_deeply $hash2, $hash, "Load " . $test->name;

is ref($hash2->{foo}), 'Foo::Bar',
    "Object at 'foo' is blessed 'Foo::Bar'";
is ref($hash2->{bar}), 'Foo::Bar',
    "Object at 'bar' is blessed 'Foo::Bar'";
is ref($hash2->{one}), 'BigList',
    "Object at 'one' is blessed 'BigList'";
is ref($hash2->{two}), 'BigList',
    "Object at 'two' is blessed 'BigList'";

{
    local $YAML::XS::DisableBlessed = 1;
    my $hash3 = Load($test->yaml);
    is ref($hash3->{two}), '',
      "Object at 'two' is not blessed";
}

my $yaml = Dump($hash2);

is $yaml, $test->yaml_dump, "Dumping " . $test->name . " works";

######
$test = get_block_by_name("Blessed Scalar Ref");
my $array = $test->perl;
my $array2 = $test->yaml;

# is_deeply is broken and doesn't check blessings
is_deeply $array2, $array, "Load " . $test->name;

is ref($array2->[0]), 'Blessed',
    "Scalar ref is class name 'Blessed'";

like "$array2->[0]", qr/=SCALAR\(/,
    "Got a scalar ref";

$yaml = Dump($array2);

is $yaml, $test->yaml_dump, "Dumping " . $test->name . " works";

__DATA__
=== Blessed Hashes and Arrays
+++ yaml
foo: !!perl/hash:Foo::Bar {}
bar: !!perl/hash:Foo::Bar
  bass: bawl
one: !!perl/array:BigList []
two: !!perl/array:BigList
- lola
- alol
+++ perl
+{
    foo => (bless {}, "Foo::Bar"),
    bar => (bless {bass => 'bawl'}, "Foo::Bar"),
    one => (bless [], "BigList"),
    two => (bless [lola => 'alol'], "BigList"),
};
+++ yaml_dump
---
bar: !!perl/hash:Foo::Bar
  bass: bawl
foo: !!perl/hash:Foo::Bar {}
one: !!perl/array:BigList []
two: !!perl/array:BigList
- lola
- alol

=== Blessed Scalar Ref
+++ yaml
---
- !!perl/scalar:Blessed hey hey
+++ perl
my $x = 'hey hey';
[bless \$x, 'Blessed'];
+++ yaml_dump
---
- !!perl/scalar:Blessed hey hey
