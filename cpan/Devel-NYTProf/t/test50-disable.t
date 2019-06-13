use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

my $cperl = $^V =~ /c$/;
plan skip_all => "Not yet passing on cperl" if $cperl and ! -d '.git';

run_test_group;
