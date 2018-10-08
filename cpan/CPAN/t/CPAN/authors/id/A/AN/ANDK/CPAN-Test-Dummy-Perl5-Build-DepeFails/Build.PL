use strict;
use Module::Build;
use File::Spec;
sub _f ($) {File::Spec->catfile(split /\//, shift);}

my $b = Module::Build->new(
                           module_name  => 'CPAN::Test::Dummy::Perl5::Build::DepeFails',
                           license      => 'perl',
                           dist_version_from => _f('./lib/CPAN/Test/Dummy/Perl5/Build/DepeFails.pm'),
                           dist_author  => "Andreas Koenig",
                           requires => {
                                        'CPAN::Test::Dummy::Perl5::Build::Fails' => 0,
                                       }
);

$b->create_build_script();
