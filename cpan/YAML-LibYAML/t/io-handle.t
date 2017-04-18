use lib '.';
use strict;
use lib -e 't' ? 't' : 'test';
my $t = -e 't' ? 't' : 'test';

use utf8;
use Encode;
use IO::Pipe;
use IO::File;
use t::TestYAML tests => 6;
use YAML::XS qw/DumpFile LoadFile/;;

my $testdata = 'El país es medible. La patria es del tamaño del corazón de quien la quiere.';


# IO::Pipe

my $pipe = new IO::Pipe;

if ( fork() ) { # parent reads from IO::Pipe handle
    $pipe->reader();
    my $recv_data = LoadFile($pipe);
    is length($recv_data), length($testdata), 'LoadFile from IO::Pipe read data';
    is $recv_data, $testdata, 'LoadFile from IO::Pipe contents is correct';
} else { # child writes to IO::Pipe handle
    $pipe->writer();
    DumpFile($pipe, $testdata);
    exit 0;
}

# IO::File

my $file = "$t/dump-io-file-$$.yaml";
my $fh = new IO::File;

# write to IO::File handle
$fh->open($file, ">") or die $!;
DumpFile($fh, $testdata);
$fh->close;
ok -e $file, 'IO::File output file exists';

# read from IO::File handle
$fh->open($file, '<') or die $!;
my $yaml = do { local $/; <$fh> };
is decode_utf8($yaml), "--- $testdata\n", 'LoadFile from IO::File contents is correct';

$fh->seek(0, 0);
my $read_data = LoadFile($fh) or die $!;
$fh->close;

is length($read_data), length($testdata), 'LoadFile from IO::File read data';
is $read_data, $testdata, 'LoadFile from IO::File read data';

END {
    unlink $file if defined $file;  # $file will be undefined in fork child.
}
