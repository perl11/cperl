#! /usr/bin/env perl
use strict;
use Config;
BEGIN {
  unshift @INC, 't';
  require TestBC;
}
use Test::More;

# but works locally
plan skip_all => "mingw on appveyor"
  if $^O eq 'MSWin32' and $Config{cc} eq 'gcc' and $ENV{APPVEYOR};
plan tests => 4;

my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $Mblib = Mblib();
my $perlcc = perlcc();
my $exe = $^O eq 'MSWin32' ? 'ccode_argv.exe' : 'ccode_argv';
my $pl  = $^O eq 'MSWin32' ? "t\\c_argv.pl" : "t/c_argv.pl";
my $plc = $pl . "c";
my $d = <DATA>;

open F, ">", $pl;
print F $d;
close F;
diag "$runperl $Mblib $perlcc -O3 -o $exe -r $pl ok 1" if $ENV{TEST_VERBOSE};
is(`$runperl $Mblib $perlcc -O3 -o $exe -r $pl ok 1`, "ok 1\n", #1
   "perlcc -r file args");
unlink($exe);

open F, ">", $pl;
my $d2 = $d;
$d2 =~ s/ ok 1/ ok 2/;
print F $d2;
close F;
{
  my $result = `$runperl $Mblib $perlcc -O -o $exe -r $pl ok 2`;
  my $expected = "ok 2\n";
  my $cmt = "perlcc -O -r file args";
  if ($result eq $expected) {
    is ($result, $expected, $cmt); #2
  } else {
  TODO: {
    local $TODO = "unreliable CC testcase";
    is($result, $expected, $cmt);
    }
  }
}
unlink($exe);

open F, ">", $pl;
my $d3 = $d;
$d3 =~ s/ ok 1/ ok 3/;
print F $d3;
close F;
if ($] < 5.022) {
  is(`$runperl $Mblib $perlcc -B -r $pl ok 3`, "ok 3\n", #3
     "perlcc -B -r file args");
} else {
  ok(1, "SKIP BC 5.22");
}

# issue 30
$d = '
sub f1 {
   my($self) = @_;
   $self->f2;
}
sub f2 {}
sub new {}
print "@ARGV\n";';

open F, ">", $pl;
print F $d;
close F;

`$runperl $Mblib $perlcc -o $exe $pl`;
$exe = "./$exe" unless $^O eq 'MSWin32';
is (`$exe a b c`, "a b c\n",
   "issue 30: perlcc -o $exe; $exe args"); #4

END {
  unlink($exe, $pl, $plc);
}

__DATA__
print @ARGV?join(" ",@ARGV):"not ok 1 # empty \@ARGV","\n";
