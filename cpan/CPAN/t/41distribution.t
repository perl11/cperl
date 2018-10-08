# Test CPAN::Distribution objects
#
# Very, very preliminary API testing, but we have to start somewhere

BEGIN {
    unshift @INC, './lib', './t';

    require local_utils;
    local_utils::cleanup_dot_cpan();
    local_utils::prepare_dot_cpan();
    local_utils::read_myconfig();
    require CPAN::MyConfig;
    require CPAN;

    CPAN::HandleConfig->load;
    $CPAN::Config->{load_module_verbosity} = q[none];
    my $yaml_module = CPAN::_yaml_module();
    my $exit_message;
    if ($CPAN::META->has_inst($yaml_module)) {
        #print STDERR "# yaml_module[$yaml_module] loadable\n";
    } else {
        $exit_message = "No yaml module installed";
    }
    unless ($exit_message) {
        if ($YAML::VERSION && $YAML::VERSION < 0.60) {
            $exit_message = "YAML v$YAML::VERSION too old for this test";
        }
    }
    if ($exit_message) {
        $|=1;
        print "1..0 # SKIP $exit_message\n";
        eval "require POSIX; 1" and POSIX::_exit(0);
        warn "Error while trying to load POSIX: $@";
        exit(0);
    }
}

use strict;

use Cwd qw(cwd);
use File::Copy qw(cp);
use File::Path qw(rmtree mkpath);
use File::Temp qw(tempdir);
use File::Spec::Functions qw/catdir catfile/;
use File::Basename qw/basename/;

use lib $Config::Config{usecperl} ? ("t") : ("inc", "t");
use local_utils;
use version;

# prepare local CPAN
local_utils::cleanup_dot_cpan();
local_utils::prepare_dot_cpan();
# and be sure to clean it up
END{ local_utils::cleanup_dot_cpan(); }

use Test::More;

*note = Test::More->can("note") || sub { warn shift };

my (@tarball_suffixes, @meta_yml_tests, $isa_perl_tests); # defined later in BEGIN blocks

plan tests => 1 + @tarball_suffixes + 3 * @meta_yml_tests + $isa_perl_tests;

require_ok( "CPAN" );

#--------------------------------------------------------------------------#
# base_id() testing
#--------------------------------------------------------------------------#

BEGIN {
    @tarball_suffixes = qw(
        .tgz
        .tbz
        .tar.gz
        .tar.bz2
        .tar.Z
        .zip
    );
}

{
        my $dist_base = "Bogus-Module-1.234";
        for my $s ( @tarball_suffixes ) {
                my $dist = CPAN::Distribution->new(
                        ID => "D/DA/DAGOLDEN/$dist_base$s"
                );
                is( $dist->base_id, $dist_base, "base_id() strips $s" );
        }
}

#--------------------------------------------------------------------------#
# read_meta() testing
#--------------------------------------------------------------------------#

BEGIN {
    @meta_yml_tests = (
        {
            label => 'no META.yml',
            copies => [],
            requires => undef,
        },
        {
            label => 'dynamic META.yml',
            copies => [ 'META-dynamic.yml', 'META.yml' ],
            requires => undef,
        },
        {
            label => 'non-dynamic META.yml',
            copies => [ 'META-static.yml', 'META.yml' ],
            requires => {
                'Time::Local' => 0,
                'perl' => 5.006
            },
        },
        {
            label => 'dynamic META.yml plus MYMETA.yml',
            copies => [ 
                'META-dynamic.yml', 'META.yml',
                'META-dynamic.yml', 'MYMETA.yml', # NOT MYMETA as source
            ],
            requires => {
                'Time::Local' => 0,
                'perl' => 5.006
            },
        },
    );
}

{
    for my $case ( @meta_yml_tests ) {
        my $yaml;
        my $label = $case->{label};
        my $tempdir = tempdir( "t/41distributionXXXX", CLEANUP => 1 );

        # dummy distribution
        my $dist = CPAN::Distribution->new(
            ID => "D/DA/DAGOLDEN/Bogus-Module-1.234"
        );
        $dist->{build_dir} = $tempdir;    

        # copy files
        if ( $case->{copies} ) {
            while (@{$case->{copies}}) {
                my ($from, $to) = splice(@{$case->{copies}},0,2);
                cp catfile( qw/t data/, $from) => catfile($tempdir, $to); 
            }
        }

        # check read_yaml
        $yaml = $dist->read_yaml;
        if ( defined $case->{requires} ) {
            my $type = ref $yaml;
            is( $type, 'HASH', "$label\: read_yaml returns HASH ref" );
            is( ref $dist->read_yaml, $type, "$label\: repeat read_yaml is same" );
            if ( $type ) {
                my $mismatch = 0;
                for my $k ( keys %{ $case->{requires} } ) {
                    $mismatch++ unless $yaml->{requires}{$k} == $case->{requires}{$k};
                }
                ok( $mismatch == 0, "$label\: found expected requirements" );
            }
            else {
                fail( "$label\: no requirements available\n" );
            }
        }
        else {
            is( $yaml, undef, "$label\: read_yaml returns undef");
            is( $dist->read_yaml, undef, "$label\: repeat read_yaml returns undef");
            pass( "$label\: no requirement checks apply" );
        }
    }
}

my @CPR;
BEGIN {
    @CPR = eval { require CPAN::Perl::Releases } ? CPAN::Perl::Releases::perl_versions() : ();
    $isa_perl_tests = @CPR ? 2 + @CPR : 1;
}

{
    {
        no strict;
        package Silent;
        for my $m (qw(myprint mydie mywarn mysleep)){
            *$m = sub {
                return;
            }
        }
    }
    $CPAN::Frontend = $CPAN::Frontend = "Silent";
    if (@CPR) {
        my @fail;
        for (@CPR){
            if (/-(RC|TRIAL)\d*$/){
                pass("ignoring $_ due $1");
                next;
            }
            my $basename = basename CPAN::Perl::Releases::perl_tarballs($_)->{"tar.gz"};
            my $d = $CPAN::META->instance('CPAN::Distribution' => "X/XX/XXX/$basename");
            if (my $v = $d->isa_perl()){
                $v =~ s/_.*//;
                cmp_ok(version->new($v)->numify, '>', 5, "$v > 5");
            } else {
                push @fail, $_;
            }
        }
        ok !@fail, "no perl distros unrecognized; fail=(@fail)";
    } else {
        note("No CPAN::Perl::Releases installed");
    }
    my @fail;
    for my $distro (qw(INGY/perl5-0.21.tar.gz)) {
        my $d = $CPAN::META->instance('CPAN::Distribution' => $distro);
        push @fail, $distro if $d->isa_perl();
    }
    ok !@fail, "no legit distros taken for perls; fail=(@fail)";
}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
# vi: ts=4:sts=4:sw=4:et:
