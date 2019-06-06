use Test::More tests => 4;

use_ok('Devel::NYTProf::Core');
my $version = $Devel::NYTProf::Core::VERSION;
ok $version, 'lib/Devel/NYTProf/Core.pm $VERSION should be set';
if (defined $Devel::NYTProf::Core::XS_VERSION) {
  $version = $Devel::NYTProf::Core::XS_VERSION;
}

use_ok('Devel::NYTProf');
is $Devel::NYTProf::VERSION, $version, 'lib/Devel/NYTProf.pm $VERSION should match Core::XS_VERSION';

# clean up after ourselves
DB::finish_profile();
unlink 'nytprof.out';
