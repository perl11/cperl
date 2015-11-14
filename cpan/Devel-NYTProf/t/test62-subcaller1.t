use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "needs perl >= 5.8.9 or >= 5.10.1"
    if $] < 5.008009 or $] eq "5.010000";

run_test_group;
