#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=34
# B::C -O4 ignores $/ = undef
use Test::More tests => 2;
use strict;
my $base = "ccode34i";

sub test {
  my ($num, $script, $expected, $todo) =  @_;
  my $name = $base."_$num";
  unlink($name, "$name.c", "$name.pl", "$name.exe");
  open F, ">", "$name.pl";
  print F $script;
  close F;

  my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
  $runperl .= " -Iblib/arch -Iblib/lib";
  my $b = $] > 5.008 ? "-qq,CC" : "CC";
  system "$runperl -MO=$b,-o$name.c $name.pl";
  unless (-e "$name.c") {
    print "not ok 1 #B::CC failed\n";
    exit;
  }
  system "$runperl blib/script/cc_harness -q -o $name $name.c";
  my $runexe = $^O eq 'MSWin32' ? "$name.exe" : "./$name";
  ok(-e $runexe, "$runexe exists");
  my $result = `$runexe`;
  my $ok = $result eq $expected;
  if ($todo) {
  TODO: {
      local $TODO = $todo;
      ok($ok);
    }
  } else {
    ok($ok);
  }
  if ($ok) {
    unlink($runexe, "$name.c", "$name.pl", "$name.dat");
  }
}

my $script = <<'EOF';
$/ = undef;
open FILE, 'ccode34i.dat';
my $first = <FILE>;
my $rest = <FILE>;
print "1:\n$first";
print "2:\n$rest";
EOF

open F, ">", "ccode34i.dat";
print F "line1\n";
print F "line2\n";
close F;

my $expected = <<'EOF1';
1:
line1
line2
2:
EOF1

test(1, $script, $expected, 'B::CC issue 34 $/=undef ignored');
