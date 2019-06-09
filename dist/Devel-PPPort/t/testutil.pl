{
  my $__ntest;
  my $__total;

  sub plan {
    @_ == 2 or die "usage: plan(tests => count)";
    my $what = shift;
    $what eq 'tests' or die "cannot plan anything but tests";
    $__total = shift;
    if (defined $__total && $__total eq 'no_plan') {
      return;
    }
    defined $__total && $__total > 0 or die "need a positive number of tests";
    print "1..$__total\n";
  }

  sub done_testing {
    print "1..",$__ntest,"\n";
  }

  sub skip {
    my $reason = shift;
    ++$__ntest;
    print "ok $__ntest # skip: $reason\n"
  }

  sub ok ($;$$) {
    local($\,$,);
    my $ok = 0;
    my $result = shift;
    my $comment = '';
    if (@_ == 0) {
      $ok = $result;
    } else {
      $expected = shift;
      if (!defined $expected) {
        $ok = !defined $result;
      } elsif (!defined $result) {
        $ok = 0;
      } elsif (ref($expected) eq 'Regexp') {
        $ok = $result =~ $expected;
        #die "using regular expression objects is not backwards compatible";
      } else {
        $ok = $result eq $expected;
      }
      $comment = ' # '.shift if @_;
    }
    ++$__ntest;
    if ($ok) {
      print "ok $__ntest$comment\n"
    }
    else {
      print "not ok $__ntest$comment\n"
    }
    $ok
  }
}

1;
