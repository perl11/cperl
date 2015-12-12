#! /usr/bin/env perl
# GH #208 utf8 symbols and stashes > 5.16
# get_cvn_flags, gv_fetchpvn_flags, gv_stashpvn_flags
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
plan skip_all => 'unicode symbols with 5.16' if $] < 5.016;
plan tests => 3;
use B::C ();
my $todo = ($B::C::VERSION lt '1.52_03' ? "TODO " : "");

ctestok(1,'C','ccode206i',<<'EOF',$todo.'#206 utf8 symbols');
use utf8;package 텟ţ::ᴼ; sub ᴼ_or_Ḋ { "ok" } print ᴼ_or_Ḋ;
EOF

ctestok(2,'C,-O3','ccode206i',<<'EOF',$todo.'#206 utf8 symbols');
use utf8;package 텟ţ::ᴼ; sub ᴼ_or_Ḋ { "ok" } print ᴼ_or_Ḋ;
EOF

ctestok(3,'C,-O3','ccode206i',<<'EOF',$todo.'#206 utf8 symbols');
use utf8;package ƂƂƂƂ; sub ƟK { "ok" }
package ƦƦƦƦ; use base "ƂƂƂƂ"; my $x = bless {}, "ƦƦƦƦ";
print $x->ƟK();
EOF
