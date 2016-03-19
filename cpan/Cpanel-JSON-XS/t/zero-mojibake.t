#!/usr/bin/perl

use strict;
use Test::More tests => 5;
use Cpanel::JSON::XS;
my $json = Cpanel::JSON::XS->new;

my $input = q[
{
   "dynamic_config" : 0,
   "x_contributors" : [
      "å¤§æ²¢ åå®",
      "Ãvar ArnfjÃ¶rÃ°"
   ]
}
];
eval { $json->decode($input) };
is $@, '', 'decodes default mojibake without error';

$json->utf8;
eval { $json->decode($input) };
is $@, '', 'decodes utf8 mojibake without error';

$json->utf8(0)->ascii;
eval { $json->decode($input) };
is $@, '', 'decodes ascii mojibake without error';

$json->ascii(0)->latin1;
eval { $json->decode($input) };
is $@, '', 'decodes latin1 mojibake without error';

$json->latin1(0)->binary;
eval { $json->decode($input) };
is $@, '', 'decodes binary mojibake without error';
