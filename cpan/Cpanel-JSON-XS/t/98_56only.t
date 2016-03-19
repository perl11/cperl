use Test::More tests => 4;
# $] < 5.008 ? (tests => 4) : (skip_all => "5.6 only");
use Cpanel::JSON::XS;

{
    my $formref = {
        'cpanel_apiversion' => 1,
        'utf8'       => 'אאאאאאאխ"',
        'func'       => 'phpmyadminlink',
        'module'     => 'Cgi',
        "включен"    => "日本語"
    };

    ok( decode_json( encode_json($formref) ),
	"Cpanel::JSON::XS :: round trip untied utf8 with int" );
}

{
    my $formref = {
        'cpanel_apiversion' => 1,
        'utf8'       => 'română',
        'func'       => 'phpmyadminlink',
        'module'     => 'Cgi',
        "включен"    => "日本語"
    };

    ok( decode_json( encode_json($formref) ),
        "JSON::XS :: round trip utf8 complex" );
}

my $json = Cpanel::JSON::XS->new;
$js  = q|[-12.34]|;
$obj = $json->decode($js);
is($obj->[0], -12.34, 'digit -12.34');
$js = $json->encode($obj);
is($js,'[-12.34]', 'digit -12.34');
