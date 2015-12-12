use Test::More tests => 2;

use YAML::XS;

$_ = 'foo';

YAML::XS::LoadFile('t/empty.yaml');

pass 'LoadFile on empty file does not fail';
is $_, 'foo', '$_ is unchanged';
