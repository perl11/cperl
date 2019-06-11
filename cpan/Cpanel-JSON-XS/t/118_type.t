use strict;
use warnings;

use Config;

use Cpanel::JSON::XS;
use Cpanel::JSON::XS::Type;

my $have_weaken;
BEGIN {
    if (eval { require Scalar::Util }) {
        Scalar::Util->import('weaken');
        $have_weaken = 1;
    }
}

use Test::More tests => 307;

my $cjson = Cpanel::JSON::XS->new->canonical->allow_nonref->require_types;

foreach my $false (Cpanel::JSON::XS::false, undef, 0, 0.0, 0E0, !!0, !1, "0", "", \0) {
    is($cjson->encode($false, JSON_TYPE_BOOL), 'false');
}

foreach my $true (Cpanel::JSON::XS::true, 1, !!1, !0, 2, 3, 100, -1, -100, 1.0, 1.5, 1E1, "0E0", "0 but true", "1", "2", "100", "-1", "-1", "false", "true", "string", \1) {
    is($cjson->encode($true, JSON_TYPE_BOOL), 'true');
    is($cjson->encode($true, JSON_TYPE_BOOL_OR_NULL), 'true');
}

foreach my $zero (0, 0.0, 0E0, "0") {
    is($cjson->encode($zero, JSON_TYPE_BOOL), 'false');
    is($cjson->encode($zero, JSON_TYPE_INT), '0');
    is($cjson->encode($zero, JSON_TYPE_FLOAT), '0.0');
    is($cjson->encode($zero, JSON_TYPE_STRING), '"0"');
    is($cjson->encode($zero, JSON_TYPE_BOOL_OR_NULL), 'false');
    is($cjson->encode($zero, JSON_TYPE_INT_OR_NULL), '0');
    is($cjson->encode($zero, JSON_TYPE_FLOAT_OR_NULL), '0.0');
    is($cjson->encode($zero, JSON_TYPE_STRING_OR_NULL), '"0"');
}

foreach my $ten (10, 10.0, 1E1, "10") {
    is($cjson->encode($ten, JSON_TYPE_BOOL), 'true');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_BOOL)), 'true');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_BOOL, [])), 'true');
    is($cjson->encode($ten, JSON_TYPE_INT), '10');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_INT)), '10');
    is($cjson->encode($ten, json_type_anyof([], JSON_TYPE_INT)), '10');
    is($cjson->encode($ten, JSON_TYPE_FLOAT), '10.0');
    is($cjson->encode($ten, json_type_anyof({}, JSON_TYPE_FLOAT)), '10.0');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_FLOAT, {})), '10.0');
    is($cjson->encode($ten, JSON_TYPE_STRING), '"10"');
    is($cjson->encode($ten, json_type_anyof([], JSON_TYPE_STRING, {})), '"10"');
    is($cjson->encode($ten, json_type_anyof({}, JSON_TYPE_STRING, [])), '"10"');
    is($cjson->encode($ten, JSON_TYPE_BOOL_OR_NULL), 'true');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_BOOL_OR_NULL)), 'true');
    is($cjson->encode($ten, json_type_anyof([], JSON_TYPE_BOOL_OR_NULL)), 'true');
    is($cjson->encode($ten, JSON_TYPE_INT_OR_NULL), '10');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_INT_OR_NULL)), '10');
    is($cjson->encode($ten, json_type_anyof({}, JSON_TYPE_INT_OR_NULL)), '10');
    is($cjson->encode($ten, JSON_TYPE_FLOAT_OR_NULL), '10.0');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_FLOAT_OR_NULL)), '10.0');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_FLOAT_OR_NULL, [])), '10.0');
    is($cjson->encode($ten, JSON_TYPE_STRING_OR_NULL), '"10"');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_STRING_OR_NULL)), '"10"');
    is($cjson->encode($ten, json_type_anyof(JSON_TYPE_STRING_OR_NULL, {})), '"10"');
}

is($cjson->encode(Cpanel::JSON::XS::false, JSON_TYPE_BOOL), 'false');
is($cjson->encode(Cpanel::JSON::XS::false, JSON_TYPE_INT), '0');
is($cjson->encode(Cpanel::JSON::XS::false, JSON_TYPE_FLOAT), '0.0');
is($cjson->encode(Cpanel::JSON::XS::false, JSON_TYPE_STRING), '"false"');
is($cjson->encode(Cpanel::JSON::XS::false, json_type_anyof([], {}, JSON_TYPE_BOOL)), 'false');

