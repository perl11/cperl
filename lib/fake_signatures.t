#!./perl -- -*- mode: cperl; cperl-indent-level: 4 -*-

BEGIN {
    chdir 't' if -d 't';
    @INC = ( '.', '../lib' );
    use Config;
    if (!$Config{'fake_signatures'}
        && ($Config{'ccflags'} !~ m!\bDPERL_FAKE_SIGNATURE\b!)) {
	print "1..0 # Skip -- Perl configured without fake_signatures\n";
	exit 0;
    }
}

#use strict;
require '../t/test.pl';
plan(4);

use B::Deparse;
$|=1;

sub with {
    my ($arg) = @_;
    print $arg;
}

sub without {
    my $arg = shift;
    print $arg;
}

my $deparse = B::Deparse->new();

sub test {
    #my $text = $deparse->coderef2text(shift);
    # TODO: check for OP_SIGNATURE
    print "# $text $_[1] $_[2]\n";
    ok(1);
}

test(\&with, 1, "fake");
test(\&without, 0, "no fake");

{
    no fake_signatures;
    sub nwith {
        my ($arg) = @_;
        print $arg;
    }

    sub nwithout {
        my $arg = shift;
        print $arg;
    }
}

test(\&nwith, 1, "disabled fake");
test(\&nwithout, 0, "disabled no fake");
