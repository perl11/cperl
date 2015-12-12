#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=50
# B::CC UV for <<
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

use Config;
my $ivsize = $Config{ivsize};

my $script = <<'EOF';
my $ok = 1;
sub check {
    my $m = shift;
    my $s = sprintf("%lx $m\n", $m);
    $ok = 0 if $s =~ /fffe -2/;
}

my $maxuv = 0xffffffff if $ivsize == 4;
$maxuv    = 0xffffffffffffffff if $ivsize == 8;
$maxuv    = 0xffff if $ivsize == 2;
die "1..1 skipped, unknown ivsize\n" unless $maxuv;
my $maxiv = 0x7fffffff if $ivsize == 4;
$maxiv    = 0x7fffffffffffffff if $ivsize == 8;
$maxiv    = 0x7fff if $ivsize == 2;

check($maxuv);
check(($maxuv & $maxiv) << 1);

my $mask =  $maxuv;
check($mask);
my $mask1 = ($mask & $maxiv) << 1;
check($mask1);
$mask1 &= $maxuv;
check($mask1);
print "ok\n" if $ok;
EOF

$script =~ s/\$ivsize/$ivsize/eg;

use B::CC;
ctestok(1, "CC", "ccode50i", $script, # fixed with r633
	($B::CC::VERSION < 1.08 ? "TODO ":"")
	. "perlcc UV << issue50 - fixed with B-C-1.28");
