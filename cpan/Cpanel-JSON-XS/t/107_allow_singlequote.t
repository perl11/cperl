
use Test::More tests => 8;
use strict;
use Cpanel::JSON::XS;
#########################

my $json = Cpanel::JSON::XS->new;

eval q| $json->decode("{'foo':'bar'}") |;
ok($@, "error $@"); # in XS and PP, the error message differs.
# '"' expected, at character offset 1 (before "'foo':'bar'}")

$json->allow_singlequote;

is($json->decode(q|{'foo':"bar"}|)->{foo}, 'bar');
is($json->decode(q|{'foo':'bar'}|)->{foo}, 'bar');
is($json->allow_barekey->decode(q|{foo:'bar'}|)->{foo}, 'bar');

is($json->decode(q|{'foo baz':'bar'}|)->{"foo baz"}, 'bar');

# GH 54 from Locale::Wolowitz
is($json->decode(q|{xo:"how's it hangin 1"}|)->{"xo"}, q(how's it hangin 1));
$json->allow_barekey(0);
is($json->decode(q|{"xo":"how's it hangin 1"}|)->{"xo"}, q(how's it hangin 1));
$json->allow_singlequote(0);
is($json->decode(q|{"xo":"how's it hangin 1"}|)->{"xo"}, q(how's it hangin 1));
