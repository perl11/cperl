#
#  Copyright (c) 1995-2000, Raphael Manfredi
#  Copyright (c) 2017-2019, Reini Urban
#  
#  You may redistribute only under the same terms as Perl 5, as specified
#  in the README file that comes with the distribution.
#

use strict;
use warnings;
use ExtUtils::MakeMaker;
use Config;
use File::Copy qw(move copy);
use File::Spec;

my ($fn, $in) = ("stacksize.h", "stacksize_in.h");
copy $in, $fn;
unlink "lib/Storable/Limit.pm";

my $limit_pm = File::Spec->catfile('lib', 'Storable', 'Limit.pm');

my $pm = { 'Storable.pm' => '$(INST_ARCHLIB)/Storable.pm' };
unless ($ENV{PERL_CORE}) {
    # the core Makefile takes care of this for core builds
    $pm->{$limit_pm} = '$(INST_ARCHLIB)/Storable/Limit.pm';
}

WriteMakefile(
    NAME            => 'Storable',
    AUTHOR          => 'Reini Urban',
    LICENSE         => 'perl',
    DISTNAME        => "Storable",
    PL_FILES        => { }, # prevent default behaviour
    PM              => $pm,
    PREREQ_PM       => { XSLoader => 0, perl => '5.004' },
    INSTALLDIRS     => ($] >= 5.007 && $] < 5.012) ? 'perl' : 'site',
    VERSION_FROM    => 'Storable_pm.PL',
    ABSTRACT_FROM   => 'Storable_pm.PL',
    ($ExtUtils::MakeMaker::VERSION > 6.45 ?
     (META_MERGE    => { resources =>
                         { bugtracker => 'https://github.com/rurban/Storable/issues',
                           repository => 'https://github.com/rurban/Storable/',
                         },
                         provides => {
                           'Storable'  => {
                             file        => 'Storable_pm.PL',
                             version     => MM->parse_version('Storable_pm.PL'),
                           },
                         },
                         recommends => {
                           'Test::Kwalitee'      => '1.00',
                           'Test::CheckManifest' => '1.42',
                           'Test::CPAN::Meta'    => 0,
                           'Pod::Spell::CommonMistakes' => 0,
                           'Test::Spelling'      => 0,
                           'Test::Pod'           => 0,
                           'Devel::Refcount'     => 0,
                         }
      },
     ) : ()),
    ($ExtUtils::MakeMaker::VERSION >= 6.64 ?
     (TEST_REQUIRES => {
        'Test::More'          => '0.82', # for t/malice.t using note()
      }
     ) : ()),
    dist            => { SUFFIX => 'gz', COMPRESS => 'gzip -f' },
    clean           => { FILES => 'Storable-* Storable.pm stacksize.h lib' },
    SIGN            => 1,
);

# Unlink the .pm file included with the distribution
1 while unlink "Storable.pm";

my $ivtype = $Config{ivtype};

# I don't know if the VMS folks ever supported long long on 5.6.x
if ($ivtype and $ivtype eq 'long long' and $^O !~ /^MSWin/) {
  print <<'EOM';

You appear to have a perl configured to use 64 bit integers in its scalar
variables.  If you have existing data written with an earlier version of
Storable which this version of Storable refuses to load with a

   Byte order is not compatible

error, then please read the section "64 bit data in perl 5.6.0 and 5.6.1"
in the Storable documentation for instructions on how to read your data.

(You can find the documentation at the end of Storable.pm in POD format)

EOM
}

# compute the maximum stacksize, before and after linking
package MY;
use Config;

sub depend {
    my $extra_deps = "";
    my $options = "";
    my $mkblib = '';
    my $linktype = uc($_[0]->{LINKTYPE});
    my $s;
    # EUMM bug for core builds, missing ldlibpthname
    if ($ENV{PERL_CORE}) {
      $options = "--core";
      # $extra_deps = ' $(PERLEXE)' if $^O eq 'MSWin32';
      my $ldlibpthname = $Config{ldlibpthname};
      if ($Config{useshrplib} && $ldlibpthname && $ENV{$ldlibpthname}) {
          $s = "LDPERLRUNINST = $ldlibpthname=$ENV{$ldlibpthname}" .
            " \$(FULLPERLRUNINST)\n";
      } else {
        $s = "LDPERLRUNINST = \$(FULLPERLRUNINST)\n";
      }
    } else {
      # blib.pm needs arch/lib
      $extra_deps = ' Storable.pm';
      $s = "LDPERLRUNINST = \$(FULLPERLRUNINST)\n";
      $mkblib = "-\$(MKPATH) \$(INST_ARCHLIB)\n\t" .
        "-\$(CHMOD) \$(PERM_RW) \$(INST_ARCHLIB)/Storable.pm\n\t" .
        "\$(CP) Storable.pm \$(INST_ARCHLIB)/Storable.pm\n\t";
    }
    $s . "
stacksize: Makefile \$(INST_$linktype)$extra_deps
	$mkblib\$(LDPERLRUNINST) stacksize $options

Storable\$(OBJ_EXT) Storable.c: stacksize.h

stacksize.h: stacksize_in.h
	\$(CP) stacksize_in.h stacksize.h

$limit_pm : stacksize

release : dist
	git tag \$(VERSION)
	cpan-upload \$(DISTVNAME).tar\$(SUFFIX)
	git push
	git push --tags
"
}

sub test {
    my ($self, %attr) = @_;

    my $out = $self->SUPER::test(%attr);

    if ($ENV{PERL_CORE}) {
        $out =~ s!^(test(?:db)?_(?:static|dynamic)\b.*)!$1 $limit_pm!gm;
    }

    $out;
}

sub postamble {
'
all :: Storable.pm
	$(NOECHO) $(NOOP)

Storable.pm :: Storable_pm.PL
	$(PERLRUN) Storable_pm.PL

'
}
