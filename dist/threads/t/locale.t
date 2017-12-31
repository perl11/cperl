use strict;
use warnings;

# test [perl #127708] locale race
BEGIN {
    use Config;
    if (! $Config{'useithreads'}) {
        print("1..0 # SKIP Perl not compiled with 'useithreads'\n");
        exit(0);
    }
    if ($^O !~ /^(darwin|cygwin)$/) {
        print("1..0 # SKIP #127708 locale race only observed on darwin and cygwin\n");
        exit(0);
    }
    if ($ENV{PERL_SKIP_LOCALE_INIT}) {
        print("1..0 # SKIP #127708 locale race skipped with env PERL_SKIP_LOCALE_INIT\n");
        exit(0);
    }
    require POSIX;
    if (POSIX::setlocale(&POSIX::LC_MESSAGES) eq 'C') {
        print("1..0 # SKIP #127708 locale race not with the C locale\n");
        exit(0);
    }
}

use threads;
use Test::More;

my @threads = map +threads->create(sub {
    sleep 0.1;

    for (1..5_000) {
        eval "1("; # my_strerror sets locale of LC_MESSAGES to C
        is(1, 1);
    }
}), (0..1);

$_->join for splice @threads;
done_testing;
