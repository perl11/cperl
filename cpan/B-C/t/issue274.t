#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=274
# multiple match once

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;
use B::C ();
my $todo = ($B::C::VERSION ge '1.43_06') ? "" : "TODO ";
# currently also fails on: cPanel perl5.14, cygwin 5.14. No idea yet why
my $todo = "TODO " if $] < 5.010;
#$todo = "" if $] >= 5.020;

ctest(1,"1..5\nok 1\nok 2\nok 3\nok 4\nok 5", 'C,-O3','ccode274i',<<'EOF',$todo.'multiple match once #274');
package Foo;

sub match { shift =~ m?xyz? ? 1 : 0; }
sub match_reset { reset; }

package Bar;

sub match { shift =~ m?xyz? ? 1 : 0; }
sub match_reset { reset; }

package main;
print "1..5\n";

print "ok 1\n" if Bar::match("xyz");
print "ok 2\n" unless Bar::match("xyz");
print "ok 3\n" if Foo::match("xyz");
print "ok 4\n" unless Foo::match("xyz");

Foo::match_reset();
print "ok 5\n" if Foo::match("xyz");
EOF
