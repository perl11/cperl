################################################################################
#
#  Makefile.PL -- generate Makefile
#
################################################################################
#
#  Version 3.x, Copyright (C) 2004-2013, Marcus Holland-Moritz.
#               Copyright (C) 2018-2019, The perl5 porters
#               Copyright (C) 2015-2019, Reini Urban.
#  Version 2.x, Copyright (C) 2001, Paul Marquess.
#  Version 1.x, Copyright (C) 1999, Kenneth Albanowski.
#
#  This program is free software; you can redistribute it and/or
#  modify it under the same terms as Perl itself.
#
################################################################################

require 5.003;

use strict;
use ExtUtils::MakeMaker;

use vars '%opt';  # needs to be global, and we can't use 'our'

unless ($ENV{'PERL_CORE'}) {
  $ENV{'PERL_CORE'} = 1 if grep { $_ eq 'PERL_CORE=1' } @ARGV;
}
my $PERL_CORE = $ENV{'PERL_CORE'} ? 'PERL_CORE=1' : '';

@ARGV = map { /^--with-(apicheck)$/ && ++$opt{$1} ? () : $_ } @ARGV;

my %mf = (
  NAME          => 'Devel::PPPort',
  VERSION_FROM  => 'PPPort_pm.PL',
  PM            => { 'PPPort.pm' => '$(INST_LIBDIR)/PPPort.pm' },
  H             => [ qw(ppport.h) ],
  OBJECT        => 'RealPPPort$(OBJ_EXT) $(O_FILES)',
  XSPROTOARG    => '-noprototypes',
  CONFIGURE     => \&configure,
);
delete $mf{META_MERGE} unless eval { ExtUtils::MakeMaker->VERSION (6.46) };
WriteMakefile(%mf);

sub configure
{
  my @clean    = qw{ $(H_FILES) RealPPPort.xs RealPPPort.c PPPort.pm };
  my %depend   = ('$(OBJECT)' => '$(H_FILES)');
  my @C_FILES  = qw{ module2.c module3.c },
  my %PL_FILES = (
    'ppport_h.PL'  => 'ppport.h',
    'PPPort_pm.PL' => 'PPPort.pm',
    'RealPPPort_xs.PL' => 'RealPPPort.xs',
  );
  my @moreopts;

  if (eval $ExtUtils::MakeMaker::VERSION >= 6) {
    push @moreopts, AUTHOR => 'Reini Urban <rurban@cpan.org>';
    push @moreopts, ABSTRACT_FROM => 'PPPort_pm.PL';
  }

  if (eval $ExtUtils::MakeMaker::VERSION >= 6.30_01) {
    print "Setting license tag...\n";
    push @moreopts, LICENSE => 'perl';
  }

  if (not $ENV{'PERL_CORE'}) {
    # Devel::PPPort is in the core since 5.7.3
    # 5.11.0+ has site before perl
    push @moreopts, INSTALLDIRS => (
      ("$]" >= 5.007003 and "$]" < 5.011)
        ? 'perl'
        : 'site'
    );
  }

  if ($opt{'apicheck'}) {
    $PL_FILES{'apicheck_c.PL'} = 'apicheck.c';
    push @C_FILES, qw{ apicheck.c };
    push @clean,   qw{ apicheck.c apicheck.i };
    $depend{'apicheck.i'} = 'ppport.h';
  }

  open FH, '<PPPort_pm.PL' or die "cannot open PPPort_pm.PL for reading: $!";
  my $version;
  while (my $line = <FH>) {
    ($version) = $line =~ /^\$VERSION = '([\d._]+)';$/ and last;
  };
  die 'failed to extract $VERSION from PPPort_pm.PL' if not $version;
  close FH;

  if (eval $ExtUtils::MakeMaker::VERSION > 6.45) {
    push @moreopts, META_MERGE => {
      'meta-spec' => { version => 2 },
      provides => {
        'Devel::PPPort' => {
          file    => 'PPPort_pm.PL',
          version => $version,
        },
      },
      resources => {
        bugtracker => {
          web => 'https://github.com/perl11/cperl/issues/',
        },
        repository => {
          type => 'git',
          url  => 'git://github.com/rurban/Devel-PPPort',
          web  => 'https://github.com/rurban/Devel-PPPort',
        },
      },
    };
  }

  return {
    C        => \@C_FILES,
    XS       => { 'RealPPPort.xs' => 'RealPPPort.c' },
    PL_FILES => \%PL_FILES,
    depend   => \%depend,
    clean    => { FILES => "@clean" },
    @moreopts,
  };
}

package MY;

sub depend {
  "
t/warn.t : mktests.PL regen_tests
RealPPPort.c : ppport.h
"
}

sub postamble
{
  my $post = shift->SUPER::postamble(@_);
  $post .= <<'POSTAMBLE';

purge_all: realclean
	@$(RM_F) PPPort.pm t/*.t

regen_pm:
	$(PERL) -I$(INST_ARCHLIB) -I$(INST_LIB) -I$(PERL_ARCHLIB) -I$(PERL_LIB) PPPort_pm.PL PERL_CORE=$(PERL_CORE)

regen_xs:
	$(PERL) -I$(INST_ARCHLIB) -I$(INST_LIB) -I$(PERL_ARCHLIB) -I$(PERL_LIB) RealPPPort_xs.PL PERL_CORE=$(PERL_CORE)

regen_tests:
	$(PERL) -I$(INST_ARCHLIB) -I$(INST_LIB) -I$(PERL_ARCHLIB) -I$(PERL_LIB) mktests.PL PERL_CORE=$(PERL_CORE)

regen_h:
	$(PERL) -I$(INST_ARCHLIB) -I$(INST_LIB) -I$(PERL_ARCHLIB) -I$(PERL_LIB) ppport_h.PL PERL_CORE=$(PERL_CORE)

regen: regen_pm regen_xs regen_tests regen_h

POSTAMBLE
  return $post;
}

sub dist_core
{
  my $dist = shift->SUPER::dist_core(@_);

  my $updated = '';
  my @rules = split( m{^\s*$}m, $dist );
  foreach my $rule ( @rules ) {
    if ( $rule =~ m{^\s*^dist\s+:}m ) {
        $rule =~ s{:}{: manifest}; # make sure we regenerate the manifest
        $rule .= qq[\t].q[$(NOECHO) $(ECHO) "Warning: Please check '__MAX_PERL__' value in PPPort_pm.PL"].qq[\n];
    }
    $updated .= $rule;
  }

  return $updated;
}


sub c_o
{
  my $co = shift->SUPER::c_o(@_);

  if ($::opt{'apicheck'} && $co !~ /^\.c\.i:/m) {
    print "Adding custom rule for preprocessed apicheck file...\n";

    $co .= <<'CO'

.SUFFIXES: .i

.c.i:
	$(CCCMD) -E -I$(PERL_INC) $(DEFINE) $*.c > $*.i
CO
  }

  return $co;
}
