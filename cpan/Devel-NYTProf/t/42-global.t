# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;

use Devel::NYTProf::Run qw(profile_this);

my $pre589 = ($] < 5.008009 or $] eq "5.010000");
my $cperl = $^V =~ /c$/;
plan skip_all => "Not yet passing on cperl" if $cperl and ! -d '.git';

eval { require Test::Differences; };

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
            #keepoutfile => 1,
            #verbose => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs1 = $profile->subname_subinfo_map;

        my $BEGIN = ($pre589 || $cperl) ? 'main::BEGIN'
                                        : 'main::BEGIN@4';
        my $RUNTIME = 'main::RUNTIME';
        my $foo     = 'main::foo';
        ok $subs1->{$BEGIN};
        ok $subs1->{$RUNTIME};
        ok $subs1->{$foo};

        my @fi = $profile->all_fileinfos;
        is @fi, 1, 'should be 1 fileinfo';
        my $fid = $fi[0]->fid;

        my @a; # ($file, $fid, $first, $last);
        @a = $profile->file_line_range_of_sub($BEGIN);
        is "$a[1] $a[2] $a[3]", "$fid 4 7", "details for $BEGIN should match";
        @a = $profile->file_line_range_of_sub($RUNTIME);
        is "$a[1] $a[2] $a[3]", "$fid 1 1", "details for $RUNTIME should match";
        @a = $profile->file_line_range_of_sub($foo);
        is "$a[1] $a[2] $a[3]", "$fid 2 2", "details for $foo should match";

        my $subs2 = $profile->subs_defined_in_file($fid);

        if (defined &Test::Differences::eq_or_diff) {
          &Test::Differences::eq_or_diff([ sort keys %$subs2 ],
                                         [ sort keys %$subs1 ],
            'keys from subname_subinfo_map and subs_defined_in_file should match');
        }

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
        ok $sub = $subs2->{$RUNTIME};
        is $sub->calls, 0, "$RUNTIME should be called 0 times";
        ok $sub = $subs2->{$foo};
        is $sub->calls, 2, "$foo should be called 2 times";

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

