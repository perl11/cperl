package
  Mock; # do not index
use strict;
BEGIN {
  unshift @INC, 't';
}

=head1 NAME

Mock lengthy compiler tests. Replay from TAP.

=head1 DESCRIPTION

Replay results from stored log files to test the result of the
current TODO status.

Currently perl compiler tests are stored in two formats:

1. log.test-$arch-$perlversion

2. log.modules-$perlversion

When running the Mock tests the actual tests are not executed,
instead the results from log file are used instead. A typical
perl-compiler testrun lasts several hours to days, with Mock
several seconds.

=head1 SYNOPSIS

  perlall="5.6.2 5.8.9 5.10.1 5.12.1 5.13.4"
  # actual tests
  for p in perl$perlall; do
    perl$p Makefile.PL && make && \
      make test TEST_VERBOSE=1 2>&1 > log.test-`uname -s`-$p
  done
  # fixup TODO's
  # check tests
  for p in perl$perlall; do
    perl$p t/mock t/*.t
  done

=cut

require "test.pl";
use Test::More;
use TAP::Parser;
use Test::Harness::Straps;
use Config;
use Cwd;
use Exporter;
our $details;
our @ISA     = qw(Exporter);
our @EXPORT = qw(find_modules_report find_test_report
                 mock_harness run_cc_test ctest ctestok ccompileok
);

# log.test or log.modules
# check only the latest version, and match revision and perlversion
sub find_test_report ($;$) {
  my $logdir = shift;
  my $arch = shift || `uname -s`;
  #log.test-$arch-$versuffix
  my $tmpl = "$logdir/log.test-*-5.*";
  my @f = latest_files($tmpl);
}

sub find_modules_report {
  my $logdir = shift;
  #log.modules-$ver$suffix
  latest_files("$logdir/log.modules-5.*");
}

# check date, max diff one day from youngest
sub latest_files {
  my $tmpl = shift;
  my @f = glob $tmpl;
  my @fdates = sort{$a->[1]<=>$b->[1]} map { [$_ => -M $_] } @f;
  my $latest = $fdates[0]->[1]; 
  my @ret;
  for (@fdates) {
    if ($_->[1]-$latest < 1.2) {
      push @ret, $_->[0]; 
    } else {
      last;
    }
  }
  @ret;
}

sub parse_report {
  my ($log, $t) = @_;
  my $straps = Test::Harness::Straps->new;
  open my $fh, "<", $log;
  my $result = $straps->analyze_fh($t, $fh);
  close $fh;
  # XXX replay only the part for the given test
  $result;
}

sub result ($) {
  my $parse = shift;
}

# 1, "C", "require LWP::UserAgent;\nprint q(ok);", "ok",0,1,"#TODO issue 27"
sub run_cc_test {
  my ($cnt, $backend, $script, $expect, $keep_c, $keep_c_fail, $todo) = @_;
  print @_;
}
# 1, "ok", "CC", "ccode37i", $script, $todo
sub ctest {
  my ($num, $expected, $backend, $base, $script, $todo) =  @_;
  print @_;
}
# 1, "CC", "ccode37i", $script, $todo
#sub ctestok {
#}
# 1, "CC", "ccode36i", $script, $todo
sub ccompileok {
  my ($num, $backend, $base, $script, $todo) =  @_;
  print @_;
}

sub mock_harness {
  my ($log, $t) = @_;
  my $rpt = parse_report($log, $t);
  $details = $rpt->details;
  # execute the real tests with mock_harness (overridden test)
  my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
  my $dbg = $^P ? "-d" : "";
  system("$X $dbg -It -MMock -MExtUtils::Command::MM -e\"test_harness(1, 'blib/lib', 'blib/arch')\" $t");
}

1;
