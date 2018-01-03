#!perl
# A simple listing of core files that have specific maintainers,
# or at least someone that can be called an "interested party".
# Also, a "module" does not necessarily mean a CPAN module, it
# might mean a file or files or a subdirectory.
# Most (but not all) of the modules have dual lives in the core
# and in CPAN.

package Maintainers;

use utf8;
use File::Glob qw(:case);

# IGNORABLE: files which, if they appear in the root of a CPAN
# distribution, need not appear in core (i.e. core-cpan-diff won't
# complain if it can't find them)

@IGNORABLE = qw(
    .cvsignore .dualLivedDiffConfig .gitignore .perlcriticrc .perltidyrc
    .travis.yml ANNOUNCE Announce Artistic AUTHORS BENCHMARK BUGS Build.PL
    CHANGELOG ChangeLog Changelog CHANGES Changes CONTRIBUTING CONTRIBUTING.md
    CONTRIBUTING.mkdn COPYING Copying cpanfile CREDITS dist.ini GOALS HISTORY
    INSTALL INSTALL.SKIP LICENCE LICENSE Makefile.PL MANIFEST MANIFEST.SKIP
    META.json META.yml MYMETA.json MYMETA.yml NEW NEWS NOTES perlcritic.rc
    ppport.h README README.md README.pod README.PATCHING SIGNATURE THANKS TODO
    Todo VERSION WHATSNEW
);

# Each entry in the  %Modules hash roughly represents a distribution,
# except when DISTRIBUTION is set, where it *exactly* represents a single
# CPAN distribution.

# The keys of %Modules are human descriptions of the distributions,
# and need to match a module or distribution name, so that cpan name
# will install this module.  Distributions which have an obvious
# top-level module associated with them will usually have a key named
# for that module, e.g. 'Archive::Extract' for
# Archive-Extract-N.NN.tar.gz; the remaining keys are likely to be
# based on the name of the distribution, e.g. 'Locale-Codes' for
# Locale-Codes-N.NN.tar.gz'.

# UPSTREAM indicates where patches should go.  This is generally now
# inferred from the FILES: modules with files in dist/, ext/ and lib/
# are understood to have UPSTREAM 'blead', meaning that the copy of the
# module in the blead sources is to be considered canonical, while
# modules with files in cpan/ are understood to have UPSTREAM 'cpan',
# meaning that the module on CPAN is to be patched first.

# MAINTAINER has previously been used to indicate who the current maintainer
# of the module is, but this is no longer stated explicitly. It is now
# understood to be either the Perl 5 Porters if UPSTREAM is 'blead', or else
# the CPAN author whose PAUSE user ID forms the first part of the DISTRIBUTION
# value, e.g. 'BINGOS' in the case of 'BINGOS/Archive-Tar-2.00.tar.gz'.
# (PAUSE's View Permissions page may be consulted to find other authors who
# have owner or co-maint permissions for the module in question.)

# FILES is a list of filenames, glob patterns, and directory
# names to be recursed down, which collectively generate a complete list
# of the files associated with the distribution.

# BUGS is an email or url to post bug reports.  For modules with
# UPSTREAM => 'blead', use perl5-porters@perl.org.  rt.cpan.org
# appears to automatically provide a URL for CPAN modules; any value
# given here overrides the default:
# http://rt.cpan.org/Public/Dist/Display.html?Name=$ModuleName

# DISTRIBUTION names the tarball on CPAN which (allegedly) the files
# included in core are derived from. Note that the file's version may not
# necessarily match the newest version on CPAN.

# EXCLUDED is a list of files to be excluded from a CPAN tarball before
# comparing the remaining contents with core. Each item can either be a
# full pathname (eg 't/foo.t') or a pattern (e.g. qr{^t/}).
# It defaults to the empty list.

# CUSTOMIZED is a list of files that have been customized within the
# Perl core.  Use this whenever patching a cpan upstream distribution
# or whenever we expect to have a file that differs from the tarball.
# If the file in blead matches the file in the tarball from CPAN,
# Porting/core-cpan-diff will warn about it, as it indicates an expected
# customization might have been lost when updating from upstream.  The
# path should be relative to the distribution directory.  If the upstream
# distribution should be modified to incorporate the change then be sure
# to raise a ticket for it on rt.cpan.org and add a comment alongside the
# list of CUSTOMIZED files noting the ticket number.

# DEPRECATED contains the *first* version of Perl in which the module
# was considered deprecated.  It should only be present if the module is
# actually deprecated.  Such modules should use deprecated.pm to
# issue a warning if used.  E.g.:
#
#     use if $] >= 5.011, 'deprecate';
#

# MAP is a hash that maps CPAN paths to their core equivalents.
# Each key represents a string prefix, with longest prefixes checked
# first. The first match causes that prefix to be replaced with the
# corresponding key. For example, with the following MAP:
#   {
#     'lib/'     => 'lib/',
#     ''     => 'lib/Foo/',
#   },
#
# these files are mapped as shown:
#
#    README     becomes lib/Foo/README
#    lib/Foo.pm becomes lib/Foo.pm
#
# The default is dependent on the type of module.
# For distributions which appear to be stored under ext/, it defaults to:
#
#   { '' => 'ext/Foo-Bar/' }
#
# otherwise, it's
#
#   {
#     'lib/'     => 'lib/',
#     ''     => 'lib/Foo/Bar/',
#   }

