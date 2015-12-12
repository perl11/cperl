#! /usr/bin/env perl
# GH #306, destruction of init_av and end_av

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 4;
use Config;
use B::C ();
my $todo = ($B::C::VERSION ge '1.52_12') ? "" : "TODO ";
$todo = "TODO 5.22-thr " if $] > 5.021 and $Config{useithreads};
my $script = <<'EOF';
INIT { $SIG{__WARN__} = sub { die } } print "ok\n";
EOF

ctestok(1, 'C',    'ccode306i', $script, $todo.'C     init_av refcount');
ctestok(2, 'C,-O3','ccode306i', $script, $todo.'C,-O3 init_av refcount');
$script =~ s/INIT /END /;
ctestok(3, 'C',    'ccode306i', $script, $todo.'C     end_av refcount');
ctestok(4, 'C,-O3','ccode306i', $script, $todo.'C,-O3 end_av refcount');
