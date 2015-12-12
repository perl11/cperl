#! /usr/bin/env perl
# better use testcc.sh -O1 for debugging
BEGIN {
  unless (-d '.git' and !$ENV{NO_AUTHOR}) {
    print "1..0 #SKIP Only if -d .git\n";
    exit;
  }
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
my $ITHREADS  = ($Config{useithreads});

my @todo  = todo_tests_default("cc_o1");
# skip core dump causing known limitations, like custom sort or runtime labels
my @skip = (14,21,24,31,46);
push @skip, 103 if $] == 5.010000 and $ITHREADS and !$DEBUGGING; # hanging
push @skip, 105 if $] > 5.015;

run_c_tests("CC,-O1", \@todo, \@skip);
