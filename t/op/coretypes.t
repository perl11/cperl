#!./perl

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require "./test.pl";
}

use coretypes;
plan 22;

# native or coretypes. the result should be the same
my int $x = 4;
my int $y = 5;
my int $z;

$z = $x + $y;
is($z, 9, "i_add");

$z = $x - $y;
is($z, -1, "i_subtract");

$z = $x * $y;
is($z, 20, "i_multiply");

is($x / $y, 0.8, "divide (special case)");
is(4 / 5, 0.8, "divide (special case)");
$z = 4 / 5; # but z is int type, so use i_divide
ok($z == 0, "i_divide (result must be int, cheating using i_eq)");

$z = $x % $y;
is($z, 4, "i_modulo");

SKIP: {
    use integer;
    use Config;
    my $ivsize = $Config{ivsize};
    skip "ivsize == $ivsize", 4 unless $ivsize == 4 || $ivsize == 8;

    my int $null = 0;
    is(~$null, -1, "signed i_complement");
    my uint $unull = 0;
    my uint $z2;

    if ($ivsize == 4) {
	$z = 2**31 - 1;
	is($z + 1, -2147483648, "left shift (use integer)");
        {
            no integer;
            is(++$z, 2147483648, "i_preinc");
            is(~$unull, 4294967295, "unsigned i_complement");
        }
    } elsif ($ivsize == 8) {
	$z = 2**63 - 1;
	is($z + 1, -9223372036854775808, "left shift (use integer)");
        {
            no integer;
            is(++$z, 9223372036854775808, "i_preinc");
            is(~$unull, 18446744073709551615, "unsigned i_complement");
        }
    }
}

my num $a = 4.2;
my num $b = 5.1;
my num $c;

$c = $a + $b;
is($c, 9.3, "num_add");

sub EPS () {0.00001}
$c = $b - $a;
ok($c >= 0.9-EPS && $c <= 0.9+EPS, "num_subtract");

$c = $a * $b;
is($c, 21.42, "num_multiply");

$c = $a / $b;
is($c, 4.2/5.1, "num_divide");

$c = atan2 $a, $b;
ok($c >= 0.688924388214861-EPS && $c <= 0.688924388214861+EPS, "num_atan2");
$c = sin $a;
ok($c >= -0.871575772413588-EPS && $c <= -0.871575772413588+EPS, "num_sin");
$c = log $a;
ok($c >= 1.43508452528932-EPS && $c <= 1.43508452528932+EPS, "num_log");

my $args = { switches => ['-w'] };
my $err = qr/Type of scalar assignment to [@%]a must be Int \(not Str\)/;
fresh_perl_like(<<'EOF', $err, $args, 'ck_sassign aelem');
my Int @a;
$a[0] = "";
EOF

fresh_perl_like(<<'EOF', $err, $args, 'ck_sassign helem');
my Int %a;
$a{"key"} = "";
EOF

$err = qr/Type of list assignment to [@%]a must be Int \(not Str\)/;
fresh_perl_like(<<'EOF', $err, $args, 'ck_aassign array');
my Int @a; my Str @b;
@a = @b;
EOF

fresh_perl_like(<<'EOF', $err, $args, 'ck_aassign hash');
my Int %a; my Str %b;
%a = %b;
EOF
