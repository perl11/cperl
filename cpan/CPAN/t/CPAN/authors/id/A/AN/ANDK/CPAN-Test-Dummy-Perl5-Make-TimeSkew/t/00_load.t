#!perl 

print "1..3\n";

for my $err ("CPAN does not support perl prior to 5.004") {
    if ( $] >= 5.004 ) {
	print "ok 1 - $err\n";
    } else {
	print "not ok 1 - $err\n";
    }
}

eval {
    require CPAN::Test::Dummy::Perl5::Make::TimeSkew;
};

my $err = $@;
for my $label ("CPAN::Test::Dummy::Perl5::Make::TimeSkew loads ok") {
    if ( length($err) ) {
	print "not ok 2 - $label\: $err\n";
    } else {
	print "ok 2 - $label\n";
    }
}

my @stat = stat "Makefile.PL";
my $mtime = $stat[9];
my @mtime = gmtime $mtime;
$mtime[4]++;
$mtime[5]+=1900;
print "ok 3 - Makefile.PL timestamp @mtime[5,4,3,2,1,0]\n";

exit(0);
