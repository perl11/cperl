use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;

eval "use autodie; 1"
    or plan skip_all => "autodie required";

print "autodie $autodie::VERSION $INC{'autodie.pm'}\n";

plan skip_all => "Currently a developer-only test" unless -d '../.git';

warn "This test script needs more work\n";

use Devel::NYTProf::Run qw(profile_this);

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => {
        start => 'begin', compress => 1, stmts => 0, slowops => 0,
    },
    extra_test_count => 2,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
            htmlopen => $ENV{NYTPROF_TEST_HTMLOPEN},
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs = $profile->subname_subinfo_map;

        ok 1;
    },
});

__DATA__
#!perl
package P;
use autodie;
eval { rmdir "nonsuch file name" };
