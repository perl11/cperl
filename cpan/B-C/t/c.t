#! /usr/bin/env perl
# better use testc.sh for debugging
use Config;
use File::Spec;
BEGIN {
  if ($ENV{PERL_CORE}) {
    unshift @INC, ('t', '../../lib');
  } else {
    unshift @INC, 't';
  }
  require TestBC;
}
use strict;
#my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
#my $ITHREADS  = ($Config{useithreads});

prepare_c_tests();

my @todo  = todo_tests_default("c");
my @skip = ();
#push @skip, 29 if $] > 5.015; #hangs at while Perl_hfree_next_entry hv.c:1670
push @skip, (21,38) if $^O eq 'cygwin'; #hangs
# 38 hangs in IO reading from /dev/null
push @todo, (27,41,44,45,49) if $^O eq 'cygwin'; #SEGV

run_c_tests("C", \@todo, \@skip);
