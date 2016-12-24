# -*- cperl -*-
use strict;
BEGIN {
  unshift @INC, 't';
}
require TestBC;
use Test::More;
use Config;
use Cwd;
use Exporter;
our @ISA     = qw(Exporter);
our @EXPORT = qw(%modules $keep
		 perlversion
		 percent log_diag log_pass log_err get_module_list
                 random_sublist is_subset
		);
our (%modules);
our $log = 0;
our $keep = '';

sub perlversion {
  my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
  return sprintf("%1.6f%s%s%s", $],
                 ($Config{usecperl} ? "c" : ""),
                 ($DEBUGGING ? 'd' : ''),
                 ($Config{useithreads} ? ''
                  : $Config{usemultiplicity} ? '-m'
                  : '-nt'));
}

sub percent {
  $_[1] ? sprintf("%0.1f%%", $_[0]*100/$_[1]) : '';
}

sub log_diag {
  my $message = shift;
  chomp $message;
  diag( $message );
  return unless $log;

  foreach ($log, "$log.err") {
    open(LOG, ">>", $_);
    $message =~ s/\n./\n# /xmsg;
    print LOG "# $message\n";
    close LOG;
  }
}

sub log_pass {
  my ($pass_msg, $module, $todo) = @_;
  return unless $log;

  if ($todo) {
    $todo = " #TODO $todo";
  } else {
    $todo = '';
  }

  diag( "$pass_msg $module$todo" );
  open(LOG, ">>", "$log");
  print LOG "$pass_msg $module$todo\n";
  close LOG;
}

sub log_err {
  my ($module, $out, $err) = @_;
  return if(!$log);

  # diag prints for TODO to a special todo fh, which does not end at the console
  # ignore diag the TODO empty STDERR test for now. we diag the ok test only
  # diag( "fail $module $out" );
  # Test::More->builder->_print_comment( Test::More->builder->failure_output, "fail $module $out" );

  $_ =~ s/\n/\n# /xmsg foreach($out, $err); # Format for comments

  open(ERR, ">>", "$log.err");
  print ERR "Failed $module\n";
  print ERR "# No output\n" if(!$out && !$err);
  print ERR "# STDOUT:\n# $out\n" if($out && $out ne 'ok');
  print ERR "# STDERR:\n# $err\n" if($err);
  close ERR;
}

sub is_subset {
  return 0 if grep /^-no-subset$/, @ARGV;
  return ! (-d '.svn' or -d'.git') || grep /^-subset$/, @ARGV;
}

sub get_module_list {
  # Parse for command line modules and use this if seen.
  my @modules = grep {$_ !~ /^-([\w-]+)$/} @ARGV; # ignore options
  # -no-subset defaults to all top100
  my $module_list  = (grep /^-no-subset$/, @ARGV) ? 't/top100' : 't/test10';
  if (@modules and -e $modules[0] and ! -x $modules[0]) { # skip an executable compiled module
    $module_list = $modules[0];
  }
  elsif (@modules) {
    # cmdline overrides require check and keeps .c
    $modules{$_} = 1 for @modules;
    $keep = "-S";
    return @modules;
  }

  local $/;
  open F, "<", $module_list or die "$module_list not found";
  my $s = <F>;
  close F;
  @modules = grep {s/\s+//g;!/^#/} split /\n/, $s;

  diag "scanning installed modules" unless $ENV{PERL_CORE};
  for my $m (@modules) {
    # redirect stderr
    open (SAVEOUT, ">&STDERR");
    close STDERR;
    open (STDERR, ">", \$modules::saveout);
    if (eval "require $m;" or $m eq 'if') {
      $modules{$m} = 1;
    }
    # restore stderr
    close STDERR;
    open (STDERR, ">&SAVEOUT");
    close SAVEOUT;
  }

  if (&is_subset and @modules > 10) {
    log_diag("testing a random subset of the $module_list modules");
    @modules = random_sublist(@modules);
  }

  @modules;
}

sub random_sublist {
  my @modules = @_;
  my %sublist;
  return 1 if scalar(@modules) < 2;
  while (keys %sublist < 10) {
    my $m = $modules[int(rand(scalar @modules))];
    next unless $modules{$m}; # Don't random test uninstalled modules
    $sublist{$m} = 1;
  }
  return keys %sublist;
}

# for t/testm.sh -s
sub skip_modules {
  my @modules = get_module_list;
  my @skip = ();
  for my $m (@modules) {
    push @skip, ($m) unless $modules{$m};
  }
  @skip;
}

# preparing automatic module tests

package CPAN::Shell;
#{   # add testcc to the dispatching methods
#    no strict "refs";
#    my $command = 'testcc';
#    *$command = sub { shift->rematein($command, @_); };
#}
sub testcc { shift->rematein('testcc', @_); }
package CPAN::Module;
sub testcc   {
    my $self = shift;
    my $inst_file = $self->inst_file or return;
    # only if its a not-deprecated CPAN module. perl core not
    if ($self->can('_in_priv_or_arch')) { # 1.9301 not, 1.94 yes
      return if $self->_in_priv_or_arch($inst_file);
    }
    if ($] >= 5.011){
      if ($self->can('deprecated_in_core')) {
        return if $self->deprecated_in_core;
      } else {
        # CPAN-1.9402 has no such method anymore
        # trying to support deprecated.pm by Nicholas 2009-02
        if (my $distribution = $self->distribution) {
          return if $distribution->isa_perl;
        }
      }
    }
    $self->rematein('testcc', @_);
}
package CPAN::Distribution;
sub testcc   {
    my $self = shift;
    # $CPAN::DEBUG++;
    my $cwd = Cwd::getcwd();
    # posix shell only, but we are using a posix shell here. XXX -Wb=-uTest::Builder
    my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
    # we cannot use that in PERL_CORE, only as module
    $self->prefs->{test}->{commandline} =
      "for t in t/*.t; do "
	. "echo \"# \$t\"; $X -Iblib/arch -Iblib/lib -I\"$cwd/blib/arch\" -I\"$cwd/blib/lib\" \"$cwd/blib/script/perlcc\" -T -r \$t;"
     ."done";
    $self->prefs->{test_report} = ''; # XXX ignored!
    $self->{make_test} = 'NO'; # override YAML check "Has already been tested successfully"
    $self->test(@_);
    # done
}

1;
