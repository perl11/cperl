#!perl 

print "1..2\n";

if ( $] >= 5.004 ) {
	print "ok 1 - CPAN does not support perl prior to 5.004\n";
} else {
	print "not ok 1 - CPAN does not support perl prior to 5.004\n";
}

print STDERR qq{The following failure is intentional in order to
trigger the corresponding action of the installer program on distros
with failing tests\n};

print "not ok 2 - CPAN::Test::Dummy::Perl5::Build::Fails loads ok\n";

exit(0);
