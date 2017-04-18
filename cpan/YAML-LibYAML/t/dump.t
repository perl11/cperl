use lib '.';
use t::TestYAMLTests tests => 4;

spec_file('t/data/basic.yml');
filters {
    perl => ['eval', 'test_dump'],
};

run_is perl => 'libyaml_emit';

sub test_dump {
    Dump(@_) || "Dump failed";
}
