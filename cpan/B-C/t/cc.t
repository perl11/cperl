#! /usr/bin/env perl
# better use testcc.sh for debugging
BEGIN {
  if ($ENV{PERL_CORE}) {
    unshift @INC, ('t', '../../lib');
  } else {
    unshift @INC, 't';
    #push @INC, "blib/arch", "blib/lib";
  }
  require 'test.pl'; # for run_perl()
}
use strict;
my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
#my $ITHREADS  = ($Config{useithreads});

prepare_c_tests();

my @todo  = todo_tests_default("cc");
# skip core dumps and endless loops, like custom sort or runtime labels
my @skip = (14,21,30,
	    46, # unsupported: HvKEYS(%Exporter::) is 0 unless Heavy is included also
            103, # hangs with non-DEBUGGING
	    ((!$DEBUGGING and $] > 5.010) ? (105) : ()),
           );

run_c_tests("CC", \@todo, \@skip);
