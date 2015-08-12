#!./perl -w
# This test checks for RT #123878, keeping the die handler still 
# disabled into goto'd function. And the other documented
# exceptions to enable dying from a die handler.

print "1..4\n";

eval {
  sub f1 { die "ok 1\n" }
  $SIG{__DIE__} = \&f1;
  die;
};
print $@;

eval {
  sub loopexit { for (0..2) { next if $_ } }
  $SIG{__DIE__} = \&loopexit;
  die "ok 2\n";
};
print $@;

eval {
  sub foo1 { die "ok 3\n" }
  sub bar1 { foo1() }
  $SIG{__DIE__} = \&bar1;
  die;
};
print $@;

#eval {
#  sub foo2 { die "ok 4\n" }
#  sub bar2 { goto &foo2 }
#  $SIG{__DIE__} = \&bar2;
#  die;
#};
#print $@;
print "ok 4 #skip RT #123878\n";

# Deep recursion on subroutine "main::foo".
# SEGV

# Segfault aside, I did not expect the die() in foo() to trigger the __DIE__
# handler; according to perlvar(1), the handler "is explicitly disabled *during*
# the call", from which we haven't returned yet (even though we have technically
# left the subroutine).

# perlvar %SIG
# When a "__DIE__" hook routine returns, the exception processing
# continues as it would have in the absence of the hook,
# unless the hook routine itself exits via a "goto &sub",
# a loop exit, or a "die()".  The "__DIE__" handler is
# explicitly disabled during the call, so that you can
# die from a "__DIE__" handler.
