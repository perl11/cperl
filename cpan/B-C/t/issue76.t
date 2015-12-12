#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=76
# Fix lexical warnings: warn->sv
use Test::More tests => 3;
use strict;
use Config;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
my $script = <<'EOF';
use warnings;
{ 
  no warnings q(void); # issue76 lexwarn
  length "ok";
  print "ok"
}
EOF

ok(1, "bytecode LEXWARN skip");

use B::C;
ctestok(2, "C", "ccode76i", $script,
	(($B::C::VERSION lt '1.36' or ($] =~ /^5\.010/ and $Config{useithreads})) ? "TODO " : "").
        "C LEXWARN implemented with B-C-1.36"
       );

use B::CC;
ctestok(3, "CC", "ccode76i", $script, "CC LEXWARN");
