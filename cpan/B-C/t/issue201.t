#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=201
# broken %INC. Subroutine import redefined at .../Config.pm line 38
BEGIN {
  unless (-d '.git' and !$ENV{NO_AUTHOR}) {
    print "1..0 #SKIP Only if -d .git\n";
    exit;
  }
}
use strict;
use Test::More tests => 2;

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $perlcc = "$X -Iblib/arch -Iblib/lib blib/script/perlcc";

my $result = `$perlcc -O3 -UB -occode201i -r -e 'sub can {require Config; Config->import;return \$Config{d_flock}}use IO::File;can();print "ok\n"' 2>pccerr`;
my $err = do { local $/; open my $fh, "pccerr"; <$fh> };
is($err, "", "stderr");
is($result, "ok\n");
END { unlink "pccerr" }
