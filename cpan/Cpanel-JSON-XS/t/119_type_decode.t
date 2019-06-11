use strict;
use warnings;

use Cpanel::JSON::XS;
use Cpanel::JSON::XS::Type;

use Test::More tests => 24;

my $cjson = Cpanel::JSON::XS->new->allow_nonref;

{
    my $value = $cjson->decode('false', my $type);
    ok(!$value);
    is($type, JSON_TYPE_BOOL);
}

{
    my $value = $cjson->decode('true', my $type);
    ok($value);
    is($type, JSON_TYPE_BOOL);
}

{
    my $value = $cjson->decode('0', my $type);
    is($value, 0);
    is($type, JSON_TYPE_INT);
}

{
    my $value = $cjson->decode('0.0', my $type);
    is($value, 0.0);
    is($type, JSON_TYPE_FLOAT);
}

{
    my $value = $cjson->decode('"0"', my $type);
    is($value, '0');
    is($type, JSON_TYPE_STRING);
}

{
    my $value = $cjson->decode('null', my $type);
    is($value, undef);
    is($type, JSON_TYPE_NULL);
}

SKIP: {
    skip "in 5.6 true is the string '1'",2 if $] < 5.008;
    my $struct = $cjson->decode('[null,1,1.1,"1",[0],true]', my $type);
    is_deeply($struct, [undef, 1, 1.1, '1', [0], 1]);
    is_deeply($type, [JSON_TYPE_NULL, JSON_TYPE_INT, JSON_TYPE_FLOAT, JSON_TYPE_STRING, [JSON_TYPE_INT], JSON_TYPE_BOOL]);
}

SKIP: {
    skip "in 5.6 true is the string '1'",2 if $] < 5.008;
    my $struct = $cjson->decode('{"key1":true,"key2":false,"key3":null,"key4":"0","key5":0,"key6":["string",1.1],"key7":{"key8":-1.0,"key9":-1}}', my $type);
    is_deeply($struct, { key1 => 1, key2 => 0, key3 => undef, key4 => 0, key5 => 0, key6 => [ 'string', 1.1 ], key7 => { key8 => -1.0, key9 => -1 } });
    is_deeply($type, { key1 => JSON_TYPE_BOOL, key2 => JSON_TYPE_BOOL, key3 => JSON_TYPE_NULL, key4 => JSON_TYPE_STRING, key5 => JSON_TYPE_INT, key6 => [ JSON_TYPE_STRING, JSON_TYPE_FLOAT ], key7 => { key8 => JSON_TYPE_FLOAT, key9 => JSON_TYPE_INT } });
}

{
    my $value = Cpanel::JSON::XS::decode_json('false', 1, my $type);
    ok(!$value);
    is($type, JSON_TYPE_BOOL);
}

{
    my $value = Cpanel::JSON::XS::decode_json('0', 1, my $type);
    is($value, 0);
    is($type, JSON_TYPE_INT);
}

{
    my $value = Cpanel::JSON::XS::decode_json('1000000000000000000000000', 1, my $type);
    is($value, '1000000000000000000000000');
    is($type, JSON_TYPE_INT);
}

{
    my $value = Cpanel::JSON::XS::decode_json('"1000000000000000000000000"', 1, my $type);
    is($value, '1000000000000000000000000');
    is($type, JSON_TYPE_STRING);
}
