use lib '.';
use t::TestYAMLTests tests => 5;

my $array = [
    undef,
    'undef',
    33,
    '~',
    undef,
    undef,
    '~/file.txt',
];
undef $array->[2];

my $yaml = Dump($array);

is $yaml, <<'...', "Nulls dump as ~";
---
- ~
- undef
- ~
- '~'
- ~
- ~
- ~/file.txt
...

my $array2 = Load($yaml);

is_deeply $array2, $array,
    "YAML with undefs loads properly";

$yaml = "{foo, bar}\n";
my $perl = {foo => undef, bar => undef};

is_deeply Load($yaml), $perl,
    "Set notation has null values";

$yaml = <<'...';
---
foo:
bar:
-
- -
gorch: null
...
$perl = {foo => undef, bar => [undef, [undef]], gorch => undef};

is_deeply Load($yaml), $perl,
    "Empty values Load as undefs";

$yaml = <<'...';
---
- -
- -
...
$perl = [[undef], [undef]];

is_deeply Load($yaml), $perl,
    "Can Load 'dash art'";

