use lib '.';
use strict;
use warnings;

use t::TestYAML tests => 2;
use YAML::XS qw/ DumpFile LoadFile /;

my $pc = eval "use Path::Class; 1";

my $file;

SKIP: {
    skip "Path::Class need for this test", 2 unless $pc;

    my $data = {
        foo => "boo",
    };
    $file = file("t", "path-class-$$.yaml");
    DumpFile($file, $data);
    ok -f $file, "Path::Class $file exists";

    my $data2 = LoadFile($file);
    is_deeply($data, $data2, "Path::Class roundtrip works");
}

END {
    unlink $file if defined $file;
}
