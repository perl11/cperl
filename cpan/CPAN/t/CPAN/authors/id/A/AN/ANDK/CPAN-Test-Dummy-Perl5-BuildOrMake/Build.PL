use strict;
use Module::Build;
use File::Spec;
sub _f ($) {File::Spec->catfile(split /\//, shift);}

my $b = Module::Build->new(
                           module_name  => 'CPAN::Test::Dummy::Perl5::BuildOrMake',
                           license      => 'perl',
                           dist_version_from => _f('./lib/CPAN/Test/Dummy/Perl5/BuildOrMake.pm'),
                           dist_author  => "Andreas Koenig",
);

$b->create_build_script();
