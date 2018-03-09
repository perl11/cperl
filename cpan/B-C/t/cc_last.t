#! /usr/bin/env perl
# B::CC limitations with last/next/continue. See README.
# See also issue36.t
use strict;
BEGIN {
  if ($ENV{PERL_CORE}) {
    @INC = ('t', '../../lib');
  } else {
    unshift @INC, 't';
  }
  require TestBC;
}
use Test::More tests => 3;
my $base = "ccode_last";

# XXX Bogus. This is not the real 'last' failure as described in the README
my $script1 = <<'EOF';
# last outside loop
label: {
  print "ok\n";
  my $i = 1;
  {
    last label if $i;
  }
  print " not ok\n";
}
EOF

use B::CC;
# 5.12 still fails test 1
ctestok(1, "CC", $base, $script1,
       ($B::CC::VERSION < 1.08 or $] =~ m/5\.01[12]/
	? "TODO last outside loop fixed with B-CC-1.08"
	: "last outside loop"));

# computed labels are invalid
my $script2 = <<'EOF';
# Label not found at compile-time for last
lab1: {
  print "ok\n";
  my $label = "lab1";
  last $label;
  print " not ok\n";
}
EOF

#TODO: {
  #local $TODO = "Same result and errcode as uncompiled. Label not found for last";
  ctest(2, '$ok$', "CC", $base, $script2, "Label not found at compile-time for last");
#}

# Fixed by Heinz Knutzen for issue 36
my $script3 = <<'EOF';
# last for non-loop block
{
  print "ok";
  last;
  print " not ok\n";
}
EOF
ctestok(3, "CC", $base, $script3,
	$B::CC::VERSION < 1.08 
	  ? "TODO last for non-loop block fixed with B-CC-1.08" 
	  : "last for non-loop block");

if ($^O eq 'MSWin32' and $Config{cc} eq 'cl') {
  ok(1, "skip MSVC");
  exit;
}    

#my $script4 = <<'EOF';
## issue 55 segfault for non local loop exit
#LOOP:
#{
#    my $sub = sub { last LOOP; };
#    $sub->();
#}
#print "ok";
#EOF
## TODO
#ctestok(4, "CC", $base, $script4,
#	$B::CC::VERSION < 1.11
#	  ? "TODO B::CC issue 55 non-local exit with last => segv"
#	  :  "non local loop exit");
