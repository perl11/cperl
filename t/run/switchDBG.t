#!./perl -w

# Tests for the -D debug command-line switches

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require "./test.pl";
    require Config; Config->import;
    skip_all('no DEBUGGING') if $Config{ccflags} !~ /DDEBUGGING/;
}

plan(tests => 36);

BEGIN {
    eval 'use POSIX qw(setlocale LC_ALL)';
    $ENV{LC_ALL} = 'C';
}

# due to a bug in VMS's piping which makes it impossible for runperl()
# to emulate echo -n (ie. stdin always winds up with a newline), these 
# tests almost totally fail.
$TODO = "runperl() unable to emulate echo -n due to pipe bug" if $^O eq 'VMS';

my @tmpfiles = ();
END { unlink_all @tmpfiles }

# Tests for -D

like( runperl( switches => [ "-D?" ], stderr => 1,
               prog => 'die' ),
      qr/^Unrecognized switch: -\?  \(-h will show valid options\)\.\n Debugging flag values: \(see also -d\)/,
      "-D? invalid" );
like( runperl( switches => [ "-D''" ], stderr => 1,
               prog => 'die' ),
      qr/\n Debugging flag values: \(see also -d\)\n/m,
      "-D'' valid" );

like( runperl( switches => [ "-Dp" ], stderr => 1,
               prog => '1' ),
      qr/^Starting parse\nEntering state 0/,
      "-Dp Tokenizing and parsing" );
like( runperl( switches => [ "-Ds" ], stderr => 1,
               prog => '1' ),
      qr/=>  SV_YES/,
      "-Ds Stack snapshots (with v, displays all stacks)" );
like( runperl( switches => [ "-Dl" ], stderr => 1,
               prog => '1' ),
      qr/^\(-e:0\)\tENTER scope 2 \(savestack=0\) at op.c:/,
      "-Dl Context (loop) stack processing" );
like( runperl( switches => [ "-Dt" ], stderr => 1,
               prog => '1' ),
      qr/\(-e:0\)\tenter\n\(-e:0\)\tnextstate\n\(-e:\d\)\tleave\n/s,
      "-Dt Trace execution" );
like( runperl( switches => [ "-Do" ], stderr => 1,
               prog => '1' ),
      qr/^\(-e:0\)\tsv_upgrade clearing PL_stashcache\n/m,
      "-Do Method and overloading resolution" );
like( runperl( switches => [ "-Dc" ], stderr => 1,
               prog => '1+20.0' ),
      qr/^0x[0-9a-f]+ iv\(20 => 20\) \(precise\)\n0x[0-9a-f]+ 2iv\(20\)\n/m,
      "-Dc String/numeric conversions" );
like( runperl( switches => [ "-DP" ], stderr => 1,
               prog => '1' ),
      qr/^filter_add func [0-9a-f]+ \(\)\n/,
      "-DP Print profiling info, source file input state" );
like( runperl( switches => [ "-Dm" ], stderr => 1,
               prog => '1' ),
      qr/^0x[0-9a-f]+: \(0\d+\) (new_SV|realloc) /m,
      "-Dm Memory and SV allocation" );
like( runperl( switches => [ "-Df" ], stderr => 1,
               prog => '1' ),
      qr/^\n/,
      "-Df Format processing" );
