use strict;

BEGIN {
    require Time::HiRes;
    unless(&Time::HiRes::d_nanosleep) {
	require Test::More;
	Test::More::plan(skip_all => "no nanosleep()");
    }
}

use Test::More tests => 3;
BEGIN { push @INC, '.' }
use t::Watchdog;
use Config;

eval { Time::HiRes::nanosleep(-5) };
like $@, qr/::nanosleep\(-5\): negative time not invented yet/,
	"negative time error";

my $one = CORE::time;
Time::HiRes::nanosleep(10_000_000);
my $two = CORE::time;
Time::HiRes::nanosleep(10_000_000);
my $three = CORE::time;
ok ($one == $two || $two == $three, "nanosleep not measurable")
    or diag "slept too long, $one $two $three";

SKIP: {
    skip "no gettimeofday", 1 unless &Time::HiRes::d_gettimeofday;
    my $f = Time::HiRes::time();
    Time::HiRes::nanosleep(500_000_000);
    my $f2 = Time::HiRes::time();
    my $d = $f2 - $f;
    # skip fail on overly slow or loaded smokers. 0.5 => 3 secs
    if ($ENV{TRAVIS} and $Config::Config{ccflags} =~ /DEBUGGING/
        and !($d > 0.4 && $d < 0.9))
    {
      ok(1, "skip nanosleep test on overly slow smoker. slept $d secs, not 0.5 secs");
    } else {
      ok ($d > 0.4 && $d < 0.9, "slept $d secs of 0.5 secs") or diag "slept $d secs $f to $f2";
   }
}

1;
