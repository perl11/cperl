use Test::More tests => 13;
use utf8;
use Cpanel::JSON::XS;

is(Cpanel::JSON::XS->new->allow_nonref (1)->utf8 (1)->encode ("ü"), "\"\xc3\xbc\"");
is(Cpanel::JSON::XS->new->allow_nonref (1)->encode ("ü"), "\"ü\"");

is(Cpanel::JSON::XS->new->allow_nonref (1)->ascii (1)->utf8 (1)->encode (chr 0x8000), '"\u8000"');
is(Cpanel::JSON::XS->new->allow_nonref (1)->ascii (1)->utf8 (1)->pretty (1)->encode (chr 0x10402), "\"\\ud801\\udc02\"\n");

SKIP: {
  skip "5.6", 1 if $] < 5.008;
  eval { Cpanel::JSON::XS->new->allow_nonref (1)->utf8 (1)->decode ('"ü"') };
  like $@, qr/malformed UTF-8/;
}

is(Cpanel::JSON::XS->new->allow_nonref (1)->decode ('"ü"'), "ü");
is(Cpanel::JSON::XS->new->allow_nonref (1)->decode ('"\u00fc"'), "ü");
is(Cpanel::JSON::XS->new->allow_nonref (1)->decode ('"\ud801\udc02' . "\x{10204}\""), "\x{10402}\x{10204}");
is(Cpanel::JSON::XS->new->allow_nonref (1)->decode ('"\"\n\\\\\r\t\f\b"'), "\"\012\\\015\011\014\010");

my $love = $] < 5.008 ? "I \342\235\244 perl" : "I ❤ perl";
is(Cpanel::JSON::XS->new->ascii->encode ([$love]),
   $] < 5.008 ? '["I \u00e2\u009d\u00a4 perl"]' : '["I \u2764 perl"]', 'utf8 enc ascii');
is(Cpanel::JSON::XS->new->latin1->encode ([$love]),
      $] < 5.008 ? "[\"I \342\235\244 perl\"]" : '["I \u2764 perl"]', 'utf8 enc latin1');

SKIP: {
  skip "5.6", 1 if $] < 5.008;
  require Encode;
  # [RT #84244] wrong complaint: JSON::XS double encodes to ["I â¤ perl"]
  #             and with utf8 triple encodes it to ["I Ã¢ÂÂ¤ perl"]
  if ($Encode::VERSION < 2.40 or $Encode::VERSION >= 2.54) { # Encode stricter check: Cannot decode string with wide characters
    # see also http://stackoverflow.com/questions/12994100/perl-encode-pm-cannot-decode-string-with-wide-character
    $love = "I \342\235\244 perl";
  }
  my $s = Encode::decode_utf8($love); # User tries to double decode wide-char to unicode with Encode
  is(Cpanel::JSON::XS->new->utf8->encode ([$s]), "[\"I \342\235\244 perl\"]", 'utf8 enc utf8 [RT #84244]');
}
is(Cpanel::JSON::XS->new->binary->encode ([$love]), '["I \xe2\x9d\xa4 perl"]', 'utf8 enc binary');
