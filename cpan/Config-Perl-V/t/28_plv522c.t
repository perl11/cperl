#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    use Test::More;
    unless ($ENV{PERL_CORE}) {
	require Test::NoWarnings;
	Test::NoWarnings->import ();
    }
}

use Config::Perl::V;

ok (my $conf = Config::Perl::V::plv2hash (<DATA>), "Read perl -V block");
ok (exists $conf->{$_}, "Has $_ entry") for qw( build environment config inc );

is ($conf->{build}{osname}, $conf->{config}{osname}, "osname");
is ($conf->{build}{stamp}, "Apr 13 2016 18:26:00", "Build time");
is ($conf->{config}{version}, "5.22.2", "reconstructed \$Config{version}");

my $opt = Config::Perl::V::plv2hash ("")->{build}{options};
foreach my $o (sort qw(
	HAS_TIMES PERLIO_LAYERS
	PERL_DONT_CREATE_GVSV
	PERL_HASH_FUNC_FNV1A
        PERL_MALLOC_WRAP
	PERL_NEW_COPY_ON_WRITE PERL_PRESERVE_IVUV
	PERL_PERTURB_KEYS_TOP
	PERL_USE_DEVEL USE_64_BIT_ALL USE_64_BIT_INT USE_CPERL
	USE_LARGE_FILES USE_LOCALE USE_LOCALE_COLLATE
	USE_LOCALE_CTYPE USE_LOCALE_NUMERIC USE_LOCALE_TIME
	USE_PERLIO USE_PERL_ATOF PERL_USE_SAFE_PUTENV
	)) {
    is ($conf->{build}{options}{$o}, 1, "Runtime option $o set");
    delete $opt->{$o};
    }
foreach my $o (sort keys %$opt) {
    is ($conf->{build}{options}{$o}, 0, "Runtime option $o unset");
    }

is_deeply ($conf->{build}{patches}, [], "No local patches");

my %check = (
    alignbytes      => 8,
    api_version     => 22,
    bincompat5005   => "undef",
    byteorder       => 12345678,
    cc              => "ccache gcc-mp-5",
    cccdlflags      => "",
    ccdlflags       => "",
    config_args     => '-sde -Dusedevel -Dusecperl -Dprefix=/usr/local -Dcc=ccache gcc-mp-5 -Dld=ccache gcc-mp-5 -Accflags=-march=corei7 -DPERL_FAKE_SIGNATURE -Doptimize=-O3 -g -Dmake=gmake -Darchname=darwin -Darchlib=/usr/local/lib/cperl/5.22.2/darwin -Dsitebin=/usr/local/lib/cperl/site_cperl/5.22.2/bin -Dscriptdir=/usr/local/lib/cperl/5.22.2/bin -Dsitearch=/usr/local/lib/cperl/site_cperl/5.22.2/darwin -Dperlpath=/usr/local/bin/cperl5.22.2-nt -Dstartperl=#!/usr/local/bin/cperl5.22.2-nt -Dinstallman1dir=none -Dinstallman3dir=none -Dinstallsiteman1dir=none -Dinstallsiteman3dir=none -Dcf_email=rurban@cpan.org',
    gccversion      => "5.3.0",
    gnulibc_version => "",
    ivsize          => 8,
    ivtype          => "long",
    ld              => "ccache gcc-mp-5",
    lddlflags       => " -bundle -undefined dynamic_lookup -L/opt/local/lib -L/usr/local/lib -L/opt/local/lib/libgcc -fstack-protector",
    ldflags         => ' -fstack-protector -L/opt/local/lib -L/usr/local/lib -L/opt/local/lib/libgcc',
    libc            => "",
    lseektype       => "off_t",
    osvers          => "15.4.0",
    use64bitint     => "define",
    );
is ($conf->{config}{$_}, $check{$_}, "reconstructed \$Config{$_}") for sort keys %check;

done_testing();

