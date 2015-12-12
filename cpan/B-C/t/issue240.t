#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=240
# not repro. fails only as file
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;

ctestok(1,'C,-O3','ccode240i',<<'EOF',($ENV{HARNESS_ACTIVE} ? "":"").'#240 not repro unicode race condition with \U');
my $a = "\x{100}\x{101}Aa";
print "ok\n" if "\U$a" eq "\x{100}\x{100}AA";
my $b = "\U\x{149}cD"; # no pb without that line
__END__
EOF
