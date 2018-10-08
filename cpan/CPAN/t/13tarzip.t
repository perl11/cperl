my $count;
use strict;
use Cwd;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
sub _f ($) {
    File::Spec->rel2abs(File::Spec->catfile(split /\//, shift));
}
unshift @INC, "t";
eval { require CPAN::MyConfig; }; # may fail
require CPAN;
require CPAN::Kwalify;
require CPAN::HandleConfig;
require CPAN::Tarzip;
{
    BEGIN{$count+=4}
    my $tgz = _f("t/CPAN/authors/id/A/AN/ANDK/CPAN-Test-Dummy-Perl5-Build-1.03.tar.gz");
    my $CT = CPAN::Tarzip->new($tgz);
    ok($CT, "Tarzip object for tgz '$tgz' constructed");
    my $tmpdir = tempdir("t/13tarzipXXXX", CLEANUP => 1);
    ok($tmpdir, "tmpdir '$tmpdir' created");
    my $cwd = Cwd::cwd;
    ok($cwd, "cwd '$cwd' determined");
    chdir $tmpdir or die "Could not chdir to '$tmpdir': $!";
    ok($CT->untar, "untar/ungzip finished");
    chdir $cwd;
}
BEGIN{plan tests => $count}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
