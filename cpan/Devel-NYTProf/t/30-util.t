use Test::More tests => 28;

use Devel::NYTProf::Util qw(
    fmt_time fmt_incl_excl_time
    html_safe_filename
    trace_level
);

my $us = "µs";

is(fmt_time(0), "0s");

is(fmt_time(1.1253e-10), "0ns");
is(fmt_time(1.1253e-9), "1ns");
is(fmt_time(1.1253e-8), "11ns");
is(fmt_time(1.1253e-7), "113ns");
is(fmt_time(1.1253e-6), "1$us");
is(fmt_time(1.1253e-5), "11$us");
is(fmt_time(1.1253e-4), "113$us");
is(fmt_time(1.1253e-3), "1.13ms");
is(fmt_time(1.1253e-2), "11.3ms");
is(fmt_time(1.1253e-1), "113ms");
is(fmt_time(1.1253e-0), "1.13s");
is(fmt_time(1.1253e+1), "11.3s");
is(fmt_time(1.1253e+2), "113s");
is(fmt_time(1.1253e+3), "1125s");

is(fmt_incl_excl_time(3, 3), "3.00s");
is(fmt_incl_excl_time(3, 2), "3.00s (2.00+1.00)");
is(fmt_incl_excl_time(3, 2.997), "3.00s (3.00+3.00ms)");
is(fmt_incl_excl_time(0.1, 0.0997), "100ms (99.7+300$us)");
is(fmt_incl_excl_time(4e-5, 1e-5), "40$us (10+30)");

is html_safe_filename('/foo/bar'), 'foo-bar';
is html_safe_filename('\foo\bar'), 'foo-bar';
is html_safe_filename('\foo/bar'), 'foo-bar';
is html_safe_filename('C:foo'), 'C-foo';
is html_safe_filename('C:\foo'), 'C-foo';
is html_safe_filename('<lots>of|\'really\'special*"chars"?'), 'lots-of-really-special-chars';
is html_safe_filename('no.dots.please'), 'no-dots-please';

my $trace_level = (($ENV{NYTPROF}||'') =~ m/\b trace=(\d+) /x) ? $1 : 0;
is trace_level(), $trace_level, "trace_level $trace_level";
