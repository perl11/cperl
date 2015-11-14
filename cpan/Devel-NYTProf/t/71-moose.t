use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;

eval "use Moose 2.0; 1"
    or plan skip_all => "Moose 2.0 required";

print "Moose $Moose::VERSION $INC{'Moose.pm'}\n";

plan skip_all => "Test is incomplete (has no results defined yet)";# unless -d '.svn';

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
use Moose;
has attrib_std  => ( is => 'rw',  default => 42 );
has attrib_lazy => ( is => 'rw', lazy => 1, default => sub { 43 } );
END {
    my $p = P->new;
    print $p->attrib_std."\n";
    print $p->attrib_lazy."\n";
}
