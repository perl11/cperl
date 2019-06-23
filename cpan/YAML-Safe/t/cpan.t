use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 2;

# test CPAN::Meta conformity in nonstrict mode
no warnings 'once';
my $o = YAML::Safe->new->nonstrict;

spec_file('t/data/cpan.yml');
filters {
    yaml => ['parse_to_byte'],
    perl => ['eval'],
};

run_is_deeply yaml => 'perl';

sub parse_to_byte {
    $o->Load($_);
}
