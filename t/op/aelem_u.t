#!./perl
# Test unchecked, shaped arrays, untyped, and typed.

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
}
plan( tests => 16 );
use coretypes;
use v5.23;

my @a[5];
my Int @i[5];
my int @in[5];
my Num @n[5];
my num @nn[5];
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

$a[0] = 1;
is($a[0], 1, "set const w/o read-only");
$a[-1] = 2; # compile-time changed to 4
is($a[4], 2, "negative constant index");
my $i = 0;
$a[$i] = 1;
is($a[$i], 1, "set");
$i = -1;
$a[$i] = 2; # run-time logic
is($a[4], 2, "negative run-time index");

# eliminating loop out-of-bounds:
my @b = (0..4);
for (0..$#b) { $b[$_] };       # _u
for (0..$#b) { $a[$_] };       # wrong array
for my $i (0..$#b) { $b[$i] }; # _u
my $j = 0;
for my $i (0..$#b) { $b[$j] }; # wrong index: lex
for my $our (0..$#b) { $b[$i] }; # _u
for (0..$#b) { $b[$_+1] };     # wrong index: expr
{ no strict;
  for $k (0..$#b) { $b[$k] };    # _u
  for $k (0..$#b) { $b[$j] };    # wrong index: glob
}
