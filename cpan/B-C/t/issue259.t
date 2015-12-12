#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=259
# enforce atttrbutes to be loaded before JSON::XS

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
eval "use JSON::XS;";
if ($@) {
  plan skip_all => "JSON::XS required for testing issue259" ;
} else {
  plan tests => 1;
}
use B::C ();
my $todo = ($B::C::VERSION ge '1.43_02' or $] < 5.009) ? "" : "TODO ";

ctestok(1,'C,-O3','ccode259i',<<'EOF',$todo.'attributes load-order #259');
use JSON::XS;
print q(ok) if q([false]) eq encode_json([\0]);
EOF
