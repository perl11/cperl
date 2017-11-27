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
set_up_inc('lib', '.');

find_git_or_skip('all');
skip_all("on Travis CI" ) if $ENV{TRAVIS} and $^V =~ /c$/; # cperl #32
skip_all("This distro may have modified some files in cpan/. Skipping validation.")
  if $ENV{'PERL_BUILD_PACKAGING'};

# use 'v5.22.0..' as default. no reason to recheck all previous commits
my $revision_range = 'v5.22.0..';
if ( $ENV{TRAVIS} && defined $ENV{TRAVIS_COMMIT_RANGE} ) {
  # travisci is adding a merge commit when smoking a pull request
  #	unfortunately it's going to use the default GitHub email from the author
  #	which can differ from the one the author wants to use as part of the pull request
  #	let's simply use the TRAVIS_COMMIT_RANGE which list the commits we want to check
  #	all the more a pull request should not be impacted by blead being incorrect
  $revision_range = $ENV{TRAVIS_COMMIT_RANGE};
}

# This is the subset of "pretty=fuller" that checkAUTHORS.pl actually needs:
my $quote = $^O eq 'MSWin32' ? q(") : q(');
system(qq(git log --pretty=format:${quote}Author: %an <%ae>%n${quote} $revision_range ) .
       "| $^X -Ilib Porting/checkAUTHORS.pl --tap -");

# EOF
