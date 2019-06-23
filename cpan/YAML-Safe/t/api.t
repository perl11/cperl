use FindBin '$Bin';
use lib $Bin;
use TestYAML tests => 20;

package A;
use YAML::Safe;

package B;
use YAML::Safe();

package C;
use YAML::Safe('DumpFile', 'LoadFile');

package D;
use YAML::Safe ':all';

package E;
use YAML::Safe('Dump', 'LoadFile');

package main;

ok defined(&A::Dump), 'Dump is exported by default';
ok defined(&A::Load), 'Load is exported by default';
ok !defined(&A::DumpFile), 'DumpFile is not exported by default';
ok !defined(&A::LoadFile), 'LoadFile is not exported by default';

ok not(defined(&B::Dump)), 'Dump is not exported for ()';
ok not(defined(&B::Load)), 'Load is not exported for ()';
ok not(defined(&B::DumpFile)), 'DumpFile is not exported for ()';
ok not(defined(&B::LoadFile)), 'LoadFile is not exported for ()';

ok not(defined(&C::Dump)), 'Dump is not exported for qw(LoadFile DumpFile)';
ok not(defined(&C::Load)), 'Load is not exported for qw(LoadFile DumpFile)';
ok defined(&C::DumpFile), 'DumpFile is exportable';
ok defined(&C::LoadFile), 'LoadFile is exportable';

ok defined(&D::Dump), 'Dump is exported for :all';
ok defined(&D::Load), 'Load is exported for :all';
ok defined(&D::DumpFile), 'DumpFile is exported for :all';
ok defined(&D::LoadFile), 'LoadFile is exported for :all';

ok defined(&E::Dump), 'Dump is exported for qw(LoadFile Dump)';
ok not(defined(&E::Load)), 'Load is not exported for qw(LoadFile Dump)';
ok not(defined(&E::DumpFile)), 'DumpFile is exported for qw(LoadFile Dump)';
ok defined(&E::LoadFile), 'LoadFile is not exported for qw(LoadFile Dump)';


