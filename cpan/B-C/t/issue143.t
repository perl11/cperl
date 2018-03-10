#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=143
# wrong length after double regex compilation
use Test::More tests => 3;
use strict;
BEGIN {
  unshift @INC, 't';
  require TestBC;
}
use Config ();
# broken on 5.10.1 with 1.48
my $todo = "TODO #143 " if $]>=5.010 and $]<5.012;
$todo = "TODO Free to wrong pool with MSVC " if $^O eq 'MSWin32' and $Config{cc} =~ 'cl';

ctestok(1, "C,-O3", 'ccode143i', <<'EOS', "wrong length after double regex compilation");
BEGIN {
  package Net::IDN::Encode;
  our $DOT = qr/[\.]/;
  my $RE  = qr/xx/;
  sub domain_to_ascii {
    my $x = shift || "";
    $x =~ m/$RE/o;
    return split( qr/($DOT)/o, $x);
  }
}
package main;
Net::IDN::Encode::domain_to_ascii(42);
print q(ok);
EOS

ctestok(2, "C,-O3", 'ccode143i', 'BEGIN{package Foo;our $DOT=qr/[.]/;};package main;print "ok\n" if "dot.dot" =~ m/($Foo::DOT)/',
        $todo."our qr");
ctestok(3, "C,-O3", 'ccode143i', 'BEGIN{$DOT=qr/[.]/}print "ok\n" if "dot.dot" =~ m/($DOT)/',
        $todo."global qr");
