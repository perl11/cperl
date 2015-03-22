#!/usr/bin/perl -w
#
# regen.pl - a wrapper that runs all *.pl scripts to autogenerate files

require 5.004;	# keep this compatible, an old perl is all we may have before
                # we build the new one

# The idea is to move the regen_headers target out of the Makefile so that
# it is possible to rebuild the headers before the Makefile is available.
# (and the Makefile is unavailable until after Configure is run, and we may
# wish to make a clean source tree but with current headers without running
# anything else.

use strict;
use Config;

my $tap = $ARGV[0] && $ARGV[0] eq '--tap' ? '# ' : '';

#miniperl mostly
foreach my $pl (map {chomp; "regen/$_"} <DATA>) {
  my @command =  ($^X, '-I.', $pl, @ARGV);
  print "$tap@command\n";
  system @command
    and die "@command failed: $?";
}

# and now fullperl for Config
if (!$tap) {
  my $perl = ($^O =~ /^(MSWin32|symbian|os2|cygwin|dos)$/) ? 'perl.exe' : "perl";
  my @command = (($perl eq 'perl' ? './perl' : $perl), '-I.',
                 'ext/Config/Config_xs.PL', '--force', '--regen', @ARGV);
  # This is fine to use, we only care about the os here
  my $ldlibpthname = $Config{ldlibpthname};
  # But this is a fallback only
  my $useshrplib = $Config{useshrplib};
  # as we need the current useshrplib, not the one from the perl
  # which we are using (like /usr/bin/perl)
  if (-f 'config.sh') {
    my $f;
    open $f, 'config.sh';
    while (<$f>) {
      if (/^useshrplib='(.*)'/) {
        $useshrplib = $1; last;
      }
    }
    close $f;
  }
  if ($useshrplib eq 'true' and $ldlibpthname) {
    require Cwd;
    $ENV{$ldlibpthname} = Cwd::getcwd();
  }
  print "@command\n";
  system @command
    and die "@command failed: $?";
}

__END__
mg_vtable.pl
opcode.pl
overload.pl
reentr.pl
regcomp.pl
../ext/warnings/warnings_xs.PL
embed.pl
feature.pl
uconfig_h.pl
