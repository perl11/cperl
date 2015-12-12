#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=46
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

# crashes non-threaded pp_ctl.c:248 cLOGOP->op_first being 0
my $script = <<'EOF';
my $pattern = 'x'; 'foo' =~ /$pattern/o;
print "ok";
EOF

use B::CC;
ctestok(1, "CC", "ccode46i", $script,
	(($Config{useithreads} or $B::CC::VERSION >= 1.08)
	 ? "" : "TODO "). "issue46 m//o cLOGOP->op_first fixed with r610, threaded only");
