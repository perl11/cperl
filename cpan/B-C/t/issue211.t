#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=211
# eval die and stderr/stdout order
BEGIN{
  if ($ENV{HARNESS_ACTIVE}) {
    print "1..0 #skip under harness\n";
    exit 0;
  }
}
my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
system(qq{
$X -Mblib script/perlcc -occode211i -O3 -r -e'print "1..3\n";print "ok 1 - howdy\n";print "ok 2 - dooty\n";
eval { die "foo" }; warn "ok 3 - wazzup \$\@\n" if \$\@;'
});
