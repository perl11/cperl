use Test::More;

use strict;
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "needs perl >= 5.8.9 or >= 5.10.1"
    if $] < 5.008009 or $] eq "5.010000";

use Devel::NYTProf::Run qw(profile_this);

run_test_group( {
    extra_test_count => 8,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        my $src_eval = "foo()";
        my $src_code = "sub foo { } foo(); eval '$src_eval'; ";
        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my @fi = $profile->all_fileinfos;
        is scalar @fi, 2, 'should have one fileinfo';
        #printf "# %s\n", $_->filename for @fi;

        my $fi_s = $profile->fileinfo_of('-');
        isa_ok $fi_s, 'Devel::NYTProf::FileInfo', 'should have fileinfo for "-"';

        if ($env->{savesrc}) {
            my $lines_s = $fi_s->srclines_array;
            isa_ok $lines_s, 'ARRAY', 'srclines_array should return an array ref';
            is $lines_s->[0], $src_code, 'source code line should match';
        }
        else { pass() for 1..2 }

        #  Strawberry perl portable has eval ID '(eval 5)[-:1]',
        #  others have '(eval 0)[-:1]'.
        #  Assume that, if we get two fileinfos then second is what we wanted.
        #  Possibly should check if we match /\(eval [15]\)\[-:1\]/.
        my @file_infos = $profile->all_fileinfos;
        is (scalar @file_infos, 2, 'Got two file infos');
        my $target_eval_name = $file_infos[-1]->filename;

        my $fi_e = $profile->fileinfo_of($target_eval_name);
        isa_ok $fi_e, 'Devel::NYTProf::FileInfo',
            'should have fileinfo for "$target_eval_name"'
            or do {
                diag "Have fileinfo for: '$_'"
                    for sort map { $_->filename } $profile->all_fileinfos;
            };

        if ($env->{savesrc} && $fi_e) {
            my $lines_e = $fi_e->srclines_array;
            # perl adds a newline to eval strings
            is $lines_e->[0], "$src_eval\n", 'source code line should match';
            #warn "@$lines_e";
        }
        else {
            pass() for 1;
        }
    },
});
