#!./perl

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require "./test.pl";
}

use coretypes;
plan 37;

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

my $args = { switches => ['-w', '-Mtypes=strict'] };
my $err = qr/Type of scalar assignment to [@%]a must be Int \(not Str\)/;
fresh_perl_like(<<'EOF', $err, $args, 'ck_sassign aelem strict');
my Int @a;
$a[0] = "";
EOF

fresh_perl_like(<<'EOF', $err, $args, 'ck_sassign helem strict');
my Int %a;
$a{"key"} = "";
EOF

$err = qr/Type of list assignment to [@%]a must be Int \(not Str\)/;
fresh_perl_like(<<'EOF', $err, $args, 'ck_aassign array strict');
my Int @a; my Str @b;
@a = @b;
EOF

fresh_perl_like(<<'EOF', $err, $args, 'ck_aassign hash strict');
my Int %a; my Str %b;
%a = %b;
EOF

# Warn on coretypes casts
$args = { switches => ['-w'] };
$err = qr/Type of scalar assignment to [@%]a must be Int \(not Str\)/;
fresh_perl_like(<<'EOF', $err, $args, 'ck_sassign aelem Int = Str');
my Int @a;
$a[0] = "";
EOF

fresh_perl_like(<<'EOF', $err, $args, 'ck_sassign helem Int = Str');
my Int %a;
$a{"key"} = "";
EOF

$err = qr/Type of list assignment to [@%]a must be Int \(not Str\)/;
fresh_perl_like(<<'EOF', $err, $args, 'ck_aassign array Int = Str');
my Int @a; my Str @b;
@a = @b;
EOF

fresh_perl_like(<<'EOF', $err, $args, 'ck_aassign hash Int = Str');
my Int %a; my Str %b;
%a = %b;
EOF

$err = qr/Type of scalar assignment to \@a must be Int \(not Bla\)/;
fresh_perl_like(<<'EOF', $err, $args, 'warn with user-type to coretype');
package Bla;
my Bla $b;
my Int @a;
$a[0] = $b;
EOF

# Bla can dynamically inherit from Str.
# Basically @Bla::ISA = qw(Str);
# With a class this would be forbidden.
fresh_perl_is(<<'EOF', '', $args, 'allow coretype to user-type');
package Bla;
my Bla %a;
$a{"key"} = "";
EOF

$args = { switches => ['-w', '-Mtypes=strict'] };
fresh_perl_is(<<'EOF', '', $args, 'even strict coretype to user-type');
package Bla;
my Bla %a;
$a{"key"} = "";
EOF

fresh_perl_is(<<'EOF', '', $args, 'scalar = implicit shift list. #258');
(my int $arg) = @_;
EOF

$err = qr/Type of list assignment to \$arg must be int \(not Bla\)/;
fresh_perl_like(<<'EOF', $err, $args, 'scalar = typed array');
package Bla;
my Bla @a;
(my int $arg) = @a;
EOF

$err = qr/Type of scalar assignment to \$arg must be int \(not Bla\)/;
fresh_perl_like(<<'EOF', $err, $args, 'scalar = typed aelem');
package Bla;
my Bla @a;
my int $arg = $a[0];
EOF
fresh_perl_like(<<'EOF', $err, $args, 'scalar = shift typed array');
package Bla;
my Bla @a;
my int $arg = shift @a;
EOF

# Need type cast or dynamic inheritence from Bla to int
fresh_perl_like(<<'EOF', $err, $args, 'scalar = typed hash');
package Bla;
my Bla %a;
my int $arg = $a{1};
EOF

TODO: {
  local $::TODO = 'mderef';
  # should warn, but does not.
  fresh_perl_like(<<'EOF', $err, $args, 'scalar = typed mderef hash');
package Bla;
my int %a;
my Bla $arg = $a{1};
EOF
}

$args = { switches => ['-Mtypes=strict'] };
fresh_perl_is(<<'EOF', '', $args, 'scalar = helem');
my str $arg = $h{1};
EOF

# A normal dynamic class, inheriting from a restricted coreclass
# bug #250: Attempt to access disallowed key 'DESTROY' in the restricted hash '%Int::'
{
  @MyInt::ISA = ('Int');
  my $j = 1;
  my MyInt $i = bless \$j, "MyInt";
  sub dummy($x) { ok(1, "MyInt=>int arg") }
  dummy($i);
}
