use lib '.';
use t::TestYAML tests => 7;

use YAML::XS qw'LoadFile';

ok exists &LoadFile, 'LoadFile is imported';
ok not(exists &DumpFile), 'DumpFile is not imported';
ok not(exists &Dump), 'Dump is not imported';

rmtree('t/output');
mkdir('t/output');

my $test_file = 't/output/test.yaml';
ok not(-f $test_file), 'YAML output file does not exist yet';

my $t1 = {foo => [1..4]};
my $t2 = 'howdy ho';
YAML::XS::DumpFile($test_file, $t1, $t2);

ok -f $test_file, 'YAML output file exists';

my ($t1_, $t2_) = LoadFile($test_file);

is_deeply [$t1_, $t2_], [$t1, $t2], 'File roundtrip ok';

my $t3 = {"foo\x{123}" => [1..4]};
my $t4 = "howdy ho \x{5050}";
YAML::XS::DumpFile($test_file, $t3, $t4);

my ($t3_, $t4_) = LoadFile($test_file);

is_deeply [$t3_, $t4_], [$t3, $t4], 'Unicode roundtrip ok';
