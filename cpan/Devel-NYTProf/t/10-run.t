use Test::More;

use strict;
use lib qw(t/lib);
use NYTProfTest;

# test run_test_group() with extra_test_code and profile_this()

use Devel::NYTProf::Run qw(profile_this);

# tiny amount of source code to exercise RT#50851
my @src = (
    "\$a = 1;\n",
    "\$b = 2;\n",
);

run_test_group( {
    extra_options => {
    },
    extra_test_count => 17,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => join('', @src),
            out_file => $env->{file},
            skip_sitecustomize => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my ($fi, @others) = $profile->all_fileinfos;
        is @others, 0, 'should be one fileinfo';

        is $fi->fid, 1;
        is $fi->filename, '-'; # profile_this() does "| perl -"
        is $fi->abs_filename, '-';
        is $fi->filename_without_inc, '-';

        is $fi->eval_fi, undef;
        is $fi->eval_fid,  ''; # PL_sv_no
        is $fi->eval_line, ''; # PL_sv_no
        is_deeply $fi->evals_by_line, {};

        is $fi->profile, $profile;
        ok not $fi->is_eval;
        ok not $fi->is_fake;
        ok not $fi->is_pmc;

        my $line_time_data = $fi->line_time_data;
        is ref $line_time_data, 'ARRAY';

        is $fi->sum_of_stmts_count, 2;

        # should be tiny (will be 0 on systems without a highres clock)
        cmp_ok $fi->sum_of_stmts_time, '<', 10;
    },
});
