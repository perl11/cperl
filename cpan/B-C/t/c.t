#! /usr/bin/env perl
# better use testc.sh for debugging
BEGIN {
  if ($ENV{PERL_CORE}) {
    unshift @INC, ('t', '../../lib');
  } else {
    unshift @INC, 't';
    #push @INC, "blib/arch", "blib/lib";
  }
  require 'Test.pm';
}
use strict;
#my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
#my $ITHREADS  = ($Config{useithreads});

prepare_c_tests();

my @todo  = todo_tests_default("c");
my @skip = ();
#push @skip, 29 if $] > 5.015; #hangs at while Perl_hfree_next_entry hv.c:1670

run_c_tests("C", \@todo, \@skip);
