#!./perl
#
# Tests for Perl run-time environment variable settings
#
# $PERL5OPT, $PERL5LIB, etc.

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require Config; import Config;
    require './test.pl';
    skip_all_without_config('d_fork');
}

plan tests => 116;

my $STDOUT = tempfile();
my $STDERR = tempfile();
my $PERL = './perl';
my $FAILURE_CODE = 119;

delete $ENV{PERLLIB};
delete $ENV{PERL5LIB};
delete $ENV{PERL5OPT};
delete $ENV{PERL_USE_UNSAFE_INC};


# Run perl with specified environment and arguments, return (STDOUT, STDERR)
sub runperl_and_capture {
  local *F;
  my ($env, $args) = @_;

  local %ENV = %ENV;
  delete $ENV{PERLLIB};
  delete $ENV{PERL5LIB};
  delete $ENV{PERL5OPT};
  delete $ENV{PERL_USE_UNSAFE_INC};
  my $pid = fork;
  return (0, "Couldn't fork: $!") unless defined $pid;   # failure
  if ($pid) {                   # parent
    wait;
    return (0, "Failure in child.\n") if ($?>>8) == $FAILURE_CODE;

    open my $stdout, '<', $STDOUT
	or return (0, "Couldn't read $STDOUT file: $!");
    open my $stderr, '<', $STDERR
	or return (0, "Couldn't read $STDERR file: $!");
    local $/;
    # Empty file with <$stderr> returns nothing in list context
    # (because there are no lines) Use scalar to force it to ''
    return (scalar <$stdout>, scalar <$stderr>);
  } else {                      # child
    for my $k (keys %$env) {
      $ENV{$k} = $env->{$k};
    }
    open STDOUT, '>', $STDOUT or exit $FAILURE_CODE;
    open STDERR, '>', $STDERR and do { exec $PERL, @$args };
    # it did not work:
    print STDOUT "IWHCWJIHCI\cNHJWCJQWKJQJWCQW\n";
    exit $FAILURE_CODE;
  }
}

sub try {
  my ($env, $args, $stdout, $stderr) = @_;
  my ($actual_stdout, $actual_stderr) = runperl_and_capture($env, $args);
  local $::Level = $::Level + 1;
  my @envpairs = ();
  for my $k (sort keys %$env) {
    push @envpairs, "$k => $env->{$k}";
  }
  my $label = join(',' => (@envpairs, @$args));
  if (ref $stdout) {
    ok ( $actual_stdout =~/$stdout/, $label . ' stdout' );
  } else {
    is ( $actual_stdout, $stdout, $label . ' stdout' );
  }
  if (ref $stderr) {
    ok ( $actual_stderr =~/$stderr/, $label . ' stderr' );
  } else {
    is ( $actual_stderr, $stderr, $label . ' stderr' );
  }
}

#  PERL5OPT    Command-line options (switches).  Switches in
#                    this variable are taken as if they were on
#                    every Perl command line.  Only the -[DIMUdmtw]
#                    switches are allowed.  When running taint
#                    checks (because the program was running setuid
#                    or setgid, or the -T switch was used), this
#                    variable is ignored.  If PERL5OPT begins with
#                    -T, tainting will be enabled, and any
#                    subsequent options ignored.

try({PERL5OPT => '-w'}, ['-e', 'print $::x'],
    "", 
    qq{Name "main::x" used only once: possible typo at -e line 1.\nUse of uninitialized value \$x in print at -e line 1.\n});

try({PERL5OPT => '-Mstrict'}, ['-I../lib', '-e', 'print $::x'],
    "", "");

try({PERL5OPT => '-Mstrict'}, ['-I../lib', '-e', 'print $x'],
    "", 
    qq{Global symbol "\$x" requires explicit package name (did you forget to declare "my \$x"?) at -e line 1.\nExecution of -e aborted due to compilation errors.\n});

# Fails in 5.6.0
try({PERL5OPT => '-Mstrict -w'}, ['-I../lib', '-e', 'print $x'],
    "", 
    qq{Global symbol "\$x" requires explicit package name (did you forget to declare "my \$x"?) at -e line 1.\nExecution of -e aborted due to compilation errors.\n});

# Fails in 5.6.0
try({PERL5OPT => '-w -Mstrict'}, ['-I../lib', '-e', 'print $::x'],
    "", 
    <<ERROR
Name "main::x" used only once: possible typo at -e line 1.
Use of uninitialized value \$x in print at -e line 1.
ERROR
    );

# Fails in 5.6.0
try({PERL5OPT => '-w -Mstrict'}, ['-I../lib', '-e', 'print $::x'],
    "", 
    <<ERROR
Name "main::x" used only once: possible typo at -e line 1.
Use of uninitialized value \$x in print at -e line 1.
ERROR
    );

try({PERL5OPT => '-MExporter'}, ['-I../lib', '-e0'],
    "", 
    "");

# Fails in 5.6.0
try({PERL5OPT => '-MExporter -MExporter'}, ['-I../lib', '-e0'],
    "", 
    "");

