use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests;

my $yaml = <<'...';
---
boolfalse: false
booltrue: true
stringfalse: 'false'
stringtrue: 'true'
...

plan skip_all => "perl $] too old for boolean()"
  if ($] < 5.008009);
skip_all_unless_require "JSON::MaybeXS";

my $class = JSON::MaybeXS::_choose_json_module();
my $ver;
{ no strict 'refs'; $ver = ${$class."::VERSION"}; }
my %minver = ( 'Cpanel::JSON::XS' => 3.0236,
               'JSON::XS' => 3.0,
               'JSON'     => 3.0,
               'JSON::PP' => 3.0);
plan skip_all => "$class $ver too old"
  if !exists $minver{$class} or $ver < $minver{$class};
print STDERR "# Found $class $ver\n";

my $obj = eval { YAML::Safe->new->boolean("JSON::PP") };
plan skip_all => "JSON::PP also not installed"
  if ($@ and $@ =~ m{JSON/PP});

plan tests => 7;

my $hash = $obj->Load($yaml);
isa_ok($hash->{booltrue}, 'JSON::PP::Boolean');
isa_ok($hash->{boolfalse}, 'JSON::PP::Boolean');

cmp_ok($hash->{booltrue}, '==', 1, "boolean true is true");
cmp_ok($hash->{boolfalse}, '==', 0, "boolean false is false");

ok(! ref $hash->{stringtrue}, "string 'true' stays string");
ok(! ref $hash->{stringfalse}, "string 'false' stays string");

my $yaml2 = $obj->Dump($hash);
cmp_ok($yaml2, 'eq', $yaml, "Roundtrip booleans ok");

