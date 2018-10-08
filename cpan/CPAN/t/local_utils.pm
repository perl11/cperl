package local_utils;

use Config;
use Cwd;
use File::Copy qw(cp);
use File::Path qw(rmtree mkpath);
use File::Spec ();

sub _f ($) {File::Spec->catfile(split /\//, shift);}
sub _d ($) {File::Spec->catdir(split /\//, shift);}

sub prepare_dot_cpan {
    rmtree _d"t/dot-cpan-$$/sources";
    rmtree _d"t/dot-cpan-$$/build";
    mkpath _d"t/dot-cpan-$$/build";
    rmtree _d"t/dot-cpan-$$/prefs";
    mkpath _d"t/dot-cpan-$$/prefs";
    unlink _f"t/dot-cpan-$$/Metadata";
    unlink _f"t/dot-cpan-$$/.lock";
    mkpath _d"t/dot-cpan-$$/sources/authors/id/A/AN/ANDK";
    mkpath _d"t/dot-cpan-$$/Bundle";
    # cp is not-overwriting on OS/2
    unlink _f"t/CPAN/MyConfig_$$.pm", _f"t/dot-cpan-$$/sources/MIRRORED.BY";
    write_myconfig();
    cp _f"t/CPAN/TestMirroredBy", _f"t/dot-cpan-$$/sources/MIRRORED.BY"
        or die "Could not cp t/CPAN/TestMirroredBy over t/dot-cpan-$$/sources/MIRRORED.BY: $!";
}

sub write_myconfig {
    open my $fh, _f"t/CPAN/TestConfig.pm" or die "Could not open 't/CPAN/TestConfig.pm': $!";
    open my $fh2, ">", _f"t/CPAN/MyConfig_$$.pm"
        or die "Could not open > t/CPAN/MyConfig_$$.pm: $!";
    print $fh2 "package CPAN::MyConfig_$$ ;\n";
    while (<$fh>) {
        s/dot-cpan/dot-cpan-$$/g;
        if (/^__END__/) {
            printf $fh2 q{$INC{"CPAN/MyConfig.pm"} = $INC{"CPAN/MyConfig_%s.pm"} = '%s';%s},
                $$, File::Spec->rel2abs(_f"t/CPAN/MyConfig_$$.pm"), "\n";
        }
        print $fh2 $_;
    }
    close $fh2 or die "Could not close t/CPAN/MyConfig_$$.pm: $!";
}

sub cleanup_dot_cpan {
    unlink _f"t/CPAN/MyConfig_$$.pm";
    unlink _f"t/CPAN/MyConfig_$$.pm~";
    unlink _f"t/dot-cpan-$$/sources/authors/id/A/AN/ANDK/CHECKSUMS";
    unlink _f"t/dot-cpan-$$/sources/MIRRORED.BY";
    unlink _f"t/dot-cpan-$$/prefs/FTPstats.yml";
    unlink _f"t/dot-cpan-$$/prefs/TestDistroPrefsFile.yml";
    unlink _f"t/dot-cpan-$$/prefs/ANDK.CPAN-Test-Dummy-Perl5-Make-Expect.yml";
    rmtree _d"t/dot-cpan-$$";
}

sub read_myconfig () {
    local *FH;
    open *FH, _f"t/CPAN/MyConfig_$$.pm" or die "Could not read t/CPAN/MyConfig_$$.pm: $!";
    my $eval = do { local($/); <FH>; };
    eval $eval;
    die $@ if $@;
}

# shamelessly stolen from Test::Builder
sub mydiag {
    my(@msgs) = @_;
    my $msg = join '', map { defined($_) ? $_ : 'undef' } @msgs;
    # Escape each line with a #.
    $msg =~ s/^/# /gm;
    # Stick a newline on the end if it needs it.
    $msg .= "\n" unless $msg =~ /\n\Z/;
    print $msg;
}

sub mreq ($) {
    my $m = shift;
    eval "require $m; 1";
}

sub splitchunk ($) {
    my $ch = shift;
    my @s = split /(^\#[A-Za-z]:)/m, $ch;
    shift @s; # leading empty string
    for (my $i = 0; $i < @s; $i+=2) {
        $s[$i] =~ s/\#//;
        $s[$i] =~ s/://;
    }
    @s;
}

sub test_name {
    my($prog,$comment) = @_;
    ($comment||"") . ($prog ? " (testing command '$prog')" : "[empty RET]")
}

sub run_shell_cmd_lit ($$) {
    my $cwd = shift;
    my $dup_pid = shift;
    my $t = File::Spec->catfile($cwd,"t");
    my @system = (
                  $^X,
                  "-I$t",                 # get this test's own MyConfig
                  "-Mblib",
                  "-MCPAN::MyConfig_$$",
                  "-Mlocal_utils",
                  "-MCPAN",
                  ($INC{"Devel/Cover.pm"} ? "-MDevel::Cover" : ()),
                  # (@ARGV) ? "-d" : (), # force subtask into debug, maybe useful
                  "-e",
                  # "\$CPAN::Suppress_readline=1;shell('$prompt\n')",
                  $dup_pid ? ("local_utils::dup_pid_inc($dup_pid);", "-e") : (),
                  "\@CPAN::Defaultsites = (); shell",
                 );
}

sub dup_pid_inc {
    my($pid) = @_;
    $INC{qq{CPAN/MyConfig.pm}} = $INC{qq{CPAN/MyConfig_$pid.pm}};
}

1;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
