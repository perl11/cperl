use strict;
use 5.008;
use ExtUtils::MakeMaker;
use Config;

# update.sh shouldn't be used, needs fix
#if (-d '.git') {
#    system("./update.sh") == 0
#        or die "update.sh failed";
#}

my $DEFINE = '';
# https://gcc.gnu.org/onlinedocs/gcc-4.0.0/gcc/Warning-Options.html
if ($Config{gccversion} and $Config{gccversion} =~ /^(\d+\.\d+)\./) {
  my $gccver = $1;
  if ($gccver >= 4.3) {
    $DEFINE = '-Wall -Werror=declaration-after-statement -Wextra -W';
  } elsif ($gccver >= 3.4) {
    $DEFINE = '-Wall -Wdeclaration-after-statement -Wextra -W';
  }
}
$DEFINE .= $^O eq 'MSWin32'
  ? ' -DHAVE_CONFIG_H -DYAML_DECLARE_EXPORT'
  : ' -DHAVE_CONFIG_H';

WriteMakefile(
  NAME => 'YAML::Safe',
  ABSTRACT_FROM => 'Safe.pm',
  VERSION_FROM => 'Safe.pm',
  PREREQ_PM => {
    'constant'   => 0.1,
    'Test::Base' => 0.80,
    'File::Path' => 0.1,
    'lib' => 0.1,
    'JSON::PP' => 2.27300,
    'boolean' => 0.30,
  },
  INC => '-I.',
  LIBS => [''], # e.g., '-lm'
  OBJECT => q/$(O_FILES)/,
  DEFINE => $DEFINE,
  AUTHOR => 'Reini Urban <rurban@cpan.org>',
);

package MY;
sub top_targets {
  local $_ = shift->SUPER::top_targets(@_);
  s/\$\(FIRST_MAKEFILE\) blibdirs/\$(FIRST_MAKEFILE\) blibdirs README/
      unless $ENV{PERL_CORE};
  $_
}
sub depend {
  $ENV{PERL_CORE}
  ? ""
  : "
README : \$(VERSION_FROM)
	pod2text \$(VERSION_FROM) > README

release : dist
	git tag \$(VERSION)
	cpan-upload \$(DISTVNAME).tar\$(SUFFIX)
	git push
	git push --tags

xtest :: test
	\$(MAKE) test TEST_FILES=xt/*.t

# versioned gcc needs overrides
GCOV = gcov
test_cover :: pure_all
	\$(RM_RF) cover_db
	+\$(PERLRUNINST) -S cover -test

test_coveralls :: pure_all
	+\$(PERLRUNINST) -S cover -test -report coveralls

gcov : \$(BASEEXT).c.gcov \$(BASEEXT).gcov cover_db/\$(BASEEXT)-xs.html

\$(BASEEXT).c.gcov \$(BASEEXT).xs.gcov : \$(BASEEXT).xs
	\$(MAKE) CCFLAGS=\"\$(CCFLAGS) -fprofile-arcs -ftest-coverage\" LDDLFLAGS=\"\$(LDDLFLAGS) -fprofile-arcs -ftest-coverage\"
	\$(GCOV) \$(BASEEXT).c \$(BASEEXT).xs

cover_db/\$(BASEEXT)-xs.html : \$(BASEEXT).xs.gcov
	PERL5OPT=-MDevel::Cover make test
	-$^X -S gcov2perl \$(BASEEXT).c.gcov \$(BASEEXT).xs.gcov
	$^X -S cover

gprof :
	\$(MAKE) CCFLAGS=\"\$(CCFLAGS) -pg\" LDDLFLAGS=\"\$(LDDLFLAGS) -pg\"
"
}
