package test14;
use AutoLoader 'AUTOLOAD';

# The tests run with start=init so we need to arrange to execute some
# profiled code before the first autosplit sub gets loaded in order to
# test the handling of autosplit subs. We could use an INIT block for
# that but calling a sub suits the tests better for obscure reasons.
sub pre { 1 }

1;
__END__
sub foo {
  $&;
}

sub bar {
  eval 2;
}
