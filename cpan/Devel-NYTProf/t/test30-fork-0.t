use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "doesn't work with fork() emulation" if (($^O eq "MSWin32") || ($^O eq 'VMS'));

run_test_group;
