#! /usr/bin/env perl
# brian d foy: "Compiled perlpod should be faster then uncompiled"
use Test::More;
use strict;
BEGIN {
  if ($ENV{PERL_CORE}) {
    unshift @INC, ('t', '../../lib');
  } else {
    unshift @INC, 't';
  }
  require TestBC;
}

use Config;
use File::Spec;
use Time::HiRes qw(gettimeofday tv_interval);

sub faster { ($_[1] - $_[0]) < 0.05 }
sub diagv {
  diag @_ if $ENV{TEST_VERBOSE};
}
sub todofaster {
  my ($t1, $t2, $cmt) = @_;
  if (faster($t1,$t2)) {
    ok(1, $cmt);
  } else {
  TODO: {
      # esp. with $ENV{HARNESS_ACTIVE}
      local $TODO = " (unreliable timings with parallel testing)";
      ok(0, $cmt);
    }
  }
}

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $Mblib = Mblib();
my $perldoc = File::Spec->catfile($Config{installbin}, 'perldoc');
if ($ENV{PERL_CORE}) {
  $perldoc = File::Spec->catfile(
    '..','..','utils', ($Config{usecperl} ? 'cperldoc' : 'perldoc'));
  $X .= ' -I../../pod';
}
my $perlcc = "$X $Mblib script/perlcc";
$perlcc .= " -Wb=-fno-fold,-fno-warnings" if $] > 5.013;
$perlcc .= " -UB -uFile::Spec -uCwd";
$perlcc .= " -uPod::Perldoc::ToText" if $] >= 5.023004;
#$perlcc .= " -uFile::Temp" if $] > 5.015;
$perlcc .= " -uExporter" if $] < 5.010;
my $exe = $Config{exe_ext};
my $perldocexe = $^O eq 'MSWin32' ? "perldoc$exe" : "./perldoc$exe";
# XXX bother File::Which?
plan skip_all => "$perldoc not found" unless -f $perldoc;
plan skip_all => "MSVC" if ($^O eq 'MSWin32' and $Config{cc} eq 'cl');
plan skip_all => "mingw" if ($^O eq 'MSWin32' and $Config{cc} eq 'gcc'); # fail 1,4
plan tests => 7;

# XXX interestingly 5.8 perlcc cannot compile perldoc because Cwd disturbs the method finding
# vice versa 5.14 cannot compile perldoc manually because File::Temp is not included
my $compile = "$perlcc -o $perldocexe $perldoc";
diagv $compile;
my $res = `$compile`;
ok(-s $perldocexe, "$perldocexe compiled"); #1

diagv "see if $perldoc -T works";
my $T_opt = "-T -f wait";
my $PAGER = '';
my ($result, $ori, $out, $err);
my $t0 = [gettimeofday];
if ($^O eq 'MSWin32') {
  $T_opt = "-t -f wait";
  $PAGER = "PERLDOC_PAGER=type ";
  ($result, $ori, $err) = run_cmd("$PAGER$X -S $perldoc $T_opt", 20);
} else {
  ($result, $ori, $err) = run_cmd("$X -S $perldoc $T_opt", 20);
}
my $t1 = tv_interval( $t0 );
if ($ori =~ /Unknown option/) {
  $T_opt = "-t -f wait";
  $PAGER = "PERLDOC_PAGER=cat " if $^O ne 'MSWin32';
  diagv "No, use $PAGER instead";
  $t0 = [gettimeofday];
  ($result, $ori, $err) = run_cmd("$PAGER$X -S $perldoc $T_opt", 20);
  $t1 = tv_interval( $t0 );
} else {
  diagv "it does";
}
my $strip_banner = 0;
# check if we need to strip 1st and last line. Needed for 5.18-5.20
sub strip_banner($) {
  my $s = shift;
  $s =~ s/^.* User Contributed Perl Documentation (.*?)$//m;
  $s =~ s/^perl v.*$//m;
  return $s;
}
if ($ori =~ / User Contributed Perl Documentation /) {
  $strip_banner++;
  $ori = strip_banner $ori;
}

$t0 = [gettimeofday];
($result, $out, $err) = run_cmd("$PAGER $perldocexe $T_opt", 20);
my $t2 = tv_interval( $t0 );
# old perldoc 3.14_04-3.15_04: Can't locate object method "can" via package "Pod::Perldoc" at /usr/local/lib/perl5/5.14.1/Pod/Perldoc/GetOptsOO.pm line 34
# dev perldoc 3.15_13: Can't locate object method "_is_mandoc" via package "Pod::Perldoc::ToMan"
$ori =~ s{ /\S*perldoc }{ perldoc };
$out =~ s{ ./perldoc }{ perldoc };
$out = strip_banner $out if $strip_banner;
if ($] > 5.023 and $out ne $ori) {
  ok(1, "TODO 5.24 Pod::Simple");
} else {
  is($out, $ori, "same result"); #2
}

SKIP: {
  skip "cannot compare times", 1 if $out ne $ori;
  todofaster($t1,$t2,"compiled faster than uncompiled: $t2 < $t1"); #3
}

unlink $perldocexe if -e $perldocexe;
$perldocexe = $^O eq 'MSWin32' ? "perldoc_O3$exe" : "./perldoc_O3$exe";
$compile = "$perlcc -O3 -o $perldocexe $perldoc";
diagv $compile;
$res = `$compile`;
ok(-s $perldocexe, "perldoc compiled"); #4
unlink "perldoc.c" if $] < 5.10;
diagv $res unless -s $perldocexe;

$t0 = [gettimeofday];
($result, $out, $err) = run_cmd("$PAGER $perldocexe $T_opt", 20);
my $t3 = tv_interval( $t0 );
$out =~ s{ ./perldoc_O3 }{ perldoc };
$out = strip_banner $out if $strip_banner;
if ($] > 5.023 and $out ne $ori) {
  ok(1, "TODO 5.24 Pod::Simple");
} else {
  is($out, $ori, "same result"); #5
}

SKIP: {
  skip "cannot compare times", 2 if $out ne $ori;
  todofaster($t2,$t3,"compiled -O3 not slower than -O0: $t3 <= $t2"); #6
  todofaster($t1,$t3,"compiled -O3 faster than uncompiled: $t3 < $t1"); #7
}

END {
  unlink $perldocexe if -e $perldocexe;
}
