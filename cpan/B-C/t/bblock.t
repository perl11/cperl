#!/usr/bin/env perl -w
# blead cannot run -T

BEGIN {
    if ($ENV{PERL_CORE}) {
	push @INC, ('.', '../../lib');
    }
    require Config;
    if ($ENV{PERL_CORE} and ($Config::Config{'extensions'} !~ /\bB\b/) ){
        print "1..0 # Skip -- Perl configured without B module\n";
        exit 0;
    }
}

use Test::More tests => 1;

use_ok('B::Bblock', qw(find_leaders));

# For now only test loading Bblock works.
# We could add tests to split op groups by Basic Blocks for CC.
