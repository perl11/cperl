#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=36
# B::CC fails on some loops
# The problem seems to be non deterministic.
# Some runs of B::CC succeed, some fail and others give a warning.
use B::CC;
use Test::More tests => $B::CC::VERSION < 1.08 ? 5 : 1;
use strict;
BEGIN {
    unshift @INC, 't';
    require "test.pl";
}

# panic: leaveloop, no cxstack at /usr/local/lib/perl/5.10.1/B/CC.pm line 1977
my $script = <<'EOF';
sub f { shift == 2 }
sub test {
    while (1) {
        last if f(2);
    }
    while (1) {
        last if f(2);
    }
}
EOF

use B::CC;
# The problem seems to be non deterministic.
# Some runs of B::CC succeed, some fail and others give a warning.
if ($B::CC::VERSION < 1.08) {
  ccompileok($_, "CC", "ccode36i", $script,
	     "TODO B::CC issue 36 fixed with B-C-1.28 r556 (B::CC 1.08) by Heinz Knutzen")
    for 1..5;
} else {
  ccompileok($_, "CC", "ccode36i", $script,
	     "CC fails sometimes on some loops (fixed with B-C-1.28 r556)");
}

