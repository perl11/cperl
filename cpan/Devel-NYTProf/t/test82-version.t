# Tests interaction with UNIVERSAL::VERSION (RT#54600)

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
        leave => 0,
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
#!perl -w
{
  package X;

  sub warner {
    print "# Hello world\n"
  }

  sub DESTROY {
    goto \&warner;
  }
}

my $a = bless [], 'X';

undef $a;
