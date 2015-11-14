use strict;
use Test::More;
use List::Util qw(sum);
use lib qw(t/lib);
use NYTProfTest;

# don't normalize eval seqn because doing so would create duplicates
$ENV{NYTPROF_TEST_SKIP_EVAL_NORM} = 1;

use Devel::NYTProf::Constants qw(NYTP_SCi_elements);

run_test_group( {
    extra_test_count => 2 + (3 * 3),
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        # check sub callers from sub perspective
        my $subs = $profile->subname_subinfo_map;
        my @anon = grep { $_->is_anon } values %$subs;
        is @anon, 3, 'should be 3 anon subs (after merging)';
        is sum(map { $_->calls } @anon), 5, 'call count';

        my %fids;
        for my $si (@anon) {
            printf "------ sub %s\n", $si->subname;
            my $called_by_subnames = $si->called_by_subnames;
            ok $called_by_subnames;
            is_deeply [ keys %$called_by_subnames ],
                      [ 'main::RUNTIME' ],
                'should be called from only from main::RUNTIME';

            my $callers = $si->caller_fid_line_places;
            ok $callers;
            print "caller_fid_line_places: ".Data::Dumper::Dumper($callers);

            ++$fids{$_} for keys %$callers;
        }

        return;

        # check sub callers from file perspective
        for my $fid (keys %fids) {
            print "------ fid $fid\n";
            ok my $fi = $profile->fileinfo_of($fid);
            ok my $sub_call_lines = $fi->sub_call_lines;
            warn "sub_call_lines: ".Data::Dumper::Dumper($sub_call_lines);
            is keys %$sub_call_lines, 1;
            is keys %{$sub_call_lines->{1}}, 1;
            ok my $sc = $sub_call_lines->{1}{'main::foo'};
            is @$sc, NYTP_SCi_elements(), 'si should have all elements';
        }
    },
} );

exit 0;

__END__
my $code = 'sub { print "sub called\n" }';
eval($code)->();
eval($code)->(); eval($code)->();
eval q{
    eval($code)->(); eval($code)->();
};
