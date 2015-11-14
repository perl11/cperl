use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

# hack to disable sawampersand test, just to simplify the testing across versions
$ENV{DISABLE_NYTPROF_SAWAMPERSAND} = 1;

run_test_group;
