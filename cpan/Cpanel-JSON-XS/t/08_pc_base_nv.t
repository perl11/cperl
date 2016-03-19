use Test::More tests => 1;

# copied over from JSON::PC and modified to use Cpanel::JSON::XS

use strict;
use Cpanel::JSON::XS;
my $o = decode_json("[-0.12]");

is($o->[0],"-0.12");
