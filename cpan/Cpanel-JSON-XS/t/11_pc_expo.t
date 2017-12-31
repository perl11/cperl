# copied over from JSON::XS and modified to use Cpanel::JSON::XS

use Test::More;
use strict;
BEGIN { plan tests => 8 };
use Cpanel::JSON::XS;
use Config ();

#########################
my ($js,$obj);
my $pc = new Cpanel::JSON::XS;

$js  = q|[-12.34]|;
$obj = $pc->decode($js);
is($obj->[0], -12.34, 'digit -12.34');
$js = $pc->encode($obj);
is($js,'[-12.34]', 'digit -12.34');

$js  = q|[-1.234e5]|;
$obj = $pc->decode($js);
is($obj->[0], -123400, 'digit -1.234e5');
$js = $pc->encode($obj);
is($js,'[-123400.0]', 'digit -1.234e5');

$js  = q|[1.23E-4]|;
$obj = $pc->decode($js);
is($obj->[0], 0.000123, 'digit 1.23E-4');
$js = $pc->encode($obj);
if ($] < 5.007 and $Config::Config{d_Gconvert} =~ /^g/ and $js ne '[0.000123]') {
   is($js,'[1.23e-04]', 'digit 1.23e-4 v5.6');
} else {
   is($js,'[0.000123]', 'digit 1.23E-4');
}

$js  = q|[1.01e+30]|;
$obj = $pc->decode($js);
is($obj->[0], 1.01e+30, 'digit 1.01e+30');
$js = $pc->encode($obj);
if ($Config::Config{usequadmath}) {
   is($js,'[1010000000000000000000000000000.0]', 'digit 1010000000000000000000000000000.0 (quadmath)');
} elsif ($Config::Config{uselongdouble} && $Config::Config{ptrsize} > 4) {
   like($js, qr/^\[(1010000000000000000000000000000\.0|1.01[Ee]\+0?30)\]/,
      'digit (64bit ld)'); # esp. non-intel
} else {
   like($js,qr/\[1.01[Ee]\+0?30\]/, 'digit 1.01e+30');
}
