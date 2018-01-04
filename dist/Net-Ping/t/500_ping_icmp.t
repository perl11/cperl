# Test to perform icmp protocol testing.
# Root access is required.
# In the core test suite it calls itself via sudo -n (no password) to test it.

use strict;
use Config;

use Test::More;
BEGIN {
  unless (eval "require Socket") {
    plan skip_all => 'no Socket';
  }
  unless ($Config{d_getpbyname}) {
    plan skip_all => 'no getprotobyname';
  }
  # Note this code is considered anti-social in p5p and was removed in
  # their variant.
  # See http://nntp.perl.org/group/perl.perl5.porters/240707
  # Problem is that ping_icmp needs root perms, and previous bugs were
  # never caught. So I rather execute it via sudo in the core test suite
  # than not at all and risk further bitrot of this API.
  require Net::Ping;
  if (!Net::Ping::_isroot()) {
    my $file = __FILE__;
    my $lib = $ENV{PERL_CORE} ? '-I../../lib' : '-Mblib';
    # -n prevents from asking for a password. rather fail then
    # A technical problem is with leak-detectors, like asan, which
    # require PERL_DESTRUCT_LEVEL=2 to be set in the root env.
    if ($ENV{PERL_CORE} and
        system("sudo -n PERL_DESTRUCT_LEVEL=2 \"$^X\" $lib $file") == 0)
    {
      exit;
    } else {
      plan skip_all => 'no sudo/failed';
    }
  }
}

SKIP: {
  skip "icmp ping requires root privileges.", 1
    if !Net::Ping::_isroot() or $^O eq 'MSWin32';
  my $p = new Net::Ping "icmp";
  my $result = $p->ping("127.0.0.1");
  if ($result == 1) {
    is($result, 1, "icmp ping 127.0.0.1");
  } else {
  TODO: {
      local $TODO = "icmp firewalled?";
      is($result, 1, "icmp ping 127.0.0.1");
    }
  }
}

done_testing;
