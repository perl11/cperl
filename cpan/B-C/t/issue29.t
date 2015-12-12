#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=29
use strict;
BEGIN {
  if ($] < 5.008) {
    print "1..1\nok 1 #skip 5.6 has no IO discipline\n"; exit;
  }
}
use Test::More tests => 2;
use Config;
use B::C::Flags;

my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
my $ITHREADS  = ($Config{useithreads});

my $name = "ccode29i";
my $script = <<'EOF';
use open qw(:std :utf8);
$_ = <>;
print unpack('U*', $_), " ";
print $_ if /\w/;
EOF

open F, ">", "$name.pl";
print F $script;
close F;

#$ENV{LC_ALL} = 'C.UTF-8'; $ENV{LANGUAGE} = $ENV{LANG} = 'en';
my $expected = "24610 ö";
my $runperl = $^X =~ m/\s/ ? qq{"$^X" -Iblib/arch -Iblib/lib} : "$^X -Iblib/arch -Iblib/lib";
system "$runperl blib/script/perlcc -o $name $name.pl";
unless (-e $name or -e "$name.exe") {
  print "ok 1 #skip perlcc failed. Try -Bdynamic or -Bstatic or fix your ldopts.\n";
  print "ok 2 #skip\n";
  exit;
}
my $runexe = $^O eq 'MSWin32' ? "$name.exe" : "./$name";
my $result = `echo "ö" | $runexe`;
$result =~ s/\n$//;
TODO: {
  local $TODO = "B::C issue 29 utf8 perlio";
  ok($result eq $expected, "C '$result' ne '$expected'");
}

if ($] < 5.008) {
  system "$runperl -MO=Bytecode56,-o$name.plc $name.pl";
} else {
  system "$runperl -MO=-qq,Bytecode,-o$name.plc $name.pl";
}
unless (-e "$name.plc") {
  print "ok 2 #skip perlcc -B failed.\n";
  exit;
}
$runexe = "$runperl -MByteLoader $name.plc";
$result = `echo "ö" | $runexe`;
$result =~ s/\n$//;
SKIP: { TODO: {
  local $TODO = "B::Bytecode issue 29 utf8 perlio: 5.12-5.16"
    if ($] >= 5.011004 and $] < 5.018 and $ITHREADS);
  skip "perl5.22 broke ByteLoader", 1
      if $] > 5.021006 and !$B::C::Flags::have_byteloader;
  ok($result eq $expected, "BC '$result' eq '$expected'");
}}

END {
  unlink($name, "$name.plc", "$name.pl", "$name.exe")
    if $result eq $expected;
}
