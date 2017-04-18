use lib '.';
use t::TestYAMLTests tests => 1;

my $yaml = <<'...';
---
foo: foo
bar: bar
baz: baz
...

my $exp = {
    foo => 'foo',
    bar => 'bar',
    baz => 'baz',
};

{
    $yaml =~ /(.+)/s;
    is_deeply Load($1), $exp, 'Loading magical scalar works';
}

