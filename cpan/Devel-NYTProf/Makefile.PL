# vim: ts=8 sw=2 sts=0 noexpandtab:
##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://metacpan.org/release/Devel-NYTProf/
##
###########################################################

use 5.008001;
use warnings;
use strict;

use ExtUtils::MakeMaker;
use Getopt::Long;
use Config;
use File::Spec;

my $is_developer = (-d '.git');

# This lets perl developers build under ext/Devel, and profile parts of the core in place
unless($ENV{PERL_CORE}) {
    $ENV{PERL_CORE} = 1 if grep { $_ eq 'PERL_CORE=1' } @ARGV;
}
my @man;
if ($ENV{PERL_CORE}) {
    @man = ( MAN1PODS => {}, MAN3PODS => {} );
} else {
    @man = ( MAN1PODS  => {
        'bin/nytprofhtml' => '$(INST_MAN1DIR)/nytprofhtml.1',
        'bin/nytprofmerge'=> '$(INST_MAN1DIR)/nytprofmerge.1',
        'bin/nytprofcsv'  => '$(INST_MAN1DIR)/nytprofcsv.1',
        'bin/nytprofcalls'=> '$(INST_MAN1DIR)/nytprofcalls.1',
        'bin/nytprofcg'   => '$(INST_MAN1DIR)/nytprofcg.1',
        'bin/nytprofpf'   => '$(INST_MAN1DIR)/nytprofpf.1'
    } );
}

# --- Options
GetOptions(
    'g!'      => \my $opt_g,            # compile with -g (for debugging)
    'assert!' => \my $opt_assert,       # enable assert()ions in the code (and perl headers)
    'pg!'     => \my $opt_pg,           # compile with -pg (for profiling NYTProf itself)
    'zlib!'     => \(my $opt_zlib=1),       # --nozlib to disallow use of zlib
    'gettime!'  => \(my $opt_gettime=1),    # --nogettime to disallow use of POSIX clock_gettime
    'machtime!' => \(my $opt_machtime=1),   # --nomachtime to disallow use of mac osx clock
) or exit 1;

if (not defined $opt_assert) {
    $opt_assert = 1 if $opt_g;
    $opt_assert = 1 if $ENV{AUTOMATED_TESTING}; # enable assert()s for cpan-testers
}

# The -m32 cross-compiler traditionally gets this wrong
if ($ENV{PERL_CORE} and ($Config{ccflags} =~ /-m32/ or $Config{cc} =~ / -m32/)) {
  $opt_zlib = 0;
}

# --- make sure t/test40pmc.pmc is newer than t/test40pmc.pmc (??)
if (-f "t/test40pmc.pmc") {
  utime time(), time(), "t/test40pmc.pmc"
    or die "Can't update mod time of t/test40pmc.pmc";
}


# --- Discover how much of stdio is implemented

my $cpp = $Config{cpp} || do {
    warn "Warning: cpp not found in your perl config.  Falling back to 'cat'\n";
    'cat';
};

print "Looking for header files and functions...\n";
my $INCLUDE;

my $h_files;
my @h_dirs;
push @h_dirs, split /:/, $ENV{INCLUDE} if $ENV{INCLUDE};
push @h_dirs, split ' ', $Config{libsdirs};
push @h_dirs, qw(/include /usr/include /usr/local/include /usr/include/mach);
@h_dirs = grep { -d $_ } @h_dirs;

$h_files = find_h_files(@h_dirs);

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
my %mm_opts;
my @libs = ();

