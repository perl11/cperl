#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=338
# set qr UTF8 flags, t/testc.sh -q -O3 -A -c 20 39 44 71 131 143 1431 1432 330 333 338

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;

my $todo = ($] > 5.009 and $] < 5.011) ? "TODO " : "";
ctestok(1, 'C,-O3', 'ccode338i', <<'EOF', $todo.'C #338 qr utf8');
use utf8; my $l = "ñ"; my $re = qr/ñ/; print $l =~ $re ? qq{ok\n} : length($l)."\n".ord($l)."\n";
EOF

# $todo = ($] > 5.021) ? "TODO " : $todo; # 5.22 fixed with B-C-1.52_13
ctestok(2, 'C,-O3', 'ccode333i', <<'EOF', $todo.'C #333 qr utf8');
use encoding "utf8";
my @hiragana =  map {chr} ord("ぁ")..ord("ん");
my @katakana =  map {chr} ord("ァ")..ord("ン");
my $hiragana = join(q{} => @hiragana);
my $katakana = join(q{} => @katakana);
my %h2k; @h2k{@hiragana} = @katakana; 
$str = $hiragana;
$str =~ s/([ぁ-ん])/$h2k{$1}/go;
print $str eq $katakana ? "ok\n" : "not ok\n$hiragana\n$katakana\n";
EOF
