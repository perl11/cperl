#!/usr/bin/perl

if (scalar keys %Config:: > 2) {
  print "0..1 #SKIP Cannot test with static or builtin Config\n";
  exit;
}

require Config; #this is supposed to be XS config
require B;

*isXSUB = !B->can('CVf_ISXSUB')
  ? sub { shift->XSUB }
  : sub { shift->CvFLAGS & B::CVf_ISXSUB() }; #CVf_ISXSUB added in 5.9.4

#is_deeply->overload.pm wants these 2 XS modules
#can't be required once DynaLoader is removed later on
require Scalar::Util;
eval { require mro; };
my $cv = B::svref_2object(*{'Config::FETCH'}{CODE});
unless (isXSUB($cv)) {
  if (-d 'regen') { #on CPAN
    warn "Config:: is not XS Config";
  } else {
    print "0..1 #SKIP Config:: is not XS Config, miniperl?\n";
    exit;
  }
}

# change the class name of XS Config so there can be XS and PP Config at same time
foreach (qw( TIEHASH DESTROY DELETE CLEAR EXISTS NEXTKEY FIRSTKEY KEYS SCALAR FETCH)) {
  *{'XSConfig::'.$_} = *{'Config::'.$_}{CODE};
}
tie(%XSConfig, 'XSConfig');

# delete package
undef( *main::Config:: );
require Data::Dumper;
$Data::Dumper::Useperl = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq = 0;
$Data::Dumper::Quotekeys = 0;

# full perl is now miniperl
undef( *main::XSLoader::);
require 'Config_mini.pl';
Config->import();
require 'Config_heavy.pl';
require Test::More;
Test::More->import (tests => 4);

ok(isXSUB($cv), 'XS Config:: is XS');

$cv = B::svref_2object(*{'Config::FETCH'}{CODE});
ok(!isXSUB($cv), 'PP Config:: is PP');

my $klenXS = scalar(keys %XSConfig);
my $copy = 0;
my %Config_copy;
if (exists $XSConfig{canned_gperf}) { #fix up PP Config to look like XS Config
  $copy = 1;
  for (keys %Config) {
    $Config_copy{$_} = $Config{$_};
  }
  # See Config_xs.PL:
  # postprocess the values a bit:
  # reserve up to 20 config_args
  for (0..20) {
    my $k = "config_arg".$_;
    $Config_copy{$k} = '' unless exists $Config{$k};
  }
  for my $k (qw(bin_ELF bootstrap_charset canned_gperf ccstdflags ccwarnflags
                charsize config_argc config_args d_re_comp d_regcmp git_ancestor
                git_remote_branch git_unpushed hostgenerate hostosname hostperl
                incpth installhtmldir installhtmlhelpdir ld_can_script
                libdb_needs_pthread mad malloc_cflags sysroot targetdir
                targetenv targethost targetmkdir targetport
                useversionedarchname)) {
    $Config_copy{$k} = '' unless exists $Config{$k};
  }
  is (scalar keys %Config_copy, $klenXS, 'same adjusted key count');
} else {
  is (scalar(keys %Config), $klenXS, 'same key count');
}

is_deeply ($copy ? \%Config_copy : \%Config, \%XSConfig, "cmp PP to XS hashes");

if (!Test::More->builder->is_passing()) {
  if (index(`diff --help`, 'Usage: diff') != -1) {
    open my $f, '>','xscfg.txt';
    print $f Data::Dumper::Dumper({%XSConfig});
    close $f;
    open my $g, '>', 'ppcfg.txt';
  
    print $g ($copy
              ? Data::Dumper::Dumper({%Config_copy})
              : Data::Dumper::Dumper({%Config}));
    close $g;
    system('diff -U 0 ppcfg.txt xscfg.txt > cfg.diff');
    unlink('xscfg.txt');
    unlink('ppcfg.txt');
    if (-s 'cfg.diff') {
      open my $h , '<','cfg.diff';
      local $/;
      my $file = <$h>;
      close $h;
      diag($file);
    }
    unlink('cfg.diff');
  } else {
    diag('diff not available, can\'t output config delta');
  }
}
