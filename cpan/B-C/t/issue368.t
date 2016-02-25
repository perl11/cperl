#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=293
# Empty &Coro::State::_jit and READONLY no_modify double-init run-time errors
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
use Config;
eval "use EV;";
if ($@) {
  plan skip_all => "EV required for testing issue #368";
} else {
  plan tests => 1;
}

use B::C ();
my $cmt = '#368 boot EV';
my $todo = $B::C::VERSION ge '1.51' ? "" : "TODO ";
$todo = "TODO 5.10thr " if $] =~ /^5\.010001/ and $Config{useithreads};
$todo = "TODO cperl " if $Config{usecperl} or $] >= 5.022;
my $script = 'use EV; print q(ok)';

ctestok(1, 'C,-O3', 'ccode368i', $script, $todo.'C '.$cmt);

