# -*- cperl -*-
# t/modules.t [OPTIONS] [t/mymodules]
# check if some common CPAN modules exist and
# can be compiled successfully. Only B::C is fatal,
# CC and Bytecode optional. Use -all for all three (optional), and
# -log for the reports (now default).
#
# OPTIONS:
#  -all     - run also B::CC and B::Bytecode
#  -subset  - run only random 10 of all modules. default if ! -d .svn
#  -no-subset  - all 100 modules
#  -no-date - no date added at the logfile
#  -t       - run also tests
#  -log     - save log file. default on test10 and without subset
#  -keep    - keep the source, perlcc -S
#
# The list in t/mymodules comes from two bigger projects.
# Recommended general lists are Task::Kensho and http://ali.as/top100/
# We are using 10 problematic modules from the latter.
# We are NOT running the full module testsuite yet with -t, we can do that
# in another author test to burn CPU for a few hours resp. days.
#
# Reports:
# for p in 5.6.2 5.8.9 5.10.1 5.12.2; do make -S clean; perl$p Makefile.PL; make; perl$p -Mblib t/modules.t -log; done
#
# How to installed skip modules:
# grep ^skip log.modules-bla|perl -lane'print $F[1]'| xargs perlbla -S cpan
# or t/testm.sh -s
BEGIN {
  if ($ENV{PERL_CORE}) {
    unshift @INC, ('t', '../../lib');
  } else {
    unshift @INC, 't';
  }
  require TestBC;
}
use strict;
use Test::More;
use File::Temp;
use Config;

my $ccopts;
BEGIN {
  plan skip_all => "Overlong tests, timeout on Appveyor CI"
    if $^O eq 'MSWin32' and $ENV{APPVEYOR};
  if ($^O eq 'MSWin32' and $Config{cc} eq 'cl') {
    # MSVC takes an hour to compile each binary unless -Od
    $ccopts = '"--Wc=-Od"';
  } elsif ($^O eq 'MSWin32' and $Config{cc} eq 'gcc') {
    # mingw is much better but still insane with <= 4GB RAM
    $ccopts = '"--Wc=-O0"';
  } else {
    $ccopts = '';
  }
}

# Try some simple XS module which exists in 5.6.2 and blead
# otherwise we'll get a bogus 40% failure rate
my $staticxs = '';

BEGIN {
  $staticxs = '--staticxs';
  # check whether linking with xs works at all. Try with and without --staticxs
  if ($^O eq 'darwin') { $staticxs = ''; goto BEGIN_END; }
  my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
  my $tmp = File::Temp->new(TEMPLATE => 'pccXXXXX');
  my $out = $tmp->filename;
  my $Mblib = Mblib();
  my $perlcc = perlcc();
  my $result = `$X $Mblib $perlcc -O3 $ccopts --staticxs -o$out -e"use Data::Dumper;"`;
  my $exe = $^O eq 'MSWin32' ? "$out.exe" : $out;
  unless (-e $exe or -e 'a.out') {
    my $cmd = qq($X $Mblib $perlcc -O3 $ccopts -o$out -e"use Data::Dumper;");
    warn $cmd."\n" if $ENV{TEST_VERBOSE};
    my $result = `$cmd`;
    unless (-e $out or -e 'a.out') {
      plan skip_all => "perlcc cannot link XS module Data::Dumper. Most likely wrong ldopts.";
      unlink $out;
      exit;
    } else {
      $staticxs = '';
    }
  } else {
    diag "-O3 --staticxs ok";
  }
 BEGIN_END:
  unshift @INC, 't';
}

our %modules;
our $log = 0;
use modules;

my $opts_to_test = 1;
my $do_test;
$opts_to_test = 3 if grep /^-all$/, @ARGV;
$do_test = 1 if grep /^-t$/, @ARGV;

# Determine list of modules to action.
our @modules = get_module_list();
my $test_count = scalar @modules * $opts_to_test * ($do_test ? 5 : 4);
# $test_count -= 4 * $opts_to_test * (scalar @modules - scalar(keys %modules));
plan tests => $test_count;

use B::C;
use POSIX qw(strftime);

eval { require IPC::Run; };
my $have_IPC_Run = defined $IPC::Run::VERSION;
log_diag("Warning: IPC::Run is not available. Error trapping will be limited, no timeouts.")
  if !$have_IPC_Run and !$ENV{PERL_CORE};

