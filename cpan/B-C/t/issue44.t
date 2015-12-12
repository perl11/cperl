#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=44
# pp_aelemfast not implemented for local vars OPf_SPECIAL
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

# fails to compile non-threaded, wrong result threaded
my $script = <<'EOF';
my @a = (1,2);
print $a[0], "\n";
EOF

use B::CC;
ctest(1, '^1$', "CC", "ccode44i", $script, # fixed with B::CC 1.08 r601 (B-C-1.28)
      ($B::CC::VERSION < 1.08 ? "TODO " : "")
      . "pp_aelemfast not implemented for local vars OPf_SPECIAL, fixed with B-C-1.28");
