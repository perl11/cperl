#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=281
# wrong @- values: issues 90, 220, 281, 295
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 3;
use B::C ();
use Config;
my $cmt = 'wrong @- values';
# fixed with 1.45_11
# $cmt = "TODO ".$cmt if $] >= 5.010;

# was previously issue90.t test 16
ctestok(1, 'C,-O3', 'ccode281i', <<'EOF', $cmt." #220");
my $content = "ok\n";
while ( $content =~ m{\w}g ) {
    $_ .= "$-[0]$+[0]";
}
print "ok" if $_ eq "0112";
EOF

ctestok(2, 'C,-O3', 'ccode281i', <<'EOF', $cmt." #281");
"I like pie" =~ /(I) (like) (pie)/;
"@-" eq  "0 0 2 7" and print "ok\n";
#print "\@- = @-\n\@+ = @+\n"
EOF

ctestok(3, 'C,-O3', 'ccode281i', <<'EOF', $cmt. ' #295');
"zzaaabbb" =~ m/(a+)(b+)/;
print "ok\n" if "@-" eq "2 2 5"
EOF
