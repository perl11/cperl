#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=59
# Problems compiling scripts that use IO::Socket
use Test::More tests => 3;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Config;

my $name = "ccode59i";
my $script = <<'EOF';
use strict;
use warnings;
use IO::Socket;
my $remote = IO::Socket::INET->new( Proto => "tcp", PeerAddr => "perl.org", PeerPort => "80" );
if ($remote) {
  print $remote "GET / HTTP/1.0" . "\r\n\r\n";
  my $result = <$remote>;
  $result =~ m|HTTP/1.1 200 OK| ? print "ok" : print $result;
  close $remote;
}
EOF

open F, "> $name.pl";
print F $script;
close F;

my $expected = "ok";
my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $q = $] < 5.008001 ? "" : "-qq,";
my $result = qx($runperl $name.pl);
my $canconnect = $result eq $expected ? 1 : 0;
my $cmt = "connect to http://perl.org:80 via IO::Socket";

SKIP: {
  skip "cannot $cmt", 3 if !$canconnect;
  #skip "eats memory on 5.6", 2 if $] <= 5.008001;
  #skip "fails 5.14 threaded", 2
  #  if $] > 5.014 and $] < 5.015 and $Config{'useithreads'} and (!-d ".git" or $ENV{NO_AUTHOR});

  plctestok(1, $name, $script, ($] >= 5.018 ? "TODO ":"")."BC $name ".$cmt);

  #$cmt = "TODO 5.14thr" if $] > 5.014 and $] < 5.015 and $Config{'useithreads'};
  #$cmt = "TODO >=5.16" if $] >= 5.016; # fixed with 1.45_04
  $cmt = "TODO <5.10 "  if $] < 5.010; # no idea why
  ctestok(2, "C", $name, $script, "C $name $cmt");
  $cmt = $] > 5.021 ? "TODO 5.22" : $cmt;
  ctestok(3, "CC", $name, $script, "CC $name $cmt");
}
