use Cpanel::JSON::XS;
no utf8;
use Test::More tests => 12;

my $xs = Cpanel::JSON::XS->new->latin1->allow_nonref;

is($xs->encode ("\x{12}\x{89}       "), "\"\\u0012\x{89}       \"");
is($xs->encode ("\x{12}\x{89}\x{abc}"), "\"\\u0012\x{89}\\u0abc\"");

is($xs->decode ("\"\\u0012\x{89}\""       ), "\x{12}\x{89}");
is($xs->decode ("\"\\u0012\x{89}\\u0abc\""), "\x{12}\x{89}\x{abc}");

is(Cpanel::JSON::XS->new->ascii->encode (["I ❤ perl"]),
   '["I \\u00e2\\u009d\\u00a4 perl"]', 'non-utf8 enc ascii');
is(Cpanel::JSON::XS->new->ascii->decode ('["I \\u00e2\\u009d\\u00a4 perl"]')->[0],
   "I \x{e2}\x{9d}\x{a4} perl", 'non-utf8 dec ascii');

is(Cpanel::JSON::XS->new->latin1->encode (["I \x{e2}\x{9d}\x{a4} perl"]),
   "[\"I \x{e2}\x{9d}\x{a4} perl\"]", 'non-utf8 enc latin1');
is(Cpanel::JSON::XS->new->latin1->decode ("[\"I \x{e2}\x{9d}\x{a4} perl\"]")->[0],
   "I \x{e2}\x{9d}\x{a4} perl", 'non-utf8 dec latin1');

SKIP: {
  skip "5.6", 2 if $] < 5.008;
  require Encode;
  # [RT #84244] complaint: JSON::XS double encodes to ["I â perl"]
  is(Cpanel::JSON::XS->new->utf8->encode ([Encode::decode_utf8("I \x{e2}\x{9d}\x{a4} perl")]),
     "[\"I \x{e2}\x{9d}\x{a4} perl\"]", 'non-utf8 enc utf8 [RT #84244]');
  is(Cpanel::JSON::XS->new->utf8->decode ("[\"I \x{e2}\x{9d}\x{a4} perl\"]")->[0],
     Encode::decode_utf8("I \x{e2}\x{9d}\x{a4} perl"), 'non-utf8 dec utf8');
}

is(Cpanel::JSON::XS->new->binary->encode (["I \x{e2}\x{9d}\x{a4} perl"]),
   '["I \xe2\x9d\xa4 perl"]', 'non-utf8 enc binary');
is(Cpanel::JSON::XS->new->binary->decode ('["I \xe2\x9d\xa4 perl"]')->[0],
   "I \x{e2}\x{9d}\x{a4} perl", 'non-utf8 dec binary');
