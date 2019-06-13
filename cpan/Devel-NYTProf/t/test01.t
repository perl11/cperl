use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

run_test_group({
    extra_test_count => 1,
    extra_test_code  => sub {
        my ($profile, $env) = @_;
        isa_ok($profile, 'Devel::NYTProf::Data');
    },
});
