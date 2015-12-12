#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=35
# B::CC generates wrong C code for same variable in different scope
use Test::More tests => 2;
use strict;
use Config;
my $ITHREADS  = $Config{useithreads};
my $base = "ccode35i";

sub test {
  my ($num, $script, $todo) =  @_;
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
  my $ok = -e $name or -e "$name.exe";
  if ($todo) {
  TODO: {
      local $TODO = $todo;
      ok($ok, 'CC same variable in different scope');
    }
  } else {
    ok($ok, 'CC same variable in different scope');
  }
  if ($ok) {
    unlink($name, "$name.c", "$name.pl", "$name.exe");
  }
}

# error: redeclaration of ‘d_x’ with no linkage
my $script = <<'EOF';
sub new {}
sub test {
   { my $x = 1; my $y = $x + 1;}
  my $x = 2;
  if ($x != 3) { 4; }
}
EOF

#fixed with B-C-1.28 r527 (B::CC 1.08)
use B::CC;
test(1, $script, $B::CC::VERSION < 1.08 ? "B::CC issue 35" : undef);

# error: redeclaration of ‘d_tmp5’ with no linkage
$script = <<'EOF';
sub test {
  my $tmp5 = 1;
  my $x = $tmp5 + 1;
  if ($x != 3) { 4; }
}
EOF

# passes non-threaded (5.8.9d-nt, perl5.10.1d-nt)
test(2, $script, ($B::CC::VERSION < 1.08 and $ITHREADS) ? "B::CC issue 35 fail3.pl" : undef);
