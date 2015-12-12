use Cpanel::JSON::XS;
use strict;
print "1..1\n";

my @foo_params = map {( "foo$_" => 1 )} 1..61;
my $foo = Foo->new(@foo_params);
my $encoded = Cpanel::JSON::XS->new()->allow_tags(1)->encode(
    Foo->new(
        foo => Foo->new(@foo_params),
        bar => Foo->new(foo => $foo),
    )
);
print defined($encoded) ? "ok 1\n" : "nok 1\n";

package Foo;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub FREEZE {
    return %{ $_[0] };
}