my @opts = ("-O3");				  # only B::C
@opts = ("-O3", "-O", "-B") if grep /-all/, @ARGV;  # all 3 compilers
my $perlversion = perlversion();
$log = 0 if @ARGV;
$log = 1 if grep /top100$/, @ARGV;
$log = 1 if grep /-log/, @ARGV or $ENV{TEST_LOG};
my $nodate = 1 if grep /-no-date/, @ARGV;
my $keep = 1 if grep /-keep/, @ARGV;

if ($log) {
  $log = (@ARGV and !$nodate)
    ? "log.modules-$perlversion-".strftime("%Y%m%d-%H%M%S",localtime)
    : "log.modules-$perlversion";
  if (-e $log) {
    use File::Copy;
    copy $log, "$log.bak";
  }
  open(LOG, ">", "$log");
  close LOG;
}
unless (is_subset) {
  my $svnrev = "";
  if (-d '.svn') {
    local $ENV{LC_MESSAGES} = "C";
    $svnrev = `svn info|grep Revision:`;
    chomp $svnrev;
    $svnrev =~ s/Revision:\s+/r/;
    my $svnstat = `svn status lib/B/C.pm t/TestBC.pm t/*.t`;
    chomp $svnstat;
    $svnrev .= " M" if $svnstat;
  } elsif (-d '.git') {
    local $ENV{LC_MESSAGES} = "C";
    $svnrev = `git log -1 --pretty=format:"%h %ad | %s" --date=short`;
    chomp $svnrev;
    my $gitdiff = `git diff lib/B/C.pm t/TestBC.pm t/*.t`;
    chomp $gitdiff;
    $svnrev .= " M" if $gitdiff;
  }
  log_diag("B::C::VERSION = $B::C::VERSION $svnrev");
  log_diag("perlversion = $perlversion");
  log_diag("path = $^X");
  my $bits = 8 * $Config{ptrsize};
  log_diag("platform = $^O $bits"."bit ".(
	   $Config{'useithreads'} ? "threaded"
	   : $Config{'usemultiplicity'} ? "multi"
	     : "non-threaded").
	   ($Config{ccflags} =~ m/-DDEBUGGING/ ? " debug" : ""));
}

my $module_count = 0;
my ($skip, $pass, $fail, $todo) = (0,0,0,0);
my $Mblib = Mblib();
my $perlcc = perlcc();

