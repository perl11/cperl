# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;

use Devel::NYTProf::Run qw(profile_this);

plan skip_all => "Currently a developer-only test" unless -d '../.git';

warn "This test script needs more work\n";

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => {
        start => 'begin', compress => 1, stmts => 1, slowops => 0,
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
sub a { 0 }
#line 101 "hash-line-first"
sub b { 1 }
#line 202 "hash-line-second"
sub c { 2 }
eval qq{#line 303 "hash-line-eval"
sub d { 3 }
1} or die;
a(); b(); c(); d();
print "# File: $_\n" for sort grep { m/_</ } keys %{'main::'};
print "# Sub:  $_ => $DB::sub{$_}\n" for sort keys %DB::sub;
