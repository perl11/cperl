#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=238 239
# format STDOUT: t/CORE/comp/form_scope.t + t/CORE/io/defout.t
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 4;
# 5.10 fixed with 1.48
my $todo = ""; # ($] =~ /^5\.010/) ? "TODO " : "";

ctestok(1,'C,-O3','ccode238i',<<'EOF',$todo.'#238 format f::STDOUT');
sub f ($);
sub f ($) {
  my $test = $_[0];
  write;
  format STDOUT =
ok @<<<<<<<
$test
.
}
f('');
EOF

ctestok(2,'C,-O3','ccode239i',<<'EOF',$todo.'#239,#285 format main::STDOUT');
my $x="1";
format STDOUT =
ok @<<<<<<<
$x
.
write;print "\n";
EOF

ctestok(3,'C,-O3','ccode277i',<<'EOF',$todo.'#277,#284 format -O3 ~~');
format OUT =
bar ~~
.
open(OUT, ">/dev/null"); write(OUT); close OUT;
print "ok\n";
EOF

ctestok(4,'C,-O3','ccode283i',<<'EOF',$todo.'#283 implicit format STDOUT');
format =
ok
.
write
EOF

