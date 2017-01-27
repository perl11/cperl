#!./perl -w
BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require './test.pl';
    skip_all_if_miniperl();
}

use Config;

my $perlio_log = "perlio$$.txt";

skip_all "DEBUGGING build required"
  unless $::Config{ccflags} =~ /(?<!\S)-DDEBUGGING(?!\S)/
         or $^O eq 'VMS' && $::Config{usedebugging_perl} eq 'Y';

plan tests => 8;

END {
    unlink $perlio_log;
}
{
    unlink $perlio_log;
    local $ENV{PERLIO_DEBUG} = $perlio_log;
    fresh_perl_is("print qq(hello\n)", "hello\n",
                  { stderr => 1 },
                  "No perlio debug output without -DI...");
    # cperl with PERLIO_DEBUG redirects all DEBUGGING output to the outfile
    # perl5 with PERLIO_DEBUG needs -Di and just does perlio debug output
    ok(!-s $perlio_log, "...empty perlio.txt found without -DI");
    unlink $perlio_log;
    # cperl with -DI redirects all DEBUGGING output to the outfile
    # perl5 with -Di just the perlio debug output
    fresh_perl_is("print qq(hello\n)", "hello",
                  { stderr => 1, switches => [ "-DI" ] },
                  "Perlio debug file with both -DI and PERLIO_DEBUG...");
    ok(-e $perlio_log, "... perlio debugging file found with -DI and PERLIO_DEBUG");

    unlink $perlio_log;
    fresh_perl_like("print qq(hello\n)", qr/\nEXECUTING...\n\nhello/,
                  { stderr => 1, switches => [ "-TDI" ] },
                  "Perlio debug output to stderr with -TDI (with PERLIO_DEBUG)...");
    ok(!-e $perlio_log, "...no perlio debugging file found");
}

{
    local $ENV{PERLIO_DEBUG};
    fresh_perl_like("print qq(hello)", qr/PerlIO_pop/,
                    { stderr => 1, switches => [ '-DI' ] },
                   "-DI defaults to stderr");
    fresh_perl_like("print qq(hello)", qr/PerlIO_pop/,
                    { stderr => 1, switches => [ '-TDI' ] },
                   "Perlio debug output to STDERR with -TDI (no PERLIO_DEBUG)");
}

