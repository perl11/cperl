#!./perl -w
#   BEGIN may not pollute the namespace for the compiler
BEGIN {
	unshift @INC, 't';
	require Config;
	if (($Config::Config{'extensions'} !~ /\bB\b/) ){
		print "1..0 # Skip -- Perl configured without B module\n";
		exit 0;
	}
	require 'test.pl';
}

use B;

CHECK {
  plan(1);
  ok(!defined &B::SVf_IOK, "RT#81332 B constants may not be imported at BEGIN" );
}

1;
