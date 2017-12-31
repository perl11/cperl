use ExtUtils::MakeMaker;
use Config;
use File::Spec;
use 5.006;
use Carp;


if ($Config{d_cplusplus}) {
    # ByteLoader/Bytecode can but don't bother
    print "error B-C cannot yet be compiled with C++\n";
    exit(1);
}

my $CORE = $ENV{PERL_CORE} || grep { $_ eq 'PERL_CORE=1' } @ARGV;
mkdir "lib/B/C" unless -d "lib/B/C";
unless (-e 'lib/B/C/Config.pm') {
    open PH, ">", "lib/B/C/Config.pm";
    print PH "package B::C::Config;\n\n";
    print PH "\n1;\n";
    close PH;
    chmod 0644, "lib/B/C/Config.pm";
}

# my $X = $^X =~ / / ? qq("$^X") : $^X;
if ($CORE) {
    $ENV{PERL_CORE} = 1;
    system($^X,"-I".File::Spec->catfile(qw(.. .. lib)),
           "-I".File::Spec->catfile(qw(.. .. regen)),
           "bytecode.pl");
} else {
    my $asmdata = File::Spec->catfile('lib', 'B', 'Asmdata.pm');
    # generate lib/B/Asmdata.pm
    unlink $asmdata if -f $asmdata;
    system($^X, "bytecode.pl");
}

my ($use_declare_independent_comalloc, $extra_cflags, $extra_libs) = (0, "", "");
my $have_independent_comalloc = check_independent_comalloc();
if (grep { $_ eq 'INSTALL_PTMALLOC3' } @ARGV) {
    install_independent_comalloc() ;
    $have_independent_comalloc = check_independent_comalloc();
}
my $have_op_rettype = check_op_rettype();
my $have_HEK_STATIC = check_hek_static();
{
    my ($e_c) = grep { /-extra-cflags[= ](.+)/ } @ARGV;
    my ($e_l) = grep { /-extra-libs[= ](.+)/ } @ARGV;
    $extra_cflags .= " $e_c" if $e_c;
    $extra_libs .= " $e_l" if $e_l;
}
# cygwin still has the old gdb-6 debugger which does not understand dwarf4 features from gcc-4.5
#if ($Config{gccversion} =~ /^4\.[56]\./) {
#    my $gdb_ver = `gdb --version`;
#    if ($gdb_ver =~ /gdb 6\./) {
#        print "Adding extra_cflags=-gstrict-dwarf for gcc-4.5 for a gdb-6 debugger which does not understand dwarf4 features\n";
#        $extra_cflags .= " -gstrict-dwarf";
#    }
#}
my $have_byteloader = $] < 5.022 ? 1 : check_byteloader();

# does not work with miniperl
sub b_c_deps {
    my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
    my $blib = "-I".File::Spec->catfile(qw(.. .. lib auto))
      ." -I".File::Spec->catfile(qw(.. .. lib));
    my $runperl = $X . ($CORE ? ' '.$blib : "");
    return "AnyDBM_File AutoLoader B B::AV B::Asmdata B::BINOP B::BM B::C B::C::Config B::C::InitSection B::C::Section B::CC B::COP B::CV B::FAKEOP B::FM B::GV B::HE B::HV B::INVLIST B::IO B::IV B::LEXWARN B::LISTOP B::LOGOP B::LOOP B::MAGIC B::METHOP B::NULL B::NV B::OBJECT B::OP B::PADLIST B::PADNAME B::PADNAMELIST B::PADOP B::PMOP B::PV B::PVIV B::PVLV B::PVMG B::PVNV B::PVOP B::REGEXP B::RHE B::RV B::SPECIAL B::STASHGV B::SV B::SVOP B::Section B::UNOP B::UNOP_AUX B::UV CORE CORE::GLOBAL Carp Config DB DynaLoader EV Encode Errno Exporter Exporter::Heavy ExtUtils ExtUtils::Constant ExtUtils::Constant::ProxySubs Fcntl FileHandle IO IO::File IO::Handle IO::Poll IO::Seekable IO::Socket IO::Socket::SSL Int Internals Net Net::DNS Num O POSIX PerlIO PerlIO::Layer PerlIO::scalar Regexp SelectSaver Str Symbol UInt UNIVERSAL XSConfig XSLoader __ANON__ arybase arybase::mg attributes constant coretypes int main mro num re str strict threads uint utf8 vars version warnings warnings::register Socket" if $CORE and $] > 5.020;
    return `$runperl -Ilib -mB::C -mO -MB -e"B::C::collect_deps()"`;
}

