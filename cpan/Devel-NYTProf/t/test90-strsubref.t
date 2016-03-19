# Tests dieing on Can't use string ... as a subroutine ref while "strict refs" in use
# that used to core dump (RT#86638)
# https://rt.cpan.org/Ticket/Display.html?id=86638

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;

use Devel::NYTProf::Run qw(profile_this);

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => {
        start => 'begin',
        compress => 1,
        calls => 0,
        savesrc => 0,
        stmts => 0,
        slowops => 0,
    },
    extra_test_count => 2,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';
        # check if data was truncated
        ok $profile->{attribute}{complete};
    },
});

__DATA__
#!perl
use strict;
# Can't use string ("") as a subroutine ref while "strict refs" in use at - line 4.
eval { $x::z->() };
die $@ if $@ !~ /^Can't use .* as a subroutine ref/;
