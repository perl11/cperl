use Test::More;
BEGIN {
  eval "require JSON && require JSON::XS;";
  if ($@) {
    plan skip_all => "JSON::XS and JSON required for testing interop";
    exit 0;
  } else {
    plan tests => 4;
  }
  $ENV{PERL_JSON_BACKEND} = 0;
}

use JSON (); # limitation: for interop with JSON load JSON before Cpanel::JSON::XS
use Cpanel::JSON::XS ();

my $boolstring = q({"is_true":true});
my $js;
{
    require JSON::XS;
    my $json = JSON::XS->new;
    $js = $json->decode( $boolstring );
    # bless { is_true => 1 }, "JSON::PP::Boolean"
}
my $cjson = Cpanel::JSON::XS->new->allow_blessed;

is($cjson->encode( $js ), $boolstring) or diag "\$JSON::XS::VERSION=$JSON::XS::VERSION";

{
    local $ENV{PERL_JSON_BACKEND} = 'JSON::PP';
    my $json = JSON->new;
    $js = $json->decode( $boolstring );
    # bless { is_true => 1 }, "JSON::PP::Boolean"
}

is ($cjson->encode( $js ), $boolstring) or diag "\$JSON::VERSION=$JSON::VERSION";

{
    local $ENV{PERL_JSON_BACKEND} = 'JSON::XS';
    my $json = JSON->new;
    $js = $json->decode( $boolstring );
    # bless { is_true => 1}, "Types::Serialiser"
}

is($cjson->encode( $js ), $boolstring) or diag "\$JSON::VERSION=$JSON::VERSION";

# issue18: support Types::Serialiser without allow_blessed (if JSON-XS-3.x is loaded)
$js = $cjson->decode( $boolstring );
is ($cjson->encode( $js ), $boolstring) or diag(ref $js->{is_true});

