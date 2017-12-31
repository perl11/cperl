#! /usr/bin/env perl

BEGIN {
    if ($ENV{PERL_CORE}) {
      @INC = ('.', '../../lib', '../../lib/auto',);
    }
    use Config;
    if (($Config{'extensions'} !~ /\bB\b/) ){
        print "1..0 # Skip -- Perl configured without B module\n";
        exit 0;
    }
    if ($] < 5.007 and $^O eq 'os2'){
        print "1..0 # Skip -- stash tests disabled for OS2 5.6\n";
        exit 0;
    }
    #if ($^O eq 'MSWin32' and $Config{cc} =~ /^cl/i) {
    #    print "1..0 # Skip -- stash tests skipped on MSVC for now\n";
    #    exit 0;
    #}
}

use Test::More tests => 4;
use strict;
use Config;

my $got;
my $Is_VMS = $^O eq 'VMS';
my $Is_MacOS = $^O eq 'MacOS';
my $perl_core = $ENV{PERL_CORE};

my $path = join " ", map { qq["-I$_"] } @INC;
$path = '"-I../lib" "-Iperl_root:[lib]"' if $Is_VMS;   # gets too long otherwise
my $redir = $Is_MacOS ? "" : "2>&1";
my $cover = $ENV{HARNESS_PERL_SWITCHES} || "";
my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;

chomp($got = `$X $path "-MB::Stash" $cover "-Mwarnings" -e1`);
$got =~ s/Using \w+blib\n// if $] < 5.008001;
$got =~ s/-u//g;
diag "got = $got" unless $perl_core;

my @got = map { s/^\S+ //; $_ }
              sort { $a cmp $b }
                   map { lc($_) . " " . $_ }
                       split /,/, $got;
diag "(after sorting)" unless $perl_core;
diag "got = @got" unless $perl_core;
ok (@got > 3, "not empty");
ok ($got =~ /main,/, "contains main");
ok ($got =~ /,warnings/, "contains warnings");

@got = grep { ! /^(PerlIO|open)(?:::\w+)?$/ } @got;

diag "(after perlio censorings)" unless $perl_core;
diag "got = @got" unless $perl_core;

@got = grep { ! /^Win32$/                     } @got  if $^O eq 'MSWin32';
@got = grep { ! /^NetWare$/                   } @got  if $^O eq 'NetWare';
@got = grep { ! /^(Cwd|File|File::Copy|OS2)$/ } @got  if $^O eq 'os2';
@got = grep { ! /^(Win32|Win32CORE|Cwd|Cygwin)$/} @got if $^O eq 'cygwin';
@got = grep { ! /^(Devel::Cover)$/            } @got  if $cover =~ /-MDevel::Cover/;
# XXX freebsd prepends BSDPAN.pm ?
@got = grep { ! /^(Exporter::Heavy|strict)$/} @got
  if $^O eq 'freebsd';
@got = grep { ! /^(threads)$/} @got; # < 5.8.9

if ($Is_VMS) {
    @got = grep { ! /^File(?:::Copy)?$/    } @got;
    @got = grep { ! /^VMS(?:::Filespec)?$/ } @got;
    @got = grep { ! /^vmsish$/             } @got;
     # Socket is optional/compiler version dependent
    @got = grep { ! /^Socket$/             } @got;
}

diag "(after platform censorings)" unless $perl_core;
diag "got = @got" unless $perl_core;

$got = "@got";

my $expected = "attributes Carp Carp::Heavy DB Exporter Exporter::Heavy main Regexp strict warnings";
if ($] < 5.008009) {
    $expected = "attributes Carp DB Exporter Exporter::Heavy main overload Regexp strict warnings";
}
if ($] < 5.008001) {
    $expected = "attributes Carp Carp::Heavy DB Exporter Exporter::Heavy main strict warnings";
}
if ($] >= 5.010) {
    $expected = "attributes Carp Carp::Heavy DB Exporter Exporter::Heavy main mro re Regexp strict Tie Tie::Hash warnings";
}
if ($] >= 5.011002) {
    $expected = "Carp DB Exporter Exporter::Heavy main mro re Regexp strict Tie Tie::Hash warnings";
    #Carp DB Exporter main mro re Regexp Tie Tie::Hash Tie::Hash::NamedCapture utf8 version warnings";
}
if ($] >= 5.011001 and $] < 5.011004) {
    $expected .= " XS::APItest::KeywordRPN";
}
if ($] >= 5.013004) {
    $expected = "Carp DB Exporter Exporter::Heavy main mro re Regexp strict Tie Tie::Hash warnings";
}
if ($] >= 5.013006) {
    $expected = "Carp DB Exporter Exporter::Heavy main mro re Regexp strict warnings";
}
$expected =~ s/(Exporter::Heavy|strict) //g if $^O eq 'freebsd';

{
    no strict 'vars';
    if ($^O eq 'os2') {
      eval q(use vars '$OS2::is_aout';);
    }
}

TODO: {
  # todo: freebsd
  # local $TODO = "exact stashes may vary" if $^O !~ /^(MSWin32|cygwin|linux|darwin)$/;
  local $TODO = "exact stashes may vary";
  if ((($Config{static_ext} eq ' ')
       || ($Config{static_ext} eq '')
       || ($^O eq 'cygwin' and $Config{static_ext} =~ /^(Cwd )?Win32CORE$/))
      && !($^O eq 'os2' and $OS2::is_aout)
     ) {
    diag "got      [$got]" if $got ne $expected;
    diag "expected [$expected]" if $got ne $expected;
    ok($got eq $expected);
  } else {
    ok(1, "skip: one or more static extensions");
  }
}
