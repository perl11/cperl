#! /usr/bin/env perl
# GH #318 utf8 labels

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
if ($] < 5.016) {
  plan skip_all => "No utf8 labels perl-$]";
  exit;
} else {
  plan tests => 3;
}

use B::C ();
# fixed with 1.52_16
my $todo = $B::C::VERSION lt '1.52_16' ? "TODO " : "";
my $cmt = '#318 utf8 labels';
my $script = 'use utf8; ＬＯＯＰ: { last ＬＯＯＰ } print qq(ok\n)';

ctestok(1, 'C,-O3', 'ccode318i', $script, $todo."C $cmt");
ctestok(2, 'CC', 'ccode318i', $script, $todo."CC $cmt");

TODO: {
   local $TODO = 'not yet';
   plctestok(3, "ccode318i", $script, "BC $cmt");
}
