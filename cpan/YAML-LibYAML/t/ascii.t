use lib '.';
use t::TestYAMLTests tests => 7;

is utf8::is_utf8(Load("--- Foo\n")), !!0, 'ASCII string does not have UTF8 flag on';

my $yaml1 = <<'...';
---
foo: foo
bar: bar
baz: baz
...

{
    my $hash = Load($yaml1);
    is utf8::is_utf8($hash->{foo}), !!0, 'ASCII string string does not have UTF8 flag on';
    is utf8::is_utf8($hash->{bar}), !!0, 'ASCII string string does not have UTF8 flag on';
    is utf8::is_utf8($hash->{baz}), !!0, 'ASCII string string does not have UTF8 flag on';
}


my $yaml2 = <<'...';
---
- foo
- bar
- baz
...

{
    my $array = Load($yaml2);
    is utf8::is_utf8($array->[0]), !!0, 'ASCII string string does not have UTF8 flag on';
    is utf8::is_utf8($array->[1]), !!0, 'ASCII string string does not have UTF8 flag on';
    is utf8::is_utf8($array->[2]), !!0, 'ASCII string string does not have UTF8 flag on';
}

