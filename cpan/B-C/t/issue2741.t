#! /usr/bin/env perl
# GH #274, custom op Devel_Peek_Dump

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More ($] >= 5.019003 ? (tests => 2) : (skip_all => 'custom op Dump since 5.19.3'));
use B::C ();
my $todo = ($B::C::VERSION ge '1.52_11') ? "" : "TODO ";
$todo = "" if $] < 5.019003;

ctest(1, "ok", 'C','ccode2741i',<<'EOF',$todo.'custom op');
use Devel::Peek; my %hash = ( a => 1 ); Dump(%hash); print "ok\n"
EOF

ctest(2, "ok", 'C,-O1','ccode2741i',<<'EOF',$todo.'custom op -O1');
use Devel::Peek; my %hash = ( a => 1 ); Dump(%hash); print "ok\n"
EOF

# no tests yet for other custom ops, with the address via Perl_custom_op_xop( $$op )
