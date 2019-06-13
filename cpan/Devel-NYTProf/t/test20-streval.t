use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;
use Devel::NYTProf::Constants qw(NYTP_SCi_elements);

run_test_group( {
    extra_test_count => 8 + (3 * 6),
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        # check sub callers from sub perspective
        my $subs = $profile->subname_subinfo_map;
        my $si = $subs->{'main::foo'};
        ok $si;
        is $si->calls, 4;
        my $called_by_subnames = $si->called_by_subnames;
        ok $called_by_subnames;
        is_deeply [ keys %$called_by_subnames ],
                  [ 'main::RUNTIME' ],
            'should be called from only from main::RUNTIME';

        my $callers = $si->caller_fid_line_places;
        ok $callers;
        #warn Data::Dumper::Dumper($callers);
        # two calls from evals on same line get collapsed
        my @fids = keys %$callers;
        is @fids, 3, 'should be called from 3 files';
        is_deeply [ map { keys %$_ } values %$callers ], [ 1, 1, 1 ],
            'should all be called from line 1';
        my @sc = map { values %$_ } values %$callers;
        is_deeply [ map { scalar @$_ } @sc ], [ (NYTP_SCi_elements()) x 3],
            'all sub calls infos should have all elements';

        # check sub callers from file perspective
        for my $fid (@fids) {
            ok my $fi = $profile->fileinfo_of($fid);
            ok my $sub_call_lines = $fi->sub_call_lines;
            #warn Data::Dumper::Dumper($sub_call_lines);
            is keys %$sub_call_lines, 1;
            is keys %{$sub_call_lines->{1}}, 1;
            ok my $sc = $sub_call_lines->{1}{'main::foo'};
            is @$sc, NYTP_SCi_elements(), 'si should have all elements';
        }
    },
} );
