#! /usr/bin/env perl
# better use testc.sh -O3 for debugging
BEGIN {
  #unless (-d '.git' and !$ENV{NO_AUTHOR}) {
  #  print "1..0 #SKIP Only if -d .git\n";
  #  exit;
  #}
  if ($ENV{PERL_CORE}) {
    unshift @INC, ('t', '../../lib');
  } else {
    unshift @INC, 't';
  }
  require TestBC;
}
use strict;
my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
#my $ITHREADS  = ($Config{useithreads});

prepare_c_tests();

my @todo  = todo_tests_default("c_o3");
my @skip = (
	    $DEBUGGING ? () : 29, # issue 78 if not DEBUGGING > 5.15
	    );
push @skip, 28 if $] > 5.023 and
  ($Config{cc} =~ / -m32/ or $Config{ccflags} =~ / -m32/);

run_c_tests("C,-O3", \@todo, \@skip);
