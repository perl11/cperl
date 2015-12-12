# shared hek destruction. with debugging perls or valgrind only
# https://github.com/rurban/Cpanel-JSON-XS/issues/10
print "1..1\n";
use Cpanel::JSON::XS qw<decode_json>;
my %h = ('{"foo":"bar"}' => 1);
while (my ($k) = each %h) {
    my $obj = decode_json($k);
}
print "ok 1\n";
