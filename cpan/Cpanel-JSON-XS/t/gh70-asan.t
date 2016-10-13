#! perl
# check a too short new() argument to memcmp, only with asan or valgrind.
# GH #70

use Test::Simple tests => 1;

package J;
use base "Cpanel::JSON::XS";
J->new;

package main;
ok(1);