# does not work with miniperl
sub write_b_c_config {
    my $version = shift;
    mkdir "lib/B/C" unless -d "lib/B/C";
    my $b_c_deps = b_c_deps();
    $b_c_deps .= " Socket" if $] > 5.021;
    open PH, ">", "lib/B/C/Config.pm";
    print PH "# written by B::C Makefile.PL. \$extra_{cflags,libs} need a leading space if used.\n";
    print PH "package B::C::Config;\n\n";
    my $devnull = $^O eq 'MSWin32' ? 'NUL' : '/dev/null';
    print PH "\$VERSION = '$version';\n";
    my $REV = '';
    if (my $sha1 = `git rev-list HEAD -1 --abbrev=7 --abbrev-commit 2>$devnull`) {
        chomp $sha1;
        # POSIX systems only with wc
        if (my $num = `git rev-list --abbrev-commit HEAD | wc -l 2>$devnull`) {
            chomp $num;
            $REV .= "-$num";
        }
        $REV .= '-g'.$sha1;
        print PH "\$B::C::REVISION = '$REV';\n\n";
    }
    print PH "# -fav-init optimization\n";
    print PH "\$have_independent_comalloc = $have_independent_comalloc;\n";
    print PH "\$use_declare_independent_comalloc = $use_declare_independent_comalloc;\n\n";
    print PH "# broken or patched upstream 5.22 ByteLoader. undef for yet undecided\n";
    $have_byteloader = 0 if $Config{usecperl}; # have it, but still broken
    print PH "\$have_byteloader = $have_byteloader;\n";
    print PH "# cperl 5.22.2:\n";
    print PH "\$have_op_rettype = $have_op_rettype;\n";
    print PH "\$have_HEK_STATIC = $have_HEK_STATIC;\n";
    print PH "# use extra compiler flags, after ccopts, resp. ldopts\n";
    print PH "\$extra_cflags = \"$extra_cflags\";\n";
    print PH "\$extra_libs = \"$extra_libs\";\n";
    print PH "\@deps = qw( ", $b_c_deps, " );\n\n";

    if (!$CORE) { # miniperl cannot load Scalar::Util
        require Data::Dumper;
        $Data::Dumper::Terse=1;
        $Data::Dumper::Sortkeys=1;
    }
    my %cfg;
    my $conf = "(\n";
    # Ensure to add all used Config keys in B::C here, otherwise they will be silently empty.
    # easier hash key/value slices only came with 5.22
    for my $s (qw(archname cc ccflags
                  d_c99_variadic_macros d_dlopen d_isinf d_isnan d_longdbl dlext
                  i_dlfcn ivdformat ivsize longsize mad nvgformat ptrsize static_ext
                  usecperl usedl useithreads uselongdouble usemultiplicity usemymalloc uvuformat))
    {
        if ($CORE) {
            my $v = $Config::Config{$s};
            if (!defined $v) {
                $v = 'undef';
            } else {
                $v =~ s/'/\\'/g;
                if ($v !~ /^\d+$/) {
                    $v = "'".$v."'";
                }
            }
            $conf .= "\t$s => $v,\n";
        } else {
            $cfg{$s} = $Config::Config{$s};
        }
    }
    if ($CORE) {
        $conf .= ");";
    } else {
        $conf = Data::Dumper::Dumper(\%cfg);
        $conf =~ s/^\s*{/(/;
        $conf =~ s/}\s*$/);/;
    }
    print PH "our \%Config = $conf\n";
    print PH "\n";
    print PH "1;\n";
    close PH;
    chmod 0644, "lib/B/C/Config.pm";
}

# XXX Check for 5.16.0 B-1.34 and offer to patch it? rather use `perlall build --patches=Compiler`
my $unicode_warning =
         "  Perl handling of new unicode identifiers - package and symbol names - \n".
	 "  without proper TR39 handling is considered a security risc and is not fully supported.\n".
	 "  See http://websec.github.io/unicode-security-guide/\n\n";
