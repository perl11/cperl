# This test does a basic `use` check on all the code.
use Test::More;

use File::Find;

sub test {
    s{^lib/(.*)\.pm$}{$1} or return;
    s{/}{::}g;
    ok eval("require $_; 1"), "require $_;$@";
}

find {
    wanted => \&test,
    no_chdir => 1,
}, 'lib';

done_testing;
