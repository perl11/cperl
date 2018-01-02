package t::TestYAMLTests;
use lib 'inc';
use Test::Base -Base;
@t::TestYAMLTests::EXPORT = qw(Load Dump LoadFile DumpFile
                               n2y y2n nyny get_block_by_name);

sub load_config() {
    my $config_file = shift;
    my $config = {};
    return $config unless -f $config_file;
    open CONFIG, $config_file or die $!;
    my $yaml = do {local $/; <CONFIG>};
    if ($yaml =~ /^yaml_module:\s+([\w\:]+)/m) {
        $config->{yaml_module} = $1;
    }
    if ($yaml =~ /^use_blib:\s+([01])/m) {
        $config->{use_blib} = $1;
    }
    $config->{use_blib} ||= 0;
    return $config;
}

my $yaml_module;
BEGIN {
    my $config = load_config('t/yaml_tests.yaml');
    if ($config->{use_blib}) {
      if ($ENV{PERL_CORE}) {
        @INC = ('../../lib', 'inc', '.');
      } else {
        eval "use blib; 1" or die $@;
      }
    }
    $yaml_module = $ENV{PERL_YAML_TESTS_MODULE} || $config->{yaml_module}
      or die "Can't determine which YAML module to use for this test.";
    eval "require $yaml_module; 1" or die $@;
    $Y::T = $yaml_module;
}

sub get_block_by_name() {
    (my ($self), @_) = find_my_self(@_);
    $self->{blocks_by_name} ||= do {
        my $hash = {};
        for my $block ($self->blocks) {
            $hash->{$block->name} = $block;
        }
        $hash;
    };
    my $name = shift;
    my $object = $self->{blocks_by_name}{$name}
      or die "Can't find test named '$name'\n";
    return $object;
}

sub nyny() {
    (my ($self), @_) = find_my_self(@_);

    my $test = $self->get_block_by_name(@_);
    my $perl = eval $test->perl;
    my $result = Dump(Load(Dump($perl)));
    for my $section (qw'yaml3 yaml yaml2') {
        my $yaml = $test->$section or next;
        if ($result eq $yaml) {
            is $result, $yaml, "NYNY: " . $test->name;
            return;
        }
    }
    my $yaml = $test->yaml;
    is $result, $yaml, "NYNY: " . $test->name;
}

sub n2y() {
    (my ($self), @_) = find_my_self(@_);

    my $test = $self->get_block_by_name(@_);
    my $perl = eval $test->perl;
    my $result = Dump($perl);
    for my $section (qw'yaml3 yaml yaml2') {
        my $yaml = $test->$section or next;
        if ($result eq $yaml) {
            is $result, $yaml, "Dump: " . $test->name;
            return;
        }
    }
    my $yaml = $test->yaml;
    is $result, $yaml, "Dump: " . $test->name;
}

sub y2n() {
    (my ($self), @_) = find_my_self(@_);

    my $test = $self->get_block_by_name(@_);
    my $perl = eval $test->perl;
    my $yaml = $test->yaml;
    is_deeply Load($yaml), $perl, "Load: " . $test->name;
}

sub Load() {
    no strict 'refs';
    &{$yaml_module . "::Load"}(@_);
}
sub Dump() {
    no strict 'refs';
    &{$yaml_module . "::Dump"}(@_);
}
sub LoadFile() {
    no strict 'refs';
    &{$yaml_module . "::LoadFile"}(@_);
}
sub DumpFile() {
    no strict 'refs';
    &{$yaml_module . "::DumpFile"}(@_);
}

no_diff;
delimiters ('===', '+++');

package t::TestYAMLTests::Filter;
use Test::Base::Filter -Base;

sub load_yaml {
    t::TestYAMLTests::Load(@_);
}

sub dump_yaml {
    t::TestYAMLTests::Dump(@_);
}

sub loadfile_yaml {
    t::TestYAMLTests::LoadFile(@_);
}

sub dumpfile_yaml {
    t::TestYAMLTests::DumpFile(@_);
}
