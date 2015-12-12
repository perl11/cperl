#!/usr/bin/perl

use strict;
use Test::More tests => 4;

use Cpanel::JSON::XS;

my $json = Cpanel::JSON::XS->new->allow_nonref();

my @vs = $json->incr_parse('"a\"bc');

ok( not scalar(@vs) );

@vs = $json->incr_parse('"');

is( $vs[0], "a\"bc" );


$json = Cpanel::JSON::XS->new;

@vs = $json->incr_parse('"a\"bc');
ok( not scalar(@vs) );
@vs = eval { $json->incr_parse('"') };
ok($@ =~ qr/JSON text must be an object or array/);