%Modules = (

    'Archive::Tar' => {
        'DISTRIBUTION' => 'BINGOS/Archive-Tar-2.26.tar.gz',
        'FILES'        => q[cpan/Archive-Tar],
        'BUGS'         => 'bug-archive-tar@rt.cpan.org',
        'EXCLUDED'     => [
            qw(t/07_ptardiff.t
               t/99_pod.t),
        ],
        # CPAN RT 121685
        'CUSTOMIZED'   => [ qw( t/90_symlink.t ) ],
    },

    'Attribute::Handlers' => {
        'DISTRIBUTION' => 'RJBS/Attribute-Handlers-0.99.tar.gz',
        'FILES'        => q[dist/Attribute-Handlers],
    },

    'autodie' => {
        'DISTRIBUTION' => 'PJF/autodie-2.29.tar.gz',
        'FILES'        => q[cpan/autodie],
        'EXCLUDED'     => [
            qr{benchmarks},
            qr{README\.md},
            # All these tests depend upon external
            # modules that don't exist when we're
            # building the core.  Hence, they can
            # never run, and should not be merged.
            qw( t/author-critic.t
                t/boilerplate.t
                t/critic.t
                t/fork.t
                t/kwalitee.t
                t/lex58.t
                t/pod-coverage.t
                t/pod.t
                t/release-pod-coverage.t
                t/release-pod-syntax.t
                t/socket.t
                t/system.t
                )
        ],
        # CPAN RT 105344
        'CUSTOMIZED'   => [ qw[ t/mkdir.t ] ],
    },

    'AutoLoader' => {
        'DISTRIBUTION' => 'SMUELLER/AutoLoader-5.74.tar.gz',
        'FILES'        => q[cpan/AutoLoader],
        'EXCLUDED'     => ['t/00pod.t'],
    },

    'autouse' => {
        'DISTRIBUTION' => 'RJBS/autouse-1.11.tar.gz',
        'FILES'        => q[dist/autouse],
        'EXCLUDED'     => [
            qr{^t/release-.*\.t},
            qr{^t/author-.*\.t}
          ],
    },

    'B::C' => {
        'DISTRIBUTION' => 'RURBAN/B-C-1.55_06.tar.gz',
        'FILES'        => q[cpan/B-C],
        'EXCLUDED'     => [
            qr{^.gdb},
            qr{^t/z_pod\.t/},
            qr{^ByteLoader/BcVersions/},
            qr{^log\..*/},
            qr{^ramblings/},
            qr{^t/.*\.sh},
            qw( Artistic
                Changes
                Copying
                INSTALL
                NOTES
                MANIFEST
                README
                README.alpha
                STATUS
                TESTS
                Todo
                .gitignore
                .travis.yml
		regen_lib.pl
		status_upd
		store_rpt
		lib/B/Bytecode56.pm
		ByteLoader/ppport.h
		ByteLoader/BcVersions.pod
		Stash/Makefile.PL
                t/download-reports
		t/manifest.t
		t/moose-test.pl
		t/mymodules
		t/nowarn.pl
		t/pg.pl
		t/regex-dna.pl
		t/testcore.pl
		t/todomod.pl
		t/top100
		t/z_pod.t
                ppport.h
                META.json
                META.yml
                )
        ],
        'CUSTOMIZED'   => [ qw[ t/test10 ] ],
    },

    'B::Debug' => {
        'DISTRIBUTION' => 'RURBAN/B-Debug-1.26.tar.gz',
        'FILES'        => q[cpan/B-Debug],
        'EXCLUDED'     => ['t/pod.t'],
    },

    'base' => {
        'DISTRIBUTION' => 'RJBS/base-2.23.tar.gz',
        'FILES'        => q[dist/base],
        # revert incdot test change  
        'CUSTOMIZED'   => [ qw[ lib/base.pm ] ],
    },

    'bignum' => {
        'DISTRIBUTION' => 'PJACKLAM/bignum-0.43.tar.gz',
        'FILES'        => q[cpan/bignum],
        'EXCLUDED'     => [
            qr{^inc/Module/},
            qr{^t/0},
            qr{^t/author-},
            qw( t/pod.t
                t/pod_cov.t
                ),
        ],
    },

    'Carp' => {
        'DISTRIBUTION' => 'RJBS/Carp-1.38.tar.gz',
        'FILES'        => q[dist/Carp],
    },

    'Compress::Raw::Bzip2' => {
        'DISTRIBUTION' => 'PMQS/Compress-Raw-Bzip2-2.074.tar.gz',
        'FILES'        => q[cpan/Compress-Raw-Bzip2],
        'EXCLUDED'     => [
            qr{^t/Test/},
            qr{^bzip2-src/.*\.patch$/},
        ],
        # https://rt.cpan.org/Ticket/Display.html?id=119005
        'CUSTOMIZED'   => [ qw[ Bzip2.xs ] ],
    },

    'Compress::Raw::Zlib' => {
        'DISTRIBUTION' => 'PMQS/Compress-Raw-Zlib-2.069.tar.gz',

        'FILES'    => q[cpan/Compress-Raw-Zlib],
        'EXCLUDED' => [
            qr{^examples/},
            qr{^t/Test/},
            qw( t/000prereq.t
                t/99pod.t
                ),
        ],

        # https://rt.cpan.org/Ticket/Display.html?id=119007
        'CUSTOMIZED'   => [ qw[ Zlib.xs ] ],
    },

    'Config' => {
        'DISTRIBUTION' => 'RURBAN/XSConfig-6.22.tar.gz',
        'FILES'      => q[
                 ext/Config/Config.pm
                 ext/Config/Config_xs.{in,out,PL}
                 ext/Config/Dummy.c
                 ext/Config/Makefile.PL
                 ext/Config/gperftest.in
                 ext/Config/t/Config.t
                 ext/Config/t/XSConfig.t
                 ext/Config/typemap
        ],
        'EXCLUDED' => [
            qw(  Config_mini.pl.PL
                 Config_xs_heavy.pl.PL
                 XSConfig.pod
                 genkeys.PL
                 regen/regen_lib.pl
                 xsc_test.pl
                )
        ],
    },

    'Config::Perl::V' => {
        'DISTRIBUTION' => 'HMBRAND/Config-Perl-V-0.29.tgz',
        'FILES'        => q[cpan/Config-Perl-V],
        'EXCLUDED'     => [qw(
		examples/show-v.pl
		)],
        # added cperl support and tests, keep short format
        'CUSTOMIZED'   => [ qw[ V.pm t/28_plv522.t t/28_plv522c.t ] ],
    },

    'constant' => {
        'DISTRIBUTION' => 'RJBS/constant-1.34.tar.gz',
        'FILES'        => q[dist/constant],
        'EXCLUDED'     => [
            qw( t/00-load.t
                t/more-tests.t
                t/pod-coverage.t
                t/pod.t
                eg/synopsis.pl
                ),
        ],
    },

    'CPAN' => {
        'DISTRIBUTION' => 'ANDK/CPAN-2.16.tar.gz',
        'FILES'        => q[cpan/CPAN],
        'EXCLUDED'     => [
            qr{^distroprefs/},
            qr{^inc/Test/},
            qr{^t/CPAN/},
            qr{^t/data/},
            qr{^t/97-},
            qw( lib/CPAN/Admin.pm
                scripts/cpan-mirrors
                PAUSE2015.pub
                SlayMakefile
                t/00signature.t
                t/04clean_load.t
                t/12cpan.t
                t/13tarzip.t
                t/14forkbomb.t
                t/30shell.coverage
                t/30shell.t
                t/31sessions.t
                t/41distribution.t
                t/42distroprefs.t
                t/43distroprefspref.t
                t/44cpanmeta.t
                t/50pod.t
                t/51pod.t
                t/52podcover.t
                t/60credentials.t
                t/70_critic.t
                t/71_minimumversion.t
                t/local_utils.pm
                t/perlcriticrc
                t/yaml_code.yml
                ),
        ],
        'CUSTOMIZED'   => [
            qw( lib/CPAN.pm lib/CPAN/FirstTime.pm lib/CPAN/Distribution.pm 
                lib/CPAN/Version.pm lib/App/Cpan.pm ),
        ],
    },

    # Note: When updating CPAN-Meta the META.* files will need to be regenerated
    # perl -Icpan/CPAN-Meta/lib Porting/makemeta
    'CPAN::Meta' => {
        'DISTRIBUTION' => 'DAGOLDEN/CPAN-Meta-2.150010.tar.gz',
        'FILES'        => q[cpan/CPAN-Meta],
        'EXCLUDED'     => [
            qw[t/00-report-prereqs.t],
            qw[t/00-report-prereqs.dd],
            qr{t/README-data.txt},
            qr{^xt},
            qr{^history},
            qw[ 'lib/Parse/CPAN/Meta.pm' ],
        ],
        # support cperl version c suffix, better and safer JSON and YAML.
        'CUSTOMIZED'   => [
            qw( t/save-load.t t/prereqs.t t/validator.t t/converter-bad.t
                t/converter-fail.t
                t/parse-cpan-meta/02_api.t t/parse-cpan-meta/05_errors.t
                lib/CPAN/Meta.pm
                lib/CPAN/Meta/History/Meta_1_4.pod lib/CPAN/Meta/Spec.pm
                lib/CPAN/Meta/Validator.pm
                lib/Parse/CPAN/Meta.pm
              ),
        ],
    },

    'CPAN::Meta::Requirements' => {
        'DISTRIBUTION' => 'DAGOLDEN/CPAN-Meta-Requirements-2.140.tar.gz',
        'FILES'        => q[cpan/CPAN-Meta-Requirements],
        'EXCLUDED'     => [
            qw(t/00-report-prereqs.t),
            qw(t/00-report-prereqs.dd),
            qw(t/version-cleanup.t),
            qr{^xt},
        ],
        'CUSTOMIZED'   => [
            qw( lib/CPAN/Meta/Requirements.pm
                t/accepts.t
                t/strings.t
              ),
        ],
    },

    'CPAN::Meta::YAML' => {
        'DISTRIBUTION' => 'DAGOLDEN/CPAN-Meta-YAML-0.018.tar.gz',
        'FILES'        => q[cpan/CPAN-Meta-YAML],
        'EXCLUDED'     => [
            't/00-report-prereqs.t',
            't/00-report-prereqs.dd',
            qr{^xt},
          ],
          'CUSTOMIZED'   => [
            qw( t/lib/TestUtils.pm )
          ],
    },

    'Cpanel::JSON::XS' => {
        'DISTRIBUTION' => 'RURBAN/Cpanel-JSON-XS-3.0240.tar.gz',
        'FILES'        => q[cpan/Cpanel-JSON-XS],
        'EXCLUDED'     => [
            '.travis.yml',
            'ppport.h',
            'eg/bench',
            't/30_jsonspec.t',
            qr{^t/z_},
            qr{^t/test_(porting|transform)},
        ],
    },

    'Data::Dumper' => {
        'DISTRIBUTION' => 'SMUELLER/Data-Dumper-2.162.tar.gz',
        'FILES'        => q[dist/Data-Dumper],
    },

    'DB_File' => {
        'DISTRIBUTION' => 'PMQS/DB_File-1.840.tar.gz',
        'FILES'        => q[cpan/DB_File],
        'EXCLUDED'     => [
            qr{^patches/},
            qw( t/pod.t
                fallback.h
                fallback.xs
                ),
        ],
          'CUSTOMIZED'   => [
            qw( Makefile.PL )
          ],
    },

    'Devel::NYTProf' => {
        'DISTRIBUTION' => 'TIMB/Devel-NYTProf-6.04.tar.gz',
        'FILES'        => q[cpan/Devel-NYTProf],
        'EXCLUDED'     => [
            qr{^t/[79].*\.t},
            qr{^t/test([0-7]|80)},
            qr{^xt/},
            qr{^demo/},
            qw( Changes
                HACKING
                INSTALL
                MANIFEST
                .gdbinit
                .gitignore
                .indent.pro
                .perltidyrc
                .travis.yml
                ppport.h
                META.json
                META.yml
                t/42-global.t
                t/68-hashline.t
                )
        ],
        # cperl fixes for PERL_CORE
        'CUSTOMIZED'   => [ qw( Makefile.PL
                                MemoryProfiling.pod
                                lib/Devel/NYTProf/FileInfo.pm
                                t/lib/NYTProfTest.pm
                                t/00-load.t
                                t/22-readstream.t
                              )],
    },

    'Devel::PPPort' => {
        'DISTRIBUTION' => 'WOLFSAGE/Devel-PPPort-3.36.tar.gz',
        # RJBS has asked MHX to have UPSTREAM be 'blead'
        # (i.e. move this from cpan/ to dist/)
        'FILES'        => q[cpan/Devel-PPPort],
        'EXCLUDED'     => [
            'PPPort.pm',    # we use PPPort_pm.PL instead
        ],
        # cperl fix to support make -s.
        # 5.16 binary support: https://github.com/rurban/Devel-PPPort/tree/516gvhv
        'CUSTOMIZED'   => [ qw( PPPort_pm.PL
				PPPort_xs.PL
				ppport_h.PL
				parts/apidoc.fnc
				parts/inc/HvNAME
				parts/inc/gv
				parts/inc/misc
				parts/todo/5013007
				parts/todo/5015004
			      )],
    },

    'Devel::SelfStubber' => {
        'DISTRIBUTION' => 'FLORA/Devel-SelfStubber-1.05.tar.gz',
        'FILES'        => q[dist/Devel-SelfStubber],
        'EXCLUDED'     => [qr{^t/release-.*\.t}],
    },

    'Digest' => {
        'DISTRIBUTION' => 'GAAS/Digest-1.17.tar.gz',
        'FILES'        => q[cpan/Digest],
        'EXCLUDED'     => ['digest-bench'],
    },

    'Digest::MD5' => {
        'DISTRIBUTION' => 'GAAS/Digest-MD5-2.55.tar.gz',
        'FILES'        => q[cpan/Digest-MD5],
        'EXCLUDED'     => ['rfc1321.txt'],
        # cperl fix for static is not at beginning of declaration, amd64 align.
        # Note that ebcdic needs to regenerate the md5sum in t/files.t
        # https://github.com/rurban/digest-md5/tree/intel-align-rt77919
        'CUSTOMIZED'   => [ qw( MD5.xs MD5.pm Makefile.PL t/files.t )],
    },

    'Digest::SHA' => {
        'DISTRIBUTION' => 'MSHELOR/Digest-SHA-6.01.tar.gz',
        'FILES'        => q[cpan/Digest-SHA],
        'EXCLUDED'     => [
            qw( t/pod.t
                t/podcover.t
                examples/dups
                ),
        ],
    },

    'Dumpvalue' => {
        'DISTRIBUTION' => 'FLORA/Dumpvalue-1.17.tar.gz',
        'FILES'        => q[dist/Dumpvalue],
        'EXCLUDED'     => [qr{^t/release-.*\.t}],
    },

    'Encode' => {
        'DISTRIBUTION' => 'DANKOGAI/Encode-2.93.tar.gz',
        'FILES'        => q[cpan/Encode],
        # cperl fix to support make -s, formatting, enc2xs #114065 for win32
        'CUSTOMIZED'   => [ qw( bin/enc2xs t/Aliases.t )],
    },

    'encoding::warnings' => {
        'DISTRIBUTION' => 'AUDREYT/encoding-warnings-0.11.tar.gz',
        'FILES'        => q[dist/encoding-warnings],
        'EXCLUDED'     => [
            qr{^inc/Module/},
            qw(t/0-signature.t),
        ],
    },

    'Env' => {
        'DISTRIBUTION' => 'FLORA/Env-1.04.tar.gz',
        'FILES'        => q[dist/Env],
        'EXCLUDED'     => [qr{^t/release-.*\.t}],
    },

    'experimental' => {
        'DISTRIBUTION' => 'LEONT/experimental-0.016.tar.gz',
        'FILES'        => q[cpan/experimental],
        'EXCLUDED'     => [
          qr{^t/release-.*\.t},
          qr{^xt/},
          't/00-compile.t',
        ],
    },

    'Exporter' => {
        'DISTRIBUTION' => 'TODDR/Exporter-5.72.tar.gz',
        'FILES'        => q[dist/Exporter],
        'EXCLUDED' => [
            qw( t/pod.t
                t/use.t
                ),
        ],
    },

    'ExtUtils::CBuilder' => {
        'DISTRIBUTION' => 'AMBS/ExtUtils-CBuilder-0.280230.tar.gz',
        'FILES'        => q[dist/ExtUtils-CBuilder],
        'EXCLUDED'     => [
            qw(README.mkdn NOTAS-Alberto),
            qr{^xt},
        ],
        # skip them on travis [cperl #32]
        'CUSTOMIZED'   => [ qw( t/00-have-compiler.t
                                t/03-cplusplus.t
	                      )],
    },

    'ExtUtils::Constant' => {
        # Nick has confirmed that while we have diverged from CPAN,
        # this package isn't primarily maintained in core
        # Another release will happen "Sometime" 'NWCLARK/ExtUtils-Constant-0.16.tar.gz'
        # cperl: This module could eventually be used to maintain warnings as XS and Config as XS,
        # but unfortunately not with the current maintainership.
        'DISTRIBUTION' => 'RURBAN/ExtUtils-Constant-0.24_01.tar.gz',
        'FILES'    => q[dist/ExtUtils-Constant],
        'EXCLUDED' => [
            qw( lib/ExtUtils/Constant/Aaargh56Hash.pm
                examples/perl_keyword.pl
                examples/perl_regcomp_posix_keyword.pl
                ),
        ],
    },

    'ExtUtils::Install' => {
        'DISTRIBUTION' => 'BINGOS/ExtUtils-Install-2.14.tar.gz',
        'FILES'        => q[cpan/ExtUtils-Install],
        'EXCLUDED'     => [
            qw( t/lib/Test/Builder.pm
                t/lib/Test/Builder/Module.pm
                t/lib/Test/More.pm
                t/lib/Test/Simple.pm
                t/pod-coverage.t
                t/pod.t
                ),
        ],
    },

    'ExtUtils::MakeMaker' => {
        'DISTRIBUTION' => 'BINGOS/ExtUtils-MakeMaker-7.30.tar.gz',
        'FILES'        => q[cpan/ExtUtils-MakeMaker],
        'EXCLUDED'     => [
            qr{^t/lib/Test/},
            qr{^(bundled|my)/},
            qr{^t/Liblist_Kid.t},
            qr{^t/liblist/},
            qr{^\.perlcriticrc},
            'PATCHING',
            'README.packaging',
            'lib/ExtUtils/MakeMaker/version/vpp.pm',
        ],
        # Applied upstream remove customisation when updating EUMM
        # cperl skips the ending 'c'
        # use -e not -f for solibs  
        'CUSTOMIZED'   => 
          [ qw[ lib/ExtUtils/MM_Any.pm
                lib/ExtUtils/MM_Unix.pm
                lib/ExtUtils/Command/MM.pm
                lib/ExtUtils/MakeMaker.pm
                lib/ExtUtils/Mkbootstrap.pm
                lib/ExtUtils/Liblist/Kid.pm
                t/basic.t
                t/Liblist.t
                t/Mkbootstrap.t
                t/pm_to_blib.t
                t/prereq.t
                t/vstrings.t ],
            # Not yet submitted
            qq[t/lib/MakeMaker/Test/NoXS.pm],
          ],
    },

    'ExtUtils::Manifest' => {
        'DISTRIBUTION' => 'ETHER/ExtUtils-Manifest-1.70.tar.gz',
        'FILES'        => q[cpan/ExtUtils-Manifest],
        'EXCLUDED'     => [
            qr(^t/00-report-prereqs),
            qr(^xt/)
        ],
    },

    # Note that upstream misses now the 3 xs pods
    'ExtUtils::ParseXS' => {
        'DISTRIBUTION' => 'SMUELLER/ExtUtils-ParseXS-3.35.tar.gz',
        'FILES'        => q[dist/ExtUtils-ParseXS],
        # 3.36_03  
        'CUSTOMIZED'   => # [perl #128517] reproducible build
          [ 'lib/ExtUtils/ParseXS.pm' ],
    },

    'File::Fetch' => {
        'DISTRIBUTION' => 'BINGOS/File-Fetch-0.56.tar.gz',
        'FILES'        => q[cpan/File-Fetch],
    },

    'File::Path' => {
        'DISTRIBUTION' => 'RICHE/File-Path-2.15.tar.gz',
        'FILES'        => q[cpan/File-Path],
        'EXCLUDED'     => [
            qw( eg/setup-extra-tests ),
            qr{^xt},
        ],
        # https://github.com/rpcme/File-Path/pull/34
        'CUSTOMIZED' => [ qw( lib/File/Path.pm t/Path_win32.t ) ],
    },

    'File::Temp' => {
        'DISTRIBUTION' => 'DAGOLDEN/File-Temp-0.2304.tar.gz',
        'FILES'        => q[cpan/File-Temp],
        'EXCLUDED'     => [
            qw( misc/benchmark.pl
                misc/results.txt
                ),
            qw[t/00-report-prereqs.t],
            qr{^xt},
        ],
    },

    'Filter::Simple' => {
        'DISTRIBUTION' => 'SMUELLER/Filter-Simple-0.94.tar.gz',
        'FILES'        => q[dist/Filter-Simple],
        'EXCLUDED'     => [
            qr{^demo/}
        ],
    },

    'Filter::Util::Call' => {
        'DISTRIBUTION' => 'RURBAN/Filter-1.58.tar.gz',
        'FILES'        => q[cpan/Filter-Util-Call
                            pod/perlfilter.pod
                           ],
        'EXCLUDED' => [
            qr{^decrypt/},
            qr{^examples/},
            qr{^Exec/},
            qr{^lib/Filter/},
            qr{^tee/},
            qr{^t/z_},
            qw( .appveyor.yml
                Call/Makefile.PL
                Call/ppport.h
                Call/typemap
                mytest
                t/cpp.t
                t/decrypt.t
                t/exec.t
                t/order.t
                t/sh.t
                t/tee.t
                ),
        ],
        'MAP' => {
            'Call/'          => 'cpan/Filter-Util-Call/',
            'perlfilter.pod' => 'pod/perlfilter.pod',
            ''               => 'cpan/Filter-Util-Call/',
        },
    },

    'Getopt::Long' => {
        'DISTRIBUTION' => 'JV/Getopt-Long-2.49.tar.gz',
        'FILES'        => q[cpan/Getopt-Long],
        'EXCLUDED'     => [
            qr{^examples/},
            qw( perl-Getopt-Long.spec
                lib/newgetopt.pl
                t/gol-compat.t
                ),
        ],
    },

    'HTTP::Tiny' => {
        'DISTRIBUTION' => 'DAGOLDEN/HTTP-Tiny-0.070.tar.gz',
        'FILES'        => q[cpan/HTTP-Tiny],
        'EXCLUDED'     => [
            't/00-report-prereqs.t',
            't/00-report-prereqs.dd',
            't/200_live.t',
            't/200_live_local_ip.t',
            't/210_live_ssl.t',
            qr/^eg/,
            qr/^xt/
        ],
    },

    'I18N::Collate' => {
        'DISTRIBUTION' => 'FLORA/I18N-Collate-1.02.tar.gz',
        'FILES'        => q[dist/I18N-Collate],
        'EXCLUDED'     => [qr{^t/release-.*\.t}],
    },

    'I18N::LangTags' => {
        'FILES'        => q[dist/I18N-LangTags],
    },

    'Internals::DumpArenas' => {
        'DISTRIBUTION' => 'RURBAN/Internals-DumpArenas-0.12_04.tar.gz',
        'FILES'        => q[cpan/Internals-DumpArenas],
    },

    'if' => {
        'DISTRIBUTION' => 'RJBS/if-0.0606.tar.gz',
        'FILES'        => q[dist/if],
    },

    'IO' => {
        'DISTRIBUTION' => 'GBARR/IO-1.38.tar.gz',
        'FILES'        => q[dist/IO/],
        'EXCLUDED'     => ['t/test.pl'],
    },

    'IO::Compress::Base' => {
        'DISTRIBUTION' => 'PMQS/IO-Compress-2.069.tar.gz',
        'FILES'        => q[cpan/IO-Compress],
        'EXCLUDED'     => [
            qr{^examples/},
            qr{^t/Test/},
            't/010examples-bzip2.t',
            't/010examples-zlib.t',
            't/cz-05examples.t',
        ],
    },

    'IO::Socket::IP' => {
        'DISTRIBUTION' => 'PEVANS/IO-Socket-IP-0.38.tar.gz',
        'FILES'        => q[cpan/IO-Socket-IP],
        'EXCLUDED'     => [
            qr{^examples/},
        ],
    },

    'IO::Zlib' => {
        'DISTRIBUTION' => 'TOMHUGHES/IO-Zlib-1.10.tar.gz',
        'FILES'        => q[cpan/IO-Zlib],
    },

    'IPC::Cmd' => {
        'DISTRIBUTION' => 'BINGOS/IPC-Cmd-0.96.tar.gz',
        'FILES'        => q[cpan/IPC-Cmd],
    },

    'IPC::SysV' => {
        'DISTRIBUTION' => 'MHX/IPC-SysV-2.07.tar.gz',
        'FILES'        => q[cpan/IPC-SysV],
        'EXCLUDED'     => [
            qw( const-c.inc
                const-xs.inc
                t/pod.t
                t/podcov.t
                ),
        ],
    },

    'JSON::PP' => {
        'DISTRIBUTION' => 'MAKAMAKA/JSON-PP-2.97000_04.tar.gz',
        'FILES'        => q[cpan/JSON-PP],
        # fallback to Cpanel::JSON::XS, fixed Boolean
        'CUSTOMIZED'   => [ qw( lib/JSON/PP.pm )],
    },

    'lib' => {
        'DISTRIBUTION' => 'SMUELLER/lib-0.63.tar.gz',
        'FILES'        => q[dist/lib/],
        'EXCLUDED'     => [
            qw( forPAUSE/lib.pm
                t/00pod.t
                ),
        ],
        # cperl fix to support make -s
        'CUSTOMIZED'   => [ qw( lib_pm.PL )],
    },

    'Locale::Codes' => {
        'DISTRIBUTION' => 'SBECK/Locale-Codes-3.42.tar.gz',
        'FILES'        => q[cpan/Locale-Codes],
        'EXCLUDED'     => [
            qw( README.first
                t/pod_coverage.ign
                t/pod_coverage.t
                t/pod.t),
            qr{^t/runtests},
            qr{^t/runtests\.bat},
            qr{^internal/},
            qr{^examples/},
        ],
    },

    'Locale::Maketext' => {
        'DISTRIBUTION' => 'TODDR/Locale-Maketext-1.28.tar.gz',
        'FILES'        => q[dist/Locale-Maketext],
        'EXCLUDED'     => [
            qw(
                perlcriticrc
                t/00_load.t
                t/pod.t
                ),
        ],
    },

    'Locale::Maketext::Simple' => {
        'DISTRIBUTION' => 'JESSE/Locale-Maketext-Simple-0.21.tar.gz',
        'FILES'        => q[cpan/Locale-Maketext-Simple],
    },

    'Math::BigInt' => {
        'DISTRIBUTION' => 'PJACKLAM/Math-BigInt-1.999726.tar.gz',
        'FILES'        => q[cpan/Math-BigInt],
        'EXCLUDED'     => [
            qr{^inc/},
            qr{^examples/},
            qr{^t/author-},
            qw( t/00sig.t
                t/01load.t
                t/02pod.t
                t/03podcov.t
                ),
        ],
    },

    'Math::BigInt::FastCalc' => {
        'DISTRIBUTION' => 'PJACKLAM/Math-BigInt-FastCalc-0.42.tar.gz',
        'FILES'        => q[cpan/Math-BigInt-FastCalc],
        'EXCLUDED'     => [
            qr{^inc/},
            qw( t/00sig.t
                t/01load.t
                t/02pod.t
                t/03podcov.t
                ),

            # instead we use the versions of these test
            # files that come with Math::BigInt:
            qw( t/bigfltpm.inc
                t/bigfltpm.t
                t/bigintpm.inc
                t/bigintpm.t
                t/mbimbf.inc
                t/mbimbf.t
                ),
        ],
    },

    'Math::BigRat' => {
        'DISTRIBUTION' => 'PJACKLAM/Math-BigRat-0.260804.tar.gz',
        'FILES'        => q[cpan/Math-BigRat],
        'EXCLUDED'     => [
            qr{^inc/},
            qr{^t/author-},
            qw( t/00sig.t
                t/01load.t
                t/02pod.t
                t/03podcov.t
                ),
        ],
    },

    'Math::Complex' => {
        'DISTRIBUTION' => 'ZEFRAM/Math-Complex-1.59.tar.gz',
        'FILES'        => q[cpan/Math-Complex],
        'EXCLUDED'     => [
            qw( t/pod.t
                t/pod-coverage.t
                ),
        ],
    },

    'Memoize' => {
        'DISTRIBUTION' => 'MJD/Memoize-1.03.tgz',
        'FILES'        => q[cpan/Memoize],
        'EXCLUDED'     => ['article.html'],
    },

    'MIME::Base64' => {
        'DISTRIBUTION' => 'GAAS/MIME-Base64-3.15.tar.gz',
        'FILES'        => q[cpan/MIME-Base64],
        'EXCLUDED'     => ['t/bad-sv.t'],
    },

    'Module::CoreList' => {
        'DISTRIBUTION' => 'BINGOS/Module-CoreList-5.20160620.tar.gz',
        'FILES'        => q[dist/Module-CoreList],
        # skip ending 'c' in numeric context on cperl
        #'CUSTOMIZED'   => [ qw( lib/Module/CoreList.pm
        #                        lib/Module/CoreList/Utils.pm
	#                      )],
    },

    'Module::Load' => {
        'DISTRIBUTION' => 'BINGOS/Module-Load-0.32.tar.gz',
        'FILES'        => q[cpan/Module-Load],
    },

    'Module::Load::Conditional' => {
        'DISTRIBUTION' => 'BINGOS/Module-Load-Conditional-0.68.tar.gz',
        'FILES'        => q[cpan/Module-Load-Conditional],
    },

    'Module::Loaded' => {
        'DISTRIBUTION' => 'BINGOS/Module-Loaded-0.08.tar.gz',
        'FILES'        => q[cpan/Module-Loaded],
    },

    'Module::Metadata' => {
        'DISTRIBUTION' => 'ETHER/Module-Metadata-1.000033.tar.gz',
        'FILES'        => q[cpan/Module-Metadata],
        'EXCLUDED'     => [
            qw(t/00-report-prereqs.t),
            qw(t/00-report-prereqs.dd),
            qr{weaver.ini},
            qr{^xt},
        ],
        # Already merged upstream:
        # https://github.com/Perl-Toolchain-Gang/Module-Metadata/commit/9658697
        'CUSTOMIZED'   => [ qw[ t/lib/GeneratePackage.pm ] ],
    },

    'Net::Domain' => {
        'DISTRIBUTION' => 'SHAY/libnet-3.10.tar.gz',
        'FILES'        => q[cpan/libnet],
        'EXCLUDED'     => [
            qw( Configure
                t/changes.t
                t/critic.t
                t/pod.t
                t/pod_coverage.t
                ),
            qr(^demos/),
            qr(^t/external/),
        ],
        # cperl fix for darwin to use hostname,
        # suse fix for utf8 Net::Cmd
        'CUSTOMIZED'   => [ qw( lib/Net/Domain.pm lib/Net/Cmd.pm )],
    },

    'Net::Ping' => {
        'DISTRIBUTION' => 'RURBAN/Net-Ping-2.52.tar.gz',
        'FILES'        => q[dist/Net-Ping],
        'EXCLUDED'     => [
            qw{t/600_pod.t t/601_pod-coverage.t},
        ],
    },

    'NEXT' => {
        'DISTRIBUTION' => 'NEILB/NEXT-0.67.tar.gz',
        'FILES'        => q[cpan/NEXT],
        'EXCLUDED'     => [qr{^demo/}],
    },

    'Params::Check' => {
        'DISTRIBUTION' => 'BINGOS/Params-Check-0.38.tar.gz',
        'FILES'        => q[cpan/Params-Check],
    },

    'parent' => {
        'DISTRIBUTION' => 'CORION/parent-0.236.tar.gz',
        'FILES'        => q[cpan/parent],
        'EXCLUDED'     => [qr{^xt/}],
    },

    # merged upstream with CPAN-Meta
    #'Parse::CPAN::Meta' => {
    #    'DISTRIBUTION' => 'DAGOLDEN/Parse-CPAN-Meta-1.4417.tar.gz',
    #    'FILES'        => q[cpan/Parse-CPAN-Meta],
    #    'EXCLUDED'     => [
    #        qr[t/00-report-prereqs],
    #        qr{^xt},
    #        qr{^history/},
    #        qr{^lib/CPAN},
    #        qr{^t/(converter|data-|load|merge|meta-|no-index|optional|prereqs)},
    #        qr{^t/(README|repository|save-load|validator)},
    #    ],
    #    # use YAML::XS
    #    'CUSTOMIZED'   => [ qw( lib/Parse/CPAN/Meta.pm ) ],
    #},

    # PathTools cannot be cpan'd by sync-with-cpan
    'File::Spec' => {
        'DISTRIBUTION' => 'RJBS/PathTools-3.62.tar.gz',
        'FILES'        => q[dist/PathTools],
        'EXCLUDED'     => [qr{^t/lib/Test/}],
        # core needs to update @INC in a chdir
        'CUSTOMIZED'   => [ qw( t/rel2abs_vs_symlink.t ) ],
    },

    'Perl::OSType' => {
        'DISTRIBUTION' => 'DAGOLDEN/Perl-OSType-1.010.tar.gz',
        'FILES'        => q[cpan/Perl-OSType],
        'EXCLUDED'     => [qw(tidyall.ini), qr/^xt/, qr{^t/00-}],
    },

    'perlfaq' => {
        'DISTRIBUTION' => 'LLAP/perlfaq-5.021011.tar.gz',
        'FILES'        => q[cpan/perlfaq],
        'EXCLUDED'     => [
            qw( inc/CreateQuestionList.pm
                inc/perlfaq.tt
                t/00-compile.t),
            qr{^xt/},
        ],
    },

    'PerlIO::via::QuotedPrint' => {
        'DISTRIBUTION' => 'SHAY/PerlIO-via-QuotedPrint-0.08.tar.gz',
        'FILES'        => q[cpan/PerlIO-via-QuotedPrint],
    },

    'Pod::Checker' => {
        'DISTRIBUTION' => 'MAREKR/Pod-Checker-1.73.tar.gz',
        'FILES'        => q[cpan/Pod-Checker],
        # cperl fix to support make -s + dos2unix
        'CUSTOMIZED'   => [ qw( scripts/podchecker.PL
			      )],
    },

    'Pod::Escapes' => {
        'DISTRIBUTION' => 'NEILB/Pod-Escapes-1.07.tar.gz',
        'FILES'        => q[cpan/Pod-Escapes],
    },

    'Pod::Parser' => {
        'DISTRIBUTION' => 'MAREKR/Pod-Parser-1.63.tar.gz',
        'FILES'        => q[cpan/Pod-Parser],
    },

    'Pod::Perldoc' => {
        'DISTRIBUTION' => 'MALLEN/Pod-Perldoc-3.27.tar.gz',
        'FILES'        => q[cpan/Pod-Perldoc],

        # Note that we use the CPAN-provided Makefile.PL, since it
        # contains special handling of the installation of perldoc.pod

        # In blead, the perldoc executable is generated by perldoc.PL
        # instead
        # XXX We can and should fix this, but clean up the DRY-failure in utils
        # first
        'EXCLUDED' => ['perldoc'],

        # https://rt.cpan.org/Ticket/Display.html?id=106798
        'CUSTOMIZED'   => [ qw[ lib/Pod/Perldoc.pm Makefile.PL t/02_module_pod_output.t ] ],
    },

    'Pod::Simple' => {
        'DISTRIBUTION' => 'MARCGREEN/Pod-Simple-3.32.tar.gz',
        'FILES'        => q[cpan/Pod-Simple],
        # https://rt.cpan.org/Public/Bug/Display.html?id=103439
        # https://rt.cpan.org/Public/Bug/Display.html?id=105192
        #'CUSTOMIZED'   => [
        #    qw( cpan/Pod-Simple/lib/Pod/Simple/Search.pm
        #        cpan/Pod-Simple/lib/Pod/Simple/BlackBox.pm
        #    ),
        #],
    },

    'Pod::Usage' => {
        'DISTRIBUTION' => 'MAREKR/Pod-Usage-1.69.tar.gz',
        'FILES'        => q[cpan/Pod-Usage],
        # cperl fix to support make -s
        'CUSTOMIZED'   => [ qw( scripts/pod2usage.PL )],
        'EXCLUDED' => ['t/pod/testp2pt.pl'],
    },

    'Pod::Man' => {
        'DISTRIBUTION' => 'RRA/podlators-4.09.tar.gz',
        'FILES'        => q[cpan/podlators pod/perlpodstyle.pod],

        # cperl fix to support make -s
        #'CUSTOMIZED' => [
        #    qw( scripts/pod2man.PL
        #        scripts/pod2text.PL
        #        ),
        #],
        'MAP' => {
            ''                 => 'cpan/podlators/',
            # this file lives outside the cpan/ directory
            'pod/perlpodstyle.pod' => 'pod/perlpodstyle.pod',
        },
        'EXCLUDED' => [
          qr{^t/(style|docs)/},
          qr{/docs/},
        ],
    },

    'Safe' => {
        'DISTRIBUTION' => 'RGARCIA/Safe-2.39.tar.gz',
        'FILES'        => q[dist/Safe],
        # improved 2.39_02c on cperl
        'CUSTOMIZED'   => [ qw( Safe.pm
        			t/safeops.t ) ],
    },

    'Scalar::Util' => {
        # lexical $_ support, binary names, various other fixes
        'DISTRIBUTION' => 'RURBAN/Scalar-List-Utils-1.46_08.tar.gz',
        'FILES'        => q[cpan/Scalar-List-Utils],
        # Bump version, make blead compile: RT #113180
        #'CUSTOMIZED'   => [
        #    qw( ListUtil.xs
        #        lib/List/Util.pm
        #        lib/List/Util/XS.pm
        #        lib/Scalar/Util.pm
        #        lib/Sub/Util.pm
        #        )
        #],
    },

    'Search::Dict' => {
        'DISTRIBUTION' => 'DAGOLDEN/Search-Dict-1.07.tar.gz',
        'FILES'        => q[dist/Search-Dict],
    },

    'SelfLoader' => {
        'DISTRIBUTION' => 'SMUELLER/SelfLoader-1.20.tar.gz',
        'FILES'        => q[dist/SelfLoader],
        'EXCLUDED'     => ['t/00pod.t'],
    },

    'Socket' => {
        'DISTRIBUTION' => 'RURBAN/Socket-2.024_04.tar.gz',
        'FILES'        => q[cpan/Socket],
        #'CUSTOMIZED'   => [
        #    qw( Makefile.PL Socket.xs )
        #]
    },

    'Storable' => {
        'DISTRIBUTION' => 'RURBAN/Storable-3.05_14.tar.gz',
        'FILES'        => q[dist/Storable],
    },

    'Sys::Syslog' => {
        'DISTRIBUTION' => 'SAPER/Sys-Syslog-0.35.tar.gz',
        'FILES'        => q[cpan/Sys-Syslog],
        'EXCLUDED'     => [
            qr{^eg/},
            qw( README.win32
                t/data-validation.t
                t/distchk.t
                t/pod.t
                t/podcover.t
                t/podspell.t
                t/portfs.t
                t/facilities-routing.t
                win32/PerlLog.RES
                ),
        ],
        'CUSTOMIZED'   => [ qw( t/syslog.t ) ],
    },

    'Term::ANSIColor' => {
        'DISTRIBUTION' => 'RRA/Term-ANSIColor-4.06.tar.gz',
        'FILES'        => q[cpan/Term-ANSIColor],
        'EXCLUDED'     => [
            qr{^examples/},
            qr{^docs/},
            qr{^t/data/},
            qr{^t/docs/},
            qr{^t/style/},
            qw( t/module/aliases-env.t ),
        ],
    },

    'Term::Cap' => {
        'DISTRIBUTION' => 'JSTOWE/Term-Cap-1.17.tar.gz',
        'FILES'        => q[cpan/Term-Cap],
    },

    'Term::Complete' => {
        'DISTRIBUTION' => 'FLORA/Term-Complete-1.402.tar.gz',
        'FILES'        => q[dist/Term-Complete],
        'EXCLUDED'     => [qr{^t/release-.*\.t}],
    },

    'Term::ReadLine' => {
        'DISTRIBUTION' => 'FLORA/Term-ReadLine-1.14.tar.gz',
        'FILES'        => q[dist/Term-ReadLine],
        'EXCLUDED'     => [qr{^t/release-.*\.t}],
    },

    'Term::ReadKey' => {
        'DISTRIBUTION' => 'JSTOWE/TermReadKey-2.37.tar.gz',
        'FILES'        => q[cpan/Term-ReadKey],
        'EXCLUDED'     => [qr{^example}],
        'CUSTOMIZED'   => [ qw( ReadKey.xs t/02_terminal_functions.t ) ],
    },

    'Test' => {
        'DISTRIBUTION' => 'JESSE/Test-1.28.tar.gz',
        'FILES'        => q[dist/Test],
    },

    'Test::Harness' => {
        'DISTRIBUTION' => 'LEONT/Test-Harness-3.36.tar.gz',
        'FILES'        => q[cpan/Test-Harness],
        'EXCLUDED'     => [
            qr{^examples/},
            qr{^inc/},
            qr{^t/lib/Test/},
            qr{^xt/},
            qw( Changes-2.64
                MANIFEST.CUMMULATIVE
                NotBuild.PL
                HACKING.pod
                perlcriticrc
                t/000-load.t
                t/lib/if.pm
                t/source_tests/psql.bat
                ),
        ],
        # with compiled Config
        'CUSTOMIZED'   => [
            qw( t/multiplexer.t
                t/nofork.t
                t/regression.t
                t/sample-tests/switches
		t/source_handler.t
		t/lib/NoFork.pm
              )],
    },

    'Test::Simple' => {
        # bumped to 1.4001014 with cperl modernizations.
        # Test2 based 1.3x versions are not yet modernized,
        # Should be moved to ext/
        'DISTRIBUTION' => 'EXODIST/Test-Simple-1.001014.tar.gz',
        'FILES'        => q[cpan/Test-Simple],
        'EXCLUDED'     => [
            qr{^t/xt},
            qr{^xt},
            qw( .perlcriticrc
                .perltidyrc
                examples/indent.pl
                examples/subtest.t
                t/00compile.t
                t/xxx-changes_updated.t
                ),
        ],
    },

    'Text::Abbrev' => {
        'DISTRIBUTION' => 'FLORA/Text-Abbrev-1.02.tar.gz',
        'FILES'        => q[dist/Text-Abbrev],
        'EXCLUDED'     => [qr{^t/release-.*\.t}],
    },

    'Text::Balanced' => {
        'DISTRIBUTION' => 'SHAY/Text-Balanced-2.03.tar.gz',
        'FILES'        => q[cpan/Text-Balanced],
        'EXCLUDED'     => [
            qw( t/97_meta.t
                t/98_pod.t
                t/99_pmv.t
                ),
        ],
    },

    'Text::ParseWords' => {
        'DISTRIBUTION' => 'CHORNY/Text-ParseWords-3.30.tar.gz',
        'FILES'        => q[cpan/Text-ParseWords],
    },

    'Text::Tabs' => {
        'DISTRIBUTION' => 'MUIR/modules/Text-Tabs+Wrap-2013.0523.tar.gz',
        'FILES'        => q[cpan/Text-Tabs],
        'EXCLUDED'   => [
            qr/^lib\.old/,
            't/dnsparks.t',    # see af6492bf9e
        ],
        'MAP'          => {
            ''                        => 'cpan/Text-Tabs/',
            'lib.modern/Text/Tabs.pm' => 'cpan/Text-Tabs/lib/Text/Tabs.pm',
            'lib.modern/Text/Wrap.pm' => 'cpan/Text-Tabs/lib/Text/Wrap.pm',
        },
    },

    # Jerry Hedden does take patches that are applied to blead first, even
    # though that can be hard to discern from the Git history; so it's
    # correct for this (and Thread::Semaphore, threads, and threads::shared)
    # to be under dist/ rather than cpan/
    'Thread::Queue' => {
        'DISTRIBUTION' => 'JDHEDDEN/Thread-Queue-3.11.tar.gz',
        'FILES'        => q[dist/Thread-Queue],
        'EXCLUDED'     => [
            qr{^examples/},
            qw( t/00_load.t
                t/99_pod.t
                t/test.pl
                ),
        ],
    },

    'Thread::Semaphore' => {
        'DISTRIBUTION' => 'JDHEDDEN/Thread-Semaphore-2.13.tar.gz',
        'FILES'        => q[dist/Thread-Semaphore],
        'EXCLUDED'     => [
            qw( examples/semaphore.pl
                t/00_load.t
                t/99_pod.t
                t/test.pl
                ),
        ],
    },

    'threads' => {
        'DISTRIBUTION' => 'JDHEDDEN/threads-2.09.tar.gz',
        'FILES'        => q[dist/threads],
        'EXCLUDED'     => [
            qr{^examples/},
            qw( t/pod.t
                t/test.pl
                threads.h
                ),
          ],
        # protect ithread_free from deleted PL_modglobal
        'CUSTOMIZED'   => [
            qw( threads.xs
		lib/threads.pm
                ),
        ],
    },

    'threads::shared' => {
        'DISTRIBUTION' => 'JDHEDDEN/threads-shared-1.52.tar.gz',
        'FILES'        => q[dist/threads-shared],
        'EXCLUDED'     => [
            qw( examples/class.pl
                shared.h
                t/pod.t
                t/test.pl
                ),
        ],
    },

    'Tie::File' => {
        'DISTRIBUTION' => 'TODDR/Tie-File-1.00.tar.gz',
        'FILES'        => q[dist/Tie-File],
    },

    'Tie::RefHash' => {
        'DISTRIBUTION' => 'FLORA/Tie-RefHash-1.39.tar.gz',
        'FILES'        => q[cpan/Tie-RefHash],
    },

    'Time::HiRes' => {
        'DISTRIBUTION' => 'JHI/Time-HiRes-1.9741.tar.gz',
        'FILES'        => q[dist/Time-HiRes],
        # for overly slow smokers
        'CUSTOMIZED'   => [ 't/nanosleep.t' ],
    },

    'Time::Local' => {
        'DISTRIBUTION' => 'DROLSKY/Time-Local-1.25.tar.gz',
        'FILES'        => q[cpan/Time-Local],
        'EXCLUDED'     => [
            qr{^t/release-.*\.t},
            qr{^t/00-report},
            qr{^xt/},
            qw( perlcriticrc perltidyrc tidyall.ini ),
        ],
    },

    'Time::Piece' => {
        'DISTRIBUTION' => 'ESAYM/Time-Piece-1.31.tar.gz',
        'FILES'        => q[cpan/Time-Piece],
    },

    'Unicode::Collate' => {
        'DISTRIBUTION' => 'SADAHIRO/Unicode-Collate-1.19.tar.gz',
        'FILES'        => q[cpan/Unicode-Collate],
        'EXCLUDED'     => [
            qr{N$},
            qr{^data/},
            qr{^gendata/},
            qw( disableXS
                enableXS
                mklocale
                ),
        ],
    },

    'Unicode::Normalize' => {
        'DISTRIBUTION' => 'KHW/Unicode-Normalize-1.25.tar.gz',
        'FILES'        => q[cpan/Unicode-Normalize],
        'EXCLUDED'     => [
            qr{N$},
            qr{^data/},
            qr{^gendata/},
            qw( disableXS
                enableXS
                ),
        ],
    },

    'version' => {
        'DISTRIBUTION' => 'JPEACOCK/version-0.9917.tar.gz',
        'FILES'        => q[cpan/version vutil.c vutil.h vxs.inc],
        'EXCLUDED' => [
            qr{^vutil/lib/},
            'vutil/Makefile.PL',
            'vutil/ppport.h',
            'vutil/vxs.xs',
            't/00impl-pp.t',
            't/survey_locales',
            'lib/version/vpp.pm',
        ],

        # When adding the CPAN-distributed files for version.pm, it is necessary
        # to delete an entire block out of lib/version.pm, since that code is
        # only necessary with the CPAN release.
        'CUSTOMIZED'   => [
            qw( lib/version.pm lib/version/regex.pm
                ),

            # Merged upstream, waiting for new CPAN release: see CPAN RT#92721
            # cperl allows the ending 'c'
            qw( vutil.c vxs.inc
                ),
        ],

        'MAP' => {
            'vperl/'         => 'cpan/version/lib/version/',
            'vutil/'         => '',
            ''               => 'cpan/version/',
        },
    },

    'warnings' => {
        'FILES'      => q[
                 lib/warnings
                 lib/warnings.{pm,t}
                 regen/warnings.pl
                 t/lib/warnings
        ],
    },

    'Win32' => {
        'DISTRIBUTION' => "JDB/Win32-0.52.tar.gz",
        'FILES'        => q[cpan/Win32],
    },

    'Win32API::File' => {
        'DISTRIBUTION' => 'CHORNY/Win32API-File-0.1203.tar.gz',
        'FILES'        => q[cpan/Win32API-File],
        'EXCLUDED'     => [
            qr{^ex/},
        ],

        # Currently all EOL differences. Waiting for a new upstream release:
        # All the files in the GitHub repo have UNIX EOLs already.
        #'CUSTOMIZED'   => [
        #    qw(
        #        Makefile.PL
        #        buffers.h
        #        cFile.h
        #        cFile.pc
        #        const2perl.h
        #        t/file.t
        #        t/tie.t
        #        typemap
        #        ),
        #],
    },

    'YAML::LibYAML' => {
        'DISTRIBUTION' => "RURBAN/YAML-LibYAML-0.75.tar.gz",
        'FILES'        => q[cpan/YAML-LibYAML],
        'CUSTOMIZED'   => [
          # allow PERL_CORE tests
          qw( LibYAML/Makefile.PL t/TestYAMLTests.pm t/TestYAML.pm )
          ],
    },

    #'XSLoader' => {
    #    'DISTRIBUTION' => 'SAPER/XSLoader-0.16.tar.gz',
    #    'FILES'        => q[dist/XSLoader],
    #    'EXCLUDED'     => [
    #        qr{^eg/},
    #        qw( t/00-load.t
    #            t/01-api.t
    #            t/distchk.t
    #            t/pod.t
    #            t/podcover.t
    #            t/portfs.t
    #            ),
    #        'XSLoader.pm',    # we use XSLoader_pm.PL
    #    ],
    #},

    # this pseudo-module represents all the files under ext/ and lib/
    # that aren't otherwise claimed. This means that the following two
    # commands will check that every file under ext/ and lib/ is
    # accounted for, and that there are no duplicates:
    #
    #    perl Porting/Maintainers --checkmani lib ext
    #    perl Porting/Maintainers --checkmani

    '_PERLLIB' => {
        'FILES'    => q[
                ext/Amiga-ARexx/
                ext/Amiga-Exec/
                ext/B/
                ext/Devel-Peek/
                ext/DynaLoader/
                ext/Errno/
                ext/ExtUtils-Miniperl/
                ext/Fcntl/
                ext/File-DosGlob/
                ext/File-Find/
                ext/File-Glob/
                ext/FileCache/
                ext/GDBM_File/
                ext/Hash-Util-FieldHash/
                ext/Hash-Util/
                ext/I18N-Langinfo/
                ext/IPC-Open3/
                ext/NDBM_File/
                ext/ODBM_File/
                ext/Opcode/
                ext/POSIX/
                ext/PerlIO-encoding/
                ext/PerlIO-mmap/
                ext/PerlIO-scalar/
                ext/PerlIO-via/
                ext/Pod-Functions/
                ext/Pod-Html/
                ext/SDBM_File/
                ext/Sys-Hostname/
                ext/Tie-Hash-NamedCapture/
                ext/Tie-Memoize/
                ext/VMS-DCLsym/
                ext/VMS-Filespec/
                ext/VMS-Stdio/
                ext/Win32CORE/
                ext/XS-APItest/
                ext/XS-Typemap/
                ext/arybase/
                ext/mro/
                ext/re/
                lib/AnyDBM_File.{pm,t}
                lib/Benchmark.{pm,t}
                lib/B/Deparse{.pm,.t,-*.t}
                lib/B/Op_private.pm
                lib/CORE.pod
                lib/Class/Struct.{pm,t}
                lib/Config/Extensions.{pm,t}
                lib/DB.{pm,t}
                lib/DBM_Filter.pm
                lib/DBM_Filter/
                lib/DirHandle.{pm,t}
                lib/English.{pm,t}
                lib/ExtUtils/Embed.pm
                lib/ExtUtils/XSSymSet.pm
                lib/ExtUtils/t/Embed.t
                lib/ExtUtils/typemap
                lib/fake_signatures.{pm,t}
                lib/File/Basename.{pm,t}
                lib/File/Compare.{pm,t}
                lib/File/Copy.{pm,t}
                lib/File/stat{.pm,.t,-7896.t}
                lib/FileHandle.{pm,t}
                lib/FindBin.{pm,t}
                lib/Getopt/Std.{pm,t}
                lib/Internals.t
                lib/meta_notation.{pm,t}
                lib/Net/hostent.{pm,t}
                lib/Net/netent.{pm,t}
                lib/Net/protoent.{pm,t}
                lib/Net/servent.{pm,t}
                lib/PerlIO.pm
                lib/Pod/t/InputObjects.t
                lib/Pod/t/Select.t
                lib/Pod/t/Usage.t
                lib/Pod/t/utils.t
                lib/SelectSaver.{pm,t}
                lib/Symbol.{pm,t}
                lib/Thread.{pm,t}
                lib/Tie/Array.pm
                lib/Tie/Array/
                lib/Tie/ExtraHash.t
                lib/Tie/Handle.pm
                lib/Tie/Handle/
                lib/Tie/Hash.{pm,t}
                lib/Tie/Scalar.{pm,t}
                lib/Tie/StdHandle.pm
                lib/Tie/SubstrHash.{pm,t}
                lib/Time/gmtime.{pm,t}
                lib/Time/localtime.{pm,t}
                lib/Time/tm.pm
                lib/UNIVERSAL.pm
                lib/Unicode/README
                lib/Unicode/UCD.{pm,t}
                lib/User/grent.{pm,t}
                lib/User/pwent.{pm,t}
                lib/_charnames.pm
                lib/attributes.pm
                lib/blib.{pm,t}
                lib/bytes.{pm,t}
                lib/bytes_heavy.pl
                lib/charnames.{pm,t}
                lib/cperl.pm
                lib/dbm_filter_util.pl
                lib/deprecate.pm
                lib/diagnostics.{pm,t}
                lib/dumpvar.{pl,t}
                lib/feature.{pm,t}
                lib/feature/
                lib/filetest.{pm,t}
                lib/h2ph.t
                lib/h2xs.t
                lib/integer.{pm,t}
                lib/less.{pm,t}
                lib/locale.{pm,t}
                lib/open.{pm,t}
                lib/overload/numbers.pm
                lib/overloading.{pm,t}
                lib/overload{.pm,.t,64.t}
                lib/perl5db.{pl,t}
                lib/perl5db/
                lib/sigtrap.{pm,t}
                lib/sort.{pm,t}
                lib/strict.{pm,t}
                lib/subs.{pm,t}
                lib/unicore/
                lib/utf8.{pm,t}
                lib/utf8_heavy.pl
                lib/vars{.pm,.t,_carp.t}
                lib/vmsish.{pm,t}
                ],
    },
);

