#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=96
# defined &gv should not store the gv->CV
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
use Config;
plan tests => 3;
#plan skip_all => 'defined &gv optimization temp. disabled'; exit;

my $ITHREADS = $Config{useithreads};
my $script = 'defined(&B::OP::name) || print q(ok)';

sub compile_check {
  my ($num,$b,$base,$script,$cmt) = @_;
  my $name = $base."_$num";
  unlink("$name.c", "$name.pl");
  open F, ">", "$name.pl";
  print F $script;
  close F;
  my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
  my ($result,$out,$stderr) =
    run_cmd("$X -Iblib/arch -Iblib/lib -MO=$b,-o$name.c $name.pl", 20);
  unless (-e "$name.c") {
    print "not ok $num # $name B::$b failed\n";
    exit;
  }
  # check stderr for "blocking not found"
  #diag length $stderr," ",length $out;
  if (!$stderr and $out) {
    $stderr = $out;
  }
  $stderr =~ s/main::stderr.*//s;

  if ($ITHREADS) { # padop, not gvop
    like($stderr,qr/skip saving defined\(&/, "detect defined(&B::OP::name)");
    ok(1, "#skip save *B::OP::name with padop threads");
  } else {
    like($stderr,qr/skip saving defined\(&B::OP::name\)/, "detect defined(&B::OP::name)");
    like($stderr,qr/GV::save \*B::OP::name done/, "should save *B::OP::name");
  }
  unlike($stderr,qr/GV::save &B::OP::name/, "should not save &B::OP::name");
}

compile_check(1,'C,-O3,-DGC','ccode96i',$script,"");