MODULE:
for my $module (@modules) {
  $module_count++;
  local($\, $,);   # guard against -l and other things that screw with
                   # print

  # Possible binary files.
  my $name = $module;
  $name =~ s/::/_/g;
  $name =~ s{(install|setup|update)}{substr($1,0,4)}ie;
  my $out = 'pcc'.$name;
  my $out_c  = "$out.c";
  my $out_pl = "$out.pl";
  $out = "$out.exe" if $^O eq 'MSWin32';

 SKIP: {
    # if is a special module that can't be required like others
    unless ($modules{$module}) {
      $skip++;
      log_pass("skip", "$module", 0);

      skip("$module not installed", int(4 * scalar @opts));
      next MODULE;
    }
    if (is_skip($module)) { # !$have_IPC_Run is not really helpful here
      my $why = is_skip($module);
      $skip++;
      log_pass("skip", "$module #$why", 0);

      skip("$module $why", int(4 * scalar @opts));
      next MODULE;
    }
    $module = 'if(1) => "Sys::Hostname"' if $module eq 'if';

  TODO: {
      my $s = is_todo($module);
      local $TODO = $s if $s;
      $todo++ if $TODO;

      open F, ">", $out_pl or die;
      print F "use $module;\nprint 'ok';\n" or die;
      close F or die;

      my ($result, $stdout, $err);
      my $module_passed = 1;
      my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
      foreach (0..$#opts) {
        my $opt = $opts[$_];
        $opt .= " --testsuite --no-spawn" if $module =~ /^Test::/ and $opt !~ / --testsuite/;
        $opt .= " -S" if $keep and $opt !~ / -S\b/;
        # TODO ./a often hangs but perlcc not
        my @cmd = grep {!/^$/}
	  $runperl,split(/ /,$Mblib),split(/ /,$perlcc),split(/ /,$opt),$ccopts,$staticxs,"-o$out","-r",$out_pl;
        my $cmd = join(" ", @cmd);
        #warn $cmd."\n" if $ENV{TEST_VERBOSE};
	# Esp. darwin-2level has insane link times
        ($result, $stdout, $err) = run_cmd(\@cmd, 720); # in secs.
        ok(-s $out,
           "$module_count: use $module  generates non-zero binary")
          or $module_passed = 0;
        is($result, 0,  "$module_count: use $module $opt exits with 0")
          or $module_passed = 0;
	$err =~ s/^Using .+blib\n//m if $] < 5.007;
        like($stdout, qr/ok$/ms, "$module_count: use $module $opt gives expected 'ok' output");
        #warn $stdout."\n" if $ENV{TEST_VERBOSE};
        #warn $err."\n" if $ENV{TEST_VERBOSE};
        unless ($stdout =~ /ok$/ms) { # crosscheck for a perlcc problem (XXX not needed anymore)
          warn "crosscheck without perlcc\n" if $ENV{TEST_VERBOSE};
          my ($r, $err1);
          $module_passed = 0;
          my $c_opt = $opts[$_];
          @cmd = ($runperl,split(/ /,$Mblib),"-MO=C,$c_opt,-o$out_c",$out_pl);
          #warn join(" ",@cmd."\n") if $ENV{TEST_VERBOSE};
          ($r, $stdout, $err1) = run_cmd(\@cmd, 60); # in secs
          my $cc_harness = cc_harness();
          @cmd = ($runperl,split(/ /,$Mblib." ".$cc_harness),,"-o$out",$out_c);
          #warn join(" ",@cmd."\n") if $ENV{TEST_VERBOSE};
          ($r, $stdout, $err1) = run_cmd(\@cmd, 360); # in secs
          @cmd = ($^O eq 'MSWin32' ? "$out" : "./$out");
          #warn join(" ",@cmd."\n") if $ENV{TEST_VERBOSE};
          ($r, $stdout, $err1) = run_cmd(\@cmd, 20); # in secs
          if ($stdout =~ /ok$/ms) {
            $module_passed = 1;
            diag "crosscheck that only perlcc $staticxs failed. With -MO=C + cc_harness => ok";
          }
        }
        log_pass($module_passed ? "pass" : "fail", $module, $TODO);

        if ($module_passed) {
          $pass++;
        } else {
          diag "Failed: $cmd -e 'use $module; print \"ok\"'";
          $fail++;
        }

      TODO: {
          local $TODO = 'STDERR from compiler warnings in work' if $err;
          is($err, '', "$module_count: use $module  no error output compiling")
            && ($module_passed)
              or log_err($module, $stdout, $err)
            }
      }
      if ($do_test) {
        TODO: {
          local $TODO = 'all module tests';
          `$runperl $Mblib -It -MCPAN -Mmodules -e "CPAN::Shell->testcc("$module")"`;
        }
      }
      for ($out_pl, $out, $out_c, $out_c.".lst") {
	unlink $_ if -f $_ ;
      }
    }}
}

if (!$ENV{PERL_CORE}) {
  my $count = scalar @modules - $skip;
  log_diag("$count / $module_count modules tested with B-C-${B::C::VERSION} - "
           .$Config{usecperl}?"c":""."perl-$perlversion");
  log_diag(sprintf("pass %3d / %3d (%s)", $pass, $count, percent($pass,$count)));
  log_diag(sprintf("fail %3d / %3d (%s)", $fail, $count, percent($fail,$count)));
  log_diag(sprintf("todo %3d / %3d (%s)", $todo, $fail, percent($todo,$fail)));
  log_diag(sprintf("skip %3d / %3d (%s not installed)\n",
                   $skip, $module_count, percent($skip,$module_count)));
}

exit;

