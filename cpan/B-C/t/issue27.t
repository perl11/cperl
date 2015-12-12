#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=27
# run-time require fails at *DynaLoader::Config = *Config::Config
use strict;
BEGIN {
  unless (eval "require LWP::UserAgent;") {
    print "1..0 #skip LWP::UserAgent not installed\n";
    exit;
  }
}
use Test::More tests => 3;

my $X = $^X =~ m/\s/ ? qq{"$^X" -Iblib/arch -Iblib/lib} : "$^X -Iblib/arch -Iblib/lib";
my $perlcc = $^O eq 'MSWin32' ? "blib\\script\\perlcc" : 'blib/script/perlcc';
my $opt = '';
$opt .= ",-fno-warnings" if $] >= 5.013005;
$opt .= ",-fno-fold" if $] >= 5.013009;
$opt = "-Wb=".substr($opt,1) if $opt;

# -fno-warnings order: Carp requires DynaLoader
#TODO: {
# fixed with 1.48
#  local $TODO = 'use -fno-warnings, always and save 550KB for small scripts' if $] >= 5.013005;
  # Attempt to reload Config.pm aborted.
  # Global symbol "%Config" requires explicit package name at 5.8.9/Time/Local.pm line 36
  # 5.15: Undefined subroutine &utf8::SWASHNEW called at /usr/local/lib/perl5/5.15.3/constant.pm line 36
  # old: &Config::AUTOLOAD failed on Config::launcher at Config.pm line 72.
is(`$X $perlcc -O2 -occodei27_o2 -r -e"require LWP::UserAgent;print q(ok);"`, 'ok',
   "-O2 require LWP::UserAgent without -fno-warnings");
#}

# fine with -fno-warnings
is(`$X $perlcc $opt -occodei27 -r -e"require LWP::UserAgent;print q(ok);"`, 'ok',
   "require LWP::UserAgent $opt");
# With -O3 ditto (includes -fno-warnings)
is(`$X $perlcc -O3 -occodei27_o3 -r -e"require LWP::UserAgent;print q(ok);"`, 'ok',
   "-O3 require LWP::UserAgent");

END {
  unlink qw(ccodei27 ccodei27.c);
  unlink qw(ccodei27_o2 ccodei27_o2.c);
  unlink qw(ccodei27_o3 ccodei27_o3.c);
}