is($cjson->encode(Cpanel::JSON::XS::true, JSON_TYPE_BOOL), 'true');
is($cjson->encode(Cpanel::JSON::XS::true, JSON_TYPE_INT), '1');
is($cjson->encode(Cpanel::JSON::XS::true, JSON_TYPE_FLOAT), '1.0');
is($cjson->encode(Cpanel::JSON::XS::true, JSON_TYPE_STRING), '"true"');
is($cjson->encode(Cpanel::JSON::XS::true, json_type_anyof([], {}, JSON_TYPE_BOOL)), 'true');

is($cjson->encode(undef, JSON_TYPE_BOOL_OR_NULL), 'null');
is($cjson->encode(undef, JSON_TYPE_INT_OR_NULL), 'null');
is($cjson->encode(undef, JSON_TYPE_FLOAT_OR_NULL), 'null');
is($cjson->encode(undef, JSON_TYPE_STRING_OR_NULL), 'null');
is($cjson->encode(undef, json_type_null_or_anyof([])), 'null');
is($cjson->encode(undef, json_type_null_or_anyof({})), 'null');

is($cjson->encode(int("NaN"), JSON_TYPE_INT), '0');
is($cjson->encode('NaN', JSON_TYPE_INT), '0');

if ($Config{ivsize} == 4) {
  # values around signed IV_MAX should work correctly as they can be represented by unsigned UV
  is($cjson->encode( '2147483646', JSON_TYPE_INT),  '2147483646');  #  2^31-2
  is($cjson->encode( '2147483647', JSON_TYPE_INT),  '2147483647');  #  2^31-1
  is($cjson->encode( '2147483648', JSON_TYPE_INT),  '2147483648');  #  2^31
  is($cjson->encode( '2147483649', JSON_TYPE_INT),  '2147483649');  #  2^31+1
  is($cjson->encode( '2147483650', JSON_TYPE_INT),  '2147483650');  #  2^31+2

  # values up to signed IV_MIN should work correctly too
  is($cjson->encode('-2147483646', JSON_TYPE_INT), '-2147483646');  # -2^31+2
  is($cjson->encode('-2147483647', JSON_TYPE_INT), '-2147483647');  # -2^31+1
  is($cjson->encode('-2147483648', JSON_TYPE_INT), '-2147483648');  # -2^31

  # values up to unsigned UV_MAX should work correctly too
  is($cjson->encode( '4294967294', JSON_TYPE_INT),  '4294967294');  #  2^32-2
  is($cjson->encode( '4294967295', JSON_TYPE_INT),  '4294967295');  #  2^32-1

  # those values are rounded to unsigned UV_MAX or signed IV_MIN
  is($cjson->encode( '4294967296', JSON_TYPE_INT),  '4294967295');  #  2^32
  is($cjson->encode( '4294967297', JSON_TYPE_INT),  '4294967295');  #  2^32+1
  is($cjson->encode( '4294967298', JSON_TYPE_INT),  '4294967295');  #  2^32+2
  is($cjson->encode('-2147483649', JSON_TYPE_INT), '-2147483648');  # -2^31-1
  is($cjson->encode('-2147483650', JSON_TYPE_INT), '-2147483648');  # -2^31-2

  # those floating point values are rounded to unsigned UV_MAX or signed IV_MIN too
  is($cjson->encode( 4294967296.5, JSON_TYPE_INT),  '4294967295');  #  2^32
  is($cjson->encode( 4294967297.5, JSON_TYPE_INT),  '4294967295');  #  2^32+1
  is($cjson->encode( 4294967298.5, JSON_TYPE_INT),  '4294967295');  #  2^32+2
  is($cjson->encode(-2147483649.5, JSON_TYPE_INT), '-2147483648');  # -2^31-1
  is($cjson->encode(-2147483650.5, JSON_TYPE_INT), '-2147483648');  # -2^31-2

  is($cjson->encode(  int( 'Inf'), JSON_TYPE_INT), ($] >= 5.008 && $] < 5.008008) ? '0' :  '4294967295');
  is($cjson->encode(  int('-Inf'), JSON_TYPE_INT), ($] >= 5.008 && $] < 5.008008) ? '0' : '-2147483648');

  is($cjson->encode(        'Inf', JSON_TYPE_INT),  '4294967295');
  is($cjson->encode(       '-Inf', JSON_TYPE_INT), '-2147483648');
  is($cjson->encode(      9**9**9, JSON_TYPE_INT),  '4294967295');
  is($cjson->encode(     -9**9**9, JSON_TYPE_INT), '-2147483648');
} else {
SKIP: {
  skip "unknown ivsize $Config{ivsize}", 26 if $Config{ivsize} != 8;

  # values around signed IV_MAX should work correctly as they can be represented by unsigned UV
  is($cjson->encode( '9223372036854775806', JSON_TYPE_INT),  '9223372036854775806');  #  2^63-2
  is($cjson->encode( '9223372036854775807', JSON_TYPE_INT),  '9223372036854775807');  #  2^63-1
  is($cjson->encode( '9223372036854775808', JSON_TYPE_INT),  '9223372036854775808');  #  2^63
  is($cjson->encode( '9223372036854775809', JSON_TYPE_INT),  '9223372036854775809');  #  2^63+1
  is($cjson->encode( '9223372036854775810', JSON_TYPE_INT),  '9223372036854775810');  #  2^63+2

  # values up to signed IV_MIN should work correctly too
  is($cjson->encode('-9223372036854775806', JSON_TYPE_INT), '-9223372036854775806');  # -2^63+2
  is($cjson->encode('-9223372036854775807', JSON_TYPE_INT), '-9223372036854775807');  # -2^63+1
  is($cjson->encode('-9223372036854775808', JSON_TYPE_INT), '-9223372036854775808');  # -2^63

  # values up to unsigned UV_MAX should work correctly too
  is($cjson->encode('18446744073709551614', JSON_TYPE_INT), '18446744073709551614');  #  2^64-2
  is($cjson->encode('18446744073709551615', JSON_TYPE_INT), '18446744073709551615');  #  2^64-1

  # those values are rounded to unsigned UV_MAX or signed IV_MIN
  is($cjson->encode('18446744073709551616', JSON_TYPE_INT), '18446744073709551615');  #  2^64
  is($cjson->encode('18446744073709551617', JSON_TYPE_INT), '18446744073709551615');  #  2^64+1
  is($cjson->encode('18446744073709551618', JSON_TYPE_INT), '18446744073709551615');  #  2^64+2
  is($cjson->encode('-9223372036854775809', JSON_TYPE_INT), '-9223372036854775808');  # -2^63-1
  is($cjson->encode('-9223372036854775810', JSON_TYPE_INT), '-9223372036854775808');  # -2^63-2

  # those floating point values are rounded to unsigned UV_MAX or signed IV_MIN too
  is($cjson->encode(18446744073709551616.5, JSON_TYPE_INT), '18446744073709551615');  #  2^64
  is($cjson->encode(18446744073709551617.5, JSON_TYPE_INT), '18446744073709551615');  #  2^64+1
  is($cjson->encode(18446744073709551618.5, JSON_TYPE_INT), '18446744073709551615');  #  2^64+2
  is($cjson->encode(-9223372036854775809.5, JSON_TYPE_INT), '-9223372036854775808');  # -2^63-1
  is($cjson->encode(-9223372036854775810.5, JSON_TYPE_INT), '-9223372036854775808');  # -2^63-2

  is($cjson->encode(           int( 'Inf'), JSON_TYPE_INT), ($] >= 5.008 && $] < 5.008008) ? '0' : '18446744073709551615');
  is($cjson->encode(           int('-Inf'), JSON_TYPE_INT), ($] >= 5.008 && $] < 5.008008) ? '0' : '-9223372036854775808');

  is($cjson->encode(                 'Inf', JSON_TYPE_INT), '18446744073709551615');
  is($cjson->encode(                '-Inf', JSON_TYPE_INT), '-9223372036854775808');
  is($cjson->encode(               9**9**9, JSON_TYPE_INT), '18446744073709551615');
  is($cjson->encode(              -9**9**9, JSON_TYPE_INT), '-9223372036854775808');
 }
}


