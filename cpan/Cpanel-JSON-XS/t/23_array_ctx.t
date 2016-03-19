print "1..5\n";
use Cpanel::JSON::XS;

sub FREEZE { ( 123, 456 ); }
@foo = Cpanel::JSON::XS->new->allow_tags->encode(bless {}, 'main');

print "ok 1\n";

@foo = Cpanel::JSON::XS->new->filter_json_object(sub {12})->decode('[{}]');
print "ok 2\n";

@foo = Cpanel::JSON::XS->new->filter_json_object(sub {return shift, 1})->decode('[{}, {}]');
print "ok 3\n";

@foo = Cpanel::JSON::XS->new->filter_json_single_key_object(1 => sub { [] })->decode('{"1":0}');
print "ok 4\n";

@foo = Cpanel::JSON::XS->new->filter_json_single_key_object(1 => sub { [], [] })->decode('{"1":0}');
print "ok 5\n";
