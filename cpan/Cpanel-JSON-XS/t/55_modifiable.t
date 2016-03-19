#!perl
use strict;
use warnings;
use Test::More tests => 15;
use Cpanel::JSON::XS;

my $js = Cpanel::JSON::XS->new;
my @data = ('null', 'true', 'false', "1", "\"test\"");
my %map = ( 'null' => undef, true => 1, false => 0, 
            '1' => 1, '"test"' => "test" );

for my $k (@data) {
  my $data = $js->decode("{\"foo\":$k}");
  my $res = $data->{foo} || $k;
  ok exists $data->{foo}, "foo hvalue exists";
  if ($k eq 'true' and $res eq 'true') {
    # https://github.com/rurban/Cpanel-JSON-XS/issues/45#issuecomment-160602267
    # Older Test::More <5.12 cannot compare 1 to true.
    # We only care about the next test, modifiability,
    # not the representation of true and its eq overload.
    is $data->{foo}, $res, "foo hvalue $res (special case)";
  } else {
    is $data->{foo}, $map{$k}, "foo hvalue $res";
  }
  ok $data->{foo} = "bar", "foo can be set from $res to 'bar'";
}
