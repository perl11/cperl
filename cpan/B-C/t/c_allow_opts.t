#! /usr/bin/env perl
# test -DALLOW_PERL_OPTIONS
BEGIN {
  print "1..4\n";
}
use strict;

my $pl = "t/allow.pl";
my $d = <DATA>;
open F, ">", $pl;
print F $d;
close F;
my $exe = $^O eq 'MSWin32' ? 'ccallow.exe' : './ccallow';
my $C = $] > 5.007 ? "-qq,C" : "C";
my $X = $^X =~ m/\s/ ? qq{"$^X" -Iblib/arch -Iblib/lib} : "$^X -Iblib/arch -Iblib/lib";
system "$X -MO=$C,-O3,-occallow.c $pl";
# see if the ldopts libs are picked up correctly. This really depends on your perl package.
system "$X script/cc_harness -q -DALLOW_PERL_OPTIONS ccallow.c -o $exe";
unless (-e $exe) {
  print "ok 1 #skip wrong ldopts for cc_harness. Try -Bdynamic or -Bstatic or fix your ldopts.\n";
  print "ok 2 #skip ditto\n";
  print "ok 3 #skip\n";
  print "ok 4 #skip\n";
  exit;
}
my $ok = `$exe -s -abc=2 -def 2>&1`;
chomp $ok;
print "not " if $ok !~ /Unrecognized switch: -bc=2/;
print "ok 1\n";

$ok = `$exe -s -- -abc=2 -def`;
chomp $ok;
my $exp = "21-";
print $ok ne $exp ? "not " : "", "ok 2",
  $ok ne $exp ? "# want: $exp got: $ok\n" : "\n";

system "$X script/cc_harness -q ccallow.c -o $exe";
$ok = `$exe -s -- -abc=2 -def`;
$exp = "---";
chomp $ok;
print $ok ne $exp ? "not " : "", "ok 3", $ok ne $exp ? " # want: $exp got: $ok\n" : "\n";
$ok = `$exe -s -abc=2 -def 2>&1`;
chomp $ok;
print $ok ne $exp ? "not " : "", "ok 4", $ok ne $exp ? " # want: $exp got: $ok\n" : "\n";

END {
  unlink($exe, "ccallow.c", $pl);
}

__DATA__
for (qw/abc def ghi/) {print defined $$_ ? $$_ : q(-)};
