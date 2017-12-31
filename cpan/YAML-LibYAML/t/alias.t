use lib '.';
use t::TestYAMLTests tests => 10;

my ($a, $b) = Load(<<'...');
---
- &one [ a, b, c]
- foo: *one
--- &1
foo: &2 [*2, *1]
...

is "$a->[0]", "$a->[1]{'foo'}",
   'Loading an alias works';
is "$b->{'foo'}", "$b->{'foo'}[0]",
   'Another alias load test';
is "$b", "$b->{'foo'}[1]",
   'Another alias load test';

my $value = { xxx => 'yyy' };
my $array = [$value, 'hello', $value];
is Dump($array), <<'...', 'Duplicate node has anchor/alias';
---
- &1
  xxx: yyy
- hello
- *1
...

my $list = [];
push @$list, $list;
push @$list, $array;
is Dump($list), <<'...', 'Dump of multiple and circular aliases';
--- &1
- *1
- - &2
    xxx: yyy
  - hello
  - *2
...

my $hash = {};
$hash->{a1} = $hash->{a2} = [];
$hash->{b1} = $hash->{b2} = [];
$hash->{c1} = $hash->{c2} = [];
$hash->{d1} = $hash->{d2} = [];
# XXX Failed on 5.21.4. 'e1' got quoted because it looks like a number?
# $hash->{e1} = $hash->{e2} = [];
$hash->{f1} = $hash->{f2} = [];
is Dump($hash), <<'...', 'Alias Order is Correct';
---
a1: &1 []
a2: *1
b1: &2 []
b2: *2
c1: &3 []
c2: *3
d1: &4 []
d2: *4
f1: &5 []
f2: *5
...

my $yaml = <<'...';
---
foo: &text |
  sub foo {
      print "hello\n";
  }
bar: *text
...

$hash = Load($yaml);
is $hash->{bar}, $hash->{foo}, 'Scalar anchor/aliases Load';
like $hash->{bar}, qr/"hello/, 'Aliased scalar has correct value';

$yaml = <<'...';
---
foo: &rx !!perl/regexp (?-xsim:lala)
bar: *rx
...

$hash = Load($yaml);
is $hash->{bar}, $hash->{foo}, 'Regexp anchor/aliases Load';
like "falala", $hash->{bar}, 'Aliased regexp works';
