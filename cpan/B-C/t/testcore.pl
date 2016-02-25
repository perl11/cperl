# -*- cperl -*-
# t/testcore.t - run the core testsuite with the compilers C, CC and ByteCode
# Usage:
#   t/testcore.t -fail             known failing tests only
#   t/testcore.t -c                run C compiler tests only (also -bc or -cc)
#   t/testcore.t t/CORE/op/goto.t  run this test only
#
# Prereq:
# Copy your matching CORE t dirs into t/CORE.
# For now we test qw(base comp lib op run)
# Then fixup the @INC setters, and various require ./test.pl calls.
#
#   perl -pi -e 's/^(\s*\@INC = )/# $1/' t/CORE/*/*.t
#   perl -pi -e "s|^(\s*)chdir 't' if -d|\$1chdir 't/CORE' if -d|" t/CORE/*/*.t
#   perl -pi -e "s|require './|use lib "CORE"; require '|" `grep -l "require './" t/CORE/*/*.t`
#
# See TESTS for recent results

use Cwd;
use File::Copy;

BEGIN {
  unless (-d "t/CORE" or $ENV{NO_AUTHOR}) {
    print "1..0 #skip t/CORE missing. Read t/testcore.t how to setup.\n";
    exit 0;
  }
  unshift @INC, ("t");
}

use B::C::Config;
require "test.pl";

sub vcmd {
  my $cmd = join "", @_;
  print "#",$cmd,"\n";
  run_cmd($cmd, 120); # timeout 2min
}

my $dir = getcwd();

#unlink ("t/perl", "t/CORE/perl", "t/CORE/test.pl", "t/CORE/harness");
#symlink "t/perl", $^X;
#symlink "t/CORE/perl", $^X;
#symlink "t/CORE/test.pl", "t/test.pl" unless -e "t/CORE/test.pl";
#symlink "t/CORE/harness", "t/test.pl" unless -e "t/CORE/harness";
`ln -sf $^X t/perl`;
`ln -sf $^X t/CORE/perl`;
# CORE t/test.pl would be better, but this fails only on 2 tests
-e "t/CORE/test.pl" or `ln -s $dir/t/test.pl t/CORE/test.pl`;
-e "t/CORE/harness" or `ln -s test.pl t/CORE/harness`; # better than nothing
#`ln -s $dir/t/test.pl harness`; # base/term
#`ln -s $dir/t/test.pl TEST`;    # cmd/mod 8

my %ALLOW_PERL_OPTIONS;
for (qw(
        comp/cpp.t
        run/runenv.t
       )) {
  $ALLOW_PERL_OPTIONS{"t/CORE/$_"} = 1;
}
my $SKIP =
  { "CC" =>
    { "t/CORE/op/bop.t" => "hangs",
      "t/CORE/op/die.t" => "hangs",
    },
    "C" =>
    { ($] >= 5.020 ? ("t/CORE/op/eval.t" => "hangs in endless recursion since 5.20") : ()),
    },
  };

# for C only, tested with 5.21.3d-nt
my @fail = map { "t/CORE/$_" }
  (#'comp/colon.t', # ok with 5.14, 5.18, failed since 5.20 (fixed with #372)
   'comp/hints.t',  # fails sv_magic assert with <= 5.14, ok since 5.16
   #'comp/package.t', # fails only with -O0
   #'comp/parser.t',# ok with 5.14, failed since 5.18, updated with 1.51_02
   #'comp/retainedlines.t',# ok with 5.14, failed since 5.18. fixed test
   'io/layers.t',
   # eval workaround fails with perlcc even with 5.14
   #'op/array.t',  # ok with 5.14, 5.18, 5.20, fails with 5.21 (push on glob deprecation)
   'op/attrs.t',   # test 32, perlcc issue #xxx: anon sub :method not stored
   'op/bop.t',     # ok with 5.14, fails since 5.18
   'op/closure.t', # ok with 5.14, fails test 271 since 5.18
   'op/do.t',      # ok with 5.14, 5.18, fails since 5.20
   'op/eval.t',    # hangs since 5.20.0
   'op/filetest.t',# ok with 5.14, fails since 5.18
   'op/goto_xs.t',
   # S_unshare_hek_or_pvn assert with glob assign'ed free,
   # >=5.18 runtime SEGV at \IO SvAMAGIC(TEMP,ROK) in rv2gv at test 51, print {*x{IO}}
   'op/gv.t',
   'op/length.t',  # ok with 5.14, fails since 5.18 (string overload #373)
   'op/local.t',   # ok with 5.14, fails test 269 since 5.18
   'op/magic.t',   # ok with 5.14, fails since 5.18
   'op/method.t',  # ok with 5.14, 5.18, 5.20, fails with 5.21
   'op/misc.t',
   'op/pwent.t',   # ok with 5.14, 5.18, fails since 5.20
   'op/regmesg.t',
   'op/sort.t',    # ok with 5.14, fails since 5.18
   'op/sprintf.t', # ok with 5.14, 5.18, 5.20, fails with 5.21
   'op/subst.t',
   'op/substr.t',
   'op/tie.t',     # ok with 5.14, fails since 5.18
   'op/universal.t',
   'uni/cache.t',  # ok with 5.14, fails since 5.18
   'uni/chr.t',    # ok with 5.14, 5.18, fails since 5.20
   # use encoding is deprecated: #354
   'uni/tr_7jis.t', # fails with 5.14, ok with 5.20
   'uni/tr_sjis.t', # fails with 5.14, ok with 5.20
   'uni/greek.t',
   'uni/latin2.t',
   'uni/write.t',
   );

