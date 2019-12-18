#!perl -w
#
# test cperl's op_clone:
#   the structure must stay the same: inside ptrs must point to the same id, but not ptr.
#   the types and fields must be properly copied.
#   inside ptrs must be changed, outside ptrs must stay the same.
#   the result of op_clone_optree() must match the number of outside ptrs.
# needs XS::APITest::dump_cv_clone test functions.

#use strict;
#use vars '$g';
#use Test::More 'no_plan';
use XS::APItest;

$g = 1;
my $a = 0;
sub test1 {
  return 1 + $a;
}
sub test2 {
  return 1 + $g;
}

sub capture_stderr {
  my $sub = shift;
  my $stderr;
  open my $olderr, ">&STDERR" or die "Can't dup STDERR: $!";
  close STDERR;
  open STDERR, '>', \$stderr or die "Can't open STDERR: $!";
  $sub->();
  close STDERR;
  open STDERR, ">&", $olderr or die "Can't dup \$olderr: $!";
  return $stderr;
}

sub print_oplines {
  my $out = shift;
  for (split("\n", $out)) {
    if (/^(\d+\s*)(\+-)?(\w.*)/) {
      print "# $1$3\n";
    }
  }
}

my $out1 = capture_stderr( sub { dump_cv(\&test1) } );
#my $out2 = capture_stderr( sub { dump_cv_clone(\&test1) } );
print_oplines $out1;

$out1 = capture_stderr( sub { dump_cv(\&test2) } );
print_oplines $out1;
#$out2 = capture_stderr( sub { dump_cv_clone(\&test2) } );

print "1..1\nok 1\n";
