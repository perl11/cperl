use strict;
use Cpanel::JSON::XS;
use Test::More;
use Config;
plan skip_all => "Yet unhandled inf/nan with $^O" if $^O eq 'dec_osf';
plan tests => 24;

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

if ($^O eq 'MSWin32'
    and $Config{ccflags} =~ /-D__USE_MINGW_ANSI_STDIO/
    and $Config{uselongdouble})
{
  $have_qnan = 0;
  ($inf, $neg_inf, $nan, $neg_nan) = ('inf','-inf','nan','-nan');
}
if ($^O eq 'MSWin32'
    and $Config{cc} eq 'gcc'
    and $] >= 5.026) # updated strawberry
{
  $have_qnan = 0;
  ($inf, $neg_inf, $nan, $neg_nan) = ('inf','-inf','nan','-nan');
}
# Windows changed it with MSVC 14.0 and the ucrtd.dll runtime
diag "ccversion = $Config{ccversion}" if $^O eq 'MSWin32' and $Config{ccversion};
if ($^O eq 'MSWin32' and $Config{ccversion}) {
  my $mscver = $Config{ccversion}; # "19.00.24215.1" for 14.0 (VC++ 2015)
  $mscver =~ s/^(\d+\.\d\+).(\d+)\.(\d+)/$1$2$3/;
  if ($mscver >= 19.0) {
    $have_qnan = 0;
    ($inf, $neg_inf, $nan, $neg_nan) = ('inf','-inf','nan','-nan(ind)');
  }
}
# newlib and glibc 2.5 have no -nan support, just nan. The BSD's neither, but they might
# come up with it lateron, as darwin did.
#if ($^O eq 'cygwin' or ($Config{glibc_version} && $Config{glibc_version} < 2.6)) {
#  $neg_nan = $nan;
#}

my $r = $json->encode([9**9**9]);
$r =~ s/\.0$// if $^O eq 'MSWin32';
is $r,         "[\"$inf\"]",  "inf -> \"inf\" stringify_infnan(1)";
$r = $json->encode([-9**9**9]);
$r =~ s/\.0$// if $^O eq 'MSWin32';
is $r,        "[\"$neg_inf\"]", "-inf -> \"-inf\"";
# The concept of negative nan is not portable and varies too much.
# Windows even emits neg_nan for the first test sometimes. HP-UX has all tests reverse.
like $json->encode([-sin(9**9**9)]),   qr/\[\"(\Q$neg_nan\E|\Q$nan\E)\"\]/,  "nan -> \"nan\"";
like $json->encode([sin(9**9**9)]),    qr/\[\"(\Q$neg_nan\E|\Q$nan\E)\"\]/, "-nan -> \"-nan\"";
like $json->encode([9**9**9/9**9**9]), qr/\[\"(\Q$neg_nan\E|\Q$nan\E)\"\]/, "-nan -> \"-nan\"";

# infnan_mode = 2: # inf/nan values, as in JSON::XS and older releases.
$json = Cpanel::JSON::XS->new->stringify_infnan(2);
is $json->encode([9**9**9]),         "[$inf]",  "inf stringify_infnan(2)";
is $json->encode([-9**9**9]),        "[$neg_inf]", "-inf";
like $json->encode([-sin(9**9**9)]),   qr/\[(\Q$neg_nan\E|\Q$nan\E)\]/,  "nan";
like $json->encode([sin(9**9**9)]),    qr/\[(\Q$neg_nan\E|\Q$nan\E)\]/, "-nan";
like $json->encode([9**9**9/9**9**9]), qr/\[(\Q$neg_nan\E|\Q$nan\E)\]/, "-nan";

# infnan_mode = 3: # inf/nan values unified to inf/-inf/nan strings. no qnan/snan/negative nan
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
