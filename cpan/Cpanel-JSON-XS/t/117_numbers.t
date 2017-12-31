use strict;
use Cpanel::JSON::XS;
use Test::More;
use Config;
plan skip_all => "Yet unhandled inf/nan with $^O" if $^O eq 'dec_osf';
plan tests => 25;

# infnan_mode = 0:
is encode_json([9**9**9]),         '[null]', "inf -> null stringify_infnan(0)";
is encode_json([-sin(9**9**9)]),   '[null]', "nan -> null";
is encode_json([-9**9**9]),        '[null]', "-inf -> null";
is encode_json([sin(9**9**9)]),    '[null]', "-nan -> null";
is encode_json([9**9**9/9**9**9]), '[null]', "-nan -> null";

# infnan_mode = 1: # platform specific strings
my $json = Cpanel::JSON::XS->new->stringify_infnan;
my $have_qnan = ($^O eq 'MSWin32' || $^O eq 'aix') ? 1 : 0;
# TODO dec_osf
# variants as in t/op/infnan.t
my (@inf, @neg_inf, @nan, @neg_nan);
my ($inf, $nan) =
  ($^O eq 'MSWin32') ? ('1.#INF','1.#QNAN') :
  ($^O eq 'solaris') ? ('Infinity','NaN') :
  ($^O eq 'aix')     ? ('inf','NANQ') :
  ($^O eq 'hpux')    ? ('++','-?') :
                       ('inf','nan');
my $neg_nan =
  ($^O eq 'MSWin32') ? "-1.#IND" :
  ($^O eq 'hpux')    ? "?" :
                       "-".$nan;
my $neg_inf =
  ($^O eq 'hpux') ? "---" :
                    "-".$inf;

if ($^O eq 'MSWin32' and $Config{ccflags} =~ /-D__USE_MINGW_ANSI_STDIO/) {
  $have_qnan = 0;
  ($inf, $neg_inf, $nan, $neg_nan) = ('inf','-inf','nan','-nan');
  @inf     = ($inf);
  @neg_inf = ($neg_inf);
  @nan     = ($nan);
  @neg_nan = ($neg_nan);
}
elsif ($^O eq 'MSWin32') { # new ucrtd.dll
  ($inf, $neg_inf, $nan, $neg_nan) = ('inf','-inf','nan','-nan');
  @inf     = ('1.#INF', 'inf');
  @neg_inf = ('-1.#INF', '-inf');
  @nan     = ('1.#QNAN', 'nan');
  @neg_nan = ('-1.#IND', '-nan', '-nan(ind)');
} else {
  @inf     = ($inf);
  @neg_inf = ($neg_inf);
  @nan     = ($nan);
  @neg_nan = ($neg_nan);
}
# newlib and glibc 2.5 have no -nan support, just nan. The BSD's neither, but they might
# come up with it lateron, as darwin did.
#if ($^O eq 'cygwin' or ($Config{glibc_version} && $Config{glibc_version} < 2.6)) {
#  $neg_nan = $nan;
#}

sub match {
  my ($r, $tmpl, $desc, @list) = @_;
  my $match = shift @list;
  my $m = $tmpl;
  $m =~ s/__XX__/$match/;
  $match = $m;
  for my $m1 (@list) { # at least one must match
    $m = $tmpl;
    $m =~ s/__XX__/$m1/;
    diag "try $m eq $r" if $ENV{TEST_VERBOSE};
    $match = $m if $r eq $m;
  }
  is $r, $match, $desc;
}

my $r = $json->encode([9**9**9]);
$r =~ s/\.0$// if $^O eq 'MSWin32';
match($r, "[\"__XX__\"]", "inf -> \"inf\" stringify_infnan(1)", @inf);

$r = $json->encode([-9**9**9]);
$r =~ s/\.0$// if $^O eq 'MSWin32';
match($r, "[\"__XX__\"]", "-inf -> \"-inf\"", @neg_inf);

# The concept of negative nan is not portable and varies too much.
# Windows even emits neg_nan for the first test sometimes. HP-UX has all tests reverse.
match($json->encode([-sin(9**9**9)]),   "[\"__XX__\"]", "nan -> \"nan\"", @nan, @neg_nan);
match($json->encode([sin(9**9**9)]),    "[\"__XX__\"]", "-nan -> \"-nan\"", @nan, @neg_nan);
match($json->encode([9**9**9/9**9**9]), "[\"__XX__\"]", "-nan -> \"-nan\"", @nan, @neg_nan);

# infnan_mode = 2: # inf/nan values, as in JSON::XS and older releases.
$json = Cpanel::JSON::XS->new->stringify_infnan(2);
match($json->encode([9**9**9]), "[__XX__]", "inf stringify_infnan(2)", @inf);
match($json->encode([-9**9**9]), "[__XX__]", "-inf", @neg_inf);
match($json->encode([-sin(9**9**9)]),   "[__XX__]", "nan", @nan, @neg_nan);
match($json->encode([sin(9**9**9)]),    "[__XX__]", "-nan", @nan, @neg_nan);
match($json->encode([9**9**9/9**9**9]), "[__XX__]", "-nan", @nan, @neg_nan);

# infnan_mode = 3:
# inf/nan values unified to inf/-inf/nan strings. no qnan/snan/negative nan
$json = Cpanel::JSON::XS->new->stringify_infnan(3);
is $json->encode([9**9**9]),         '["inf"]',  "inf stringify_infnan(3)";
is $json->encode([-9**9**9]),        '["-inf"]', "-inf";
is $json->encode([-sin(9**9**9)]),   '["nan"]',  "nan";
is $json->encode([9**9**9/9**9**9]), '["nan"]', "nan or -nan";
is $json->encode([sin(9**9**9)]),    '["nan"]', "nan or -nan";

my $num = 3;
my $str = "$num";
is encode_json({test => [$num, $str]}), '{"test":[3,"3"]}', 'int dualvar';

$num = 3.21;
$str = "$num";
is encode_json({test => [$num, $str]}), '{"test":[3.21,"3.21"]}', 'numeric dualvar';

$str = '0 but true';
$num = 1 + $str;
# 5.6 is broken, converts $num (IV+PV) to pure NV
my $resnum = ($] < 5.007) ? '1.0' : '1';
is encode_json({test => [$num, $str]}), qq|{"test":[$resnum,"0 but true"]}|,
  'int/string dualvar';

$str = 'bar';
{ no warnings "numeric"; $num = 23 + $str }
# 5.6 and >5.10 is also arguably broken:
# converts $num (IV+PV) to pure NOK+POK, not IOK+POK.
$resnum = ($] > 5.007 && $] <= 5.010) ? '23' : '23.0';
is encode_json({test => [$num, $str]}), qq|{"test":[$resnum,"bar"]}|,
  'int/string dualvar';

{
  use POSIX qw(setlocale);
  setlocale(&POSIX::LC_ALL, "fr_FR.utf-8");
  is encode_json({"invalid" => 123.45}), qq|{"invalid":123.45}|,
    "numeric radix";
}
