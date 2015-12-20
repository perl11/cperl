use ExtUtils::MakeMaker;

push(@ExtUtils::MakeMaker::Overridable, qw(pm_to_blib));
my $in_core = ! -d "regen";
WriteMakefile(
    'ABSTRACT'		=> 'Fast XS drop-in replacement for Config.pm with perfect hashing',
    'AUTHOR'		=> ($ExtUtils::MakeMaker::VERSION >= '6.58'
                                ? ['Daniel Dragan <bulkdd@cpan.org>', 'Reini Urban <rurban@cpanel.net>']
                                : 'Daniel Dragan <bulkdd@cpan.org>, Reini Urban <rurban@cpanel.net>'),
    'DISTNAME'		=> 'XSConfig',
    'LICENSE'		=> 'perl',
    'NAME'		=> 'Config',
    'META_MERGE'	=> {
        resources => {
            repository => 'https://github.com/perl11/p5-Config',
        },
    },
    'VERSION_FROM'	=> 'Config.pm',
    'PL_FILES'		=> {'Config_xs.PL' => 'Config.xs',
                            ($in_core ?
                                () : ('Config_mini.pl.PL'     => 'Config_mini.pl',
                                      'Config_xs_heavy.pl.PL' => 'Config_xs_heavy.pl')
                            )},
    'clean'		=> {FILES => 'Config.xs            Config_xs.out-new
                                      Config_xs.tmp.in-new Config_xs.tmp.out
                                      Config.c             Config_pm_mtime
                                      Config_mini.pl       Config_xs_heavy.pl
                                      '},
    'PM' => {
        'Config.pm'      => '$(INST_LIBDIR)/Config.pm',
        ($in_core ? () : ('Config_mini.pl'     => '$(INST_LIBDIR)/Config_mini.pl',
                          'Config_xs_heavy.pl' => '$(INST_LIBDIR)/Config_xs_heavy.pl')),
    },
    #XS Config can not be loaded by P5P DynaLoader, only by XSLoader WITHOUT
    #XSLoader passing the "complicated" loading scenario to DynaLoader.
    #P5P DL use'es Config, to get $Config{dlext}, a bootstraping problem for XS
    #Config, XSLoader passes onto DynaLoader if the auto/Config/Config.dll is
    #not in the same @INC dir as Config.pm, so put Config.pm in /arch.
    ($in_core ? () : (INST_LIB => '$(INST_ARCHLIB)')),

    #XSOPT  => ' -nolinenumbers ',
);

package MY;
sub postamble {
    # Config.xs is a pseudotarget in nmake, not a disk file, in nmake
    # inference rules are triggered only by disk files with the same base name,
    # not psuedotargets with the same base name, so specify the dependency
    # explicitly, dmake doesn't need this
    return $_[0]->is_make_type('nmake')
        ? '$(OBJECT) : Config.c'."\n\n".'Config.c : Config.xs'
        : '';
}

sub pm_to_blib {
    my $self = shift;
    my $blib = $self->SUPER::pm_to_blib(@_);

    my $pos = index($blib, "\n", 1);
    die "bad position in pm_to_blib" if $pos == -1 || $pos == 0;
    #backdate mtime of XS Config.pm to mtime of old mini/PP Config.pm
    #this prevents mass rebuilds of modules during perl "make all"
    #on a non-clean src tree
    substr($blib, $pos+1, 0,
'	$(NOECHO) $(EQUALIZE_TIMESTAMP) $(PERL_ARCHLIBDEP)$(DFSEP)Config.pm Config_pm_mtime
');
    return $blib
.'	$(NOECHO) $(CHMOD) $(PERM_RW) $(INST_LIB)/Config.pm
	$(NOECHO) $(EQUALIZE_TIMESTAMP) Config_pm_mtime $(INST_LIB)/Config.pm';
}

sub processPL {
    my $self = shift;
    my $processPL = $self->SUPER::processPL(@_);
    #Config_xs.PL can't use the uninstalled, blib's XS Config.pm, and the shlib
    #for XS Config wasn't even built yet when Config_xs.PL runs, Config.xs is
    #not a .pm, so it can't be listed in EUMM's PM key which would otherwise
    #cause blib to NOT be -I'ed, so de-"-I" it manually
    $processPL =~ s/ pm_to_blib//g;
    $processPL =~ s/PERLRUNINST/PERLRUN/g;
    return $processPL;
}

package main;
