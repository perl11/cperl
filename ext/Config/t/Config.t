#!/usr/bin/perl

if (scalar keys %Config:: > 2) {
  print "0..1 #SKIP Cannot test with static or builtin Config\n";
  exit;
}

require Config; #this is supposed to be XS config
require B;
my $cv = B::svref_2object(*{'Config::FETCH'}{CODE});
unless ($cv->CvFLAGS & B::CVf_ISXSUB()) {
  print "0..1 #SKIP Config:: is not XS Config, miniperl?\n";
  exit;
}

# change the class name of XS Config so there can be XS and PP Config at same time
foreach (qw( TIEHASH DESTROY DELETE CLEAR EXISTS NEXTKEY FIRSTKEY KEYS SCALAR FETCH)) {
  *{'XSConfig::'.$_} = *{'Config::'.$_}{CODE};
}
tie(%XSConfig, 'XSConfig');

# delete package
undef( *main::Config:: );
require Data::Dumper;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq = 1;

# full perl is now miniperl
undef( *main::XSLoader::);
require 'Config_mini.pl';
Config->import();
require 'Config_heavy.pl';
require Test::More;
Test::More->import (tests => 4);

ok($cv->CvFLAGS & B::CVf_ISXSUB(), 'XS Config:: is XS');

$cv = B::svref_2object(*{'Config::FETCH'}{CODE});
ok(!($cv->CvFLAGS & B::CVf_ISXSUB()), 'PP Config:: is PP');

my ($klenPP, $klenXS) = (scalar(keys %Config), scalar(keys %XSConfig));
my $copy = 0;
my %Config_copy;
if ($klenPP != $klenXS) {
  $copy = 1;
  for (keys %Config) {
    $Config_copy{$_} = $Config{$_};
  }
  # See Config_xs.PL:
  # postprocess the values a bit:
  # reserve up to 20 config_args
  for (1..20) {
    my $k = "config_arg".$_;
    $Config_copy{$k} = '' unless exists $Config{$k};
  }
  for my $k (qw(libdb_needs_pthread malloc_cflags
              git_ancestor git_remote_branch git_unpushed)) {
    $Config_copy{$k} = '' unless exists $Config{$k};
  }
  is (scalar keys %Config_copy, $klenXS, 'same adjusted key count');
} else {
  is ($klenPP, $klenXS, 'same key count');
}

is_deeply ($copy ? \%Config_copy : \%Config, \%XSConfig, "cmp PP to XS hashes");

if ( !Test::More->builder->is_passing() ) {
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
  } else {
    unlink('cfg.diff');
  }
}