my @hdr_match_lib;
push @hdr_match_lib, ['time.h', qr/(clock_gettime)\s*\(/, '-DHAS_CLOCK_GETTIME', '-lrt']
    if $opt_gettime;
push @hdr_match_lib, ['zlib.h', qr/(deflateInit2)(?:_)?\s*\(/, '-DHAS_ZLIB',     '-lz']
    if $opt_zlib;
push @hdr_match_lib, ['mach_time.h', qr/(mach_absolute_time)\s*\(/, '-DHAS_MACH_TIME', undef]
    if $opt_machtime and $^O eq 'darwin';

foreach (@hdr_match_lib) {
    my ($header, $regexp, $define, $libs) = @$_;
    if (my $result = search_h_file($header, $regexp)) {
        print "Found $result in $header\n";
        push @libs, $libs if $libs;
        $mm_opts{DEFINE} .= " $define" if $define;
    }
}

if ($opt_assert or (not defined $opt_assert and $is_developer)) {
    warn "Assertion testing enabled\n";
    $mm_opts{DEFINE} .= " -DUSE_HARD_ASSERT";
}

if ($ENV{NYTP_MAX_SUB_NAME_LEN}) {
    $mm_opts{DEFINE} .= " -DNYTP_MAX_SUB_NAME_LEN=$ENV{NYTP_MAX_SUB_NAME_LEN}";
}

$mm_opts{LICENSE}  = 'perl' if $ExtUtils::MakeMaker::VERSION >= 6.3002;
$mm_opts{OPTIMIZE} = '-g'   if $opt_g;
$mm_opts{CCFLAGS}  = "-pg"  if $opt_pg;

if( $ExtUtils::MakeMaker::VERSION >= 6.45 ) {
    $mm_opts{META_MERGE} = {
    	"meta-spec" => { version => 2 },
	no_index => {
	    package => [ 'SVG' ], # in bin/flamegraph.pl
	},
        resources => {
            license     => 'http://dev.perl.org/licenses/',
            homepage    => 'https://code.google.com/p/perl-devel-nytprof/',
            bugtracker  => {
                web    => 'https://github.com/timbunce/devel-nytprof/issues',
                # old => 'http://rt.cpan.org/Public/Dist/Display.html?Name=Devel-NYTProf',
                mailto => 'bug-devel-nytprof@rt.cpan.org',
            },
            repository  => {
                url  => 'git://github.com/timbunce/devel-nytprof.git',
                web  => 'https://github.com/timbunce/devel-nytprof',
                type => 'git',
            },
            # not a valid key:
            MailingList => 'http://groups.google.com/group/develnytprof-dev',
        }
    }
}

if (my $gccversion = $Config{gccversion}) {    # ask gcc to be more pedantic
    print "Your perl was compiled with gcc (version $Config{gccversion}), okay.\n";
    $gccversion =~ s/[^\d\.]//g;               # just a number please
    $mm_opts{DEFINE} .= ' -W -Wall -Wpointer-arith';
    $mm_opts{DEFINE} .= ' -Wbad-function-cast' unless $Config{d_cplusplus};
    $mm_opts{DEFINE} .= ' -Wno-comment -Wno-sign-compare -Wno-cast-qual';
    $mm_opts{DEFINE} .= ' -Wmissing-noreturn -Wno-unused-parameter' if $gccversion ge "3.0";
    if ($is_developer && $opt_g) {
        $mm_opts{DEFINE} .= ' -DPERL_GCC_PEDANTIC -ansi -pedantic' if $gccversion ge "3.0";
        $mm_opts{DEFINE} .= ' -Wdisabled-optimization -Wformat'    if $gccversion ge "3.0";
        $mm_opts{DEFINE} .= ' -Wmissing-prototypes';
    }
}


WriteMakefile(
    NAME          => 'Devel::NYTProf',
    VERSION_FROM  => 'lib/Devel/NYTProf/Core.pm',    # finds $VERSION
    ABSTRACT_FROM => 'lib/Devel/NYTProf.pm',         # retrieve abstract from module
    AUTHOR    => 'Tim Bunce <timb@cpan.org>',
    LICENSE => 'perl',
    PREREQ_PM => {
        'List::Util'   => 0,
        'Test::More'   => '0.84',
        'File::Which'  => '1.09',
        'Test::Differences' => '0.60',
        'XSLoader'     => 0,
        'Getopt::Long' => 0,
        'Cpanel::JSON::XS' => 0,
    },
    INST_LIB  => ($ENV{PERL_CORE} ? File::Spec->catfile(qw(.. .. lib)) : 'blib/lib'),
    INST_ARCHLIB => ($ENV{PERL_CORE} ? File::Spec->catfile(qw(.. .. lib)) : 'blib/arch'),
    LIBS      => [join ' ', @libs],
    OBJECT    => q/$(O_FILES)/,
    EXE_FILES => ['bin/nytprofhtml', 'bin/flamegraph.pl', 'bin/nytprofcsv', 'bin/nytprofcalls', 'bin/nytprofcg', 'bin/nytprofmerge', 'bin/nytprofpf'],
    @man,
    INC   => $INCLUDE,
    clean => {
        FILES => join(" ",
            "nytprof demo-out",
            map { ("t/$_", "xt/$_") } qw(
                nytprof nytprof*.out nytprof*.out.* *_outdir test*.*_new auto
            ))
    },
    dist  => {
        DIST_DEFAULT => 'clean distcheck disttest tardist',
        PREOP        => '$(MAKE) -f Makefile.old distdir',
        COMPRESS     => 'gzip -v9',
        SUFFIX       => 'gz',
    },
    META_MERGE => {
      resources => {
        repository => 'https://github.com/timbunce/devel-nytprof',
      },
    },
    %mm_opts,
);

# exit 0;

# --- Utility functions ---


sub find_h_files {
    my @dirs = @_;
    my %h_files;
    foreach my $dir (@dirs) {
        next unless $dir;
        opendir(DIR, $dir)
            or next;    # silently ignore missing directories

        while (my $file = readdir(DIR)) {
            next unless $file =~ /\.h$/;
            $h_files{$file} ||= $dir;    # record first found
        }
    }
    close DIR;
    return \%h_files;
}

sub search_h_file {
    my ($h_file, $regex) = @_;
    my $dir = $h_files->{$h_file}
              or return undef;
    # darwin is very noisy preprocessing mach_time.h
    my $devnull = $^O eq 'MSWin32' ? "2>NUL" : "2>/dev/null";
    open H, "$cpp $dir/$h_file $devnull |";
    while (<H>) {
        return $1 if m/$regex/;
    }
    close H;
    return undef;
}


# --- MakeMaker overrides ---

package MY;

# add some extra utility targets to the make file
sub post_constants {
    q{

ptest prove:: pure_all
	time nice prove -b -j 9 --shuffle

# not require because it confuses the call-graph
# not dofile because it's an alias for require
# (and causes problems like http://www.nntp.perl.org/group/perl.cpan.testers/2009/12/msg6409150.html)
# not fork because it doesn't make much sense
slowops::
	$(NOECHO) $(PERL) -e 'require v5.10.0; # only regenerate with 5.10+ to get all ops'
	$(PERL) -MOpcode=opset_to_ops,opset \
	    -e 'print "/* generated by Makefile.PL for perl $$] */\n";' \
	    -e 'my @ops = opset_to_ops(opset(":base_io",":filesys_read",":filesys_write",":filesys_open",":sys_db",":subprocess",":others",qw(match subst substcont qr regcomp prtf crypt chdir flock ioctl socket getpeername ssockopt bind connect listen accept shutdown gsockopt getsockname sleep sort pack unpack syscall dump chroot dbmopen dbmclose lock sselect select), qw(!fileno !require !dofile !fork)));' \
	    -e 'print "PL_ppaddr[OP_\U$$_\E] = pp_slowop_profiler;\n" for sort @ops;' \
	    > slowops.h
	$(PERL) -e "warn qq{NOTE: slowops.h will need manual editing to restore lost #ifdef's around some opcodes!\n}";

svnmanifest::
	svn list -R .@HEAD | sort | grep -v '/$$' > MANIFEST
	svn diff MANIFEST

checkkeywords:
	$(RM_RF) blib
	find .  \( -name .svn -prune -or -name t -prune -or -name \*.pm -or -name \*.PL -or -name \*.pl \) -type f \
	    -exec bash -c '[ "$$(svn pg svn:keywords {})" != "Id Revision Date" ] && echo svn propset svn:keywords \"Id Revision Date\" {}' \;

checkpod:
	$(RM_RF) blib
	find . -type f \( -name .svn -prune -o -name \*.pm -o -name \*.PL -o -name \*.pl \) \
	    -exec podchecker {} \; 2>&1 | grep -v "pod syntax OK"

PERLTIDY=perltidy --profile=.perltidyrc -nst -b
perltidy:
	$(PERLTIDY) bin/nytprofhtml bin/nytprofcsv
	$(PERLTIDY) lib/Devel/NYTProf.pm lib/Devel/NYTProf/*.pm

# the XS portion of the file will be mangled and require manual fixup
ctidy_bcpp:
	bcpp -f 2 -i 4 -bcl -qb 10 -ylcnc -yb NYTProf.xs

}
}

sub dynamic {
    my $make = shift->SUPER::dynamic(@_);
    return $make if $Config::Config{usecperl}; # cperl has no broken XSLoader

    my $xsl_dest_dir = File::Spec->catdir('$(INST_LIB)','auto','$(FULLEXT)'.'$(PARENT_NAME)');
    my $xsl_dest     = File::Spec->catdir('$(XSL_DEST_DIR)','$(DLBASE).$(DLEXT)');

    if($^O eq 'VMS'){
        $xsl_dest_dir = File::Spec->catdir('blib','lib','Devel','auto','Devel','NYTProf');
        $xsl_dest     = File::Spec->catfile('blib','lib','Devel','auto','Devel','NYTProf','PL_Devel__NYTProf'.'.exe');
    }

    $make .= join "\n",
        '# Copy extension to where XSLoader looks to avoid fallback to DynaLoader',
        '# See t/test14.p for more details',
        "XSL_DEST_DIR = $xsl_dest_dir",
        "XSL_DEST = $xsl_dest",
        '',
        'dynamic :: $(INST_DYNAMIC)',
        "\t" . '$(NOECHO) $(MKPATH) $(XSL_DEST_DIR)',
        "\t" . '$(CP) $(INST_DYNAMIC) $(XSL_DEST)',
        '';
    return $make;
}


# vim:ts=8:sw=4:sts=0:noexpandtab
