use lib '.';
use t::TestYAMLTests tests => 2;
use utf8;

is Dump("1234567890\n1234567890\n1234567890\n"), "--- |
  1234567890
  1234567890
  1234567890
", 'Literal Scalar';

is Dump("A\nB\nC\n"), q{--- "A\nB\nC\n"} . "\n", 'Double Quoted Scalar';
