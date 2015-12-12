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
eval "use Coro;";
if ($@) {
  plan skip_all => "Coro required for testing issue #293";
} else {
  plan tests => 1;
}

use B::C ();
my $cmt = '#293 boot Coro::State';
my $todo = $B::C::VERSION ge '1.46_04' ? "" : "TODO ";
$todo = "TODO 5.10thr " if $] =~ /^5\.010001/ and $Config{useithreads};
my $script = 'use Coro; print q(ok)';

ctestok(1, 'C,-O3', 'ccode293i', $script, $todo.'C '.$cmt);
