use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'		=> 'Config',
    'VERSION_FROM'	=> 'Config.pm',
    'PL_FILES'		=> {'Config_xs.PL' => 'Config.xs'},
);
