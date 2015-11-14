use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "needs perl >= 5.8.9 or >= 5.10.1"
    if $] < 5.008009 or $] eq "5.010000";

plan skip_all => "needs perl < 5.21.1 (see t/test62-tie-b.t)" # XXX
    if $] >= 5.021001;

run_test_group;
