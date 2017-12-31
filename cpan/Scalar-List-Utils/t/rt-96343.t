#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 2;

TODO: { SKIP: {
  local $TODO = '5.20' if $] > 5.019 and $] < 5.022;
  skip "on $]",1 if $] < 5.008;
  use List::Util qw( first );

  my $hash = {
    'HellO WorlD' => 1,
  };

  is( ( first { 'hello world' eq lc($_) } keys %$hash ), "HellO WorlD",
    'first (lc$_) perserves value' );
}}

{
  use List::Util qw( any );

  my $hash = {
    'HellO WorlD' => 1,
  };

  my $var;

  no warnings 'void';
  any { lc($_); $var = $_; } keys %$hash;

  is( $var, 'HellO WorlD',
    'any (lc$_) leaves value undisturbed' );
}
