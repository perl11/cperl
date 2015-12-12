#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=235
# branch empty-cv: assert !CvCVGV_RC(cv) in function Perl_newATTRSUB. again.
#   skip saving empty CVs
# But note #246 edge-case conflict: skipping empty CVs needs still prototypes
#   to be stored if existing, to be able to catch prototype errors.
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;

use B::C;
my $when = "1.42_61";
ctest(1,'6','C,-O3,-UCarp','ccode235i',<<'EOF',($B::C::VERSION lt $when ? "TODO #235 assert !CvCVGV_RC(cv)" : "#235 bytes::length"));
BEGIN{$INC{Carp.pm}++}
my ($d,$ol); $d = pack("U*", 0xe3, 0x81, 0xAF); { use bytes; $ol = bytes::length($d) } print $ol
EOF

ctest(2,'^Not enough arguments for main','C,-O3','ccode235i',<<'EOF',"#246 missing proto decl for empty subs");
sub foo($\@); eval q/foo "s"/; print $@
EOF
