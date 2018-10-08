#!perl 

print "1..2\n";

if ( $] >= 5.004 ) {
  print "ok 1 - CPAN does not support perl prior to 5.004\n";
} else {
  print "not ok 1 - CPAN does not support perl prior to 5.004\n";
}

eval {
  require CPAN::Test::Dummy::Perl5::Make::OptionalPrereq;
};

if ( length($@) ) {
  print "not ok 2 - CPAN::Test::Dummy::Perl5::Make::OptionalPrereq loads ok\n";
} else {
  print "ok 2 - CPAN::Test::Dummy::Perl5::Make::OptionalPrereq loads ok\n";
}

exit(0);
