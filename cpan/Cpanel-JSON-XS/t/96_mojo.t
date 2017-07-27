use Test::More;
BEGIN {
  eval "require Mojo::JSON;";
  if ($@) {
    plan skip_all => "Mojo::JSON required for testing interop";
    exit 0;
  }
  if (!defined &Mojo::JSON::decode_json) {
    plan skip_all => "Mojo::JSON::decode_json required for testing interop";
    exit 0;
  }
  plan tests => 9;
}

use Mojo::JSON ();
use Cpanel::JSON::XS ();

my $booltrue  = q({"is_true":true});
my $boolfalse = q({"is_false":false});
my $yesno = [ !1, !0 ];
my $js = Mojo::JSON::decode_json( $booltrue );
is( $js->{is_true}, 1, 'true == 1' );
ok( $js->{is_true}, 'ok true');

my $cjson = Cpanel::JSON::XS->new;
is($cjson->encode( $js ), $booltrue, 'can encode Mojo true')
  or diag "\$Mojolicious::VERSION=$Mojolicious::VERSION,".
  " \$Cpanel::JSON::XS::VERSION=$Cpanel::JSON::XS::VERSION";

$js = Mojo::JSON::decode_json( $boolfalse );
is( $cjson->encode( $js ), $boolfalse, 'can encode Mojo false' );
is( $js->{is_false}, 0 ,'false == 0');
ok( !$js->{is_false}, 'ok !false');

my $mj = Mojo::JSON::encode_json( $yesno );
$js = $cjson->decode( $mj );

# fragile
ok( $js->[0] eq '' or $js->[0] == 0 or !$js->[0], 'can decode Mojo false' );
is( $js->[1], 1,  'can decode Mojo true' );
# Note this is fragile. it depends on the internal representation of booleans.
# It can also be ['0', '1']
if ($js->[0] eq '') {
  is_deeply( $js, ['', 1], 'can decode Mojo booleans' )
    or diag( $mj, $js );
} else {
 TODO: {
    local $TODO = 'fragile false => "0"';
    is_deeply( $js, ['', 1], 'can decode Mojo booleans' )
      or diag( $mj, $js );
  }
}
