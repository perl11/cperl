use ExtUtils::MakeMaker;
use Config;
use File::Spec;
use 5.006;
use Carp;

WriteMakefile(
    'NAME'	 => "B::Stash",
    'VERSION_FROM' => "Stash.pm",
    'AUTHOR'   => 'Reini Urban <perl-compiler@googlegroups.com>',
    'ABSTRACT' => 'Perl compiler',
    'LICENSE'  => 'perl',
    'SIGN'     => 1,
);

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
