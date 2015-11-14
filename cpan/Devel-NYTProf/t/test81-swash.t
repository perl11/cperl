# Tests implicit calling of utf8::SWASHNEW from unicode regex.
#
# Actually a stress test of all sorts of nasty cases including opcodes calling
# back to perl and stack switching (PUSHSTACKi(PERLSI_MAGIC)).

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
        # check if data truncated due to assertion failure
        ok $profile->{attribute}{complete};
    },
});

# crashes with perl 5.11.1+
__DATA__
$_ = "N\x{100}";
chop $_;
s/
    (?: [A-Z] | [\d] )+
    (?= [\s] )
//x;
