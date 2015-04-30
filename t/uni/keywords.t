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

plan( tests => 7 );

{
  my $h = eval '{main ⇒ 1}';
  diag $@ if $@;
  ok %$h, "unicode => HASHBRACK";
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
ok $a, 'unicode / DIVIDE';
