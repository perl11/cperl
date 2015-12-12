use strict;
use Test::More tests => 17;
use Cpanel::JSON::XS ();

my $booltrue  = q({"is_true":true});
my $boolfalse = q({"is_false":false});
# since 5.16 yes/no is !0/!1, but for earlier perls we need to use a BoolSV
my $a   = 0;
my $yes = do{$a==0}; # < 5.16 !0 is not sv_yes
my $no  = do{$a==1}; # < 5.16 !1 is not sv_no
my $yesno     = [ $yes, $no ]; # native yes/no. YAML::XS compatible
my $truefalse = "[true,false]";
my $cjson = Cpanel::JSON::XS->new;
my $true  = Cpanel::JSON::XS::true;
my $false = Cpanel::JSON::XS::false;

# from JSON::MaybeXS
my $data = $cjson->decode('{"foo": true, "bar": false, "baz": 1}');
ok($cjson->is_bool($data->{foo}), 'true decodes to a bool')
  or diag 'true is: ', explain $data->{foo};
ok($cjson->is_bool($data->{bar}), 'false decodes to a bool')
  or diag 'false is: ', explain $data->{bar};
ok(!$cjson->is_bool($data->{baz}), 'int does not decode to a bool')
  or diag 'int is: ', explain $data->{baz};

my $js = $cjson->decode( $booltrue );
is( $cjson->encode( $js ), $booltrue);
ok( $js->{is_true} == $true );
ok( Cpanel::JSON::XS::is_bool($js->{is_true}) );

$js = $cjson->decode( $boolfalse );
is( $cjson->encode( $js ), $boolfalse );
ok( $js->{is_false} == $false );
ok( Cpanel::JSON::XS::is_bool($js->{is_false}) );

is( $cjson->encode( [\1,\0] ), $truefalse  );
is( $cjson->encode( [ $true, $false] ),
    $truefalse );

TODO: {
  local $TODO = 'GH #39';
  is( $cjson->encode( $yesno ), $truefalse, "map yes/no to [true,false]");
}
$js = $cjson->decode( $truefalse );
ok ($js->[0] == $true,  "decode true to yes");
ok ($js->[1] == $false, "decode false to no");
ok( Cpanel::JSON::XS::is_bool($js->[0]) );
ok( Cpanel::JSON::XS::is_bool($js->[1]) );

# GH #53
ok( !Cpanel::JSON::XS::is_bool( [] ) );
