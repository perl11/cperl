# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;
use lib '/home/travis/perl5'; # travis workaround https://travis-ci.org/timbunce/devel-nytprof/jobs/35285944
use Test::Differences;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;

use Devel::NYTProf::Run qw(profile_this);

my $pre589 = ($] < 5.008009 or $] eq "5.010000");

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => { start => 'begin' },
    extra_test_count => 17,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs1 = $profile->subname_subinfo_map;

        my $begin = ($pre589) ? 'main::BEGIN' : 'main::BEGIN@4';
        ok $subs1->{$begin};
        ok $subs1->{'main::RUNTIME'};
        ok $subs1->{'main::foo'};

        my @fi = $profile->all_fileinfos;
        is @fi, 1, 'should be 1 fileinfo';
        my $fid = $fi[0]->fid;

        my @a; # ($file, $fid, $first, $last); 
        @a = $profile->file_line_range_of_sub($begin);
        is "$a[1] $a[2] $a[3]", "$fid 4 7", "details for $begin should match";
        @a = $profile->file_line_range_of_sub('main::RUNTIME');
        is "$a[1] $a[2] $a[3]", "$fid 1 1", 'details for main::RUNTIME should match';
        @a = $profile->file_line_range_of_sub('main::foo');
        is "$a[1] $a[2] $a[3]", "$fid 2 2", 'details for main::foo should match';

        my $subs2 = $profile->subs_defined_in_file($fid);

        eq_or_diff [ sort keys %$subs2 ], [ sort keys %$subs1 ],
            'keys from subname_subinfo_map and subs_defined_in_file should match';

        my @begins = grep { $_->subname =~ /\bBEGIN\b/ } values %$subs2;
        if ($pre589) { # we only see one sub and we don't see it called
            is @begins, 1, 'number of BEGIN subs';
            is grep({ $_->calls == 1 } @begins), 0, 'BEGIN has no calls';
        }
        else {
            is @begins, 3, 'number of BEGIN subs';
            is grep({ $_->calls == 1 } @begins), scalar @begins,
                'all BEGINs should be called just once';
        }

        my $sub;
        ok $sub = $subs2->{'main::RUNTIME'};
        is $sub->calls, 0, 'main::RUNTIME should be called 0 times';
        ok $sub = $subs2->{'main::foo'};
        is $sub->calls, 2, 'main::foo should be called 2 times';

        ok my $called_by_subnames = $sub->called_by_subnames;
        is keys %$called_by_subnames, 2, 'should be called from 2 subs';

    },
});

__DATA__
#!perl
sub foo { 42 }
BEGIN { 'b' } BEGIN { 'c' } # two on same line
BEGIN { # BEGIN@3
    foo(2);
    *CORE::GLOBAL::sleep = \&foo;
}
sleep 1;

