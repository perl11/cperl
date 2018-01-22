#!perl -w

# Check that the current version of perl exists in Module-CoreList data

use TestInit qw(T);
use strict;
use Config;

require './t/test.pl';

plan(tests => 5);

use_ok('Module::CoreList');
use_ok('Module::CoreList::Utils');

{
  no warnings 'once';
  my $v = $];
  $v .= 'c' if $Config{usecperl};
  ok( defined $Module::CoreList::released{ $v }, "$v exists in released" );
  ok( defined $Module::CoreList::version{ $v }, "$v exists in version" );
  ok( defined $Module::CoreList::Utils::utilities{$v }, "$v exists in Utils" );
}
