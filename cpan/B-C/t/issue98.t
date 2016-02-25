#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=98
# v5.15 Bytecode Attempt to access disallowed key 'strict/subs' in a restricted hash
use strict;
my $name = "ccode98i";
use Test::More;
use B::C::Config;
Test::More->import($] <= 5.021006 || $B::C::Config::have_byteloader
                   ? (tests => 1) : (skip_all => 'perl5.22 broke ByteLoader'));
use Config;

# New bug reported by Zloysystem
# This is common-sense.pm
my $source = 'BEGIN {
local $^W; # work around perl 5.16 spewing out warnings for next statement
# use warnings
${^WARNING_BITS} ^= ${^WARNING_BITS} ^ "";
# use strict, use utf8; use feature;
$^H |= 0x1c820ec0;
@^H{qw(feature___SUB__ feature_fc feature_unicode feature_evalbytes feature_say feature_state feature_switch)} = (1) x 7;}
sub test { eval(""); }
print q(ok);';
# old bug reported by Zloysystem
#$source = "use strict; eval(\@_);print q(ok);";

open F, ">", "$name.pl";
print F $source;
close F;

my $expected = "ok";
my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $Mblib = "-Iblib/arch -Iblib/lib";
if ($] < 5.008) {
  system "$runperl -MO=Bytecode,-o$name.plc $name.pl";
} else {
  system "$runperl $Mblib -MO=-qq,Bytecode,-H,-o$name.plc $name.pl";
}
unless (-e "$name.plc") {
  print "not ok 1 #B::Bytecode failed.\n";
  exit;
}
my $runexe = $] < 5.008
  ? "$runperl -MByteLoader $name.plc"
  : "$runperl $Mblib $name.plc";
my $result = `$runexe`;
$result =~ s/\n$//;

SKIP: {
  skip "no features on 5.6", 1 if $] < 5.008;
  ok($result eq $expected, "issue98 - set feature hash");
}

END {
  unlink($name, "$name.plc", "$name.pl")
    if $result eq $expected;
}
