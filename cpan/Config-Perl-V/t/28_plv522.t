#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    use Test::More;
    my $tests = 122;
    unless ($ENV{PERL_CORE}) {
	require Test::NoWarnings;
	Test::NoWarnings->import ();
	$tests++;
	}

    plan tests => $tests;
    }

use Config::Perl::V;

ok (my $conf = Config::Perl::V::plv2hash (<DATA>), "Read perl -V block");
ok (exists $conf->{$_}, "Has $_ entry") for qw( build environment config inc );

is ($conf->{build}{osname}, $conf->{config}{osname}, "osname");
is ($conf->{build}{stamp}, "Dec 21 2015 00:05:02", "Build time");
is ($conf->{config}{version}, "5.22.1", "reconstructed \$Config{version}");

my $opt = Config::Perl::V::plv2hash ("")->{build}{options};
foreach my $o (sort qw(
	HAS_TIMES PERLIO_LAYERS PERL_DONT_CREATE_GVSV
	PERL_HASH_FUNC_ONE_AT_A_TIME_HARD PERL_MALLOC_WRAP
	PERL_NEW_COPY_ON_WRITE PERL_PRESERVE_IVUV
	PERL_USE_DEVEL USE_64_BIT_ALL USE_64_BIT_INT
	USE_LARGE_FILES USE_LOCALE USE_LOCALE_COLLATE
	USE_LOCALE_CTYPE USE_LOCALE_NUMERIC USE_LOCALE_TIME
	USE_PERLIO USE_PERL_ATOF
	)) {
    is ($conf->{build}{options}{$o}, 1, "Runtime option $o set");
    delete $opt->{$o};
    }
foreach my $o (sort keys %$opt) {
    is ($conf->{build}{options}{$o}, 0, "Runtime option $o unset");
    }

is_deeply ($conf->{build}{patches}, ['Devel::PatchPerl 1.30'], "local patches");

my %check = (
    alignbytes      => 8,
    api_version     => 22,
    bincompat5005   => "undef",
    byteorder       => 12345678,
    cc              => "gcc-mp-5",
    cccdlflags      => "",
    ccdlflags       => "",
    # TODO double single quotes (yes, config.sh has these, perlall)
    #config_args     => "-de -Dusedevel -Uversiononly -Dinstallman1dir=none -Dinstallman3dir=none -Dinstallsiteman1dir=none -Dinstallsiteman3dir=none -Uuseithreads -D'cc=gcc-mp-5' -D'ld=gcc-mp-5' -Accflags=''-m64'' -Accflags=''-mssse3''",
    gccversion      => "5.3.0",
    gnulibc_version => "",
    ivsize          => 8,
    ivtype          => "long",
    ld              => "gcc-mp-5",
    lddlflags       => " -bundle -undefined dynamic_lookup -L/opt/local/lib -L/usr/local/lib -L/opt/local/lib/libgcc -fstack-protector-strong",
    ldflags         => ' -fstack-protector-strong -L/opt/local/lib -L/usr/local/lib -L/opt/local/lib/libgcc',
    libc            => "",
    lseektype       => "off_t",
    osvers          => "15.2.0",
    use64bitint     => "define",
    );
is ($conf->{config}{$_}, $check{$_}, "reconstructed \$Config{$_}") for sort keys %check;

__END__
Summary of my perl5 (revision 5 version 22 subversion 1) configuration:
   
  Platform:
    osname=darwin, osvers=15.2.0, archname=darwin-2level
    uname='darwin airc.local 15.2.0 darwin kernel version 15.2.0: fri nov 13 19:56:56 pst 2015; root:xnu-3248.20.55~2release_x86_64 x86_64 i386 macbookair6,2 darwin '
    config_args='-de -Dusedevel -Uversiononly -Dinstallman1dir=none -Dinstallman3dir=none -Dinstallsiteman1dir=none -Dinstallsiteman3dir=none -Uuseithreads -D'cc=gcc-mp-5' -D'ld=gcc-mp-5' -Accflags=''-m64'' -Accflags=''-mssse3'''
    hint=recommended, useposix=true, d_sigaction=define
    useithreads=undef, usemultiplicity=undef
    use64bitint=define, use64bitall=define, uselongdouble=undef
    usemymalloc=n, bincompat5005=undef
  Compiler:
    cc='gcc-mp-5', ccflags ='-fno-common -DPERL_DARWIN -m64 -mssse3 -fwrapv -fno-strict-aliasing -pipe -fstack-protector-strong -I/usr/local/include -I/opt/local/include',
    optimize='-O3',
    cppflags='-fno-common -DPERL_DARWIN -m64 -mssse3 -fwrapv -fno-strict-aliasing -pipe -fstack-protector-strong -I/usr/local/include -I/opt/local/include'
    ccversion='', gccversion='5.3.0', gccosandvers=''
    intsize=4, longsize=8, ptrsize=8, doublesize=8, byteorder=12345678, doublekind=3
    d_longlong=define, longlongsize=8, d_longdbl=define, longdblsize=16, longdblkind=3
    ivtype='long', ivsize=8, nvtype='double', nvsize=8, Off_t='off_t', lseeksize=8
    alignbytes=8, prototype=define
  Linker and Libraries:
    ld='gcc-mp-5', ldflags =' -fstack-protector-strong -L/opt/local/lib -L/usr/local/lib -L/opt/local/lib/libgcc'
    libpth=/opt/local/lib /opt/local/lib/gcc5/gcc/x86_64-apple-darwin15/5.3.0/include-fixed /usr/lib /usr/local/lib /opt/local/lib/libgcc
    libs=-lpthread -lgdbm -ldbm -ldl -lm -lutil -lc
    perllibs=-lpthread -ldl -lm -lutil -lc
    libc=, so=dylib, useshrplib=false, libperl=libperl.a
    gnulibc_version=''
  Dynamic Linking:
    dlsrc=dl_dlopen.xs, dlext=bundle, d_dlsymun=undef, ccdlflags=' '
    cccdlflags=' ', lddlflags=' -bundle -undefined dynamic_lookup -L/opt/local/lib -L/usr/local/lib -L/opt/local/lib/libgcc -fstack-protector-strong'


