use Test::More tests => 1;
use Internals::DumpArenas;

my $fh;
open $fh, '>', 'tmp';
Internals::DumpArenas::DumpArenasFd(3);
close $fh;
unlink 'tmp';
pass( 'Still alive' );
