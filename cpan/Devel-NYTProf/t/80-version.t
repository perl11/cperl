use Test::More tests => 4;

use_ok('Devel::NYTProf::Core');
my $version = $Devel::NYTProf::Core::VERSION;
ok $version, 'lib/Devel/NYTProf/Core.pm $VERSION should be set';

use_ok('Devel::NYTProf');
is $Devel::NYTProf::VERSION, $version, 'lib/Devel/NYTProf.pm $VERSION should match';

# clean up after ourselves
DB::finish_profile();
unlink 'nytprof.out';
