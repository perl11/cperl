use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 15;

my $obj = YAML::Safe->new;

my $yaml = <<"EOM";
local_array: !Foo::Bar [a]
local_hash: !Foo::Bar { a: 1 }
local_scalar: !Foo::Bar a
hash: !!perl/hash:Foo::Bar { a: 1 }
array: !!perl/array:Foo::Bar [a]
regex: !!perl/regexp:Foo::Bar OK
scalar: !!perl/scalar:Foo::Bar scalar
EOM

my $objects = Load $yaml;
isa_ok($objects->{local_array}, "Foo::Bar", "local tag (array)");
isa_ok($objects->{local_hash}, "Foo::Bar", "local tag (hash)");
isa_ok($objects->{local_scalar}, "Foo::Bar", "local tag (scalar)");
isa_ok($objects->{array}, "Foo::Bar", "perl tag (array)");
isa_ok($objects->{hash}, "Foo::Bar", "perl tag (hash)");
isa_ok($objects->{regex}, "Foo::Bar", "perl tag (regexp)");
isa_ok($objects->{scalar}, "Foo::Bar", "perl tag (scalar)");

# was LoadBlessed = 0
my $hash = $obj->disableblessed->Load($yaml);
cmp_ok(ref $hash->{local_array}, 'eq', 'ARRAY', "Array not blessed (local)");
cmp_ok(ref $hash->{local_hash}, 'eq', 'HASH', "Hash not blessed (local)");
cmp_ok(ref $hash->{local_scalar}, 'eq', '', "Scalar not blessed (local)");
cmp_ok(ref $hash->{array}, 'eq', 'ARRAY', "Array not blessed");
cmp_ok(ref $hash->{hash}, 'eq', 'HASH', "Hash not blessed");
cmp_ok(ref $hash->{regex}, 'eq', 'Regexp', "Regexp not blessed");
cmp_ok(ref $hash->{scalar}, 'eq', '', "Scalar not blessed");

my $expected = {
    local_array => ["a"],
    local_hash => { a => 1 },
    local_scalar => "a",
    hash => { a => 1 },
    array => ["a"],
    regex => qr{OK},
    scalar => "scalar",
};
if ($hash->{regex} =~ m/:OK/) {
    $hash->{regex} = $expected->{regex};
}
is_deeply($hash, $expected);

# !!perl/glob and !!perl/ref aren't blessed at the moment.
# !!perl/code isn't loaded at the moment