Characteristics of this binary (from libperl): 
  Compile-time options: HAS_TIMES PERLIO_LAYERS PERL_DONT_CREATE_GVSV
                        PERL_HASH_FUNC_ONE_AT_A_TIME_HARD PERL_MALLOC_WRAP
                        PERL_NEW_COPY_ON_WRITE PERL_PRESERVE_IVUV
                        PERL_USE_DEVEL USE_64_BIT_ALL USE_64_BIT_INT
                        USE_LARGE_FILES USE_LOCALE USE_LOCALE_COLLATE
                        USE_LOCALE_CTYPE USE_LOCALE_NUMERIC USE_LOCALE_TIME
                        USE_PERLIO USE_PERL_ATOF
  Locally applied patches:
	Devel::PatchPerl 1.30
  Built under darwin
  Compiled at Dec 21 2015 00:05:02
  @INC:
    /usr/local/lib/perl5/site_perl/5.22.1/darwin-2level
    /usr/local/lib/perl5/site_perl/5.22.1
    /usr/local/lib/perl5/5.22.1/darwin-2level
    /usr/local/lib/perl5/5.22.1
    /usr/local/lib/perl5/site_perl/5.22.0
    /usr/local/lib/perl5/site_perl/5.21.11
    /usr/local/lib/perl5/site_perl/5.21.10
    /usr/local/lib/perl5/site_perl/5.21.9
    /usr/local/lib/perl5/site_perl/5.21.8
    /usr/local/lib/perl5/site_perl/5.21.5
    /usr/local/lib/perl5/site_perl/5.21.4
    /usr/local/lib/perl5/site_perl/5.21.3
    /usr/local/lib/perl5/site_perl/5.21.2
    /usr/local/lib/perl5/site_perl/5.21.1
    /usr/local/lib/perl5/site_perl/5.20.3
    /usr/local/lib/perl5/site_perl/5.20.2
    /usr/local/lib/perl5/site_perl/5.20.1
    /usr/local/lib/perl5/site_perl/5.20.0
    /usr/local/lib/perl5/site_perl/5.19.9
    /usr/local/lib/perl5/site_perl/5.19.8
    /usr/local/lib/perl5/site_perl/5.19.6
    /usr/local/lib/perl5/site_perl/5.19.4
    /usr/local/lib/perl5/site_perl/5.19.2
    /usr/local/lib/perl5/site_perl/5.18.4
    /usr/local/lib/perl5/site_perl/5.18.2
    /usr/local/lib/perl5/site_perl/5.18.1
    /usr/local/lib/perl5/site_perl/5.18.0
    /usr/local/lib/perl5/site_perl/5.16.3
    /usr/local/lib/perl5/site_perl/5.16.1
    /usr/local/lib/perl5/site_perl/5.15.8
    /usr/local/lib/perl5/site_perl/5.14.4
    /usr/local/lib/perl5/site_perl/5.14.3
    /usr/local/lib/perl5/site_perl/5.14.2
    /usr/local/lib/perl5/site_perl/5.14.1
    /usr/local/lib/perl5/site_perl/5.14.0
    /usr/local/lib/perl5/site_perl/5.12.5
    /usr/local/lib/perl5/site_perl/5.12.4
    /usr/local/lib/perl5/site_perl/5.10.1
    /usr/local/lib/perl5/site_perl/5.8.9
    /usr/local/lib/perl5/site_perl/5.8.8
    /usr/local/lib/perl5/site_perl/5.8.5
    /usr/local/lib/perl5/site_perl/5.8.4
    /usr/local/lib/perl5/site_perl/5.6.2
    /usr/local/lib/perl5/site_perl
    .
