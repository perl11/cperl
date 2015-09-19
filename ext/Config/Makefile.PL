use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'		=> 'Config',
    'VERSION_FROM'	=> 'Config.pm',
    'PL_FILES'		=> {'Config_xs.PL' => 'Config.xs'},
);

package MY;
sub postamble {
    #Config.xs is a psuedotarget in nmake, not a disk file, in nmake
    #inference rules are triggered only by disk files with the same base name,
    #not psuedotargets with the same base name, so specify the dependency
    #explicitly, dmake doesn't need this
    return $_[0]->is_make_type('nmake')
        ? '$(OBJECT) : Config.c'."\n\n".'Config.c : Config.xs'
        : '';
}
package main;
