#!perl 

print "1..2\n";

if ( $] >= 5.004 ) {
	print "ok 1 - CPAN does not support perl prior to 5.004\n";
} else {
	print "not ok 1 - CPAN does not support perl prior to 5.004\n";
}

print "ok 2 - CPAN::Test::Dummy::Perl5::Build::DepeFails loads ok\n";

exit(0);