my @tests = $ARGV[0] eq '-fail'
  ? @fail
  : ((@ARGV and $ARGV[0] !~ /^-/)
     ? @ARGV
     : <t/CORE/*/*.t>);
shift if $ARGV[0] eq '-fail';
my $Mblib = $^O eq 'MSWin32' ? '-Iblib\arch -Iblib\lib' : "-Iblib/arch -Iblib/lib";

sub run_c {
  my ($t, $backend) = @_;
  chdir $dir;
  my $result = $t; $result =~ s/\.t$/-c.result/;
  $result =~ s/-c.result$/-cc.result/ if $backend eq 'CC';
  my $a = $result; $a =~ s/\.result$//;
  unlink ($a, "$a.c", "t/$a.c", "t/CORE/$a.c", $result);
  # perlcc 2.06 should now work also: omit unneeded B::Stash -u<> and fixed linking
  # see t/c_argv.t
  my $backopts = $backend eq 'C' ? "-qq,C,-O3" : "-qq,CC";
  #$backopts .= ",-fno-warnings" if $backend =~ /^C/ and $] >= 5.013005;
  #$backopts .= ",-fno-fold"     if $backend =~ /^C/ and $] >= 5.013009;
  vcmd "$^X $Mblib -MO=$backopts,-o$a.c $t";
  # CORE often does BEGIN chdir "t", patched to chdir "t/CORE"
  chdir $dir;
  move ("t/$a.c", "$a.c") if -e "t/$a.c";
  move ("t/CORE/$a.c", "$a.c") if -e "t/CORE/$a.c";
  my $d = "";
  $d = "-DALLOW_PERL_OPTIONS" if $ALLOW_PERL_OPTIONS{$t};
  vcmd "$^X $Mblib script/cc_harness -q $d $a.c -o $a" if -e "$a.c";
  vcmd "./$a | tee $result" if -e "$a";
  prove ($a, $result, $i, $t, $backend);
  $i++;
}

sub prove {
  my ($a, $result, $i, $t, $backend) = @_;
  if ( -e "$a" and -s $result) {
    system(qq[prove -Q --exec cat $result || echo -n "n";echo "ok $i - $backend $t"]);
  } else {
    print "not ok $i - $backend $t\n";
  }
}

my @runtests = qw(C CC BC);
if ($ARGV[0] and $ARGV[0] =~ /^-(c|cc|bc)$/i) {
  @runtests = ( uc(substr($ARGV[0],1) ) );
}
my $numtests = scalar @tests * scalar @runtests;
my %runtests = map {$_ => 1} @runtests;

print "1..", $numtests, "\n";
my $i = 1;

for my $t (@tests) {
 C:
  if ($runtests{C}) {
    (print "ok $i #skip $SKIP->{C}->{$t}\n" and goto CC)
      if exists $SKIP->{C}->{$t};
    run_c($t, "C");
    }

 CC:
  if ($runtests{CC}) {
    (print "ok $i #skip $SKIP->{CC}->{$t}\n" and goto BC)
      if exists $SKIP->{CC}->{$t};
    run_c($t, "CC");
  }

 BC:
  if ($runtests{BC}) {
    (print "ok $i #skip $SKIP->{BC}->{$t}\n" and next)
      if exists $SKIP->{BC}->{$t};
    print "ok $i #skip  perl5.22 broke ByteLoader\n" if
      $] > 5.021006 and !$B::C::Config::have_byteloader;

    my $backend = 'Bytecode';
    chdir $dir;
    $result = $t; $result =~ s/\.t$/-bc.result/;
    unlink ("b.plc", "t/b.plc", "t/CORE/b.plc", $result);
    vcmd "$^X $Mblib -MO=-qq,Bytecode,-H,-s,-ob.plc $t";
    chdir $dir;
    move ("t/b.plc", "b.plc") if -e "t/b.plc";
    move ("t/CORE/b.plc", "b.plc") if -e "t/CORE/b.plc";
    vcmd "$^X $Mblib b.plc > $result" if -e "b.plc";
    prove ("b.plc", $result, $i, $t, $backend);
    $i++;
  }
}

END {
  unlink ( "t/perl", "t/CORE/perl", "harness", "TEST" );
  unlink ("a","a.c","t/a.c","t/CORE/a.c","aa.c","aa","t/aa.c","t/CORE/aa.c","b.plc");
}