is(encode_json([10, "10", 10.25], [JSON_TYPE_INT, JSON_TYPE_INT, JSON_TYPE_STRING]), '[10,10,"10.25"]');
is(encode_json([10, "10", 10.25], json_type_arrayof(JSON_TYPE_INT)), '[10,10,10]');
is(encode_json([10, "10", 10.25], json_type_anyof(json_type_arrayof(JSON_TYPE_INT))), '[10,10,10]');
is(encode_json([10, "10", 10.25], json_type_null_or_anyof(json_type_arrayof(JSON_TYPE_INT))), '[10,10,10]');

is(encode_json(
    [
            10,
            [
                        11,
                        12,
                        [
                            13,
                        ],
                        14,
            ],
            15,
    ],

    json_type_anyof(
        JSON_TYPE_BOOL,
        [
            JSON_TYPE_INT,
            json_type_anyof(
                json_type_arrayof(
                    json_type_anyof(
                        json_type_arrayof(
                            JSON_TYPE_STRING
                        ),
                        JSON_TYPE_INT,
                    )
                ),
            ),
            JSON_TYPE_FLOAT,
        ],
    )
), '[10,[11,12,["13"],14],15.0]');

{
    my $true = Cpanel::JSON::XS::true;
    my $perl_struct = [ $true, $true, $true, $true ];
    my $type_spec = [ JSON_TYPE_BOOL, JSON_TYPE_INT, JSON_TYPE_FLOAT, JSON_TYPE_STRING ];
    my $json_string = encode_json($perl_struct, $type_spec);
    is($json_string, '[true,1,1.0,"true"]');
}

