use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

my $cperl = $^V =~ /c$/;
plan skip_all => "Not yet passing on cperl" if $cperl and ! -d '.git';

run_test_group({
    extra_test_count => 3,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        is_deeply(sub_calls($profile), {
            'main::sub1' => 1,
            'DB::disable_profile' => 1,
            'main::CORE:unlink' => 1,
        });

        my $file_b = "nytprof-test51-b.out";
        my $file_c = "nytprof-test51-c.out";

        my $pb = Devel::NYTProf::Data->new( { filename => $file_b, quiet => 0 } );
        is_deeply(sub_calls($pb), {
            'main::sub1' => 1,
            'main::sub3' => 1,
            'DB::disable_profile' => 1,
            'main::CORE:unlink' => 1,
        }, "$file_b sub calls");

        my $pc = Devel::NYTProf::Data->new( { filename => $file_c, quiet => 0 } );
        is_deeply(sub_calls($pc), {
            'main::sub7' => 1,
            'DB::finish_profile' => 1,
        }, "$file_c sub calls");
    },
});

sub sub_calls {
    my ($profile) = @_;
    my %sub_calls;
    for my $si (values %{ $profile->subname_subinfo_map }) {
        my $calls = $si->calls
            or next;
        $sub_calls{ $si->subname } = $calls;
    }
    print "sub_calls: { @{[ %sub_calls ]} }\n";
    return \%sub_calls;
}
