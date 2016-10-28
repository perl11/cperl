# Detect BOM and possibly convert to UTF-8 and set UTF8 flag.
#
# https://tools.ietf.org/html/rfc7159#section-8.1
# JSON text SHALL be encoded in UTF-8, UTF-16, or UTF-32.
use Test::More tests => 5;
use Cpanel::JSON::XS;
my $json = Cpanel::JSON::XS->new->utf8->allow_nonref;

# parser need to succeed, result should be valid
sub y_pass {
  my ($str, $name) = @_;
  my $result = $json->decode($str);
  ok(ref $result eq 'HASH', "bom $name");
}
# without multibyte BOM support, just UTF-8
sub y_pass_nobom {
  my ($str, $name) = @_;
  my $result = eval { $json->decode($str) };
  like($@, qr/^Cannot handle multibyte BOM yet/, "bom $name");
  #is($result, undef, "undef result bom $name");
}

my @bom = (["\xef\xbb\xbf{}",               'UTF-8'],
           ["\xff\xfe\0{\0}",               'UTF16-LE'],
           ["\xfe\xff{\0}\0",               'UTF16-BE'],
           ["\xff\xfe\0\0\0\0\0{\0\0\0}",   'UTF32-LE'],
           ["\0\0\xfe\xff{\0\0\0}\0\0\0",   'UTF32-BE'],
          );

y_pass(@{$bom[0]});
shift @bom;
for my $bom (@bom) {
  y_pass_nobom(@$bom);
}
