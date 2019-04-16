#!./perl

use FileCache;
my $tmp = "foo$$";
END { unlink($tmp) }

use Test::More tests => 1;

{# Test 4: that 2 arg format works, and that we cycle on mode change
     cacheout '>', $tmp;
     print $tmp "foo 4\n";
     cacheout '+>', $tmp;
     print $tmp "$tmp 44\n";
     seek($tmp, 0, 0);
     ok(<$tmp> eq "$tmp 44\n");
     close $tmp;
}
