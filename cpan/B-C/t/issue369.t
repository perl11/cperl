#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=369
# Coro::State transfer run-time stack corruption
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
use Config;
eval "use Coro; use EV;";
if ($@) {
  plan skip_all => "Coro and EV are required for testing issue #369";
} else {
  plan tests => 1;
}

use B::C ();
my $cmt = '#369 Coro::State transfer run-time stack corruption';
my $todo = "TODO ";
#my $todo = $B::C::VERSION ge '1.52' ? "" : "TODO ";
#$todo = "TODO 5.10thr " if $] =~ /^5\.010001/ and $Config{useithreads};

ctestok(1, 'C,-O3', 'ccode369i', <<'EOF', $todo.'C '.$cmt);
use EV;
use Coro;
use Coro::Timer;
my @a;
push @a, async {
  while() {
    warn $c++;
    Coro::Timer::sleep 1;
  };
};
push @a, async {
  while() {
    warn $d++;
    Coro::Timer::sleep 0.5;
  };
};
schedule;
EOF
