use Test::More;

use strict;

use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "doesn't work with fork() emulation" if (($^O eq "MSWin32") || ($^O eq 'VMS'));

plan tests => 5;

my $out = 'nytprof-forkdepth.out';

is run_forkdepth(  0 ),   1;
is run_forkdepth(  1 ),   2;
is run_forkdepth(  2 ),   3;
is run_forkdepth( -1 ),   3;
is run_forkdepth( undef), 3;

exit 0;

sub run_forkdepth {
    my ($forkdepth) = @_;
    printf "run_forkdepth %s\n", defined($forkdepth) ? $forkdepth : "undef";

    unlink $_ for glob("$out.*");

    $ENV{NYTPROF} = "file=$out:addpid=1:trace=0";
    $ENV{NYTPROF} .= ":forkdepth=$forkdepth" if defined $forkdepth;

    my $forkdepth_cmd = q{-d:NYTProf -e "sub f { fork or return; wait; exit \$? } f; f; exit 0"};
    run_perl_command($forkdepth_cmd);

    my @files = glob("$out.*");
    unlink $_ for @files;

    return scalar @files;
}

