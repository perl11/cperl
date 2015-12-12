#! /usr/bin/env perl
# GH #220, COP->hints_hash
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More ($] >= 5.010 ? (tests => 1) : (skip_all => '%^H requires v5.10'));
my $script = <<'EOF';
BEGIN { $^H{dooot} = 1 }
sub hint_fetch {
    my $key = shift;
    my @results = caller(0);
    $results[10]->{$key};
}
print qq{ok\n} if hint_fetch("dooot");
EOF

use B::C ();
my $todo = ($B::C::VERSION ge '1.52_22') ? "" : "TODO ";

ctestok(1, 'C', 'ccode200i', $script,
      $todo.'#200 hints hash saved');
