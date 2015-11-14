# this test14.pm file should not be loaded because the test14.pmc
# file should be newer and so that's the one that perl will use
die sprintf q{%s used in error. The %sc file needs to be newer so perl will use the .pmc instead.
}, __FILE__, __FILE__;
