#!./perl

use FileCache;
my $tmp = "foo$$";
END { unlink($tmp) }

use Test::More tests => 1;

{# Test 5: that close is overridden properly within the caller
     cacheout local $_ = $tmp;
     print $_ "Hello World\n";
     close($_);
     ok(!fileno($_));
}
