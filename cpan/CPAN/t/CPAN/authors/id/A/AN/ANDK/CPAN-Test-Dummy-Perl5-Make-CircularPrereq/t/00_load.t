#!perl 

print "1..3\n";

if ( $] >= 5.004 ) {
  print "ok 1 - CPAN does not support perl prior to 5.004\n";
} else {
  print "not ok 1 - CPAN does not support perl prior to 5.004\n";
}

eval {
  require CPAN::Test::Dummy::Perl5::Make::CircularPrereq;
};

if ( length($@) ) {
  print "not ok 2 - CPAN::Test::Dummy::Perl5::Make::CircularPrereq loads ok\n";
} else {
  print "ok 2 - CPAN::Test::Dummy::Perl5::Make::CircularPrereq loads ok\n";
}

# in the PREREQ_PM declaration in our Makefile.PL we have declared
# OptionalPrereq, so we expect that one to be available when we reach
# the testing phase. Remember: In OptionalPrereq we test whether we
# survive missing and circular recommendations. Here in CircularPrereq
# we test that (1) we can be installed and (2) whether we can break
# the toolchain by just pointing back

eval {
  require CPAN::Test::Dummy::Perl5::Make::OptionalPrereq;
};

if ( length($@) ) {
  print "not ok 3 - CPAN::Test::Dummy::Perl5::Make::OptionalPrereq loads ok\n";
} else {
  print "ok 3 - CPAN::Test::Dummy::Perl5::Make::OptionalPrereq loads ok\n";
}

exit(0);
