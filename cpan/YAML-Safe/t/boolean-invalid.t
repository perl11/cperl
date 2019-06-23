use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests;

my @disable = (['int 0', 0], ['string 0', '0'], ['empty string', ''],
               ['undef', undef], ['string false', 'false']);
my @invalid = (['int 1', 1], ['string 1', '1'], ['string foo', 'foo']);
my $tests = (@disable + @invalid);
plan tests => $tests;

for (@invalid) {
    my ($label, $test) = @$_;
    my $obj;
    eval { $obj = YAML::Safe->new->boolean($test) };
    cmp_ok($@, '=~', qr{Invalid YAML::Safe}, "Invalid YAML::Safe->boolean value $label");
}

for (@disable) {
    my ($label, $test) = @$_;
    my $obj;
    eval { $obj = YAML::Safe->new->boolean($test) };

    my $data = $obj ? $obj->Load("true") : undef;
    if ($@) {
        diag "ERROR: $@";
        ok(0, "$label disables YAML::Safe::Boolean");
    }
    else {
        my $ref = ref $data;
        cmp_ok($ref, 'eq', '', "$label disables YAML::Safe::Boolean $ref");
    }
}
