use lib '.';
use t::TestYAMLTests tests => ( 3 * ( 5 * 5 + 3 ) );

use Scalar::Util qw(weaken);

for ( 1 .. 3 ) {
    foreach my $case (
        sub { "foo" },
        sub { bless { foo => "bar" }, "Class" },
        sub { [ 1 .. 3 ] },
        sub { my $x = "foo"; \$x; },
        sub { my $y = 42; my $x = \$y; \$x },
        sub { my $h = {}; [ $h, $h ] },
        #sub { my $glob = gensym(); *$glob = { foo => "bar" }; \$glob },
        #sub { sub { "foo " . $_[0] } },
        #sub { sub () { 3 } },
    ) {
        my $obj = $case->();

        my $yaml = Dump($obj);

        ok( $yaml, "dumped" );

        my $loaded = Load($yaml);

        is( ref($loaded), ref($obj), "loaded $loaded from $obj" );

        is_deeply( $loaded, $obj, "eq deeply" );

        if ( ref $obj ) {
            weaken($obj);
            weaken($loaded);

            is( $obj, undef, "dumped object not leaked" );
            is( $loaded, undef, "loaded object not leaked" );
        }
    }
}
