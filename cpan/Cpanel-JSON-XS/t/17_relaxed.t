use Test::More $] < 5.008 ? (skip_all => "5.6") : (tests => 12);
use Cpanel::JSON::XS;

my $json = Cpanel::JSON::XS->new->relaxed;

is (encode_json ($json->decode (' [1,2, 3]')), '[1,2,3]');
is (encode_json ($json->decode ('[1,2, 4 , ]')), '[1,2,4]');
ok (!eval { $json->decode ('[1,2, 3,4,,]') });
ok (!eval { $json->decode ('[,1]') });

is (encode_json ($json->decode (' {"1":2}')), '{"1":2}' );
is (encode_json ($json->decode ('{"1":2,}')), '{"1":2}');
is (encode_json ($json->decode (q({'1':2}))), '{"1":2}'); # allow_singlequotes
is (encode_json ($json->decode ('{a:2}')),    '{"a":2}'); # allow_barekey
ok (!eval { $json->decode ('{,}') });

is (encode_json ($json->decode ("[1#,2\n ,2,#  ]  \n\t]")), '[1,2]');

is (encode_json ($json->decode ("[\"Hello\tWorld\"]")), '["Hello\tWorld"]');

is (encode_json ($json->decode ('{"a b":2}')),    '{"a b":2}'); # allow_barekey
