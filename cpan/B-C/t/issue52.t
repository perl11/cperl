#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=52
# B:CC errors on variable with numeric value used in second expression of 'and'
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

my $script = <<'EOF';
my $x;
my $y = 1;
$x and $y == 2;
print $y == 1 ? "ok\n" : "fail\n";
EOF

use B::CC;
ctestok(1, "CC", "ccode52i", $script,
      $B::CC::VERSION < 1.08
      ? "TODO B:CC numeric value used in second expression of 'and' - issue52 fixed with r692"
      : undef);
