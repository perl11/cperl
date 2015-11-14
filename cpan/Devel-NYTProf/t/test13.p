# Testing various types of eval calls. Some are processed differently internally

sub foo {
  print "in sub foo\n";
}

sub bar {
  print "in sub bar\n";
}

sub baz {
  print "in sub baz\n";
  eval { foo();    # two stmts executed on this line (eval + foo() call)
         foo(); }; # one stmt  executed on this line
  eval { x();      # two stmts executed on this line (eval + x() call), fails out of eval
         x(); };   # zero stmts because previous statement threw an exception
}

eval "foo();";     # one stmt in this fid, one statement in eval fid
eval { bar(); };   # two stmts
baz();
