use FindBin '$Bin';
use lib $Bin;
use TestYAML tests => 8;

use YAML::Safe qw(Dump Load);

my $data = { foo => undef };

foreach my $t_data ( $data, Load(Dump($data)) ) {
    ok( exists($t_data->{foo}), "foo exists" );
    is( $t_data->{foo}, undef, "value is undef" );
    ok( eval { my $x = \$t_data->{foo}; 1 }, "can reference foo without error" );
    is_deeply($t_data, $data, "is deeply");
}

