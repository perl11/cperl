use Test::More;

my $nytprof_out;
BEGIN {
    $nytprof_out = "t/nytprof-50-errno.out";
    $ENV{NYTPROF} = "start=init:file=$nytprof_out";
    unlink $nytprof_out;
}

use Devel::NYTProf::Test qw(example_xsub example_sub set_errno);

BEGIN {                 # https://rt.cpan.org/Ticket/Display.html?id=55049
    $! = 1;             # set errno via perl
    set_errno(2);       # set errno via C-code in NYTProf.xs
    return if $! == 2;  # all is well
    plan skip_all => "Can't control errno in this perl build (linked with different CRT than perl?)";
}

plan tests => 8;

use Devel::NYTProf;

# We set errno to some particular non-zero value to see if NYTProf changes it
# (on many unix-like systems 3 is ESRCH 'No such process')
my $dflterrno = 3;

# simple assignment and immediate check of $!
$! = $dflterrno;
is 0+$!, $dflterrno, '$! should not be altered by NYTProf';

my $size1 = -s $nytprof_out;
ok defined $size1, "$nytprof_out should at least exist"
    or die "Can't continue: $!";

SKIP: {
    skip 'On VMS buffer is not flushed', 1 if ($^O eq 'VMS'); 
    cmp_ok $size1, '>', 0, "$nytprof_out should not be empty";
}

$! = $dflterrno;
example_sub();
is 0+$!, $dflterrno, "\$! should not be altered by assigning fids to previously unprofiled modules ($!)";

$! = $dflterrno;
example_xsub();
is 0+$!, $dflterrno, "\$! should not be altered by assigning fids to previously unprofiled modules ($!)";

SKIP: {
    skip 'On VMS buffer does not flush', 1 if($^O eq 'VMS');

    $! = $dflterrno;
    while (-s $nytprof_out == $size1) {
        # execute lots of statements to force some i/o even if zipping
        busy();
    }
    is 0+$!, $dflterrno, '$! should not be altered by NYTProf i/o';
}

ok not eval { example_xsub(0, "die"); 1; };
like $@, qr/^example_xsub\(die\)/;

exit 0;

sub busy {
    # none of this should alter $!
    for (my $i = 1_000; $i > 0; --$i) {
        example_xsub();
        next if $i % 100;
        example_sub();
    }
}
