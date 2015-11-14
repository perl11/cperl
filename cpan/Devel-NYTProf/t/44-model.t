# Tests assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;

use Devel::NYTProf::Run qw(profile_this);

run_test_group( {
    extra_options => { start => 'begin' },
    extra_test_count => 2,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        my $src_code = q{
            use strict 0.01; 
        };
        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs = $profile->subname_subinfo_map;
        my ($filename, $fid, $first, $last) = $profile->file_line_range_of_sub("UNIVERSAL::VERSION");
        is "$first-$last", "0-0", 'UNIVERSAL::VERSION line range';

    },
});
