use strict;
use Module::Build;
use File::Spec;
sub _f ($) {File::Spec->catfile(split /\//, shift);}

my $b = Module::Build->new(
                           module_name  => 'CPAN::Test::Dummy::Perl5::Build',
                           license      => 'perl',
                           dist_version_from => _f('./lib/CPAN/Test/Dummy/Perl5/Build.pm'),
                           dist_author  => "Andreas Koenig",
                           build_requires => {
                                              "CPAN::Test::Dummy::Perl5::Make" => 0,
                                             },
                           requires     => {
                                            "CPAN::Test::Dummy::Perl5::Make::Zip" => 0,
                                           },
);

$b->create_build_script();
