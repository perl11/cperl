use Test::More;
require XSLoader;

# Disable "once" warnings
BEGIN {
    my $ok = eval { require warnings; 1 };
    if ( $ok ) {
        warnings->unimport( qw( once redefine ) );
    }
    else {
        $^W = 0;
    }
}

my @tests = (
    [ 'start=no:file=nytprof.out'  => { start => 'no', file => 'nytprof.out' } ],
    [ 'start=no:file=nytprof\:out' => { start => 'no', file => 'nytprof:out' } ],
    [ 'start=no:file=nytprof\=out' => { start => 'no', file => 'nytprof=out' } ],
);

plan( tests => 1 * @tests );
for my $test ( @tests ) {
    my ( $nytprof, $expected ) = @$test;

    # Abrogate the XSLoader used to load the XS function DB::set_option.
    local *XSLoader::load = sub {};

    # Hook the function used to set options to capture it's parsing.
    my %got;
    local *DB::set_option = sub {
        my ( $k, $v ) = @_;
        $got{$k} = $v;
    };
    
    # (pretend to) Unload the class.
    delete $INC{'Devel/NYTProf/Core.pm'};

    # Test the class's parsing.
    local $ENV{NYTPROF} = $nytprof;
    require Devel::NYTProf::Core;
    is_deeply( \%got, $expected, "Parsed \$ENV{NYTPROF}='$nytprof' ok" );
}

