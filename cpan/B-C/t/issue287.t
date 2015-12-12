#! /usr/bin/env perl
# https://github.com/rurban/perl-compiler/issues/287
# handle Inf,Nan stored in variables
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 3;
use Config;
use B::C ();
my $when = "1.52_06";
my $todo = $B::C::VERSION lt $when ? "TODO " : "";

ctestok(1,'C,-O3','ccode287i',<<'EOF',$todo.'C #287 inf/nan');
my $i = "Inf" + 0; print $i <= 0 ? "not " : "", "ok 1 #".int($i)."\n";
EOF

ctestok(2,'CC','ccode287i',<<'EOF',$todo.'CC #287 inf/nan');
my $i = "Inf" + 0; print qq/ok\n/ if $i > 0;
EOF

plctestok(3,'ccode287i',<<'EOF',($]>5.021?'TODO ':'').'BC #287 inf/nan');
my $i = "Inf" + 0; print qq/ok\n/ if $i > 0;
EOF
