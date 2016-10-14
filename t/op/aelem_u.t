#!./perl
# Test unchecked, shaped arrays, untyped, and typed.

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
}
plan( tests => 24 );
use coretypes;
use cperl;
use v5.22;

my @a[5];
my Int @i[5];
my int @in[5];
my Num @n[5];
my num @nn[5]; # needs a 64-bit system for true nativeness
my Str @s[5];
my str @ss[5];

# @a consists of 5x undef
ok(!defined $a[0] && !defined $a[4], '@a[5] initialized to undef');
is(scalar @i, 5,   'Int @i[5] length 5');
ok(defined $i[4] && $i[4] == 0,   'Int $i[4] initialized to 0');
ok(defined $n[4] && $n[4] == 0.0, 'Num $n[4] initialized to 0.0');
ok(defined $s[4] && $s[4] eq "",  'Str $s[4] initialized to ""');

eval 'defined $a[5];';
like ($@, qr/^Array index out of bounds \@a\[5\]/, 'Array index out of bounds $a[5]');

# caught in ck_pad when a targ was already assigned, or later in rpeep
eval 'push @a, 1;';
like ($@, qr/^Invalid modification of shaped array: push/, "invalid push");
eval 'push @a, 1,2,3;'; # only at run-time yet
like ($@, qr/^Invalid modification of shaped array: push/, "invalid multi push");
eval 'pop @a;';
like ($@, qr/^Invalid modification of shaped array: pop \@a/, "invalid pop");
eval 'shift @a, 1;';
like ($@, qr/^Invalid modification of shaped array: shift \@a/, "invalid shift");
eval 'unshift @a;';
like ($@, qr/^Invalid modification of shaped array: unshift \@a/, "invalid unshift");
# This is deferred to run-time
eval { splice @a; };
like ($@, qr/^Invalid modification of shaped array: splice/, "invalid splice (run-time)");

# aelemfast_lex_u
$a[0] = 1;
is($a[0], 1, "set const w/o read-only");
$a[-1] = 2; # compile-time changed to 4
is($a[4], 2, "negative constant index");

# mderef_u:
my $i = 0;
$a[$i] = 1;
is($a[$i], 1, "set");
$i = -1;
$a[$i] = 2; # run-time logic
is($a[4], 2, "negative run-time index");

# multi mderef_u
$a[1]->[5] = 1;
is($a[1]->[5], 1, "set mderef_u");
$a[-2]->[0] = 2;
is($a[3]->[0], 2, "negative mderef_u");
eval '$a[5]->[1];';
like ($@, qr/^Array index out of bounds \@a\[5\]/, "compile-time mderef oob");

# multidim mderef_u
$a[2][5] = 1;
is($a[2][5], 1, "set multi mderef_u");
$a[-2][0] = 2;
is($a[3][0], 2, "negative multi mderef_u");

eval '$a[5][1];';
like ($@, qr/^Array index out of bounds \@a\[5\]/, "compile-time mderef oob");

# eliminating loop out-of-bounds checks.
# how to test this? via dump/-Dt?
my @b = (0..4);
for (0..$#b) { $b[$_] };       # _u
for (0..$#b) { $a[$_] };       # wrong array
for my $i (0..$#b) { $b[$i] }; # _u
my $j = 0;
for my $i (0..$#b) { $b[$j] }; # wrong index: lex
for my $our (0..$#b) { $b[$i] }; # wrong index: lex
for (0..$#b) { $b[$_+1] };     # wrong index: expr
{ no strict;
  for $k (0..$#b) { $b[$k] };    # _u
  for $k (0..$#b) { $b[$j] };    # wrong index: glob
}

for (0..$#b) { $b[$_] = 0; }       # mderef_u gvsv
for my $i (0..$#b) { $b[$i] = 0; } # mderef_u padsv

for (0..$#a) { $a[$_] };       # shaped + mderef_u

{
  my @a[] = (1,2,3);
  ok(defined $a[0] && $a[2]==3, 'shaped @a[] initialized');
  eval 'defined $a[4];';
  like ($@, qr/^Array index out of bounds \@a\[4\]/, 'Array index out of bounds $a[4]');
}
