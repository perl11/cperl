#!/usr/bin/perl

use strict;
use Test::More tests => 15;

use Cpanel::JSON::XS;

my $json = Cpanel::JSON::XS->new->convert_blessed;

my $obj = OverloadedObject->new( 'foo' );
ok( $obj eq 'foo' );
is( $json->encode( [ $obj ] ), q{["foo"]} );

# rt.cpan.org #64783
my $foo  = bless {}, 'Foo';
my $bar  = bless {}, 'Bar';

eval q{ $json->encode( $foo ) };
ok($@);
eval q{ $json->encode( $bar ) };
ok(!$@);

# GH#116, GH#117
ok(Cpanel::JSON::XS::false eq "", 'false eq ""');
ok(Cpanel::JSON::XS::false eq 0, 'false eq 0');
ok(Cpanel::JSON::XS::false eq 0.0, 'false eq 0.0');
ok(Cpanel::JSON::XS::false eq "false", 'false eq "false"');
ok(Cpanel::JSON::XS::false eq !!0, 'false eq !!0');
ok(!(Cpanel::JSON::XS::false eq "true"), 'false ne "true"');
ok(!(Cpanel::JSON::XS::false eq "string"), 'false ne "string"');
ok(Cpanel::JSON::XS::true eq "true", 'true eq "true"');
ok(Cpanel::JSON::XS::true eq 1, 'true eq 1');
ok(Cpanel::JSON::XS::true eq !0, 'true eq !0');
ok(Cpanel::JSON::XS::false ne Cpanel::JSON::XS::true, 'false ne true');

package Foo;

use strict;
use overload (
    'eq' => sub { 0 },
    '""' => sub { $_[0] },
    fallback => 1,
);

sub TO_JSON {
    return $_[0];
}

package Bar;

use strict;
use overload (
    'eq' => sub { 0 },
    '""' => sub { $_[0] },
    fallback => 1,
);

sub TO_JSON {
    return overload::StrVal($_[0]);
}


package OverloadedObject;

use overload 'eq' => sub { $_[0]->{v} eq $_[1] }, '""' => sub { $_[0]->{v} }, fallback => 1;

sub new {
    bless { v => $_[1] }, $_[0];
}

sub TO_JSON { "$_[0]"; }

