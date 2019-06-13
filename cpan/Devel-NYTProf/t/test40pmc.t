use strict;
use Test::More;
use Config;

my $no_pmc;
if (Config->can('non_bincompat_options')) {
    foreach(Config::non_bincompat_options()) {
       if($_ eq "PERL_DISABLE_PMC"){
           $no_pmc = 1;
           last;
       }
    }
};
plan skip_all => ".pmc are disabled in this perl"
  if $no_pmc;
my $cperl = $^V =~ /c$/;
plan skip_all => "Not yet passing on cperl" if $cperl and ! -d '.git';

use lib qw(t/lib);
use NYTProfTest;

run_test_group;
