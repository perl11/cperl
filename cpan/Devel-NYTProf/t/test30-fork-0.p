sub prefork {
  print "in sub prefork\n";
  other();
}

sub other {
  print "in sub other\n";
}

sub postfork {
  print "in sub postfork\n";
  other();
}

prefork();

fork;

postfork();
other();

wait;
