#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=340
# SUPER on run-time loaded IO::Socket does not find compiled IO::Handle->autoflush
# major walker rewrite
# also test that -O3 warnings will not crash when being written to at run-time

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
unless (eval{require Net::DNS;} and eval{require IO::Socket::INET6;}) {
  plan skip_all => "require Net::DNS and IO::Socket::INET6";
  exit(0);
}
plan tests => 1;

# TODO: still prints compile-time Carp reloading cruft
ctestok(1, 'C,-O3', 'ccode340i', <<'EOF', 'C #340 inc cleanup');
eval q/use Net::DNS/;
my $new = "IO::Socket::INET6"->can("new") or die "die at new";
my $inet = $new->("IO::Socket::INET6", LocalAddr => q/localhost/, Proto => "udp", LocalPort => undef);
print q(ok) if ref($inet) eq "IO::Socket::INET6";
EOF