# t/todomod.pl
# for t in $(cat t/top100); do perl -ne"\$ARGV=~s/log.modules-//;print \$ARGV,': ',\$_ if / $t\s/" t/modules.t `ls log.modules-5.0*|grep -v .err`; read; done
sub is_todo {
  my $module = shift or die;
  my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
  # ---------------------------------------
  #foreach(qw(
  #  ExtUtils::CBuilder
  #)) { return 'overlong linking time' if $_ eq $module; }
  if ($] < 5.007) { foreach(qw(
    Sub::Name
    Test::Simple
    Test::Exception
    Storable
    Test::Tester
    Test::NoWarnings
    Moose
    Test::Warn
    Test::Pod
    Test::Deep
    FCGI
    MooseX::Types
    DateTime::TimeZone
    DateTime
  )) { return '5.6' if $_ eq $module; }}
  if ($] >= 5.008004 and $] < 5.0080006) { foreach(qw(
    Module::Pluggable
  )) { return '5.8.5 CopFILE_set' if $_ eq $module; }}
  if ($] <= 5.0080009) { foreach(qw(
    IO::Socket
  )) { return '5.8.9 empty Socket::AF_UNIX' if $_ eq $module; }}
  # PMOP quoting fixed with 1.45_14
  #if ($] < 5.010) { foreach(qw(
  #  DateTime
  #)) { return '<5.10' if $_ eq $module; }}
  # restricted v_string hash?
  if ($] eq '5.010000') { foreach(qw(
   IO
   Path::Class
   DateTime::TimeZone
  )) { return '5.10.0 restricted hash/...' if $_ eq $module; }}
  # fixed between v5.15.6-210-g5343a61 and v5.15.6-233-gfb7aafe
  #if ($] > 5.015 and $] < 5.015006) { foreach(qw(
  # B::Hooks::EndOfScope
  #)) { return '> 5.15' if $_ eq $module; }}
  #if ($] >= 5.018) { foreach(qw(
  #    ExtUtils::ParseXS
  #)) { return '>= 5.18 #137 Eval-group not allowed at runtime' if $_ eq $module; }}
  # DateTime fixed with 1.52_13
  # stringify fixed with 1.52_18
  #if ($] >= 5.018) { foreach(qw(
  #    Path::Class
  #)) { return '>= 5.18 #219 overload stringify regression' if $_ eq $module; }}
  if ($] >= 5.023005) { foreach(qw(
      Attribute::Handlers
      MooseX::Types
  )) { return '>= 5.23.5 SEGV' if $_ eq $module; }}

  # ---------------------------------------
  if ($Config{useithreads}) {
    if ($^O eq 'MSWin32') { foreach(qw(
      Test::Harness
    )) { return 'MSWin32 with threads' if $_ eq $module; }}
    if ($] >= 5.008008 and $] < 5.008009) { foreach(qw(
      Test::Tester
    )) { return '5.8.8 with threads' if $_ eq $module; }}
    if ($] >= 5.010 and $] < 5.011 and $DEBUGGING) { foreach(qw(
      Attribute::Handlers
    )) { return '5.10.1d with threads' if $_ eq $module; }}
    #if ($] >= 5.012 and $] < 5.014) { foreach(qw(
    #  ExtUtils::CBuilder
    #)) { return '5.12 with threads' if $_ eq $module; }}
    if ($] >= 5.016 and $] < 5.018) { foreach(qw(
      Module::Build
    )) { return '5.16 threaded (out of memory)' if $_ eq $module; }}
    #if ($] >= 5.022) { foreach(qw(
    #)) { return '>= 5.22 with threads SEGV' if $_ eq $module; }}
    #if ($] >= 5.022) { foreach(qw(
    #)) { return '>= 5.22 with threads, no ok' if $_ eq $module; }}
    # but works with msvc
    if ($^O eq 'MSWin32' and $Config{cc} eq 'gcc') { foreach(qw(
      Pod::Usage
    )) { return 'mingw' if $_ eq $module; }}
  } else { #no threads --------------------------------
    #if ($] > 5.008008 and $] <= 5.009) { foreach(qw(
    #  ExtUtils::CBuilder
    #)) { return '5.8.9 without threads' if $_ eq $module; }}
    # invalid free
    if ($] >= 5.016 and $] < 5.018) { foreach(qw(
        Module::Build
    )) { return '5.16 without threads (invalid free)' if $_ eq $module; }}
    # This is a flapping test
    if ($] >= 5.017 and $] < 5.020) { foreach(qw(
        Moose
    )) { return '5.18 without threads' if $_ eq $module; }}
    #if ($] > 5.019) { foreach(qw(
    #  MooseX::Types
    #)) { return '5.19 without threads' if $_ eq $module; }}
  }
  # ---------------------------------------
}

sub is_skip {
  my $module = shift or die;

  if ($] >= 5.011004) {
    #foreach (qw(Attribute::Handlers)) {
    #  return 'fails $] >= 5.011004' if $_ eq $module;
    #}
    if ($Config{useithreads}) { # hangs and crashes threaded since 5.12
      foreach (qw(  )) {
        # Old: Recursive inheritance detected in package 'Moose::Object' at /usr/lib/perl5/5.13.10/i686-debug-cygwin/DynaLoader.pm line 103
        # Update: Moose works ok with r1013
	 return 'hangs threaded, $] >= 5.011004' if $_ eq $module;
      }
    }
  }
  #if ($ENV{PERL_CORE} and $] > 5.023
  #    and ($Config{cc} =~ / -m32/ or $Config{ccflags} =~ / -m32/)) {
  #  return 'hangs in CORE with -m32' if $module =~ /^Pod::/;
  #}
}
