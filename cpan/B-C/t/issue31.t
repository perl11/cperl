#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=31
# B:CC Regex in pkg var fails on 5.6 and 5.10
use Test::More tests => 2;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

my $pm = "Ccode31i.pm";
open FH, ">", $pm;
print FH <<'EOF';
package Ccode31i;
my $regex = qr/\w+/;
sub test {
   #print "$regex\n";
   print ("word" =~ m/^$regex$/o ? "ok\n" : "not ok\n");
}
1
EOF
close FH;

my $script = <<'EOF';
use lib '.';
use Ccode31i;
&Ccode31i::test();
EOF

use B::C ();
# $]<5.007: same as test 33
my $todo = ($] >= 5.010 and $] < 5.011) ? "TODO #31 5.10 " : "";
ctestok(1, "CC", "ccode31i", $script,
      ($B::C::VERSION lt '1.42_55')
      ? "TODO B:CC Regex in pkg var fails with 5.6 and >5.10 since 1.35 until 1.42_54"
      : $todo."B:CC Regex in pkg var");
ctestok(2, "C,-O3", "ccode31i", $script, $todo."B:C Regex in pkg var");

END { unlink $pm; }
