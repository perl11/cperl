#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=208
# missing DESTROY call at DESTRUCT time 
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;
my $script = <<'EOF';
sub MyKooh::DESTROY { print "${^GLOBAL_PHASE} MyKooh " }   my $k=bless {}, MyKooh;
sub OurKooh::DESTROY { print "${^GLOBAL_PHASE} OurKooh" } our $k=bless {}, OurKooh;
EOF
my $expected = ($] >= 5.014 ? 'RUN MyKooh DESTRUCT OurKooh' : ' MyKooh  OurKooh');

# fixed with 1.42_66, 5.16+5.18
# for older perls and -O3 fixed with 1.45_02
use B::C ();
my $todo = ($] > 5.015 and $B::C::VERSION gt '1.42_65') ? "" : "TODO ";
if ($] < 5.015) {
  $todo = ($B::C::VERSION gt '1.45_01') ? "" : "TODO ";
}
my $todo_o3 = ($] < 5.013 and $B::C::VERSION gt '1.45_01') ? "" : "TODO ";
$todo_o3 = "" if $B::C::VERSION gt '1.45_08';
#if ($B::C::VERSION gt '1.45_03') { #broken with 1c5062f53 which enabled -ffast-destruct on -O0
#  $todo = $todo_o3 = $] > 5.013 ? "TODO " : "";
#}

ctest(1, $expected,'C','ccode208i',$script,$todo.'#208 missing DESTROY call at DESTRUCT time');
ctest(2, $expected,'C,-O3','ccode208i',$script,$todo_o3.'#208 -ffast-destruct');
