#! /usr/bin/perl
# http://code.google.com/p/perl-compiler/issues/detail?id=350
# special-case Moose XS. walker: missing packages
# see also t/moose-test.pl

use strict;
BEGIN {
  unless (-d '.git' and !$ENV{NO_AUTHOR}) {
    print "1..0 #SKIP Compile Moose only if -d .git\n";
    exit;
  }
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
use Config;
eval "use Moose;";

if ($@) {
  plan skip_all => "Moose required for testing issue 350" ;
} else {
  plan tests => 1;
}

my $DEBUGGING = ($Config::Config{ccflags} =~ m/-DDEBUGGING/);
my $todo = ($] > 5.017 and $DEBUGGING) ? "TODO " : "";
ctestok(1, 'C,-O3', 'ccode350i', <<'EOF', $todo.'C #350 Moose deps');
package Foo::Moose;
use Moose;
has bar => (is => "rw", isa => "Int");
package main;
my $moose = Foo::Moose->new;
print "ok" if 32 == $moose->bar(32);
EOF
