#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=93
# recover state of IO objects. Or not
# Another testcase is t/testm.sh Test::NoWarnings
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 9;
use Config;
my $i=1;

my $todo = <<'EOS';
# === compiled ===
my ($pid, $out, $in);
BEGIN {
  local(*FPID);
  $pid = open(FPID, 'echo <<EOF |'); #impossible
  open($out, '>&STDOUT');            #easy
  open(my $tmp, '>', 'pcc.tmp');     #hard to gather filename
  print $tmp "test\n";
  close $tmp;                        #ok closed, easy
  open($in, '<', 'pcc.tmp');         #hard to gather filename
}
# === run-time ===
print $out 'o';
kill 0, $pid; 			     # BAD! warn? die? how?
read $in, my $x, 4;
print 'k' if 'test' eq $x;
unlink 'pcc.tmp';
EOS

my ($cmt, $name);

TODO: {
  local $TODO = "recover IO state generally";
  $cmt = 'various hard IO BEGIN problems';
  $name = 'ccode93ib';
  plctestok($i++, $name, $todo, "BC cmt");
  ctestok($i++, "C", $name, $todo, "C $cmt");
  ctestok($i++, "CC", $name, $todo, "CC $cmt");
}

my $ok = <<'EOF';
my $out;open($out,'>&STDOUT');print $out qq(ok\n);
EOF

$cmt = '&STDOUT at run-time';
$name = 'ccode93ig';
plctestok($i++, $name, $ok, "BC cmt");
ctestok($i++, "C", $name, $ok, "C $cmt");
ctestok($i++, "CC", $name, $ok, "CC $cmt");

my $work = <<'EOF';
my $out;BEGIN{open($out,'>&STDOUT');}print $out qq(ok\n);
EOF

TODO: {
  local $TODO = "recover STDIO state";
  $cmt = '&STDOUT restore';
  $name = 'ccode93iw';
  plctestok($i++, $name, $work, ($] < 5.014?"TODO needs 5.14 ":"")."BC cmt");
  ctestok($i++, "C", $name, $work, "C $cmt");
  ctestok($i++, "CC", $name, $work, "CC $cmt");
}

END {unlink "pcc.tmp" if -f "pcc.tmp";}
