use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "needs perl >= 5.8.9 or >= 5.10.1"
    if $] < 5.008009 or $] eq "5.010000";
my $cperl = $^V =~ /c$/;
plan skip_all => "Not yet passing on cperl" if $cperl and ! -d '.git';

run_test_group;
