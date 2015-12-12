#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=54
# pad_swipe error with package pmcs
use strict;
my $name = "ccode54p";
use Test::More tests => 1;
use B::C::Flags;

my $pkg = <<"EOF";
package $name;
sub test {
  \$abc='ok';
  print "\$abc\\n";
}
1;
EOF

open F, ">", "$name.pm";
print F $pkg;
close F;

my $expected = "ok";
my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $Mblib = "-Iblib/arch -Iblib/lib";
if ($] < 5.008) {
  system "$runperl -MO=Bytecode,-o$name.pmc $name.pm";
} else {
  system "$runperl $Mblib -MO=-qq,Bytecode,-H,-o$name.pmc $name.pm";
}
unless (-e "$name.pmc") {
  print "not ok 1 #B::Bytecode failed.\n";
  exit;
}
my $runexe = "$runperl $Mblib -I. -M$name -e\"$name\::test\"";
$runexe = "$runperl -MByteLoader -I. -M$name -e\"$name\::test\"" if $] < 5.008;
my $result = `$runexe`;
$result =~ s/\n$//;

SKIP: {
  skip "no pmc on 5.6 (yet)", 1 if $] < 5.008;
  skip "perl5.22 broke ByteLoader", 1
      if $] > 5.021006 and !$B::C::Flags::have_byteloader;
  ok($result eq $expected, "issue54 - pad_swipe error with package pmcs");
}

END {
  unlink($name, "$name.pmc", "$name.pm")
    if $result eq $expected;
}
