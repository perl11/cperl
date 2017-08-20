#!./perl
#
# parse new unicode ops and keyword variants
#

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
}
use utf8;
use 5.021011;

plan( tests => 16 );

{
  my $h = eval '{main ⇒ 1}';
  diag $@ if $@;
  ok %$h, "unicode => FATCOMMA";
}

package mypkg {
  my $a = "ok";
  sub test { $a }
}
my $obj = bless {}, "mypkg";
ok eval '$obj→test', "unicode -> ARROW";

my @a = eval 'sort {$a⇔$b} (2,1)';
ok $a[0] == 1, 'unicode <=> NCMP';

$a = eval '1≠2';
ok $a, 'unicode != NE';
$a = eval '1≤2';
ok $a, 'unicode <= LE';
$a = eval '2≥1';
ok $a, 'unicode >= GE';
$a = eval '10÷2';
is ($a, 5, 'unicode / DIVIDE');
$a = eval '10⋅2';
is($a, 20, 'unicode * DOT');

eval 'my $x=2;@a=($x⁰,2¹,$x²,2³,$x⁴,$x⁵,$x⁶,$x⁷,$x⁸,$x⁹);';
ok(eq_array(\@a, [1,2,4,8,16,32,64,128,256,512]), 'unicode pow 0-9 superscripts');
$a = eval '(2²)⁵';
is($a, 1024, 'unicode pow stacked');
$a = eval '2²⁵';
is($@, '', 'unicode pow multidigits no error');
is($a, 33554432, 'unicode pow 2 digits composed: 2**25');

# no error, compose the first two, and stack it with the next single or pair.
$a = eval '2⁰²⁵'; # => (2**02)**5
is($a, 1024, 'unicode pow 3 digits composed (2**02)**5');
is($@, '', 'no error with pow >3 digits ');

{
  no utf8;
  eval '2⁴';
  is($@, 'Unrecognized character \xE2; marked by <-- HERE after 2<-- HERE near column 2 at (eval 21) line 1.'."\n", 'throws error without utf8');
}

my $b = 1;
$a = eval '(1+$b)²';
is($a, 4, 'unicode () pow 2');

