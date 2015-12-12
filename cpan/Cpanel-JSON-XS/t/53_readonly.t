#!perl
use strict;
use warnings;
use Test::More $] < 5.008 ? (skip_all => "5.6") : (tests => 1);
use Cpanel::JSON::XS;

my $json = Cpanel::JSON::XS->new->convert_blessed;

sub Foo::TO_JSON {
    return 1;
}

my $string = "something";
my $object = \$string;
bless $object,'Foo';
Internals::SvREADONLY($string,1);
my $hash = {obj=>$object};

my $enc = $json->encode ($hash);
ok $enc eq '{"obj":1}', "$enc";
