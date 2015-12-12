#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=49
# B::CC Can't "last" outside a loop block
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

# The op "leaveloop" is not handled by B::CC because it is dead code.
# Hence @cxstack only is increased by "enterloop", but never
# decreased.  Hence the second op "last" in the test program reads
# loop data from the wrong context and jumps to the end of the inner
# loop by mistake.  This issue is similar to issue 47 but not fixable
# that easy.  We either have to rethink handling of dead code or have
# to pop @cxstack not only for "leavesub" but somehow for op "last" as
# well.  But that is difficult, because there can be multiple "last"
# ops.
my $script = <<'EOF';
while (1) {
    while (1) {
        last;
    }
    last;
}
EOF

use B::CC;
ccompileok(1, "CC", "ccode49i", $script, # fixed with B::CC 1.08 r625
	   ($B::CC::VERSION < 1.08 ? "TODO " : "")
	   . "CC Can't \"last\" outside a loop block, fixed with B-C-1.28");
