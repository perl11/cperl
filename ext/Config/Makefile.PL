use ExtUtils::MakeMaker;

push(@ExtUtils::MakeMaker::Overridable, qw(pm_to_blib));
WriteMakefile(
    'NAME'		=> 'Config',
    'VERSION_FROM'	=> 'Config.pm',
    'PL_FILES'		=> {'Config_xs.PL' => 'Config.xs'},
    'clean'		=> {FILES => 'Config.xs            Config_xs.out-new
                                      Config_xs.tmp.in-new Config_xs.tmp.out
                                      Config.c             Config_pm_mtime'},
    #'PM' => {
    #    'Config.pm'      => '$(INST_LIBDIR)/Config.pm'
    #},
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

package main;
