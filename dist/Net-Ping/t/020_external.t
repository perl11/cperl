use warnings;
use strict;

use Test::More tests => 3;
BEGIN {use_ok('Net::Ping')};

SKIP: {
  local $ENV{LC_ALL} = 'C';
  eval {
    require Net::Ping::External;
  };
  skip "Without Net::Ping::External", 2 if $@;

  my $result;
  my $p = Net::Ping->new('external');
  isa_ok($p, "Net::Ping");

  eval {
    $result = $p->ping("www.google.com");
  };

  if (!$@) {
    is($result, 1, 'tested $p->ping using external');
  } elsif ($@ !~ /getaddrinfo\(www.google.com,,AF_INET\) failed/) {
    if ($@ =~ /Protocol "external" not supported on your system: Net::Ping::External not found/) {
      ok(1, "Missing Net::Ping::External handled correctly");
    } else {
      # Socket::getnameinfo on Windows systems
      like($@, qr/^getnameinfo.*failed/, "Failing Net::Ping::External handled correctly");
    }
  } else {
    # getaddrinfo AF_INET failed on POSIX
    ok(1, "skip: no internet connection");
  }
}
