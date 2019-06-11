#!perl
use strict;
use warnings;
use Test::More;
BEGIN {
  eval "require Time::Piece;";
  if ($@) {
    plan skip_all => "Time::Piece required";
    exit 0;
  }
  eval 'require JSON;'
    or plan skip_all => 'JSON required for cross testing';
  $ENV{PERL_JSON_BACKEND} = 'JSON::PP';
}
use Time::Piece;
plan $] < 5.008 ? (skip_all => "5.6 no AMG yet") : (tests => 18);
use JSON ();
use Cpanel::JSON::XS;

my $time = localtime;
my $json = Cpanel::JSON::XS->new->convert_blessed;

if ($Cpanel::JSON::XS::VERSION lt '3.0202') {
  diag 'simulate convert_blessed via TO_JSON';
  eval 'sub Foo::TO_JSON { "Foo <". shift->[0] . ">" }';
  eval 'sub main::TO_JSON { "main=REF(". $$_[0] . ")" }';
  eval 'sub Time::Piece::TO_JSON { "$time" }';
}

package Foo;
use overload '""' => sub { "Foo <". shift->[0] . ">"};

package main;

my $object = bless ["foo"], 'Foo';
my $enc = $json->encode( { obj => $object } );

is( $enc, '{"obj":"Foo <foo>"}', "mg object stringified" )
  or diag($enc);

$enc = $json->encode( { time => $time } );
isa_ok($time, "Time::Piece");

# my $dec = $json->decode($enc);
is( $enc, qq({"time":"$time"}), 'mg Time::Piece object was stringified' );

$object = bless [], 'main';
$json->allow_stringify;
$enc = $json->encode( \$object );
# fails in 5.6
like( $enc, qr/main=ARRAY\(0x[A-Fa-f0-9]+\)/, "nomg blessed array stringified" )
  or diag($enc);

$enc = $json->encode( \\$object );
like( $enc, qr/REF\(0x[A-Fa-f0-9]+\)/, "nomg ref stringified" )
  or diag($enc);

# 46, 49
my $pp = JSON->new->allow_unknown->allow_blessed;
$json = Cpanel::JSON::XS->new->allow_stringify;

is( $pp->encode  ( {false => \"some"} ), '{"false":null}',  'pp \"some"');
is( $json->encode( {false => \"some"} ), '{"false":"some"}','js \"some"');
is( $pp->encode  ( {false => \""} ),     '{"false":null}',  'pp \""');
is( $json->encode( {false => \""} ),     '{"false":null}',  'js \""');
is( $pp->encode  ( {false => \!!""} ),   '{"false":null}',  'pp \!!""');
is( $json->encode( {false => \!!""} ),   '{"false":null}',  'js \!!""');

$json->allow_unknown->allow_stringify;
$pp->allow_unknown->allow_blessed->convert_blessed;
my $e = $pp->encode(  {false => \"some"} ); # pp is a bit inconsistent
ok( ($e eq '{"false":null}') || ($e eq '{"false":some}'), 'pp stringref' );
is( $pp->encode  ( {false => \""} ),     '{"false":null}' );
is( $pp->encode  ( {false => \!!""} ),   '{"false":null}' );
is( $json->encode( {false => \"some"} ), '{"false":"some"}' );
is( $json->encode( {false => \""} ),     '{"false":null}' );
is( $json->encode( {false => \!!""} ),   '{"false":null}' );

# GH #124 missing refcnt on stringify result
package BoolTestOk;
use overload '""' => sub {"1"};
package main;
my $data = {nick => bless({}, 'BoolTestOk')};
is( $json->convert_blessed->allow_blessed->encode($data), '{"nick":"1"}' );

