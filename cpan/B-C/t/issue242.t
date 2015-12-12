#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=242
# -fno-fold and OP_UCFIRST
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;
# in branch swashnew-273 ($init1) fails since 5.16

# need -uDynaLoader or -ffold
my $script = <<'EOF';
$xyz = ucfirst("\x{3C2}"); # no problem without that line
$a = "\x{3c3}foo.bar";
($c = $a) =~ s/(\p{IsWord}+)/ucfirst($1)/ge;
print "ok\n" if $c eq "\x{3a3}foo.Bar";
EOF

ctestok(1,'C','ccode242i',$script, '#242 C,-O0 ucfirst demandloads unicore/To/Title.pl');
ctestok(2,'C,-O3','ccode242i',$script, '#242 -O3');
