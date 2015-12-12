#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=47
# B::CC gets lost of anonymous function using "while" and "return"
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

my $script = <<'EOF';
my $f = sub {
    while (1) {
        return (1);
    }
};
print $f->(), "\n";
EOF

use B::CC;
ctest(1, '^1$', "CC", "ccode47i", $script,
      ($B::CC::VERSION < 1.08 ? "TODO ":"")."CC anonsub in while fixed with r618");
