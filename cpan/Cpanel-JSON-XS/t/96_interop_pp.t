use Test::More;
BEGIN {
  # for cperl CORE
  eval "require JSON::PP;";
  if ($@) {
    plan skip_all => "JSON::PP required for testing interop_pp";
    exit 0;
  } else {
    plan tests => 3;
  }
  $ENV{PERL_JSON_BACKEND} = 0;
}

use JSON::PP (); # limitation: for interop with JSON load JSON::PP before Cpanel::JSON::XS
use Cpanel::JSON::XS ();

my $cjson = Cpanel::JSON::XS->new;
my $boolstring = q({"is_true":true});
my $js;
{
    local $ENV{PERL_JSON_BACKEND} = 'JSON::PP';
    my $json = JSON::PP->new;
    $js = $json->decode( $boolstring );
    # bless { is_true => 1 }, "JSON::PP::Boolean"
}

is ($cjson->encode( $js ), $boolstring) or diag "\$JSON::VERSION=$JSON::VERSION";

{
    local $ENV{PERL_JSON_BACKEND} = 'Cpanel::JSON::XS';
    my $json = JSON::PP->new;
    $js = $json->decode( $boolstring );
    # bless { is_true => 1}, "Types::Serialiser"
}

is($cjson->encode( $js ), $boolstring)
  or diag "\$JSON::PP::VERSION=$JSON::PP::VERSION";

$js = $cjson->decode( $boolstring );
is ($cjson->encode( $js ), $boolstring) or diag(ref $js->{is_true});

