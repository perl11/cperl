use Test::More qw(no_plan);

pass();

# we note the time in the test log here (the first test) and in t/zzz.t
# so we can judge how fast the set of tests ran and this the rough speed of the system
diag("Tests ended at ". localtime(time));
