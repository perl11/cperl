#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=272
# "" HV key SvLEN=0 => sharedhash
# if SvIsCOW(sv) && SvLEN(sv) == 0 => sharedhek (key == "")
#   >= 5.10: SvSHARED_HASH keysv: PV offset to hek_hash

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;
use B::C ();
#use Config;

my $todo = ($B::C::VERSION ge '1.43_02' or $] < 5.009) ? "" : "TODO ";
#$todo = "TODO 5.10 " if $] =~ /^5\.010/;
#my $rtodo = $todo;
#if ($Config{ccflags} =~ /DEBUGGING/ and $] > 5.009) {
#  $rtodo = "TODO hek assertion ";
#}

ctestok(1,'C,-O3','ccode272i',<<'EOF',$todo.'empty run-time HV key #272');
$d{""} = qq{ok\n}; print $d{""}
EOF

ctestok(2,'C,-O3','ccode272i',<<'EOF',$todo.'empty compile-time HV key #272');
BEGIN{ $d{""} = qq{ok\n};} print $d{""}
EOF