like( runperl( switches => [ "-Dr" ], stderr => 1,
               prog => '1' ),
      qr/^Enabling \$` \$& \$' support \(0x7\)\.\n/,
      "-Dr Regular expression parsing and execution" );
like( runperl( switches => [ "-Dx" ], stderr => 1,
               prog => '1' ),
      is_miniperl()
        ? qr/\n\d+\s+leave LISTOP\(0x[0-9a-f]+\) ===> \[0x0\]\n/m
        : qr/\n1\s+leave LISTOP\(0x[0-9a-f]+\) ===> \[0x0\]\n/m,
      "-Dx Syntax tree dump" );
like( runperl( switches => [ "-T -Du" ], stderr => 1,
               prog => 'print shift' ),
      qr/\nEXECUTING...\n\n$/,
      "-Du Empty tainting checks" );
my $taint = runperl( switches => [ "-T -Dqu" ], stderr => 1,
                     prog => '$^O=q(xx);' );
if (!$taint && $^O eq 'MSWin32' and $Config{cc} eq 'gcc') {
    ok(1, "#TODO -Dqu Quiet tainting check fails on mingw #323");
} else {
    like($taint,
         qr/assigning to \$\^O /,
         "-Dqu Quiet tainting checks" );
}
#like( runperl( switches => [ "-DH" ], stderr => 1,
#               prog => '1' ),
#      qr/^(HASH\s+)?\d*\s+\d*\s+\d/,
#      "-DH Hash dump -- usurps values()" );
my $perlio = runperl( switches => [ "-DI" ], stderr => 1,
                      prog => '1' );
if ($perlio =~  /^-e:0 Layer 1 is crlf/ && $^O eq 'MSWin32' and $Config{cc} eq 'gcc') {
    ok(1, "-DI PerlIO: Layer 1 is crlf");
} else  {
    like( $perlio,  qr/^-e:0 Layer 1 is perlio/,
        "-DI PerlIO, as previously with env PERLIO_DEBUG");
}
like( runperl( switches => [ "-DX" ], stderr => 1,
               prog => '1' ),
      qr/^Pad 0x[0-9a-f]+\[\d+\] 0x[0-9a-f]+ new:/,
      "-DX Scratchpad allocation" );
like( runperl( switches => [ "-DD" ], stderr => 1,
               prog => '$sv = bless {}, q(Internals);' ),
      qr/\nCleaning object ref:\n/m,
      "-DD Cleaning up" );
like( runperl( switches => [ "-DS -f" ], stderr => 1,
               prog => '1' ),
      qr/^allocating op at [0-9a-f]+, slab [0-9a-f]+, in space \d+ >= \d+ at -e line 1\.\n/,
      "-DS Op slab allocation" );
like( runperl( switches => [ "-DT" ], stderr => 1,
               prog => '1' ),
      qr/^### 0:LEX_NORMAL\/XSTATE "\\n"\n/,
      "-DT Tokenising" );
like( runperl( switches => [ "-DR" ], stderr => 1,
               prog => '1' ),
      qr/^\nEXECUTING...\n\n$/,
      "-DR No reference counts alone" );
like( runperl( switches => [ "-DRx" ], stderr => 1,
               prog => '1' ),
      qr/REFCNT = 1\n/,
      "-DRx Include reference counts of dumped variables" );
like( runperl( switches => [ "-DJ" ], stderr => 1,
               prog => '1' ),
      qr/^\nEXECUTING...\n\n$/,
      "-DJ Do not s,t,P-debug (Jump over) opcodes within package DB" );
like( runperl( switches => [ "-DJP" ], stderr => 1,
               prog => '1' ),
      qr/^filter_add func [0-9a-f]+ \(\)\nfilter_read 0: via function [0-9a-f]+ \(\)\n/,
      "-DJs Do not s,t,P-debug (Jump over) opcodes within package DB" );
like( runperl( switches => [ "-Dv" ], stderr => 1,
               prog => '1' ),
      qr/^\nEXECUTING...\n\n/,
      "-Dv Verbose alone" );
like( runperl( switches => [ "-Dsv" ], stderr => 1,
               prog => '1' ),
      qr/STACK 0: MAIN\n  CX 0: BLOCK  =>/m,
      "-Dsv Verbose: use in conjunction with other flags" );
like( runperl( switches => [ "-DC" ], stderr => 1,
               prog => '1' ),
      qr/\nCopy on write: clear "IO::Handle"\n/,
      "-DC Copy on write" );
like( runperl( switches => [ "-DA" ], stderr => 1,
               prog => '1' ),
      qr/^\nEXECUTING...\n\n$/,
      "-DA Consistency checks on internal structures" );
like( runperl( switches => [ "-Dq" ], stderr => 1,
               prog => '1' ),
      qr/^$/,
      "-Dq quiet" );
like( runperl( switches => [ "-DM" ], stderr => 1,
               prog => '$^O ~~ q(xx);' ),
      qr/Starting smart match resolution\n/,
      "-DM trace smart match resolution" );
like( runperl( switches => [ "-DB" ], stderr => 1,
               prog => '1' ),
      qr/\nSUB strict::import = /m,
      "-DB dump suBroutine definitions, including special Blocks like BEGIN" );
like( runperl( switches => [ "-DL" ], stderr => 1,
               prog => '1' ),
      qr/^\nEXECUTING...\n\n$/,
      "-DL trace locale setting information" );

# Tests for -D with PERLIO_DEBUG

my $filename = tempfile();
unlink $filename if -e $filename;
push @tmpfiles, $filename;
{
      local $ENV{PERLIO_DEBUG} = $filename;
      ok(!-e $filename, 'PERLIO_DEBUG');
      like( runperl( switches => [ "-Dp" ], stderr => 1,
               prog => '1' ),
            qr/^$/,
            "PERLIO_DEBUG empty stderr" );
      ok(-e $filename, "PERLIO_DEBUG into file");
      open my $fh, '<', $filename;
      my $s = <$fh>; $s .= <$fh>;
      like($s,
            qr/^Starting parse\nEntering state 0/,
            "PERLIO_DEBUG write into file only" );
}
