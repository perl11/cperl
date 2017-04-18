use lib '.';
use t::TestYAMLTests tests => 11;

run {
    my $block = shift;
    my @values = eval $block->perl;
    is Dump(@values), $block->yaml, "Dump - " . $block->name
        unless $block->SKIP_DUMP;
    is_deeply [Load($block->yaml)], \@values, "Load - " . $block->name;
};

my @warn;
$SIG{__WARN__} = sub { push(@warn, shift) };
my $z = YAML::XS::Load(<<EOY);
---
foo:
  - url: &1
      scheme: http
EOY
pop @{$z->{foo}};

is_deeply \@warn, [], "No free of unref warnings";


__DATA__

=== Simple scalar ref
+++ perl
\ 42;
+++ yaml
--- !!perl/ref
=: 42

=== Ref to scalar ref
+++ perl
\\ "foo bar";
+++ yaml
--- !!perl/ref
=: !!perl/ref
  =: foo bar

=== Scalar refs an aliases
+++ perl
my $x = \\ 3.1415;
[$x, $$x];
+++ yaml
---
- !!perl/ref
  =: &1 !!perl/ref
    =: 3.1415
- *1

=== Ref to undef
+++ perl
my $x = {foo => \undef};

+++ yaml
---
foo: !!perl/ref
  =: ~

=== Circular ref to scalar
+++ perl
my $x;
$x = \$x;
+++ yaml
--- &1 !!perl/ref
=: *1