{
    my $perl_struct = [ 1, 1, "1", undef ];
    my $type_spec = [ JSON_TYPE_INT, JSON_TYPE_STRING, JSON_TYPE_INT_OR_NULL,
                      JSON_TYPE_STRING_OR_NULL ];
    my $json_string = encode_json($perl_struct, $type_spec);
    is($json_string, '[1,"1",1,null]');
}

{
    my $perl_struct = [ "1", 1, 1.0 ];
    my $type_spec = json_type_arrayof(JSON_TYPE_INT);
    my $json_string = encode_json($perl_struct, $type_spec);
    is($json_string, '[1,1,1]');
}

{
    my $perl_struct = { key1 => 1, key2 => "2", key3 => 1 };
    my $type_spec = { key1 => JSON_TYPE_STRING, key2 => JSON_TYPE_INT,
                      key3 => JSON_TYPE_BOOL };
    my $json_string = $cjson->encode($perl_struct, $type_spec);
    is($json_string, '{"key1":"1","key2":2,"key3":true}');
}

{
    my $perl_struct = { key1 => "1", key2 => 2 };
    my $type_spec = { key1 => JSON_TYPE_INT, key2 => JSON_TYPE_STRING,
                      key3 => JSON_TYPE_BOOL };
    my $json_string = $cjson->encode($perl_struct, $type_spec);
    is($json_string, '{"key1":1,"key2":"2"}');
}

{
    my $perl_struct = { key1 => "value1", key2 => "value2", key3 => 0, key4 => 1,
                        key5 => "string", key6 => "string2" };
    my $type_spec = json_type_hashof(JSON_TYPE_STRING);
    my $json_string = $cjson->encode($perl_struct, $type_spec);
    is($json_string, '{"key1":"value1","key2":"value2","key3":"0","key4":"1",'
       .'"key5":"string","key6":"string2"}');
}

{
    my $perl_struct = [ "1", [ 10, 20 ], 13, { "key" => "string" }, [ "1", "2" ],
                        { "key" => 12 } ];
    my $type_spec = json_type_arrayof(json_type_anyof(JSON_TYPE_INT,
                        [ JSON_TYPE_INT, JSON_TYPE_INT ], { "key" => JSON_TYPE_STRING }));
    my $json_string = $cjson->encode($perl_struct, $type_spec);
    is($json_string, '[1,[10,20],13,{"key":"string"},[1,2],{"key":"12"}]');
}

{
    my $perl_struct = { key1 => { key2 => [ 10, "10", 10.6 ] }, key3 => "10.5" };
    my $type_spec = { key1 => json_type_anyof(JSON_TYPE_FLOAT,
                                json_type_hashof(json_type_arrayof(JSON_TYPE_INT))),
                      key3 => JSON_TYPE_FLOAT };
    my $json_string = $cjson->encode($perl_struct, $type_spec);
    is($json_string, '{"key1":{"key2":[10,10,10]},"key3":10.5}');
}

