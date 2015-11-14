use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

$ENV{NYTPROF_TEST_SKIP_EVAL_NORM} = 1;

run_test_group;
