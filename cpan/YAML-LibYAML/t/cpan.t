use lib '.';
use t::TestYAMLTests tests => 2;

# test CPAN::Meta conformity in NonStrict mode
no warnings 'once';
$YAML::XS::NonStrict = 1;

spec_file('t/data/cpan.yml');
filters {
    yaml => ['parse_to_byte'],
    perl => ['eval'],
};

run_is_deeply yaml => 'perl';

sub parse_to_byte {
    Load($_);
}
