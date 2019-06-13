# If the AutoSplit module has been loaded before we got initialized
# (specifically before we redirected the opcodes used when compiling)
# then the profiler won't profile AutoSplit code so the test will fail
# because the results won't match.
# The tricky part is that we need to take care to avoid being tripped up
# by the fact that XSLoader will fallback to using DynaLoader in some cases
# and DynaLoader uses AutoSplit.
# See Makefile.PL for how we avoid XSLoader fallback to using DynaLoader.

BEGIN {
  use AutoSplit;
  mkdir('./auto');
  autosplit('test14', './auto', 1, 0, 0);
}

use test14;
test14::pre();
test14::foo();
test14::bar();
