#!./perl
#
# COW performance regression RT #129802

use strict;
use warnings;
use Config;
use 5.010;

sub run_tests;

$| = 1;

BEGIN {
    chdir 't' if -d 't';
    @INC = ('../lib');
    require './test.pl';
    skip_all_if_miniperl("miniperl: List::Util XS needed");
    skip_all("PERL_NO_COW") if $Config::Config{ccflags} =~ /PERL_NO_COW/;
}

use Benchmark ':hireswallclock';
use List::Util qw(max sum);

plan tests => 2;
my (%bench, @td1, @td2);

for my $offset (0 .. $Config::Config{ptrsize}-1) {
  my $s = "A"x (2**16 + 5 - $offset);
  my $cat = 'B' . $s . 'B';
  my $spr = sprintf "B%sB", $s;

  $bench{assign} = timeit(10000, sub { my $i=0; $s   =~ /./ while $i++ < 100 });
  $bench{concat} = timeit(10000, sub { my $i=0; $cat =~ /./ while $i++ < 100 }); # slow
  # control test (grow length calculated differently as in concat)
  $bench{string} = timeit(10000, sub { my $i=0; $spr =~ /./ while $i++ < 100 });

  my $td1 = timediff($bench{concat}, $bench{assign});
  my $td2 = timediff($bench{concat}, $bench{string});
  push @td1, $td1->[1];
  push @td2, $td2->[1];
}

# find an outlier via a variant of the Grubb single outlier test, the max with 0.
# "is max the largest absolute deviation from the sample mean in
# units of the sample standard deviation"
# http://www.graphpad.com/support/faqid/1598/
# we use the quadratic diff, as the time difference is usually below 1.0,
# and with outliers >2. this stabilizes the test significantly.
sub outlier {
  my $name = shift;
  my $max  = max(@_);
  my $mean = sum(@_) / scalar(@_);
  my $sqtotal = 0.0;
  foreach (@_) { $sqtotal += ($mean - $_) ** 2; }
  my $stddev = ($sqtotal / (@_-1)) ** 0.5;
  my $Z = (($max - $mean) ** 2) / $stddev;
  my $critical_Z = 2.0; # outside of the 5% gauss-normalform confidence interval

  ok($Z < $critical_Z, "concat-$name outlier".
     " (mean: ".   sprintf("%0.02g", $mean).
     ", max: ".   sprintf("%0.02g", $max).
     ", stddev: ".sprintf("%0.02g", $stddev).
     ") Z: ".     sprintf("%0.02g", $Z) . " < $critical_Z")
    or diag @_;
}

outlier "assign", @td1;
outlier "string", @td2;

1;
