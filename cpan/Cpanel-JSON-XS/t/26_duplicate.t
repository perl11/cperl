use Test::More tests => 4;
use Cpanel::JSON::XS;

my $json = Cpanel::JSON::XS->new;

# disallow dupkeys:
ok (!eval { $json->decode ('{"a":"b","a":"c"}') }); # y_object_duplicated_key.json
ok (!eval { $json->decode ('{"a":"b","a":"b"}') }); # y_object_duplicated_key_and_value.json

$json->relaxed;
is (encode_json ($json->decode ('{"a":"b","a":"c"}')), '{"a":"c"}'); # y_object_duplicated_key.json
is (encode_json ($json->decode ('{"a":"b","a":"b"}')), '{"a":"b"}'); # y_object_duplicated_key_and_value.json

