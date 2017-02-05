use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'		=> 'warnings',
    'VERSION_FROM'	=> 'warnings.pm',
    'PL_FILES'		=> { 'warnings_xs.PL' => 'warnings.xs' },
    'PM' => {
        'warnings.pm'   => '$(INST_LIBDIR)/warnings.pm',
        'register.pm'   => '$(INST_LIBDIR)/warnings/register.pm',
    },
);

sub MY::postamble {
    return $_[0]->is_make_type('nmake')
        ? "\$(OBJECT) : warnings.c\n\nwarnings.c : warnings.xs"
        : '';
}
