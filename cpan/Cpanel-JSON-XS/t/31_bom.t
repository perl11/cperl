# Detect BOM and possibly convert to UTF-8 and set UTF8 flag.
#
# https://tools.ietf.org/html/rfc7159#section-8.1
# JSON text SHALL be encoded in UTF-8, UTF-16, or UTF-32.
use Test::More ($] >= 5.008) ? (tests => 5) : (skip_all => "needs 5.8");;
use Cpanel::JSON::XS;
use Encode; # Currently required for <5.20
use utf8;
my $json = Cpanel::JSON::XS->new->utf8->allow_nonref;

# parser need to succeed, result should be valid
sub y_pass {
  my ($str, $name) = @_;
  my $result = $json->decode($str);
  my $expected = ["é"];
  is_deeply($result, $expected, "bom $name");
}

my @bom =
  (
   ["\xef\xbb\xbf[\"\303\251\"]",                       'UTF-8'],
   ["\xfe\xff\000\133\000\042\000\351\000\042\000\135", 'UTF16-LE'],
   ["\xff\xfe\133\000\042\000\351\000\042\000\135\000", 'UTF16-BE'],
   ["\xff\xfe\000\000\133\000\000\000\042\000\000\000\351\000\000\000\042\000\000\000\135\000\000\000",   'UTF32-LE'],
   ["\000\000\xfe\xff\000\000\000\133\000\000\000\042\000\000\000\351\000\000\000\042\000\000\000\135",   'UTF32-BE'],
  );

for my $bom (@bom) {
  y_pass(@$bom);
}
