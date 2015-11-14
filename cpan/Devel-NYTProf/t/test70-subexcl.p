# This test isn't very useful until we can test subroutine timings
# perhaps by adding an option to nytprofcsv to include them
# and adjusting test.pl to test for them (including the ~N fudge factor).
# Meanwhile the test is useful for sanity checking the subroutine timing
# code using a command like
# make && NYTPROF_TEST=trace=3 perl -Mblib test.pl -leave=1 -use_db_sub=0 t/test70-subexcl.*

my $T = $ENV{NYTPROF_TEST_PAUSE_TIME} || 0.2;

sub A {     # inclusive ~= $T, exclusive ~= $T
    select undef, undef, undef, $T;
}

sub B {     # inclusive ~= $T*2, exclusive ~= $T
    A();
    select undef, undef, undef, $T;
}

sub C {     # inclusive ~= $T*2, exclusive ~= 0.0
    B();
}

sub D {     # inclusive ~= $T*4, exclusive ~= 0.0
    C();
    C();    # cumulative_subr_secs non-zero on sub entry
}

D();
