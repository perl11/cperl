#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=120
# support lexsubs and its various B::CV::GV changes
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
if ($] < 5.018) {
  plan skip_all => "lexical subs since 5.18";
  exit;
}
plan tests => 4;
use Config;

my $issue = <<'EOF';
no warnings "experimental::lexical_subs";
use feature 'lexical_subs';
my sub p{q(ok)}; my $a=\&p;
print p;
EOF

sub compile_check {
  my ($num,$b,$base,$script,$cmt) = @_;
  my $name = $base."_$num";
  unlink("$name.c", "$name.pl");
  open F, ">", "$name.pl";
  print F $script;
  close F;
  my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
  $b .= ',-DCsp,-v';
  my $Mblib = Mblib;
  my ($result,$out,$stderr) =
    run_cmd("$X $Mblib -MO=$b,-o$name.c $name.pl", 20);
  unless (-e "$name.c") {
    print "not ok $num # $name B::$b failed\n";
    exit;
  }
  # check stderr for "Can't locate object method "STASH" via package "B::SPECIAL"
  # or crashes
  if (!$stderr and $out) {
    $stderr = $out;
  }
  my $notfound = $stderr =~ /Can't locate object method/;
  ok(!$notfound, $cmt);
}

compile_check(1,'C,-O3,-UB','ccode130i',$issue,"lexsubs compile ok");
ctestok(2,'C,-O3,-UB,-Uwarnings,-UCarp,-UExporter,-UConfig','ccode130i',$issue,
        "lexsubs run C ok");
ctestok(3,'CC,-UB,-Uwarnings,-UCarp,-UExporter,-UConfig','cccode130i',$issue,
        ($]>5.021?"TODO 5.22 ":"")."lexsubs run CC ok");

plctestok(4,'ccode130i',$issue,"TODO lexsubs run BC ok"); # needs xcv_name_hek