if ($ENV{PERL_CORE}) {
    # supress the TR39 warnings in core
}
elsif ($] > 5.015005 and $] < 5.019004) {
    # We do not want to support binary identifiers. syscalls with 5.019004 should be enabled
    warn "Warning: Bad perl version $]\n".
	 $unicode_warning.
	 "  Check your code for syntax spoofs, confusables, esp. strip \\0 from package names.\n";
} elsif ($] >= 5.019004 and !($Config{usecperl} and $] >= 5.025002)) {
    warn "Warning:\n".
	 $unicode_warning.
	 "  Check your code for syntax spoofs, confusables, strip \\0 from package names.\n".
         ($Config{usecperl} ? "" :
	 "  Enable use warnings 'syscalls'.\n");
}

my $perlcc = File::Spec->catfile("script", "perlcc");
if ($CORE and $^O eq 'MSWin32') {
    $perldll = $Config{usecperl} ? "cperl*.dll" : "perl*.dll";
    system("copy ..\..\$perldll *.*");
}

WriteMakefile(
    NAME	 => "B::C",
    VERSION_FROM => "lib/B/C.pm",
    PL_FILES   => { $perlcc.'.PL'    => $perlcc },
    EXE_FILES  => [$perlcc, qw(script/cc_harness script/assemble script/disassemble)],
    PREREQ_PM  => {'Opcodes'  => '0',    # optional
		   'IPC::Run' => '0',    # optional
		   'B::Flags' => '0.15', # optional
		   'Time::HiRes' => '0', # optional
		   'ExtUtils::Embed' => '1.25' # mandatory (missing on redhat)
                   #'B'        => '1.0901' # required but in CORE
                  },
    'AUTHOR'   => 'Reini Urban <perl-compiler@googlegroups.com>, '
                . 'Malcolm Beattie (retired)',
    'ABSTRACT' => 'Perl compiler',
    'LICENSE'  => 'perl',
    # was in core until 5.9.5, need to update it there
    (($] < 5.010 || $Config{usecperl}) ?
     ('INSTALLDIRS' => 'perl') : ()),
    (($ExtUtils::MakeMaker::VERSION gt '6.31' and $ExtUtils::MakeMaker::VERSION lt '6.46') ?
       ('EXTRA_META'  => "recommends:\n" .
        "    B::Flags:  0.15\n".
        "    B::Debug:  1.16\n".
        "    Opcodes:   0.10\n".
        "    IPC::Run:  0\n",
       ) : ()),
    ($ExtUtils::MakeMaker::VERSION gt '6.46' ?
    ('META_MERGE'  => {"recommends" =>
                       {
                        'B::Flags' => '0.15',
                        "B::Debug" => '1.16',
                        "Opcodes"  => '0.10',
                        "IPC::Run" => 0,
                       },
                       resources =>
                       {
                        license     => 'http://dev.perl.org/licenses/',
                        bugtracker  => 'https://github.com/rurban/perl-compiler/issues',
                        repository  => 'https://github.com/rurban/perl-compiler',
                       },
                      }
    ) : ()),
    SIGN  => 1,
    clean => { FILES =>
               "bytecode[0-9]* ".
               "lib/B/Asmdata.pm script/perlcc ccode* cccode* Ccode* lib/B/C/Config.pm ".
 	       "*.core *.stackdump a.out a.exe *.cee *.c *.asm *.dbg *.plc *.obj ".
               "*.concise *~ dll.base dll.exp mod.pl pcc* *.bak *.a ".
               "t/CORE/v5.*/*/*.bin t/CORE/v5.*/*/*.c Io_argv* t/CORE/v5.*/*/*.subtest.*.t ".
               "t/CORE/v5.*/xtestc* t/CORE/v5.*/C-COMPILED/xtestc/*.t ".
               "t/CORE/v5.*/tmp* tmp* ".
               "perl*.dll cperl*.dll "
             },
);

sub headerpath {
    if ($CORE) {
	return File::Spec->catdir(File::Spec->updir,
				  File::Spec->updir);
    } else {
	return File::Spec->catdir($Config::Config{archlibexp}, "CORE");
    }
}


# probe for broken or patched ByteLoader since 5.22
# sets $B::C::Config::have_byteloader
sub check_byteloader {
    return 1 if $Config{usecperl} and $] >= 5.022002;
    'undef';
}

