use strict;
use Test::More tests => 9;
use Cpanel::JSON::XS;

my $json = Cpanel::JSON::XS->new;

# disallow dupkeys
ok (!eval { $json->decode ('{"a":"b","a":"c"}') }); # y_object_duplicated_key.json
ok (!eval { $json->decode ('{"a":"b","a":"b"}') }); # y_object_duplicated_key_and_value.json

# relaxed allows dupkeys
$json->relaxed;
# y_object_duplicated_key.json
is (encode_json ($json->decode ('{"a":"b","a":"c"}')), '{"a":"c"}', 'relaxed');
# y_object_duplicated_key_and_value.json
is (encode_json ($json->decode ('{"a":"b","a":"b"}')), '{"a":"b"}', 'relaxed');

# turning off relaxed disallows dupkeys
$json->relaxed(0);
$json->allow_dupkeys; # but turn it on
is (encode_json ($json->decode ('{"a":"b","a":"c"}')), '{"a":"c"}', 'allow_dupkeys');
is (encode_json ($json->decode ('{"a":"b","a":"b"}')), '{"a":"b"}', 'allow_dupkeys');

# disallow dupkeys explicitly
$json->allow_dupkeys(0);
eval { $json->decode ('{"a":"b","a":"c"}') };
like ($@, qr/^Duplicate keys not allowed/, 'allow_dupkeys(0)');

# disallow dupkeys explicitly with relaxed
$json->relaxed;
$json->allow_dupkeys(0);
eval { $json->decode ('{"a":"b","a":"c"}') }; # the XS slow path
like ($@, qr/^Duplicate keys not allowed/, 'relaxed and allow_dupkeys(0)');

$json->allow_dupkeys;
$json->relaxed(0); # tuning off relaxed needs to turn off dupkeys
eval { $json->decode ('{"a":"b","a":"c"}') };
like ($@, qr/^Duplicate keys not allowed/, 'relaxed(0)');
