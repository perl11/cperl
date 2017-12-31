use lib '.';
use t::TestYAMLTests tests => 6;

y2n("Explicit tag on array");
{
    local $YAML::XS::DisableBlessed = 1;
    my $name = "Explicit tag on array";
    (my ($self), @_) = find_my_self($name);
    my $test = $self->get_block_by_name(@_);
    my $yaml = $test->yaml;
    my $perl = Load($yaml);
    is_deeply ($perl, [2,4], 'Load: unblessed array for disabled bless')
      || do {
          require Data::Dumper;
          print Data::Dumper::Dumper($perl);
      };
}
y2n("Very explicit tag on array");

y2n("Explicit tag on hash");
{
    local $YAML::XS::DisableBlessed = 1;
    my $name = "Explicit tag on hash";
    (my ($self), @_) = find_my_self($name);
    my $test = $self->get_block_by_name(@_);
    my $yaml = $test->yaml;
    my $perl = Load($yaml);
    is_deeply ($perl, {2=>4}, 'Load: unblessed hash for disabled bless')
      || do {
          require Data::Dumper;
          print Data::Dumper::Dumper($perl);
      };
}
y2n("Very explicit tag on hash");

__DATA__
=== Explicit tag on array
+++ yaml
--- !!perl/array
- 2
- 4
+++ perl
[2, 4];

=== Very explicit tag on array
+++ yaml
--- !<tag:yaml.org,2002:perl/array>
- 2
- 4
+++ perl
[2, 4];

=== Explicit tag on hash
+++ yaml
--- !!perl/hash
2: 4
+++ perl
{2, 4};

=== Very explicit tag on hash
+++ yaml
--- !<tag:yaml.org,2002:perl/hash>
2: 4
+++ perl
{2, 4};