# legacy CPAN flag
for ( values %Modules ) {
    $_->{CPAN} = !!$_->{DISTRIBUTION};
}

# legacy UPSTREAM flag
for ( keys %Modules ) {
    # Keep any existing UPSTREAM flag so that "overrides" can be applied
    next if exists $Modules{$_}{UPSTREAM};

    if ($_ eq '_PERLLIB' or $Modules{$_}{FILES} =~ m{^\s*(?:dist|ext|lib)/}) {
        $Modules{$_}{UPSTREAM} = 'blead';
    }
    elsif ($Modules{$_}{FILES} =~ m{^\s*cpan/}) {
        $Modules{$_}{UPSTREAM} = 'cpan';
    }
    else {
        warn "Unexpected location of FILES for module $_: $Modules{$_}{FILES}";
    }
}

# legacy MAINTAINER field
for ( keys %Modules ) {
    # Keep any existing MAINTAINER flag so that "overrides" can be applied
    next if exists $Modules{$_}{MAINTAINER};

    if ($Modules{$_}{UPSTREAM} eq 'blead') {
        $Modules{$_}{MAINTAINER} = 'P5P';
        $Maintainers{P5P} = 'perl5-porters <perl5-porters@perl.org>';
    }
    elsif (exists $Modules{$_}{DISTRIBUTION}) {
        (my $pause_id = $Modules{$_}{DISTRIBUTION}) =~ s{/.*$}{};
        $Modules{$_}{MAINTAINER} = $pause_id;
        $Maintainers{$pause_id} = "<$pause_id\@cpan.org>";
    }
    else {
        warn "No DISTRIBUTION for non-blead module $_";
    }
}

1;