{
    my $perl_struct = { key1 => [ "10", 10, 10.5, Cpanel::JSON::XS::true ],
                        key2 => { key => "string" }, key3 => Cpanel::JSON::XS::false };
    my $type_spec = json_type_hashof(json_type_anyof(json_type_arrayof(JSON_TYPE_INT),
                        json_type_hashof(JSON_TYPE_STRING), JSON_TYPE_BOOL));
    my $json_string = $cjson->encode($perl_struct, $type_spec);
    is($json_string, '{"key1":[10,10,10,1],"key2":{"key":"string"},"key3":false}');
}


SKIP: {
    skip "no Scalar::Util in $]", 2 unless $have_weaken;
    my $weakref;
    {
        my $perl_struct = { key1 => 'string', key2 => '10',
                            key3 => { key1 => 'level1', key2 => '20',
                                      key3 => { key1 => 'level2', key2 => 30 } } };
        my $type_spec = { key1 => JSON_TYPE_STRING, key2 => JSON_TYPE_INT };
        $type_spec->{key3} = $type_spec;
        weaken($type_spec->{key3});
        my $json_string = $cjson->encode($perl_struct, $type_spec);
        is($json_string, '{"key1":"string","key2":10,"key3":'
           .'{"key1":"level1","key2":20,"key3":{"key1":"level2","key2":30}}}');
        $weakref = $type_spec;
        weaken($weakref);
    }
    ok(not defined $weakref);
}

SKIP: {
    skip "no Scalar::Util in $]", 2 unless $have_weaken;
    my $weakref;
    {
        my $perl_struct = [ "10", 10.2, undef, 10, [ [ "10", 10 ], 10.3, undef ], 10 ];
        my $type_arrayof = json_type_arrayof(my $type_spec);
        $type_spec = json_type_anyof(JSON_TYPE_INT_OR_NULL, $type_arrayof);
        ${$type_arrayof} = $type_spec;
        weaken(${$type_arrayof});
        my $json_string = $cjson->encode($perl_struct, $type_spec);
        is($json_string, '[10,10,null,10,[[10,10],10,null],10]');
        $weakref = $type_spec;
        weaken($weakref);
    }
    ok(not defined $weakref);
}

SKIP: {
    skip "no Scalar::Util in $]", 2 unless $have_weaken;
    my $weakref;
    {
        my $perl_struct = { type => "TYPE", value => "VALUE",
                            position => { line => 10, column => 11 },
                            content => [
                                        { type => "TYPE2", value => "VALUE2",
                                          position => { line => 12, column => 13 } } ] };
        my $type_spec = { type => JSON_TYPE_STRING, value => 0,
                          position => { line => JSON_TYPE_INT, column => JSON_TYPE_INT } };
        my $type_spec_content = json_type_arrayof($type_spec);
        weaken(${$type_spec_content});
        $type_spec->{content} = $type_spec_content;
        my $json_string = $cjson->encode($perl_struct, $type_spec);
        is ($json_string,
            '{"content":[{"position":{"column":13,"line":12},"type":"TYPE2","value":"VALUE2"}],'.
            '"position":{"column":11,"line":10},"type":"TYPE","value":"VALUE"}');
        $weakref = $type_spec;
        weaken($weakref);
    }
    ok(not defined $weakref);
}

ok(!defined eval { json_type_anyof(JSON_TYPE_STRING, JSON_TYPE_INT) });
like($@, qr/Only one scalar type can be specified in anyof/);

ok(!defined eval { json_type_anyof([ JSON_TYPE_STRING ], [ JSON_TYPE_INT ]) });
like($@, qr/Only one array type can be specified in anyof/);

ok(!defined eval { json_type_anyof({ key => JSON_TYPE_STRING }, { key => JSON_TYPE_INT }) });
like($@, qr/Only one hash type can be specified in anyof/);

ok(!defined eval { json_type_anyof([ JSON_TYPE_STRING ], json_type_arrayof(JSON_TYPE_INT)) });
like($@, qr/Only one array type can be specified in anyof/);

ok(!defined eval { json_type_anyof({ key => JSON_TYPE_STRING }, json_type_hashof(JSON_TYPE_INT)) });
like($@, qr/Only one hash type can be specified in anyof/);