__END__
Summary of my cperl (revision 5 version 22 subversion 2) configuration:
  Commit id: aac71897dfcecc7cddabf820beba67788df0559d
  Platform:
    osname=darwin, osvers=15.4.0, archname=darwin-2level
    uname='darwin airc.local 15.4.0 darwin kernel version 15.4.0: fri feb 26 22:08:05 pst 2016; root:xnu-3248.40.184~3release_x86_64 x86_64 i386 macbookair6,2 darwin '
    config_args='-sde -Dusedevel -Dusecperl -Dprefix=/usr/local -Dcc=ccache gcc-mp-5 -Dld=ccache gcc-mp-5 -Accflags=-march=corei7 -DPERL_FAKE_SIGNATURE -Doptimize=-O3 -g -Dmake=gmake -Darchname=darwin -Darchlib=/usr/local/lib/cperl/5.22.2/darwin -Dsitebin=/usr/local/lib/cperl/site_cperl/5.22.2/bin -Dscriptdir=/usr/local/lib/cperl/5.22.2/bin -Dsitearch=/usr/local/lib/cperl/site_cperl/5.22.2/darwin -Dperlpath=/usr/local/bin/cperl5.22.2-nt -Dstartperl=#!/usr/local/bin/cperl5.22.2-nt -Dinstallman1dir=none -Dinstallman3dir=none -Dinstallsiteman1dir=none -Dinstallsiteman3dir=none -Dcf_email=rurban@cpan.org'
    hint=recommended, useposix=true, d_sigaction=define
    useithreads=undef, usemultiplicity=undef
    use64bitint=define, use64bitall=define, uselongdouble=undef
    usemymalloc=n, bincompat5005=undef
  Compiler:
    cc='ccache gcc-mp-5', ccflags ='-fno-common -DPERL_DARWIN -march=corei7 -DPERL_FAKE_SIGNATURE -fwrapv -fno-strict-aliasing -pipe -fstack-protector -I/usr/local/include -I/opt/local/include -DPERL_USE_SAFE_PUTENV',
    optimize='-O3 -g',
    cppflags='-fno-common -DPERL_DARWIN -march=corei7 -DPERL_FAKE_SIGNATURE -fwrapv -fno-strict-aliasing -pipe -fstack-protector -I/usr/local/include -I/opt/local/include'
    ccversion='', gccversion='5.3.0', gccosandvers=''
    intsize=4, longsize=8, ptrsize=8, doublesize=8, byteorder=12345678, doublekind=3
    d_longlong=define, longlongsize=8, d_longdbl=define, longdblsize=16, longdblkind=3
    ivtype='long', ivsize=8, nvtype='double', nvsize=8, Off_t='off_t', lseeksize=8
    alignbytes=8, prototype=define
  Linker and Libraries:
    ld='ccache gcc-mp-5', ldflags =' -fstack-protector -L/opt/local/lib -L/usr/local/lib -L/opt/local/lib/libgcc'
    libpth=/opt/local/lib /opt/local/lib/gcc5/gcc/x86_64-apple-darwin15/5.3.0/include-fixed /usr/lib /usr/local/lib /opt/local/lib/libgcc
    libs=-lpthread -lgdbm -ldbm -ldl -lm -lutil -lc
    perllibs=-lpthread -ldl -lm -lutil -lc
    libc=, so=dylib, useshrplib=false, libperl=libperl.a
    gnulibc_version=''
  Dynamic Linking:
    dlsrc=dl_dlopen.xs, dlext=bundle, d_dlsymun=undef, ccdlflags=' '
    cccdlflags=' ', lddlflags=' -bundle -undefined dynamic_lookup -L/opt/local/lib -L/usr/local/lib -L/opt/local/lib/libgcc -fstack-protector'


Characteristics of this binary (from libperl): 
  Compile-time options: HAS_TIMES PERLIO_LAYERS PERL_DONT_CREATE_GVSV
                        PERL_HASH_FUNC_FNV1A PERL_MALLOC_WRAP
                        PERL_NEW_COPY_ON_WRITE PERL_PERTURB_KEYS_TOP
                        PERL_PRESERVE_IVUV PERL_USE_DEVEL
                        PERL_USE_SAFE_PUTENV USE_64_BIT_ALL USE_64_BIT_INT
                        USE_CPERL USE_LARGE_FILES USE_LOCALE
                        USE_LOCALE_COLLATE USE_LOCALE_CTYPE
                        USE_LOCALE_NUMERIC USE_LOCALE_TIME USE_PERLIO
                        USE_PERL_ATOF
  Built under darwin
  Compiled at Apr 13 2016 18:26:00
  @INC:
    /usr/local/lib/cperl/site_cperl/5.22.2/darwin
    /usr/local/lib/cperl/site_cperl/5.22.2
    /usr/local/lib/cperl/5.22.2/darwin
    /usr/local/lib/cperl/5.22.2
    /usr/local/lib/cperl/site_cperl
