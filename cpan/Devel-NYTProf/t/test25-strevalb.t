# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;
use Config qw(%Config);

use Devel::NYTProf::Run qw(profile_this);
use Devel::NYTProf::Constants qw(NYTP_SCi_elements);

my $pre589 = ($] < 5.008009 or $] eq "5.010000");

my $src_code = join("", <DATA>);

# perl assert failure https://rt.perl.org/Ticket/Display.html?id=122771
my $perl_rt70211 = ($] >= 5.020 && $Config{ccflags} =~ /-DDEBUGGING/);

run_test_group( {
    extra_options => {
        start => 'begin',
        optimize => ($perl_rt70211) ? 0 : 1,
    },
    extra_test_count => 8,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $fi = $profile->fileinfo_of(1);
        my $subdefs_at_line = $profile->subs_defined_in_file_by_line($fi->filename);
        # 0: version::(bool, 1: main::BEGIN@1, 2: main::BEGIN@2, 3: main::add, 4: main::inc
        #warn join ", ", map { "$_: ".$subdefs_at_line->{$_}[0]->subname } sort keys %$subdefs_at_line;
        isa_ok my $add_si = $subdefs_at_line->{4}[0], 'Devel::NYTProf::SubInfo';
        is $add_si->subname, 'main::add';

        my $callers = $add_si->caller_fid_line_places;
        print Dumper($callers);

        is keys %$callers, 1, 'called from 1 fid';
        my $caller_fid  = (keys %$callers)[0];
        my $sc_lineinfo = $callers->{$caller_fid};
        is keys %$sc_lineinfo, 1, 'called from 1 line in that fid';
        my $caller_line = (keys %$sc_lineinfo)[0];

        my $sc = (values %$sc_lineinfo)[0];
        is ref $sc, 'ARRAY';
        is @$sc, NYTP_SCi_elements(), "call from $caller_fid:$caller_line to main::add should have all elements in $sc";

        my $called_by_subnames = $add_si->called_by_subnames;
        is keys %$called_by_subnames, 1, 'called_by_subnames should report one caller for main::add';
    },
});

__DATA__
use strict;
use Benchmark;
my $i;
sub add { ++$i }
timethis( 10, \&add );
die "panic $i" unless $i == 10;