try({PERL5OPT => '-Mstrict -Mwarnings'}, 
    ['-I../lib', '-e', 'print "ok" if $INC{"strict.pm"} and $INC{"warnings.pm"}'],
    "ok",
    "");

open my $fh, ">", "tmpOooof.pm" or die "Can't write tmpOooof.pm: $!";
print $fh "package tmpOooof; 1;\n";
close $fh;
END { 1 while unlink "tmpOooof.pm" }

try({PERL5OPT => '-I. -MtmpOooof'}, 
    ['-e', 'print "ok" if $INC{"tmpOooof.pm"} eq "tmpOooof.pm"'],
    "ok",
    "");

try({PERL5OPT => '-I./ -MtmpOooof'}, 
    ['-e', 'print "ok" if $INC{"tmpOooof.pm"} eq "tmpOooof.pm"'],
    "ok",
    "");

try({PERL5OPT => '-w -w'},
    ['-e', 'print $ENV{PERL5OPT}'],
    '-w -w',
    '');

try({PERL5OPT => '-t'},
    ['-e', 'print ${^TAINT}'],
    '-1',
    '');

try({PERL5OPT => '-W'},
    ['-I../lib','-e', 'local $^W = 0;  no warnings;  print $x'],
    '',
    <<ERROR
Name "main::x" used only once: possible typo at -e line 1.
Use of uninitialized value \$x in print at -e line 1.
ERROR
);

try({PERLLIB => "foobar$Config{path_sep}42"},
    ['-e', 'print grep { $_ eq "foobar" } @INC'],
    'foobar',
    '');

try({PERLLIB => "foobar$Config{path_sep}42"},
    ['-e', 'print grep { $_ eq "42" } @INC'],
    '42',
    '');

try({PERL5LIB => "foobar$Config{path_sep}42"},
    ['-e', 'print grep { $_ eq "foobar" } @INC'],
    'foobar',
    '');

try({PERL5LIB => "foobar$Config{path_sep}42"},
    ['-e', 'print grep { $_ eq "42" } @INC'],
    '42',
    '');

try({PERL5LIB => "foo",
     PERLLIB => "bar"},
    ['-e', 'print grep { $_ eq "foo" } @INC'],
    'foo',
    '');

try({PERL5LIB => "foo",
     PERLLIB => "bar"},
    ['-e', 'print grep { $_ eq "bar" } @INC'],
    '',
    '');

my $usecperl = $Config::Config{usecperl}; # also with PERL_PERTURB_KEYS_DISABLED
my $perturb = $usecperl ? "0" : "2";
my $DEBUGGING = $Config::Config{ccflags} =~ /-DDEBUGGING/;

SKIP:
{
    skip "NO_PERL_HASH_SEED_DEBUG set", 10
      if $Config{ccflags} =~ /-DNO_PERL_HASH_SEED_DEBUG\b/;

try({PERL_HASH_SEED_DEBUG => 1},
    ['-e','1'],
    '',
    qr/HASH_FUNCTION =/);

try({PERL_HASH_SEED_DEBUG => 1},
    ['-e','1'],
    '',
    qr/HASH_SEED =/);

try({PERL_HASH_SEED_DEBUG => 1, PERL_PERTURB_KEYS => "0"},
    ['-e','1'],
    '',
    qr/PERTURB_KEYS = 0/);

$perturb = $usecperl ? "0" : "1";
try({PERL_HASH_SEED_DEBUG => 1, PERL_PERTURB_KEYS => "1"},
    ['-e','1'],
    '',
    qr/PERTURB_KEYS = $perturb/);

$perturb = $usecperl ? "0" : "2";
try({PERL_HASH_SEED_DEBUG => 1, PERL_PERTURB_KEYS => "2"},
    ['-e','1'],
    '',
    qr/PERTURB_KEYS = $perturb/);

}
    