# Check for Doug Lea's dlmalloc version, or ptmalloc2 included in glibc
# or the best: ptmalloc3 with independent_comalloc().
# http://www.malloc.de/malloc/ptmalloc3-current.tar.gz
# This improves -fav-init startup speed dramatically (18% tested).
# ptmalloc3 needs #include <malloc-2.8.3.h>, but we don't want to clash
# with an existing malloc.h from perl.h, so we declare it by ourselves.
sub try_compile {
    my $testc = shift;
    my $libs = shift;
    # For consistency (without considering LD_PRELOAD) require perl to
    # be compiled with the same malloc library.
    return 0 unless $Config{libs} =~ /\b\Q$libs\E\b/;
    unless (open PROG, ">", "test.c") {
        print ("Can't write test.c\n");
        return 0;
    }
    print PROG $testc;
    close PROG;
    @candidate = ();
    $devnull = $^O eq 'MSWin32' ? "> NUL" : ">/dev/null 2>&1";
    my $cmd = "$Config{cc} $Config{ccflags} test.c";
    push @candidate, "$cmd -o test$Config{EXE_EXT} $libs $devnull";
    push @candidate, "$cmd -otest$Config{EXE_EXT} $libs $devnull";
    while (my $cmd1 = shift (@candidate)) {
	system ($cmd1);
	unlink "test.c", "test$Config{EXE_EXT}";
	$? == 0 && return 1;
    }
    return 0;
}

sub check_op_rettype {
    return 0 if !$Config{usecperl};
    my $op_h = File::Spec->catfile(headerpath(), 'op.h');
    my ($fh, $found);
    open $fh, $op_h or die "$op_h: $!";
    while(<$fh>) {
        if (/^\s+U8\s+op_rettype/) {
            close $fh;
            return 1;
        }
    }
    close $fh;
    return 0;
}
sub check_hek_static {
    return 0 if !$Config{usecperl};
    my $hv_h = File::Spec->catfile(headerpath(), 'hv.h');
    my ($fh, $found);
    open $fh, $hv_h or die "$hv_h: $!";
    while(<$fh>) {
        if (/^#define HEK_STATIC/) {
            close $fh;
            return 1;
        }
    }
    close $fh;
    return 0;
}

sub check_independent_comalloc {
    my $testori = "
#include <stdlib.h>
#include <malloc.h>
int main() {
    void* chunks[3];
    size_t sizes[3] = {3,25,4};
    if (independent_comalloc( 3, sizes, chunks ) == 0) { exit(1); };
    return 0;
}
";
    my $testc = $testori;
    if (try_compile($testc)) {
	warn "-fav-init2 available: independent_comalloc() as-is activated\n";
	return 1;
    }

    my @extra_libs = ("-lptmalloc3", "-lptmalloc", "-ldlmalloc", "-lnedmalloc");
    for my $lib (@extra_libs) {
        $lib =~ s/^-l(.+)$/lib$1.lib/ if $^O eq 'MSWin32';
        if (try_compile($testc, $lib)) {
            $extra_libs = " $lib";
	    warn "-fav-init2 available: independent_comalloc() with $lib activated\n";
            return 1;
        }
    }
    # try without the ptmalloc3 header, just the library
    $testc =~ s/#include <malloc>/void** dlindependent_comalloc(size_t, size_t*, void**);/;
    for (@extra_libs) {
	my $lib = $_;
        $lib = 'libptmalloc3.lib' if $^O eq 'MSWin32';
        $lib =~ s/^-l(.+)$/lib$1.lib/ if $^O eq 'MSWin32';
        if (try_compile($testc, $lib)) {
            $extra_libs = " $lib";
            $use_declare_independent_comalloc = 1;
	    warn "-fav-init2 available: dlindependent_comalloc() with $lib activated\n";
            return 1;
        }
    }
    # Desperate. External ptmalloc3 header to overcome -I path shadowing
    $testc = $testori;
    $testc =~ s/#include <malloc.h>/#include "malloc-2.8.3.h"/;
    my $lib = "-lptmalloc3";
    $lib = 'libptmalloc3.lib' if $^O eq 'MSWin32';
    if (try_compile($testc, $lib)) {
	$extra_cflags = " -DNEED_MALLOC_283";
	$extra_libs = " $lib";
	warn "-fav-init2 available: independent_comalloc() with -DNEED_MALLOC_283 $lib activated\n";
	return 1;
    }
    #warn "-fav-init2 not available, independent_comalloc() not detected.\n";
    #warn "  Install on POSIX systems with:\n";
    #warn "  $^X Makefile.PL INSTALL_PTMALLOC3\n\n";
    return 0;
}

