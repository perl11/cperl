use ExtUtils::MakeMaker;

push(@ExtUtils::MakeMaker::Overridable, qw(pm_to_blib));
my $in_core = ! -d "regen";
our $uninst;
my $version = MM->parse_version('Config.pm');

WriteMakefile(
    'ABSTRACT'		=> 'Fast XS drop-in replacement for Config.pm with perfect hashing',
    'AUTHOR'		=> ($ExtUtils::MakeMaker::VERSION >= '6.58'
                            ? ['Daniel Dragan <bulkdd@cpan.org>',
                               'Reini Urban <rurban@cpan.org>']
                            : 'Daniel Dragan <bulkdd@cpan.org>, '
                              .'Reini Urban <rurban@cpan.org>'),
    'DISTNAME'		=> 'XSConfig',
    'LICENSE'		=> 'perl',
    'NAME'		=> 'Config',
    'META_MERGE'	=> {
        resources => {
            repository => 'https://github.com/perl11/p5-Config',
        },
        provides => {
            XSConfig => { file => 'Config.pm', version => $version },
        },
    },
    # Config_heavy.pl didn't exist before 5.8.7, it was part of a huge Config.pm
    # not worth the time to modify Config_xs.PL and Config_xs_heavy.pl.PL
    'MIN_PERL_VERSION'  => '5.8.7',
    'VERSION'		=> $version,
    'PL_FILES'		=> {'Config_xs.PL' => 'Config.xs',
                            ($in_core ?
                                () : ('Config_mini.pl.PL'     => 'Config_mini.pl',
                                      'Config_xs_heavy.pl.PL' => 'Config_xs_heavy.pl')
                            )},
    'clean'		=> {FILES =>  oldclean('Config.xs  Config_xs.out-new
                                      Config_xs_tmp.in     Config_xs.tmp.in-new
                                      Config_xs_tmp.out    Config.c
                                      Config_pm_mtime      Config_mini.pl
                                      Config_xs_heavy.pl   Config_def.old
                                      UNINST_0             UNINST_1
                                      ')},
    'PM' => {
        'Config.pm'     => '$(INST_ARCHLIBDIR)/Config.pm',
        ($in_core ? () : ('Config_mini.pl'     => '$(INST_ARCHLIBDIR)/Config_mini.pl',
                          'Config_xs_heavy.pl' => '$(INST_ARCHLIBDIR)/Config_xs_heavy.pl',
                          'XSConfig.pod'       => '$(INST_ARCHLIBDIR)/XSConfig.pod')),
    },
    # XS Config can not be loaded by P5P DynaLoader, only by XSLoader WITHOUT
    # XSLoader passing the "complicated" loading scenario to DynaLoader.
    # P5P DL use'es Config, to get $Config{dlext}, a bootstraping problem for XS
    # Config, XSLoader passes onto DynaLoader if the auto/Config/Config.dll is
    # not in the same @INC dir as Config.pm, so put Config.pm in /arch.
    ($in_core ? () : (INST_LIB => '$(INST_ARCHLIB)')),

    #XSOPT  => ' -nolinenumbers ',
);

use ExtUtils::Command ();

unless ($ENV{PERL_CORE}) {
    local @ARGV;
    unlink('UNINST_0');
    unlink('UNINST_1');
    # touch what we plan for UNINST to be in the makefile
    @ARGV  = 'UNINST_'.($uninst ? '1' : '0');
    ExtUtils::Command::touch();
    # now touch Makefile.PL so the above doesn't trigger a rebuild.
    # note that with a src tarball, Makefile.PL is readonly
    if (-w 'Makefile.PL') {
        @ARGV = 'Makefile.PL';
        ExtUtils::Command::touch();
    }
    @ARGV = 'Makefile'; #we aren't inside WriteMakefile with open FH anymore
    ExtUtils::Command::touch();
    # if Makefile.PL and poison target are the same second, no rebuild happens
    sleep 1;
    # Touch opposite of what we think UNINST will be in the makefile
    # to force a rebuild. The only way this becomes a dependency of Makefile
    # is to override the maketool on the command line
    @ARGV  = 'UNINST_'.($uninst ? '0' : '1');
    ExtUtils::Command::touch();
}

sub oldclean {
    # EUMM before ~6.25_02 did not add tabs and '\'s to the clean line, the list
    # of files would be tried to excuted if they had newlines in them from
    # the WriteMakefile hash
    if($ExtUtils::MM_Unix::VERSION lt '1.46_02') {
        my $clean = $_[0];
        $clean =~ y/\n//d;
        return $clean;
    } else {
        return $_[0];
    }
}

package MY;

# feat req https://rt.cpan.org/Public/Bug/Display.html?id=110631
sub post_initialize { # post_initialize() runs before constants()
    # see if it is in CPAN's configs, this is for CPANTesters/automated installs
    if ($in_core) {
        $main::uninst = 0;
    } else {
        require CPAN;
        CPAN::HandleConfig->can('load') ?
            CPAN::HandleConfig->load()
            : CPAN::Config->load(); #old CPAN.pms
        if ($CPAN::Config->{make_install_arg} =~ /\QUNINST=1\E/) {
            warn "found UNINST=1 in CPAN::Config";
            $_[0]->{UNINST} = $main::uninst = 1;
        } else {
        # from EUMM, UNINST could be from @ARGV or %ENV or anywhere
            $main::uninst = (!! $_[0]->{UNINST})+0;
        }
    }

    $_[0]->{INSTALLDIRS} =  'perl' if $main::uninst;
    # regen run of Makefile.PL gets UNINST val from maketool run
    push @ARGV, 'UNINST=$(UNINST)';
    '';
}

sub postamble {
    # Config.xs is a pseudotarget in nmake, not a disk file, in nmake
    # inference rules are triggered only by disk files with the same base name,
    # not psuedotargets with the same base name, so specify the dependency
    # explicitly, dmake doesn't need this
    # is_make_type meth existed only in EUMM on Win32 until EUMM 7.02
    # extremely old Win32 EUMMs dont even have is_make_type meth so always
    # assume nmake on Win32 then
    return ($_[0]->can('is_make_type') ?
                (  $_[0]->is_make_type('nmake')
                || $_[0]->is_make_type('gmake'))
            : $^O eq 'MSWin32')
        ? '$(OBJECT) : Config.c'."\n\n".'Config.c : Config.xs'
        : '';
}

sub pm_to_blib {
    my $self = shift;
    my $blib = $self->SUPER::pm_to_blib(@_);

    my $pos = index($blib, "\n", 1);
    die "bad position in pm_to_blib" if $pos == -1 || $pos == 0;
    # backdate mtime of XS Config.pm to mtime of old mini/PP Config.pm
    # this prevents mass rebuilds of modules during perl "make all"
    # on a non-clean src tree
    substr($blib, $pos+1, 0,
'	$(NOECHO) $(EQUALIZE_TIMESTAMP) $(PERL_ARCHLIBDEP)$(DFSEP)Config.pm Config_pm_mtime
');
    chomp($blib); #old EUMMs dont have a newline at the end, new ones do
    return $blib.'
	$(NOECHO) $(CHMOD) $(PERM_RW) $(INST_LIB)/Config.pm
	$(NOECHO) $(EQUALIZE_TIMESTAMP) Config_pm_mtime $(INST_LIB)/Config.pm';
}

sub processPL {
    my $self = shift;
    my $processPL = $self->SUPER::processPL(@_);
    # Config_xs.PL can't use the uninstalled, blib's XS Config.pm, and the shlib
    # for XS Config wasn't even built yet when Config_xs.PL runs, Config.xs is
    # not a .pm, so it can't be listed in EUMM's PM key which would otherwise
    # cause blib to NOT be -I'ed, so de-"-I" it manually
    $processPL =~ s/pm_to_blib/Config_xs.out Config_xs.in/g;
    $processPL =~ s/PERLRUNINST/PERLRUN/g;
    return $processPL;
}

sub makefile {
    my $makefile = $_[0]->SUPER::makefile(@_);
    my $pos = index($makefile, '$(FIRST_MAKEFILE) : Makefile.PL $(CONFIGDEP)');
    return $makefile if $in_core;
    die 'can\'t match in sub makefile()' if $pos == -1;
    substr($makefile, $pos,
        length('$(FIRST_MAKEFILE) : Makefile.PL $(CONFIGDEP)'),
               '$(FIRST_MAKEFILE) : Makefile.PL $(CONFIGDEP) UNINST_$(UNINST)');
    return $makefile;
}

package main;
