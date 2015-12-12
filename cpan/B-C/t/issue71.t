#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=71
# Encode::decode fails in multiple ways. 1 with B::REGEXP refs unattached to PMOPs
use Test::More tests => 3;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Config ();
my $DEBUGGING = ($Config::Config{ccflags} =~ m/-DDEBUGGING/);
my $ITHREADS  = $Config::Config{useithreads};

# Simplification of Encode::Alias to test SvANY(REGEXP)=SvANY(CALLREGCOMP)
# e.g. Encode::Alias define_alias( qr/^(.*)$/ => '"\L$1"' ) creates REGEXP refs without PMOP's.
my $script = <<'EOF';
package my;
our @a;
sub f { 
  my($alias,$name)=@_;
  unshift(@a, $alias => $name);
  my $find = "ok"; 
  my $val = $a[1];
  if ( ref($alias) eq 'Regexp' && $find =~ $alias ) {
    eval $val;
  }
  $find
}
package main;
*f=*my::f;
print "ok" if f(qr/^(.*)$/ => '"\L$1"');
EOF

use B::C;
ctestok(1, "C", "ccode71i", $script,
	($B::C::VERSION lt '1.35' ? "TODO " : ""). "SvANY(REGEXP)=SvANY(CALLREGCOMP)"
       );

$script = <<'EOF';
use Encode;
my $x = 'abc';
print "ok" if 'abc' eq Encode::decode('UTF-8', $x);
EOF

# These 2 tests failed until 1.35 because of stale QR Regexp (see test 1), 
# issue71 (const destruction) and issue76 (invalid cop_warnings).
# rx: (?^i:^(?:US-?)ascii$)"
# 5.8 failed until 1.45_07-3a25dfd at SvTEMP_off(lexwarn0) for lexwarn0=0 instead of Nullsv
use B::C;
ctestok(2, "C", "ccode71i", $script,
	($B::C::VERSION lt '1.35' or ($] > 5.010 and $] < 5.011))
        ? "TODO C reg_temp_copy from invalid r->offs"
        : "C alias reg_temp_copy failed: Unknown encoding 'UTF-8'");

SKIP: {
#skip "hangs", 1 if !$DEBUGGING;
#skip "asserts", 1 if $DEBUGGING and $] < 5.011;
#use B::CC;
ctestok(3, "CC", "ccode71i", $script,
      (($B::C::VERSION lt '1.42_57')
       or ($] > 5.010 and $] < 5.011)
       or ($ITHREADS and $] > 5.013)
      )
      ? "TODO CC Encode::decode croak: Assertion failed: (SvTYPE(TARG) == SVt_PVHV), function Perl_pp_padhv"
      : "CC");
}
