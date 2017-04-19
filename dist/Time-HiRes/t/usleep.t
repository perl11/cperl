use strict;

BEGIN {
    require Time::HiRes;
    unless(&Time::HiRes::d_usleep) {
	require Test::More;
	Test::More::plan(skip_all => "no usleep()");
    }
}

use Test::More tests => 6;
BEGIN { push @INC, '.' }
use t::Watchdog;

eval { Time::HiRes::usleep(-2) };
like $@, qr/::usleep\(-2\): negative time not invented yet/,
	"negative time error";

# Increase this to 0.60 on CI, overloaded build servers on a VM, or slow machines
my $limit = 0.25; # 25% is acceptable slosh for testing timers

my $one = CORE::time;
Time::HiRes::usleep(10_000);
my $two = CORE::time;
Time::HiRes::usleep(10_000);
my $three = CORE::time;
ok $one == $two || $two == $three
  or diag "slept too long, $one $two $three";

SKIP: {
    skip "no gettimeofday", 1 unless &Time::HiRes::d_gettimeofday;
    my $f = Time::HiRes::time();
    Time::HiRes::usleep(500_000);
    my $f2 = Time::HiRes::time();
    my $d = $f2 - $f;
    ok $d > 0.4 && $d < 0.9 or diag "slept $d secs $f to $f2";
}

SKIP: {
    skip "no gettimeofday", 1 unless &Time::HiRes::d_gettimeofday;
    my $r = [ Time::HiRes::gettimeofday() ];
    Time::HiRes::sleep( 0.5 );
    my $f = Time::HiRes::tv_interval $r;
    my $ok = $f > 0.4 && $f < 0.9 ? 1 : 0;
    if (!$ok and $ENV{TRAVIS_CI}) {
        ok 1, "SKIP flapping test on overly slow Travis CI. slept $f instead of 0.5 secs";
    } else {
        ok $ok or diag "slept $f instead of 0.5 secs.";
    }
}

SKIP: {
    skip "no gettimeofday", 2 unless &Time::HiRes::d_gettimeofday;

    my ($t0, $td);

    my $sleep = 1.5; # seconds
    my $msg;

    $t0 = Time::HiRes::gettimeofday();
    $a = abs(Time::HiRes::sleep($sleep)        / $sleep         - 1.0);
    $td = Time::HiRes::gettimeofday() - $t0;
    my $ratio = 1.0 + $a;

    $msg = "$td went by while sleeping $sleep, ratio $ratio.\n";

    SKIP: {
	skip $msg, 1 unless $td < $sleep * (1 + $limit);
	ok $a < $limit or diag "$msg";
    }

    $t0 = Time::HiRes::gettimeofday();
    $a = abs(Time::HiRes::usleep($sleep * 1E6) / ($sleep * 1E6) - 1.0);
    $td = Time::HiRes::gettimeofday() - $t0;
    $ratio = 1.0 + $a;

    $msg = "$td went by while sleeping $sleep, ratio $ratio.\n";

    SKIP: {
	skip $msg, 1 unless $td < $sleep * (1 + $limit);
	ok $a < $limit or diag "$msg";
    }
}

1;
