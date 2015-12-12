#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=305
# wrong compile-time Encode::XS &ascii_encoding
# fix in perl_init2_aaaa:
#  #include <dlfcn.h>
#  void *handle = dlopen(sv_list[5032].sv_u.svu_pv, RTLD_NOW|RTLD_NOLOAD); // <pathto/Encode.so>
#  void *ascii_encoding = dlsym(handle, "ascii_encoding");
#  SvIV_set(&sv_list[1], PTR2IV(ascii_encoding));  PVMG->iv

use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More;
if ($] < 5.007) {
  plan skip_all => "No Encode with perl-$]";
  exit;
} else {
  require Encode;
  plan tests => 3;
}
use Config;
my $ITHREADS = $Config{useithreads};

# fixed with 1.49_07 even for older Encode versions
my $todo = $Encode::VERSION lt '2.58' ? "Old Encode-$Encode::VERSION < 2.58 " : "New Encode-$Encode::VERSION >= 2.58 ";
#if ($ITHREADS and ($] > 5.015 or $] < 5.01)) {
#  $todo = "TODO $] thr ".$todo if $] < 5.020;
#}
#$todo = 'TODO 5.22 ' if $] > 5.021; # fixed with 1.52_13

my $cmt = '#305 compile-time Encode::XS encodings';
my $script = 'use constant ASCII => eval { require Encode; Encode::find_encoding("ASCII"); } || 0;
print ASCII->encode("www.google.com")';
my $exp = "www.google.com";
ctest(1, $exp, 'C,-O3', 'ccode305i', $script, $todo.'C '.$cmt);

$script = 'INIT{ sub ASCII { eval { require Encode; Encode::find_encoding("ASCII"); } || 0; }}
print ASCII->encode("www.google.com")';
ctest(2, $exp, 'C,-O3', 'ccode305i', $script, 'C run-time init');

# fixed with 1.49_07, and for 5.22 with 1.52_13
#$todo = $] > 5.021 ? 'TODO 5.22 ' : '';
ctest(3, $exp, 'C,-O3', 'ccode305i', <<'EOF', $todo.'C #365 compile-time Encode subtypes');
use constant JP => eval { require Encode; Encode::find_encoding("euc-jp"); } || 0;
print JP->encode("www.google.com")
EOF
