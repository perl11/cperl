#! /usr/bin/env perl
# better use testc.sh -O3 for debugging
BEGIN {
  #unless (-d '.git' and !$ENV{NO_AUTHOR}) {
  #  print "1..0 #SKIP Only if -d .git\n";
  #  exit;
  #}
  if ($ENV{PERL_CORE}){
    chdir('t') if -d 't';
    @INC = ('.', '../lib');
  } else {
    unshift @INC, 't';
  }
  require 'test.pl'; # for run_perl()
}
use strict;
my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
#my $ITHREADS  = ($Config{useithreads});

prepare_c_tests();

my @todo  = todo_tests_default("c_o3");
my @skip = (
	    $DEBUGGING ? () : 29, # issue 78 if not DEBUGGING > 5.15
	    );

run_c_tests("C,-O3", \@todo, \@skip);