sub _system{
    print join(" ",@_),"\n";
    local $!;
    system @_;
    croak $! if $!;
}

sub install_independent_comalloc {
    print "INSTALL_PTMALLOC3 from <http://www.malloc.de/en/index.html>\n";
    -f 'ptmalloc3-current.tar.gz'
      or _system(qw(wget http://www.malloc.de/malloc/ptmalloc3-current.tar.gz));
    -d 'ptmalloc3'
      or _system('tar xfz ptmalloc3-current.tar.gz');
    chdir "ptmalloc3" or die;
    if ($Config{useithreads}) { 
	# linux-pthread is basically the same. linux-shared is also an option.
	# just Solaris, SGI and HPUX need different options.
	_system(qw(make posix));
    } else {
	_system(qw(make nothreads));
    }
    _system('make check');
    _system('sudo cp libptmalloc3.a /usr/lib/');
    warn "No you must recompile your perl with linking to this library\n";
    chdir "..";
}

package MY;

# Ignore certain files
sub libscan {
    # Ignore temp files
    return 0 if $_[1] =~ /^(\.git|.*\.orig|bytecode.*\.pl|c?ccode.*|regen_lib\.pl|GTAGS|GPATH|GRTAGS)$/;
    # Ignore Bytecode on 5.6 for now. The 5.6 CORE module produces better code (until fixed :)
    # Not even the Byteloader works for 5.6 assembled code. The Disassembler does not stop at ret.
    return 0 if $] < 5.007 and $_[1] =~ /ByteLoader|Asmdata\.pm|Bytecode\.pm|Assembler\.pm/;
    # On windows the C compiler would work if DynaLoader.lib would be provided.
    # return 0 if $^O eq 'MSWin32' and !-d ".git" and $_[1] =~ /C\.pm|C\.xs|Stackobj\.pm/;
    return $_[1];
}


# Fix ActivePerl for MSVC6
# The linker for cl 12.0.8804 has no -opt:ref,icf, which is MSVC8 linker syntax.
sub const_config {
    my $s = shift->SUPER::const_config(@_);
    if ($Config::Config{ccversion} eq '12.0.8804' and $Config::Config{cc} eq 'cl') {
	$s =~ s/ -opt:ref,icf//gm;
    }
    $s
}

sub post_constants {
    my $mm = shift;
    main::write_b_c_config($mm->{VERSION});
    my $libs = "\nLIBS = $Config::Config{libs}";
    $libs .= $extra_libs if $extra_libs;
    #XXX PERL_MALLOC_DEF = -DPERL_EXTMALLOC_DEF -Dmalloc=Perl_malloc -Dfree=Perl_mfree -Drealloc=Perl_realloc -Dcalloc=Perl_calloc
    return "$libs\n";
}

sub ccflags {
    my $ccflags = shift->SUPER::ccflags(@_);
    $ccflags .= " -DHAVE_INDEPENDENT_COMALLOC" if $have_independent_comalloc;
    $ccflags .= $extra_cflags if $extra_cflags;
    return $ccflags if !-d ".git" or $ENV{NO_AUTHOR};
    # Recommended by http://www.network-theory.co.uk/docs/gccintro/gccintro_32.html
    # -ansi -pedantic -Wall -W -Wconversion -Wshadow -Wcast-qual -Wwrite-strings (-W => -WExtra)
    $ccflags .= " -ansi -pedantic -Wall -Wextra -Wconversion -Wshadow -Wcast-qual -Wwrite-strings"
      if $Config{cc} =~ /\bgcc/ and $Config{gccversion};
}

sub depend {
    my $headerpath = main::headerpath();
    my @headers = map { File::Spec->catfile($headerpath, $_) } qw(op.h cop.h sv.h);
    my $asmdata = File::Spec->catfile('lib', 'B', 'Asmdata.pm');
    my $byterun_c = File::Spec->catfile('ByteLoader', 'byterun.c');
    my $byterun_h = File::Spec->catfile('ByteLoader', 'byterun.h');
    my $result = "
$asmdata : Makefile bytecode.pl @headers
	\$(PERLRUN) bytecode.pl

$byterun_c : Makefile bytecode.pl @headers
	\$(PERLRUN) bytecode.pl

$byterun_h : Makefile bytecode.pl @headers
	\$(PERLRUN) bytecode.pl

TAGS : $asmdata
	etags --language=perl lib/B/*.pm
";
    if ($] > 5.009 and defined($ExtUtils::MM_Unix::VERSION)) {
        my $ver = 0+$ExtUtils::MM_Unix::VERSION;
        # 8.0403 is the cperl 5.24.0 version based on 7.04_03
        if ($ver == 8.0403 or $ver == 8.0404 or $ver < 7.0509 or $ver == 7.1) {
            $result .= "\ntest :: subdirs-test\n\n";
        } else {
            $result .= "\ntest :: subdirs-test_\$(LINKTYPE)\n\n";
        }
    }
    if ($Config{make} eq 'mingw32-make') { # mingw32 make different to msys make
        $result .= "\n.PHONY : \$(CONFIGDEP)\n\n";
    }
    $result;
}

# force reconfig of B::C::Config with compiled ByteLoader
sub subdirs {
    my $s = shift->SUPER::subdirs(@_);
    if ($] >= 5.022) {
        my $bcflags = File::Spec->catfile('lib', 'B', 'C', 'Config.pm');
        my $bytehintspatched = File::Spec->catfile('ByteLoader', 'hints', '522_patched.pl');
        return $s . "

subdirs ::
	\$(PERL) \"-I\$(PERL_ARCHLIB)\" $bytehintspatched
";
    } else {
        $s
    }
}

sub test {
    shift->SUPER::test(@_) .
"
PERL_VER = v5.".substr($],3,2) .
      q(
testmod :: pure_all
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) -Iblib/arch -Iblib/lib t/modules.t
testmodall :: pure_all
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) -Iblib/arch -Iblib/lib t/modules.t -no-subset -no-date t/top100
testc :: pure_all
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) -Iblib/arch -Iblib/lib t/c.t
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) -Iblib/arch -Iblib/lib t/c_o3.t
testcc :: pure_all
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) -Iblib/arch -Iblib/lib t/cc.t
testbc :: pure_all
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) -Iblib/arch -Iblib/lib t/bytecode.t
testfast :: pure_all
	NO_AUTHOR=1 $(FULLPERLRUN) -S prove -b -j10 -f
testfast-log :: pure_all
	NO_AUTHOR=1 $(FULLPERLRUN) -S prove -b -j10 -f  | tee log.test-).$].q(-`git describe --tags`
testcritical :: pure_all
	t/critical.sh
teststatus :: pure_all
	./status_upd -fqd
testrelease :: pure_all
	$(ECHO) run t/release-testing.sh and perlall testvm --all
testcore_init :: t/CORE
	t/core-init.sh
testcore :: pure_all testcore_init
	$(FULLPERLRUN) -S prove -b -j10 -f t/CORE/$(PERL_VER)/C-COMPILED/*/
testcore-log :: pure_all testcore_init
	$(FULLPERLRUN) -S prove -b -j10 -f t/CORE/$(PERL_VER)/C-COMPILED/*/ | \
	  tee log.test-core-$(PERL_VER)-`git describe --tags`
testcore-fail :: pure_all testcore_init
	$(FULLPERLRUN) -ane'print "t/CORE/$(PERL_VER)/C-COMPILED/$$F[0]\n" unless /^#/' t/CORE/$(PERL_VER)/C-COMPILED/known_errors.txt | xargs $(FULLPERLRUN) -S prove -b -j10 -f
)
}

sub install {
    my $result = shift->SUPER::install(@_);
    my $headerpath = main::headerpath();
    my $cc_runtime_h = File::Spec->catfile($headerpath, 'cc_runtime.h');
    if ($] > 5.013007 and !-e $cc_runtime.h) {
        $result =~ s/install :: pure_install doc_install/install :: pure_install doc_install ccinc_install/;
	$result .= '
ccinc_install :: $(PERL_INC)/cc_runtime.h

$(PERL_INC)/cc_runtime.h : cc_runtime.h
	$(NOECHO) $(CP) cc_runtime.h $@ || true
';
    }
    $result
}

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
