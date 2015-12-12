#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=200
# utf8 hash keys. still broken compile-time on 5.8
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
use Config;
if ( $] =~ /^5\.00800[45]/ ) {
  plan skip_all => "compile-time utf8 hek hack NYI for $]";
  exit;
}
plan tests => 6;

my $i=0;
sub test3 {
  my $name = shift;
  my $script = shift;
  my $cmt = join('',@_);
  my $todo = "";
  $todo = 'TODO' if $name eq 'ccode200i_c'; # or ($] >= 5.018);
  my $todoc = $] < 5.010 ? "TODO 5.8 " : "";
  $todoc = "" if $name eq 'ccode200i_r';
  plctestok($i*3+1, $name, $script, $todo." BC $cmt");
  ctestok($i*3+2, "C", $name, $script, $todoc."C $cmt");
  ctestok($i*3+3, "CC", $name, $script, $todoc."CC $cmt");
  $i++;
}

test3('ccode200i_r', '%u=("\x{123}"=>"fo"); print "ok" if $u{"\x{123}"} eq "fo"', 'run-time utf8 hek');
test3('ccode200i_c', 'BEGIN{%u=("\x{123}"=>"fo")} print "ok" if $u{"\x{123}"} eq "fo"', 'compile-time utf8 hek');
