#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=301
# detect (maybe|next)::(method|can) mro method calls
# also check #326 maybe::next::method()
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
plan ($] > 5.007003 ? (tests => 2) : (skip_all => "no NEXT on $]"));

my $script = <<EOF;
use mro;
{
  package A;
  sub foo { 'A::foo' }
}
{
  package C;
  use base 'A';
  sub foo { (shift)->next::method() }
}
print qq{ok} if C->foo eq 'A::foo'
EOF

if ($] < 5.010) {
  $script =~ s/mro/NEXT/m;
  $script =~ s/next::/NEXT::/m;
  $script =~ s/method/foo/m;
}
use B::C ();
# fixed with 1.52_17
my $todo = ($] > 5.021 and $B::C::VERSION lt '1.52_17') ? "TODO " : "";

# mro since 5.10 only
ctestok(1, 'C,-O3', 'ccode301i', $script, $todo.'#301 next::method detection');

$script = <<EOF;
package Diamond_C;
sub maybe { "Diamond_C::maybe" }
package Diamond_D;
use base "Diamond_C";
use mro "c3";
sub maybe { "Diamond_D::maybe => " . ((shift)->maybe::next::method() || 0) }
package main; print "ok\n" if Diamond_D->maybe;
EOF
if ($] < 5.010) {
  $script =~ s/mro/NEXT/m;
  $script =~ s/maybe::next::/NEXT::DISTINCT::/m;
  $script =~ s/::method/::maybe/m;
}
ctestok(2, 'C,-O3', 'ccode326i', $script, $todo.'#326 maybe::next::method detection');