SKIP:
{
    skip "NO_PERL_HASH_ENV or NO_PERL_HASH_SEED_DEBUG set", 20
      if $Config{ccflags} =~ /-DNO_PERL_HASH_ENV\b/ ||
         $Config{ccflags} =~ /-DNO_PERL_HASH_SEED_DEBUG\b/;
    
# security, disable with -t
try({PERL_HASH_SEED_DEBUG => 1, PERL_HASH_SEED => "0"},
    ['-t', '-e','1'],
    '',
    '');

# security, hide seed without DEBUGGING
try({PERL_HASH_SEED_DEBUG => 1, PERL_HASH_SEED => "0"},
    ['-e','1'],
    '',
    $DEBUGGING ? qr/HASH_SEED = 0x\d+/ : qr/HASH_SEED = <hidden>/);

# special case, seed "0" implies disabled hash key traversal randomization
try({PERL_HASH_SEED_DEBUG => 1, PERL_HASH_SEED => "0"},
    ['-e','1'],
    '',
    qr/PERTURB_KEYS = 0/);

# check that setting it to a different value with the same logical value
# triggers the normal "deterministic mode".
try({PERL_HASH_SEED_DEBUG => 1, PERL_HASH_SEED => "0x0"},
    ['-e','1'],
    '',
    qr/PERTURB_KEYS = $perturb/);

try({PERL_HASH_SEED_DEBUG => 1, PERL_HASH_SEED => "12345678"},
    ['-e','1'],
    '',
    $DEBUGGING ? qr/HASH_SEED = 0x12345678/ : qr/HASH_SEED = <hidden>/);

try({PERL_HASH_SEED_DEBUG => 1, PERL_HASH_SEED => "12"},
    ['-e','1'],
    '',
    $DEBUGGING ? qr/HASH_SEED = 0x12000000/ : qr/HASH_SEED = <hidden>/);

try({PERL_HASH_SEED_DEBUG => 1, PERL_HASH_SEED => "123456789"},
    ['-e','1'],
    '',
    $DEBUGGING ? qr/HASH_SEED = 0x12345678/ : qr/HASH_SEED = <hidden>/);

    # Test that PERL_PERTURB_KEYS works as expected.  We check that we get the same
    # results if we use PERL_PERTURB_KEYS = 0 or 2 and we reuse the seed from previous run.
    # Note that with cperl modes 1 and 2, random and deterministic, are disabled.
    # You always get PERTURB_KEYS=TOP, which might change the order with most read accesses.
    my @print_keys = ( '-e', '@_{"A".."Z"}=(); print keys %_');
    my $seed = int(rand(~1)) & 0xffff_ffff; # UINT32_MAX, ~1 might be 64bit
    $seed++ unless $seed; # 0 is a special case, avoid.
    for my $mode ( 0, 1, 2 ) { # disabled, random, deterministic
      my %base_opts = ( PERL_PERTURB_KEYS => $mode, PERL_HASH_SEED_DEBUG => 1 );
      $base_opts{PERL_HASH_SEED} = $seed unless $DEBUGGING;
      my ($out, $err) = runperl_and_capture( { %base_opts }, [ @print_keys ]);
      if ($DEBUGGING and $err=~/HASH_SEED = (0x[a-f0-9]+)/) {
        $seed = $1;
      }
      my($out2, $err2) = runperl_and_capture( { %base_opts, PERL_HASH_SEED => $seed }, [ @print_keys ]);
      # in cperl only mode 0 is enabled
      if ( !$usecperl and $mode == 1 ) {
        isnt ($out,$out2,"PERL_PERTURB_KEYS=$mode different key order with the same key");
      } else {
        is ($out,$out2,"PERL_PERTURB_KEYS=$mode allows one to recreate a random hash");
      }
      is ($err,$err2,"Same debug output with PERL_HASH_SEED=$seed and PERL_PERTURB_KEYS=$mode");
    }

}

# Tests for S_incpush_use_sep():

my @dump_inc = ('-e', 'print "$_\n" foreach @INC');

my ($out, $err) = runperl_and_capture({}, [@dump_inc]);

is ($err, '', 'No errors when determining @INC');

my @default_inc = split /\n/, $out;

SKIP: {
  if (is_miniperl() or !$Config{default_inc_excludes_dot}) {
    is ($default_inc[-1], '.', '. is last in @INC');
    skip('Not testing unsafe @INC when it includes . by default', 2);
  } else {
    ok (! grep { $_ eq '.' } @default_inc, '. is not in @INC');
    ($out, $err) = runperl_and_capture({ PERL_USE_UNSAFE_INC => 1 }, [@dump_inc]);

    is ($err, '', 'No errors when determining unsafe @INC');

    my @unsafe_inc = split /\n/, $out;

    ok (eq_array([@unsafe_inc], [@default_inc, '.']), '. last in unsafe @INC')
      or diag 'Unsafe @INC is: ', @unsafe_inc;
  }
}

my $sep = $Config{path_sep};
foreach (['nothing', ''],
	 ['something', 'zwapp', 'zwapp'],
	 ['two things', "zwapp${sep}bam", 'zwapp', 'bam'],
	 ['two things, ::', "zwapp${sep}${sep}bam", 'zwapp', 'bam'],
	 [': at start', "${sep}zwapp", 'zwapp'],
	 [': at end', "zwapp${sep}", 'zwapp'],
	 [':: sandwich ::', "${sep}${sep}zwapp${sep}${sep}", 'zwapp'],
	 [':', "${sep}"],
	 ['::', "${sep}${sep}"],
	 [':::', "${sep}${sep}${sep}"],
	 ['two things and :', "zwapp${sep}bam${sep}", 'zwapp', 'bam'],
	 [': and two things', "${sep}zwapp${sep}bam", 'zwapp', 'bam'],
	 [': two things :', "${sep}zwapp${sep}bam${sep}", 'zwapp', 'bam'],
	 ['three things', "zwapp${sep}bam${sep}${sep}owww",
	  'zwapp', 'bam', 'owww'],
	) {
  my ($name, $lib, @expect) = @$_;
  push @expect, @default_inc;

  ($out, $err) = runperl_and_capture({PERL5LIB => $lib}, [@dump_inc]);

  is ($err, '', "No errors when determining \@INC for $name");

  my @inc = split /\n/, $out;

  is (scalar @inc, scalar @expect,
      "expected number of elements in \@INC for $name");

  is ("@inc", "@expect", "expected elements in \@INC for $name");
}

# PERL5LIB tests with included arch directories still missing
