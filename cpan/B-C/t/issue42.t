#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=42
# B::CC uses value from void context in next list context
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

# Explanation:
# - f1 is called, it puts value 1 on the stack.
# - f2 should discard this value, because f1 is called in void context.
# - But if a block follows, this value is accidently added to the list
#   of return values of f2.
my $script = <<'EOF';
sub f1 { 1 }
f1();
print do { 7; 2 }, "\n";
EOF

# fixed with r596. remove enter/leave from %no_stack, sp sync.
ctest(1, '^2$', "CC", "ccode42i", $script,
      'CC uses value from void context in next list context, fixed with r596');
