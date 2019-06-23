use Test::More tests => 2;

use YAML::Safe;

$_ = 'foo';

YAML::Safe::LoadFile('t/empty.yaml');

pass 'LoadFile on empty file does not fail';
is $_, 'foo', '$_ is unchanged';
