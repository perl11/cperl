# tests loops.  noop is a hack for perl>5.6 where
# the closing "}" of a loop counts as being executed if loop is empty.

my $_z;
sub noop { 
  $_z++;
}

sub foo {
  print "in sub foo\n";
  foreach (1 .. 10) {
    noop();
    foreach (1 .. 10) {
      noop();
    }
  }
}

sub bar {
  print "in sub bar\n";
  my ($x, $y);
  while (10 > $x++) {
    $y = 0;
    while (10 > $y++) {
      noop();
    }
  }
}

sub baz {
  print "in sub baz\n";
  my ($x, $y) = (1);
  do {
    $y = 1;
    do {
      noop();
      noop();
    } while(10 > $y++);
  } while(10 > $x++);
}

foo();
bar();
baz();