ok(!defined eval { json_type_anyof(json_type_arrayof(JSON_TYPE_STRING), json_type_arrayof(JSON_TYPE_INT)) });
like($@, qr/Only one array type can be specified in anyof/);

ok(!defined eval { json_type_anyof(json_type_hashof(JSON_TYPE_STRING), json_type_hashof(JSON_TYPE_INT)) });
like($@, qr/Only one hash type can be specified in anyof/);

ok(!defined eval { json_type_anyof(bless({}, 'Object')) });
like($@, qr/Only scalar, array or hash can be specified in anyof/);

ok(!defined eval { json_type_null_or_anyof(JSON_TYPE_STRING) });
like($@, qr/Scalar cannot be specified in null_or_anyof/);

ok(!defined eval { json_type_arrayof(JSON_TYPE_STRING, JSON_TYPE_INT) });
like($@, qr/Exactly one type must be specified in arrayof/);

ok(!defined eval { json_type_hashof(JSON_TYPE_STRING, JSON_TYPE_INT) });
like($@, qr/Exactly one type must be specified in hashof/);

foreach my $val (['0', JSON_TYPE_INT], ['0.0', JSON_TYPE_FLOAT], ['""', JSON_TYPE_STRING]) {
    my $warn;
    local $SIG{__WARN__} = sub { $warn = $_[0] };
    is($cjson->encode(undef, $val->[1]), $val->[0]); my $line = __LINE__;
    like($warn, qr/Use of uninitialized value in (?:XS )?subroutine entry at \Q$0\E line \Q$line\E/);
}

foreach my $type (JSON_TYPE_BOOL_OR_NULL, JSON_TYPE_INT_OR_NULL, JSON_TYPE_FLOAT_OR_NULL, JSON_TYPE_STRING_OR_NULL) {
    my $warn;
    local $SIG{__WARN__} = sub { $warn = $_[0] };
    is($cjson->encode(undef, $type), 'null');
    ok(!defined $warn);
}

foreach my $val (['0', JSON_TYPE_INT], ['0.0', JSON_TYPE_FLOAT]) {
    my $warn;
    local $SIG{__WARN__} = sub { $warn = $_[0] };
    is($cjson->encode(my $str = 'string_value', $val->[1]), $val->[0]); my $line = __LINE__;
    like($warn, qr/Argument "string_value" isn't numeric in (?:XS )?subroutine entry at \Q$0\E line \Q$line\E/);
}

SKIP: {
    skip "no Scalar::Util in $]", 1 unless $have_weaken;
    my $struct = {};
    $struct->{recursive} = json_type_arrayof(json_type_weaken($struct));
    my $weakref = $struct->{recursive};
    weaken($weakref);
    undef $struct;
    ok(!defined $weakref);
}

SKIP: {
    skip "no Scalar::Util in $]", 1 unless $have_weaken;
    my $struct = {};
    $struct->{recursive} = json_type_hashof(json_type_weaken($struct));
    my $weakref = $struct->{recursive};
    weaken($weakref);
    undef $struct;
    ok(!defined $weakref);
}

SKIP: {
    skip "no Scalar::Util in $]", 1 unless $have_weaken;
    my $struct = {};
    $struct->{recursive} = json_type_anyof(json_type_weaken($struct));
    my $weakref = $struct->{recursive};
    weaken($weakref);
    undef $struct;
    ok(!defined $weakref);
}

ok(!defined eval { $cjson->encode(1) });
like($@, qr/type for '1' was not specified/);

ok(!defined eval { $cjson->encode(1, undef) });
like($@, qr/type for '1' was not specified/);

ok(!defined eval { $cjson->encode([1]) });
like($@, qr/type for 'ARRAY\(.*\)' was not specified/);

ok(!defined eval { $cjson->encode([1], undef) });
like($@, qr/type for 'ARRAY\(.*\)' was not specified/);

ok(!defined eval { $cjson->encode([1], [undef]) });
like($@, qr/type for '1' was not specified/);

ok(!defined eval { $cjson->encode({ key => 1 }) });
like($@, qr/type for 'HASH\(.*\)' was not specified/);

ok(!defined eval { $cjson->encode({ key => 1 }, undef) });
like($@, qr/type for 'HASH\(.*\)' was not specified/);

ok(!defined eval { $cjson->encode({ key => 1 }, { key => undef }) });
like($@, qr/type for '1' was not specified/);
