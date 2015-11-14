# test test40pmc.pmc is loaded instead of test40pmc.pm
# (which requires test40pmc.pmc to be newer, which Makefile.PL arranges)
use test40pmc;
test40pmc::foo();
