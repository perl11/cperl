#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=212
# need to share GPs for stashes
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 3;
use Config ();
use B::C ();
my $ITHREADS = $Config::Config{useithreads};
my $todo1 = ($B::C::VERSION lt '1.45_03' and ($]>=5.018 and $ITHREADS)) ? "TODO 5.18thr ": "";
# fixed with 1.45_04: non-destructive get_isa for 5.8
my $todo3 = ($] < 5.007) ? "TODO 5.6 ": "";

ctestok(1,'C,-O3,-UB','ccode212i',<<'EOF',$todo1.'#212 shared GP');
$blurfl = 123;
{
    package abc;
    $blurfl = 5;
}
$abc = join(':', sort(keys %abc::));

package abc;
$blurfl;
print q(ok) if eval q/$blurfl/ == 5;
EOF

ctestok(2,'C,-O3,-UB','ccode209i',<<'EOF','#209 empty keys %main::');
$s = join(":", sort(keys %::));
print q(ok) if $s;
EOF

ctestok(3,'C,-O3,-UB','ccode210i',<<'EOF',$todo3.'#210 keys %package return an invalid list');
$a = 123;
package xyz;
sub xsub {bless [];}
$x1 = 1; $x2 = 2;
$s = join(":", sort(keys %xyz::));
package abc;
my $foo;
print q(ok) if $xyz::s eq 's:x1:x2:xsub';
EOF
