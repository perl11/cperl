#!/usr/bin/perl

use strict;
use Test::More tests => 12;

use Cpanel::JSON::XS;

my $json = Cpanel::JSON::XS->new;

my $complete_text = qq/{"foo":"bar"}/;
my $garbaged_text  = qq/{"foo":"bar"}\n/;
my $garbaged_text2 = qq/{"foo":"bar"}\n\n/;
my $garbaged_text3 = qq/{"foo":"bar"}\n----/;

is( ( $json->decode_prefix( $complete_text )  ) [1], 13 );
is( ( $json->decode_prefix( $garbaged_text )  ) [1], 13 );
is( ( $json->decode_prefix( $garbaged_text2 ) ) [1], 13 );
is( ( $json->decode_prefix( $garbaged_text3 ) ) [1], 13 );

eval { $json->decode( "\n" ) }; ok( $@ =~ /malformed JSON/ );
eval { $json->decode('null') }; ok $@ =~ /allow_nonref/;

eval { $json->decode_prefix( "\n" ) }; ok( $@ =~ /malformed JSON/ );
eval { $json->decode_prefix('null') }; ok $@ =~ /allow_nonref/;

my $buffer = "[0][1][2][3]";
for (0..3) {
  my ($data, $size) = $json->decode_prefix($buffer);
  $buffer = substr($buffer,$size);
  is ($size, 3, "advance offset $buffer #82");
}
