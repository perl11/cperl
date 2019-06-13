use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "needs perl >= 5.21.1 (see t/test62-tie-a)"
    if $] < 5.021001;

run_test_group;
