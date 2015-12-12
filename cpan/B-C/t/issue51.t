#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=51
# B::CC errors on nested if statement with test on multiple variables
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

my $script = <<'EOF';
my ($p1, $p2) = (80, 80);
if ($p1 <= 23 && 23 <= $p2) {
    print "telnet\n";
}
elsif ($p1 <= 80 && 80 <= $p2) {
    print "http\n";
}
else {
    print "fail\n"
}
EOF

use B::CC;
ctest(1, '^http$', "CC", "ccode51i", $script,
      ($B::CC::VERSION < 1.08 ? "TODO " : "")
      . "CC nested if on multiple variables - issue51. Fixed with B-C-1.28 r659");
