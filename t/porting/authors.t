#!./perl -w
# Test that there are no missing authors in AUTHORS

BEGIN {
  if (-f '../TestInit.pm') {
    @INC = '..';
  } else {
    @INC = '.';
  }
}
use TestInit qw(T); # T is chdir to the top level
use strict;
require './t/test.pl';
use Config;

find_git_or_skip('all');
skip_all("on Travis CI" ) if $ENV{TRAVIS} and $Config{usecperl}; # cperl #32
skip_all("This distro may have modified some files in cpan/. Skipping validation.")
  if $ENV{'PERL_BUILD_PACKAGING'};

# This is the subset of "pretty=fuller" that checkAUTHORS.pl actually needs:
my $quote = $^O =~ /^mswin/i ? q(") : q(');
system("git log --pretty=format:${quote}Author: %an <%ae>%n${quote} | $^X Porting/checkAUTHORS.pl --tap -");

# EOF
