#! /usr/bin/perl
# http://code.google.com/p/perl-compiler/issues/detail?id=348
# walker: missing packages

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;

# 5.10 fixed with 1.48
#my $todo = ($] > 5.009 and $] < 5.011) ? "TODO " : "";
ctestok(1, 'C,-O3', 'ccode348i', <<'EOF', 'C #348 do not drop method-only user pkgs');
package Foo::Bar;
sub baz { 1 }

package Foo;
sub new { bless {}, shift }
sub method { print "ok\n"; }

package main;
Foo::Bar::baz();
my $foo = sub {
  Foo->new
}->();
$foo->method;
EOF


