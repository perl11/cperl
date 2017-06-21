use warnings;
use strict;

use Test::More tests => 5;
BEGIN {use_ok('Net::Ping')};

SKIP: {
    eval {
       require Net::Ping::External;
    };
    skip "Without Net::Ping::External", 2 if $@;
    my $p = Net::Ping->new('external');
    isa_ok($p, "Net::Ping");
    my $result = $p->ping("www.google.com");
    is($result, 1, 'tested $p->ping using external');
}

SKIP: {
    eval {
       require Net::Ping::External;
     };
    local $ENV{LC_ALL} = 'C';
    skip "With Net::Ping::External", 2 unless $@;
    my $p = Net::Ping->new('external');
    isa_ok($p, "Net::Ping");
    eval {
        $p->ping("www.google.com");
    };
    if ($@ !~ /getaddrinfo\(www.google.com,,AF_INET\) failed/) {
      if ($@ =~ /Protocol "external" not supported on your system: Net::Ping::External not found/) {
        ok(1, "Missing Net::Ping::External handled correctly");
      } else {
        # Socket::getnameinfo on Windows systems
        like($@, qr/^getnameinfo.*failed/, "Failing Net::Ping::External handled correctly");
      }
    } else {
        ok(1, "skip: no internet connection");
    }
}
