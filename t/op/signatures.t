#!perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

our $a = 123;
our $z;

sub t000 ($a) { $a || "z" }
is prototype(\&t000), '($a)', '($a) signature';
is $a, 123;

my $dummy1; # Deparse currently messes up pragmata just before sub def

sub t001 { $a || "z" }
is prototype(\&t001), undef;
is eval("t001()"), 123;
is eval("t001(456)"), 123;
is eval("t001(456, 789)"), 123;
is $a, 123;

sub t002 () { $a || "z" }
is prototype(\&t002), '';
is eval("t002()"), 123;
is eval("t002(456)"), undef;
like $@, qr/Too many arguments for subroutine entry t002 at \(eval \d+\) line 1/;
is eval("t002(456, 789)"), undef;
like $@, qr/Too many arguments for subroutine entry t002 at \(eval \d+\) line 1/;
is $a, 123;

sub t003 ( ) { $a || "z" }
is prototype(\&t003), ' ', '( ) sig';
is eval("t003()"), 123;
is eval("t003(456)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t003 at \(eval \d+\) line 1/;
is eval("t003(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t003 at \(eval \d+\) line 1/;
is $a, 123;

sub t006 ($a) { $a || "z" }
is prototype(\&t006), '($a)', '($a) sig';
is eval("t006()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t006. Missing \$a at \(eval \d+\) line 1/;
is eval("t006(0)"), "z";
is eval("t006(456)"), 456;
is eval("t006(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t006 exceeding max 1 args at \(eval \d+\) line 1, near/;
is eval("t006(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t006 exceeding max 1 args at \(eval \d+\) line 1, near/;
is $a, 123;

sub t007 ($a, $b) { $a.$b }
is prototype(\&t007), '($a, $b)';
is eval("t007()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t007. Missing \$a at \(eval \d+\) line 1/;
is eval("t007(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t007. Missing \$b at \(eval \d+\) line 1/;
is eval("t007(456, 789)"), "456789";
is eval("t007(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t007 exceeding max 2 args at \(eval \d+\) line 1, near/;
is eval("t007(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t007 exceeding max 2 args at \(eval \d+\) line 1, near/;
is $a, 123;

sub t008 ($a, $b, $c) { $a.$b.$c }
is prototype(\&t008), '($a, $b, $c)';
is eval("t008()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d+. Missing \$a at \(eval \d+\) line 1/;
is eval("t008(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d+. Missing \$b at \(eval \d+\) line 1/;
is eval("t008(456, 789)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d+. Missing \$c at \(eval \d+\) line 1/;
is eval("t008(456, 789, 987)"), "456789987";
is eval("t008(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t008 exceeding max 3 args at \(eval \d+\) line 1, near/;
is $a, 123;

sub t009 ($abc, $def) { $abc.$def }
is prototype(\&t009), '($abc, $def)';
is eval("t009()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t009\. Missing \$abc/;
is eval("t009(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t009\. Missing \$def/;
is eval("t009(456, 789)"), "456789";
is eval("t009(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d+ exceeding max 2 args at \(eval \d+\) line 1, near/;
is eval("t009(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d+ exceeding max 2 args at \(eval \d+\) line 1, near/;
is $a, 123;

sub t010 ($a, $) { $a || "z" }
is prototype(\&t010), '($a, $)', '($a, $) sig';
is eval("t010()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t010/;
is eval("t010(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t010/;
is eval("t010(0, 789)"), "z";
is eval("t010(456, 789)"), 456;
is eval("t010(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t010/;
is eval("t010(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t010/;
is $a, 123;

sub t011 ($, $a) { $a || "z" }
is prototype(\&t011), '($, $a)';
is eval("t011()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t011/;
is eval("t011(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t011/;
is eval("t011(456, 0)"), "z";
is eval("t011(456, 789)"), 789;
is eval("t011(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t011/;
is eval("t011(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t011/;
is $a, 123;

sub t012 ($, $) { $a || "z" }
is prototype(\&t012), '($, $)';
is eval("t012()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t012/;
is eval("t012(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t012/;
is eval("t012(0, 789)"), 123;
is eval("t012(456, 789)"), 123;
is eval("t012(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t012/;
is eval("t012(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t012/;
is $a, 123;

sub t013 ($) { $a || "z" }
is prototype(\&t013), '$';
is eval("t013()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t013 at \(eval \d+\) line 1/;
is eval("t013(0)"), 123;
is eval("t013(456)"), 123;
is eval("t013(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t013 at \(eval \d+\) line 1/;
is eval("t013(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t013 at \(eval \d+\) line 1/;
is eval("t013(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t013 at \(eval \d+\) line 1/;
is $a, 123;

sub t014 ($a = 222) { $a // "z" }
#is prototype(\&t014), undef;
is eval("t014()"), 222;
is eval("t014(0)"), 0;
is eval("t014(undef)"), "z";
is eval("t014(456)"), 456;
is eval("t014(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t014/;
is eval("t014(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t014/;
is $a, 123;

sub t015 ($a = undef) { $a // "z" }
is prototype(\&t015), '($a?)';
is eval("t015()"), "z";
is eval("t015(0)"), 0;
is eval("t015(undef)"), "z";
is eval("t015(456)"), 456;
is eval("t015(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t015/;
is eval("t015(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t015/;
is $a, 123;

sub t016 ($a = do { $z++; 222 }) { $a // "z" }
$z = 0;
is prototype(\&t016), '($a=<expr>)';
is eval("t016()"), 222;
is $z, 1;
is eval("t016(0)"), 0;
is eval("t016(undef)"), "z";
is eval("t016(456)"), 456;
is eval("t016(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t016/;
is eval("t016(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t016/;
is $z, 1;
is eval("t016()"), 222;
is $z, 2;
is $a, 123;

sub t018 { join("/", @_) }
sub t017 ($p = t018 222, $a = 333) { $p // "z" }
is prototype(\&t017), '($p=<expr>)'; #t018 binds all
is eval("t017()"), "222/333";
is $a, 333;
$a = 123;
is eval("t017(0)"), 0;
is eval("t017(undef)"), "z";
is eval("t017(456)"), 456;
is eval("t017(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t017/;
is eval("t017(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t017/;
is $a, 123;

sub t019 ($p = 222, $a = 333) { "$p/$a" }
is prototype(\&t019), '($p=222, $a=333)';
is eval("t019()"), "222/333";
is eval("t019(0)"), "0/333";
is eval("t019(456)"), "456/333";
is eval("t019(456, 789)"), "456/789";
is eval("t019(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t019/;
is $a, 123;

sub t020 :prototype($) { $_[0]."z" }
sub t021 ($p = t020 222, $a = 333) { "$p/$a" }
is prototype(\&t021), '($p=<expr>, $a=333)';
is eval("t021()"), "222z/333";
is eval("t021(0)"), "0/333";
is eval("t021(456)"), "456/333";
is eval("t021(456, 789)"), "456/789";
is eval("t021(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t021/;
is $a, 123;

sub t022 ($p = do { $z += 10; 222 }, $a = do { $z++; 333 }) { "$p/$a" }
$z = 0;
is prototype(\&t022), '($p=<expr>, $a=<expr>)';
is eval("t022()"), "222/333";
is $z, 11;
is eval("t022(0)"), "0/333";
is $z, 12;
is eval("t022(456)"), "456/333";
is $z, 13;
is eval("t022(456, 789)"), "456/789";
is eval("t022(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t022/;
is $z, 13;
is $a, 123;

sub t023 ($a = sub { $_[0]."z" }) { $a->("a")."y" }
is prototype(\&t023), '($a=<expr>)';
is eval("t023()"), "azy";
is eval("t023(sub { \"x\".\$_[0].\"x\" })"), "xaxy";
is eval("t023(sub { \"x\".\$_[0].\"x\" }, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t023/;
is $a, 123;

sub t036 ($a = $a."x") { $a."y" }
is prototype(\&t036), '($a=<expr>)';
is eval("t036()"), "123xy";
is eval("t036(0)"), "0y";
is eval("t036(456)"), "456y";
is eval("t036(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t036/;
is $a, 123;

sub t120 ($a = $_) { $a // "z" }
is prototype(\&t120), '($a=$_)';
$_ = "___";
is eval("t120()"), "___";
$_ = "___";
is eval("t120(undef)"), "z";
$_ = "___";
is eval("t120(0)"), 0;
$_ = "___";
is eval("t120(456)"), 456;
$_ = "___";
is eval("t120(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t120/;
is $a, 123;

sub t121 ($a = caller) { $a // "z" }
is prototype(\&t121), '($a=<expr>)';
is eval("t121()"), "main";
is eval("t121(undef)"), "z";
is eval("t121(0)"), 0;
is eval("t121(456)"), 456;
is eval("t121(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t121/;
is eval("package T121::Z; ::t121()"), "T121::Z";
is eval("package T121::Z; ::t121(undef)"), "z";
is eval("package T121::Z; ::t121(0)"), 0;
is eval("package T121::Z; ::t121(456)"), 456;
is eval("package T121::Z; ::t121(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t121/;
is $a, 123;

sub t129 ($a = return 222) { $a."x" }
is prototype(\&t129), '($a=<expr>)';
is eval("t129()"), "222";
is eval("t129(0)"), "0x";
is eval("t129(456)"), "456x";
is eval("t129(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t129/;
is $a, 123;

use feature "current_sub";
my $dummy2; # Deparse currently messes up pragmata just before sub def

sub t122 ($c = 5, $r = $c > 0 ? __SUB__->($c - 1) : "") { $c.$r }
is prototype(\&t122), '($c=5, $r=<expr>)';
is eval("t122()"), "543210";
is eval("t122(0)"), "0";
is eval("t122(1)"), "10";
is eval("t122(5)"), "543210";
is eval("t122(5, 789)"), "5789";
is eval("t122(5, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t122/;
is $a, 123;

sub t123 ($list = wantarray) { $list ? "list" : "scalar" }
is prototype(\&t123), '($list=<expr>)';
is eval("scalar(t123())"), "scalar";
is eval("(t123())[0]"), "list";
is eval("scalar(t123(0))"), "scalar";
is eval("(t123(0))[0]"), "scalar";
is eval("scalar(t123(1))"), "list";
is eval("(t123(1))[0]"), "list";
is eval("t123(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t123/;
is $a, 123;

sub t124 ($b = (local $a = $a + 1)) { "$a/$b" }
is prototype(\&t124), '($b=<expr>)';
is eval("t124()"), "124/124";
is $a, 123;
is eval("t124(456)"), "123/456";
is $a, 123;
is eval("t124(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t124/;
is $a, 123;

sub t125 ($c = (our $t125_counter)++) { $c }
is prototype(\&t125), '($c=<expr>)';
is eval("t125()"), 0;
is eval("t125()"), 1;
is eval("t125()"), 2;
is eval("t125(456)"), 456;
is eval("t125(789)"), 789;
is eval("t125()"), 3;
is eval("t125()"), 4;
is eval("t125(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t125/;
is $a, 123;

use feature "state";
my $dummy3; # Deparse currently messes up pragmata just before sub def

sub t126 ($c = (state $s = $z++)) { $c }
is prototype(\&t126), '($c=<expr>)';
$z = 222;
is eval("t126(456)"), 456;
is $z, 222;
is eval("t126()"), 222;
is $z, 223;
is eval("t126(456)"), 456;
is $z, 223;
is eval("t126()"), 222;
is $z, 223;
is eval("t126(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t126/;
is $z, 223;
is $a, 123;

sub t127 ($c = do { state $s = $z++; $s++ }) { $c }
is prototype(\&t127), '($c=<expr>)';
$z = 222;
is eval("t127(456)"), 456;
is $z, 222;
is eval("t127()"), 222;
is $z, 223;
is eval("t127()"), 223;
is eval("t127()"), 224;
is $z, 223;
is eval("t127(456)"), 456;
is eval("t127(789)"), 789;
is eval("t127()"), 225;
is eval("t127()"), 226;
is eval("t127(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t127/;
is $z, 223;
is $a, 123;

sub t037 ($a = 222, $b = $a."x") { "$a/$b" }
is prototype(\&t037), '($a=222, $b=<expr>)';
is eval("t037()"), "222/222x";
is eval("t037(0)"), "0/0x";
is eval("t037(456)"), "456/456x";
is eval("t037(456, 789)"), "456/789";
is eval("t037(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t037/;
is $a, 123;

sub t128 ($a = 222, $b = ($a = 333)) { "$a/$b" }
is prototype(\&t128), '($a=222, $b=<expr>)';
is eval("t128()"), "333/333";
is eval("t128(0)"), "333/333";
is eval("t128(456)"), "333/333";
is eval("t128(456, 789)"), "456/789";
is eval("t128(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t128/;
is $a, 123;

# XXX cperl
#sub t130 { join(",", @_).";".scalar(@_) }
#sub t131 ($a = 222, $b = goto &t130) { "$a/$b" } # cperl bug
#is prototype(\&t131), '$a=222, $b=<expr>';
#is eval("t131()"), ";0";
#is eval("t131(0)"), "0;1";
#is eval("t131(456)"), "456;1";
#is eval("t131(456, 789)"), "456/789";
#is eval("t131(456, 789, 987)"), undef;
#like $@, qr/\AToo many arguments for subroutine entry t131/;
#is $a, 123;

eval "#line 8 foo\n".'sub t024 ($a =) { }';
is $@, "Optional parameter lacks default expression at foo line 8\.\n";
eval "#line 8 foo\n".'sub t024 (\$a =) { }';
like $@, qr/^Reference parameter cannot take default value at foo line 8\.\n/;

sub t025 ($ = undef) { $a // "z" }
is prototype(\&t025), '($?)';
is eval("t025()"), 123;
is eval("t025(0)"), 123;
is eval("t025(456)"), 123;
is eval("t025(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t025/;
is eval("t025(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t025/;
is eval("t025(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t025/;
is $a, 123;

sub t026 ($ = 222) { $a // "z" }
is prototype(\&t026), '($=222)';
is eval("t026()"), 123;
is $@, '';
is eval("t026(0)"), 123;
is $@, '';
is eval("t026(456)"), 123;
is $@, '';
is eval("t026(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t026/;
is eval("t026(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t026/;
is eval("t026(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t026/;
is $a, 123;

sub t032 ($ = do { $z++; 222 }) { $a // "z" }
$z = 0;
is prototype(\&t032), '($=<expr>)';
is eval("t032()"), 123;
is $z, 1;
is eval("t032(0)"), 123;
is eval("t032(456)"), 123;
is eval("t032(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t032/;
is eval("t032(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t032/;
is eval("t032(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t032/;
is $z, 1;
is $a, 123;

sub t027 ($x?) { $x // "z" }
is prototype(\&t027), '($x?)';
is eval("t027()"), "z";
is $@, '';
is eval("t027(0)"), 0;
is $@, '';
is eval("t027(456)"), 456;
is $@, '';
is eval("t027(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t027/;
is eval("t027(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t027/;
is eval("t027(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t027/;

sub t027b ($self, $x ?) { $x // "z" }
is prototype(\&t027b), '($self, $x?)';
is t027b(0), "z";
is t027b(0, 0), "0";
is t027b(0, 456), 456;
is eval("t027b(0, 456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t027b/;
is eval("t027b(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t027b/;
is eval("t027b(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t027b/;

sub t027a ($x=undef, $a = 333) { $a // "z" }
is prototype(\&t027a), '($x?, $a=333)';
is eval("t027a()"), 333;
is eval("t027a(0)"), 333;
is eval("t027a(456)"), 333;
is eval("t027a(456, 789)"), 789;
is eval("t027a(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t027a/;
is eval("t027a(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t027a/;
is $a, 123;

sub t028 ($a, $b = 333) { "$a/$b" }
is prototype(\&t028), '($a, $b=333)';
is eval("t028()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t028/;
is eval("t028(0)"), "0/333";
is eval("t028(456)"), "456/333";
is eval("t028(456, 789)"), "456/789";
is eval("t028(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t028/;
is $a, 123;

sub t045 ($a, $ = 333) { "$a/" }
is prototype(\&t045), '($a, $=333)';
is eval("t045()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t045/;
is eval("t045(0)"), "0/";
is eval("t045(456)"), "456/";
is eval("t045(456, 789)"), "456/";
is eval("t045(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t045/;
is $a, 123;

sub t046 ($, $b = 333) { "$a/$b" }
is prototype(\&t046), '($, $b=333)';
is eval("t046()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t046/;
is eval("t046(0)"), "123/333";
is eval("t046(456)"), "123/333";
is eval("t046(456, 789)"), "123/789";
is eval("t046(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t046/;
is $a, 123;

sub t047 ($, $ = 333) { "$a/" }
is prototype(\&t047), '($, $=333)';
is eval("t047()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t047/;
is eval("t047(0)"), "123/";
is eval("t047(456)"), "123/";
is eval("t047(456, 789)"), "123/";
is eval("t047(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t047/;
is $a, 123;

sub t029 ($a, $b, $c = 222, $d = 333) { "$a/$b/$c/$d" }
is prototype(\&t029), '($a, $b, $c=222, $d=333)';
is eval("t029()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t029/;
is eval("t029(0)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t029/;
is eval("t029(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t029/;
is eval("t029(456, 789)"), "456/789/222/333";
is eval("t029(456, 789, 987)"), "456/789/987/333";
is eval("t029(456, 789, 987, 654)"), "456/789/987/654";
is eval("t029(456, 789, 987, 654, 321)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t029/;
is eval("t029(456, 789, 987, 654, 321, 111)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t029/;
is $a, 123;

sub t038 ($a, $b = $a."x") { "$a/$b" }
is prototype(\&t038), '($a, $b=<expr>)';
is eval("t038()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t038/;
is eval("t038(0)"), "0/0x";
is eval("t038(456)"), "456/456x";
is eval("t038(456, 789)"), "456/789";
is eval("t038(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t038/;
is $a, 123;

eval "#line 8 foo\n".'sub t030 ($a = 222, $b) { }';
is $@, "Mandatory parameter follows optional parameter at foo line 8\.\n";

eval "#line 8 foo\n".'sub t031 ($a = 222, $b = 333, $c, $d) { }';
is $@, "Mandatory parameter follows optional parameter at foo line 8\.\n";

sub t034 (@abc) { join("/", @abc).";".scalar(@abc) }
is prototype(\&t034), '(@abc)';
is eval("t034()"), ";0";
is eval("t034(0)"), "0;1";
is eval("t034(456)"), "456;1";
is eval("t034(456, 789)"), "456/789;2";
is eval("t034(456, 789, 987)"), "456/789/987;3";
is eval("t034(456, 789, 987, 654)"), "456/789/987/654;4";
is eval("t034(456, 789, 987, 654, 321)"), "456/789/987/654/321;5";
is eval("t034(456, 789, 987, 654, 321, 111)"), "456/789/987/654/321/111;6";
is $a, 123;

eval "#line 8 foo\n".'sub t136 (@abc = 222) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

eval "#line 8 foo\n".'sub t137 (@abc =) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

sub t035 (@) { $a }
is prototype(\&t035), '@';
is eval("t035()"), 123;
is eval("t035(0)"), 123;
is eval("t035(456)"), 123;
is eval("t035(456, 789)"), 123;
is eval("t035(456, 789, 987)"), 123;
is eval("t035(456, 789, 987, 654)"), 123;
is eval("t035(456, 789, 987, 654, 321)"), 123;
is eval("t035(456, 789, 987, 654, 321, 111)"), 123;
is $a, 123;

eval "#line 8 foo\n".'sub t138 (@ = 222) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

eval "#line 8 foo\n".'sub t139 (@ =) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

sub t039 (%abc) { join("/", map { $_."=".$abc{$_} } sort keys %abc) }
is prototype(\&t039), '(%abc)';
is eval("t039()"), "";
is eval("t039(0)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t039 at \(eval \d+\) line 1\.\n\z#;
is eval("t039(456)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t039 at \(eval \d+\) line 1\.\n\z#;
is eval("t039(456, 789)"), "456=789";
is eval("t039(456, 789, 987)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t039 at \(eval \d+\) line 1\.\n\z#;
is eval("t039(456, 789, 987, 654)"), "456=789/987=654";
is eval("t039(456, 789, 987, 654, 321)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t039 at \(eval \d+\) line 1\.\n\z#;
is eval("t039(456, 789, 987, 654, 321, 111)"), "321=111/456=789/987=654";
is $a, 123;

eval "#line 8 foo\n".'sub t140 (%abc = 222) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

eval "#line 8 foo\n".'sub t141 (%abc =) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

eval "#line 8 foo\n".'sub t142 (%) { }';
is $@, "";

sub t040 (%b) { $a }
is prototype(\&t040), '(%b)';
is eval("t040()"), 123;
is eval("t040(0)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t040 at \(eval \d+\) line 1\.\n\z#;
is eval("t040(456)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t040 at \(eval \d+\) line 1\.\n\z#;
is eval("t040(456, 789)"), 123;
is eval("t040(456, 789, 987)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t040 at \(eval \d+\) line 1\.\n\z#;
is eval("t040(456, 789, 987, 654)"), 123;
is eval("t040(456, 789, 987, 654, 321)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t040 at \(eval \d+\) line 1\.\n\z#;
is eval("t040(456, 789, 987, 654, 321, 111)"), 123;
is $a, 123;

eval "#line 8 foo\n".'sub t142 (% = 222) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

eval "#line 8 foo\n".'sub t143 (% =) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

sub t041 ($a, @b) { $a.";".join("/", @b) }
is prototype(\&t041), '($a, @b)';
is eval("t041()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t041/;
is eval("t041(0)"), "0;";
is eval("t041(456)"), "456;";
is eval("t041(456, 789)"), "456;789";
is eval("t041(456, 789, 987)"), "456;789/987";
is eval("t041(456, 789, 987, 654)"), "456;789/987/654";
is eval("t041(456, 789, 987, 654, 321)"), "456;789/987/654/321";
is eval("t041(456, 789, 987, 654, 321, 111)"), "456;789/987/654/321/111";
is $a, 123;

#sub t042 ($a, @) { $a.";" }
#is prototype(\&t042), '($a, @)';
#is eval("t042()"), undef;
#like $@, qr/\ANot enough arguments for subroutine entry t042/;
#is eval("t042(0)"), "0;";
#is eval("t042(456)"), "456;";
#is eval("t042(456, 789)"), "456;";
#is eval("t042(456, 789, 987)"), "456;";
#is eval("t042(456, 789, 987, 654)"), "456;";
#is eval("t042(456, 789, 987, 654, 321)"), "456;";
#is eval("t042(456, 789, 987, 654, 321, 111)"), "456;";
#is $a, 123;

#sub t043 ($, @b) { $a.";".join("/", @b) }
#is prototype(\&t043), '($, @b)';
#is eval("t043()"), undef;
#like $@, qr/\ANot enough arguments for subroutine entry t043/;
#is eval("t043(0)"), "123;";
#is eval("t043(456)"), "123;";
#is eval("t043(456, 789)"), "123;789";
#is eval("t043(456, 789, 987)"), "123;789/987";
#is eval("t043(456, 789, 987, 654)"), "123;789/987/654";
#is eval("t043(456, 789, 987, 654, 321)"), "123;789/987/654/321";
#is eval("t043(456, 789, 987, 654, 321, 111)"), "123;789/987/654/321/111";
#is $a, 123;
#
#sub t044 ($, @) { $a.";" }
#is prototype(\&t044), '($, @)';
#is eval("t044()"), undef;
#like $@, qr/\ANot enough arguments for subroutine entry t044/;
#is eval("t044(0)"), "123;";
#is eval("t044(456)"), "123;";
#is eval("t044(456, 789)"), "123;";
#is eval("t044(456, 789, 987)"), "123;";
#is eval("t044(456, 789, 987, 654)"), "123;";
#is eval("t044(456, 789, 987, 654, 321)"), "123;";
#is eval("t044(456, 789, 987, 654, 321, 111)"), "123;";
#is $a, 123;

sub t049 ($a, %b) { $a.";".join("/", map { $_."=".$b{$_} } sort keys %b) }
is prototype(\&t049), '($a, %b)';
is eval("t049()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t049/;
is eval("t049(222)"), "222;";
is eval("t049(222, 456)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t049 at \(eval \d+\) line 1\.\n\z#;
is eval("t049(222, 456, 789)"), "222;456=789";
is eval("t049(222, 456, 789, 987)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t049 at \(eval \d+\) line 1\.\n\z#;
is eval("t049(222, 456, 789, 987, 654)"), "222;456=789/987=654";
is eval("t049(222, 456, 789, 987, 654, 321)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t049 at \(eval \d+\) line 1\.\n\z#;
is eval("t049(222, 456, 789, 987, 654, 321, 111)"),
    "222;321=111/456=789/987=654";
is $a, 123;

sub t051 ($a, $b, $c, @d) { "$a;$b;$c;(".join(",", @d).")".scalar(@d) }
is prototype(\&t051), '($a, $b, $c, @d)';
is eval("t051()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t051/;
is eval("t051(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t051/;
is eval("t051(456, 789)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t051/;
is eval("t051(456, 789, 987)"), "456;789;987;()0";
is eval("t051(456, 789, 987, 654)"), "456;789;987;(654)1";
is eval("t051(456, 789, 987, 654, 321)"), "456;789;987;(654,321)2";
is eval("t051(456, 789, 987, 654, 321, 111)"), "456;789;987;(654,321,111)3";
is $a, 123;

sub t052 ($a, $b, %c) { "$a;$b;".join(";", map { $_."=>".$c{$_} } sort keys %c) }
is prototype(\&t052), '($a, $b, %c)';
is eval("t052()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t052/;
is eval("t052(222)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t052/;
is eval("t052(222, 333)"), "222;333;";
is eval("t052(222, 333, 456)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t052 at \(eval \d+\) line 1\.\n\z#;
is eval("t052(222, 333, 456, 789)"), "222;333;456=>789";
is eval("t052(222, 333, 456, 789, 987)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t052 at \(eval \d+\) line 1\.\n\z#;
is eval("t052(222, 333, 456, 789, 987, 654)"), "222;333;456=>789;987=>654";
is eval("t052(222, 333, 456, 789, 987, 654, 321)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t052 at \(eval \d+\) line 1\.\n\z#;
is eval("t052(222, 333, 456, 789, 987, 654, 321, 111)"),
    "222;333;321=>111;456=>789;987=>654";
is $a, 123;

sub t053 ($a, $b, $c, %d) {
    "$a;$b;$c;".join(";", map { $_."=>".$d{$_} } sort keys %d)
}
is prototype(\&t053), '($a, $b, $c, %d)';
is eval("t053()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t053/;
is eval("t053(222)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t053/;
is eval("t053(222, 333)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t053/;
is eval("t053(222, 333, 444)"), "222;333;444;";
is eval("t053(222, 333, 444, 456)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t053 at \(eval \d+\) line 1\.\n\z#;
is eval("t053(222, 333, 444, 456, 789)"), "222;333;444;456=>789";
is eval("t053(222, 333, 444, 456, 789, 987)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t053 at \(eval \d+\) line 1\.\n\z#;
is eval("t053(222, 333, 444, 456, 789, 987, 654)"),
    "222;333;444;456=>789;987=>654";
is eval("t053(222, 333, 444, 456, 789, 987, 654, 321)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t053 at \(eval \d+\) line 1\.\n\z#;
is eval("t053(222, 333, 444, 456, 789, 987, 654, 321, 111)"),
    "222;333;444;321=>111;456=>789;987=>654";
is $a, 123;

sub t048 ($a = 222, @b) { $a.";".join("/", @b).";".scalar(@b) }
is prototype(\&t048), '($a=222, @b)';
is eval("t048()"), "222;;0";
is eval("t048(0)"), "0;;0";
is eval("t048(456)"), "456;;0";
is eval("t048(456, 789)"), "456;789;1";
is eval("t048(456, 789, 987)"), "456;789/987;2";
is eval("t048(456, 789, 987, 654)"), "456;789/987/654;3";
is eval("t048(456, 789, 987, 654, 321)"), "456;789/987/654/321;4";
is eval("t048(456, 789, 987, 654, 321, 111)"), "456;789/987/654/321/111;5";
is $a, 123;

sub t054 ($a = 222, $b = 333, @c) { "$a;$b;".join("/", @c).";".scalar(@c) }
is prototype(\&t054), '($a=222, $b=333, @c)';
is eval("t054()"), "222;333;;0";
is eval("t054(456)"), "456;333;;0";
is eval("t054(456, 789)"), "456;789;;0";
is eval("t054(456, 789, 987)"), "456;789;987;1";
is eval("t054(456, 789, 987, 654)"), "456;789;987/654;2";
is eval("t054(456, 789, 987, 654, 321)"), "456;789;987/654/321;3";
is eval("t054(456, 789, 987, 654, 321, 111)"), "456;789;987/654/321/111;4";
is $a, 123;

sub t055 ($a = 222, $b = 333, $c = 444, @d) {
    "$a;$b;$c;".join("/", @d).";".scalar(@d)
}
is prototype(\&t055), '($a=222, $b=333, $c=444, @d)';
is eval("t055()"), "222;333;444;;0";
is eval("t055(456)"), "456;333;444;;0";
is eval("t055(456, 789)"), "456;789;444;;0";
is eval("t055(456, 789, 987)"), "456;789;987;;0";
is eval("t055(456, 789, 987, 654)"), "456;789;987;654;1";
is eval("t055(456, 789, 987, 654, 321)"), "456;789;987;654/321;2";
is eval("t055(456, 789, 987, 654, 321, 111)"), "456;789;987;654/321/111;3";
is $a, 123;

sub t050 ($a = 211, %b) { $a.";".join("/", map { $_."=".$b{$_} } sort keys %b) }
is prototype(\&t050), '($a=211, %b)';
is eval("t050()"), "211;";
is eval("t050(222)"), "222;";
is eval("t050(222, 456)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t050 at \(eval \d+\) line 1\.\n\z#;
is eval("t050(222, 456, 789)"), "222;456=789";
is eval("t050(222, 456, 789, 987)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t050 at \(eval \d+\) line 1\.\n\z#;
is eval("t050(222, 456, 789, 987, 654)"), "222;456=789/987=654";
is eval("t050(222, 456, 789, 987, 654, 321)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t050 at \(eval \d+\) line 1\.\n\z#;
is eval("t050(222, 456, 789, 987, 654, 321, 111)"),
    "222;321=111/456=789/987=654";
is $a, 123;

sub t056 ($a = 211, $b = 311, %c) {
    "$a;$b;".join("/", map { $_."=".$c{$_} } sort keys %c)
}
is prototype(\&t056), '($a=211, $b=311, %c)';
is eval("t056()"), "211;311;";
is eval("t056(222)"), "222;311;";
is eval("t056(222, 333)"), "222;333;";
is eval("t056(222, 333, 456)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t056 at \(eval \d+\) line 1\.\n\z#;
is eval("t056(222, 333, 456, 789)"), "222;333;456=789";
is eval("t056(222, 333, 456, 789, 987)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t056 at \(eval \d+\) line 1\.\n\z#;
is eval("t056(222, 333, 456, 789, 987, 654)"), "222;333;456=789/987=654";
is eval("t056(222, 333, 456, 789, 987, 654, 321)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t056 at \(eval \d+\) line 1\.\n\z#;
is eval("t056(222, 333, 456, 789, 987, 654, 321, 111)"),
    "222;333;321=111/456=789/987=654";
is $a, 123;

sub t057 ($a = 211, $b = 311, $c = 411, %d) {
    "$a;$b;$c;".join("/", map { $_."=".$d{$_} } sort keys %d)
}
is prototype(\&t057), '($a=211, $b=311, $c=411, %d)';
is eval("t057()"), "211;311;411;";
is eval("t057(222)"), "222;311;411;";
is eval("t057(222, 333)"), "222;333;411;";
is eval("t057(222, 333, 444)"), "222;333;444;";
is eval("t057(222, 333, 444, 456)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t057 at \(eval \d+\) line 1\.\n\z#;
is eval("t057(222, 333, 444, 456, 789)"), "222;333;444;456=789";
is eval("t057(222, 333, 444, 456, 789, 987)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t057 at \(eval \d+\) line 1\.\n\z#;
is eval("t057(222, 333, 444, 456, 789, 987, 654)"),
    "222;333;444;456=789/987=654";
is eval("t057(222, 333, 444, 456, 789, 987, 654, 321)"), undef;
like $@, qr#\AOdd name/value argument for subroutine t057 at \(eval \d+\) line 1\.\n\z#;
is eval("t057(222, 333, 444, 456, 789, 987, 654, 321, 111)"),
    "222;333;444;321=111/456=789/987=654";
is $a, 123;

sub t058 ($a, $b = 333, @c) { "$a;$b;".join("/", @c).";".scalar(@c) }
is prototype(\&t058), '($a, $b=333, @c)';
is eval("t058()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t058/;
is eval("t058(456)"), "456;333;;0";
is eval("t058(456, 789)"), "456;789;;0";
is eval("t058(456, 789, 987)"), "456;789;987;1";
is eval("t058(456, 789, 987, 654)"), "456;789;987/654;2";
is eval("t058(456, 789, 987, 654, 321)"), "456;789;987/654/321;3";
is eval("t058(456, 789, 987, 654, 321, 111)"), "456;789;987/654/321/111;4";
is $a, 123;

eval "#line 8 foo\n".'sub t059 (@a, $b) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t060 (@a, $b = 222) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t061 (@a, @b) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t062 (@a, %b) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t063 (@, $b) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t064 (@, $b = 222) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t065 (@, @b) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t066 (@, %b) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t067 (@a, $) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t068 (@a, $ = 222) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t069 (@a, @) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t070 (@a, %) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t071 (@, $) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t072 (@, $ = 222) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t073 (@, @) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t074 (@, %) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t075 (%a, $b) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t076 (%, $b) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t077 ($a, @b, \$c) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t078 ($a, %b, \$c) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

eval "#line 8 foo\n".'sub t079 ($a, @b, $c, $d) { }';
is $@, "Slurpy parameter not last at foo line 8\.\n";

sub t080 ($a,,, $b) { $a.$b }
is prototype(\&t080), '($a, $b)'; # XXX not a cperl syntax error?
is eval("t080()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t080/;
is eval("t080(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t080/;
is eval("t080(456, 789)"), "456789";
is eval("t080(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t080/;
is eval("t080(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

sub t081 ($a, $b,,) { $a.$b }
is prototype(\&t081), '($a, $b)'; # XXX not a cperl syntax error?
is eval("t081()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d\d\d/;
is eval("t081(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d\d\d/;
is eval("t081(456, 789)"), "456789";
is eval("t081(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is eval("t081(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

eval "#line 8 foo\n".'sub t082 (, $a) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

eval "#line 8 foo\n".'sub t083 (,) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

sub t084($a,$b){ $a.$b }
is prototype(\&t084), '($a, $b)';
is eval("t084()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d\d\d/;
is eval("t084(456)"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d\d\d/;
is eval("t084(456, 789)"), "456789";
is eval("t084(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is eval("t084(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

sub t085
    (
    $
    a
    ,
    ,
    $
    b
    =
    333
    ,
    ,
    )
    { $a.$b }
is prototype(\&t085), '($a, $b=333)';
is eval("t085()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d\d\d/;
is eval("t085(456)"), "456333";
is eval("t085(456, 789)"), "456789";
is eval("t085(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is eval("t085(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

sub t086
    ( #foo)))
    $ #foo)))
    a #foo)))
    , #foo)))
    , #foo)))
    $ #foo)))
    b #foo)))
    = #foo)))
    333 #foo)))
    , #foo)))
    , #foo)))
    ) #foo)))
    { $a.$b }
is prototype(\&t086), '($a, $b=333)';
is eval("t086()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d\d\d/;
is eval("t086(456)"), "456333";
is eval("t086(456, 789)"), "456789";
is eval("t086(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is eval("t086(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

sub t087
    (#foo)))
    $ #foo)))
    a#foo)))
    ,#foo)))
    ,#foo)))
    $ #foo)))
    b#foo)))
    =#foo)))
    333#foo)))
    ,#foo)))
    ,#foo)))
    )#foo)))
    { $a.$b }
is prototype(\&t087), '($a, $b=333)';
is eval("t087()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d\d\d/;
is eval("t087(456)"), "456333";
is eval("t087(456, 789)"), "456789";
is eval("t087(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is eval("t087(456, 789, 987, 654)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

eval "#line 8 foo\n"."sub t088 (\$ #foo\na) { }";
is $@, "";

eval "#line 8 foo\n"."sub t089 (\$#foo\na) { }";
like $@, qr/\AParse error at foo line 9\.\n/;

eval "#line 8 foo\n"."sub t090 (\@ #foo\na) { }";
is $@, "";

eval "#line 8 foo\n"."sub t091 (\@#foo\na) { }";
like $@, qr/\AParse error at foo line 9\.\n/;

eval "#line 8 foo\n"."sub t092 (\% #foo\na) { }";
is $@, "";

eval "#line 8 foo\n"."sub t093 (\%#foo\na) { }";
like $@, qr/\AParse error at foo line 9\.\n/;

eval "#line 8 foo\n".'sub t094 (123) { }';
like $@, qr/\ANo such class 123 at foo line 8, near/;

eval "#line 8 foo\n".'sub t095 ($a, 123) { }';
like $@, qr/\ANo such class 123 at foo line 8, near/;

eval "#line 8 foo\n".'sub t096 ($a 123) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

eval "#line 8 foo\n".'sub t097 ($a { }) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

eval "#line 8 foo\n".'sub t098 ($a; \$b) { }';
like $@, qr/\AParse error at foo line 8\.\n/;

eval "#line 8 foo\n".'sub t099 ($\$) { }';
is $@, "";

no warnings "experimental::lexical_topic";

my $dummy4; # Deparse currently messes up pragmata just before sub def

sub t100 ($_) { "$::_/$_" }
is prototype(\&t100), '$_';
$_ = "___";
is eval("t100()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d\d\d at \(eval \d+\) line 1/;
$_ = "___";
is eval("t100(0)"), "___/___";
$_ = "___";
is eval("t100(456)"), "___/___";
$_ = "___";
is eval("t100(456, 789)"), "___/___";
is $@, "";
#like $@, qr/\AToo many arguments for subroutine entry t\d\d\d at \(eval \d+\) line 1/;
$_ = "___";
is eval("t100(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d at \(eval \d+\) line 1/;
is $a, 123;

eval "#line 8 foo\n".'sub t101 (@_) { }';
like $@, qr/\ACan't use global \@_ in "my" at foo line 8/;

eval "#line 8 foo\n".'sub t102 (%_) { }';
like $@, qr/\ACan't use global \%_ in "my" at foo line 8/;

my $t103 = sub ($a) { $a || "z" };
is prototype($t103), '($a)';
is eval("\$t103->()"), undef; # run-time arity checks
# TODO: print the name of the lexvar $t103
like $@, qr/\ANot enough arguments for subroutine __ANON__. Want: 1, but got: 0 at \(eval \d+\) line 1\./;
is eval("\$t103->(0)"), "z";
is eval("\$t103->(456)"), 456;
is eval("\$t103->(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine __ANON__. Want: 1, but got: 2 at \(eval \d+\) line 1\./;
is eval("\$t103->(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine __ANON__. Want: 1, but got: 3 at \(eval \d+\) line 1\./;
is $a, 123;

my $t118 = sub ($a) :prototype($) { $a || "z" };
is prototype($t118), '$';
is eval("\$t118->()"), undef;
like $@, qr/\ANot enough arguments for subroutine __ANON__. Want: 1, but got: 0 at \(eval \d+\) line 1\./;
is eval("\$t118->(0)"), "z";
is eval("\$t118->(456)"), 456;
is eval("\$t118->(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine __ANON__. Want: 1, but got: 2 at \(eval \d+\) line 1\./;
is eval("\$t118->(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine __ANON__. Want: 1, but got: 3 at \(eval \d+\) line 1\./;
is $a, 123;

sub t033 ($a = sub ($a) { $a."z" }) { $a->("a")."y" }
is prototype(\&t033), '($a=<expr>)';
is eval("t033()"), "azy";
is eval("t033(sub { \"x\".\$_[0].\"x\" })"), "xaxy";
is eval("t033(sub { \"x\".\$_[0].\"x\" }, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

sub t133 ($a = sub ($a = 222) { $a."z" }) { $a->()."/".$a->("a") }
is prototype(\&t133), '($a=<expr>)';
is eval("t133()"), "222z/az";
is eval("t133(sub { \"x\".(\$_[0] // \"u\").\"x\" })"), "xux/xax";
is eval("t133(sub { \"x\".(\$_[0] // \"u\").\"x\" }, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

sub t134 ($a = sub ($a, $t = sub { $_[0]."p" }) { $t->($a)."z" }) {
    $a->("a")."/".$a->("b", sub { $_[0]."q" } )
}
is prototype(\&t134), '($a=<expr>)';
is eval("t134()"), "apz/bqz";
is eval("t134(sub { \"x\".(\$_[1] // sub{\$_[0]})->(\$_[0]).\"x\" })"),
    "xax/xbqx";
is eval("t134(sub { \"x\".(\$_[1] // sub{\$_[0]})->(\$_[0]).\"x\" }, 789)"),
    undef;
like $@, qr/\AToo many arguments for subroutine entry t134 exceeding max 1 args at \(eval \d+\) line 1/;
is $a, 123;

sub t135 ($a = sub ($a, $t = sub ($p) { $p."p" }) { $t->($a)."z" }) {
    $a->("a")."/".$a->("b", sub { $_[0]."q" } )
}
is prototype(\&t135), '($a=<expr>)';
is eval("t135()"), "apz/bqz";
is eval("t135(sub { \"x\".(\$_[1] // sub{\$_[0]})->(\$_[0]).\"x\" })"),
    "xax/xbqx";
is eval("t135(sub { \"x\".(\$_[1] // sub{\$_[0]})->(\$_[0]).\"x\" }, 789)"),
    undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

sub t132 (
    $a = sub ($a, $t = sub ($p = 222) { $p."p" }) { $t->($a)."z".$t->() },
) {
    $a->("a")."/".$a->("b", sub { ($_[0] // "u")."q" } )
}
is prototype(\&t132), '($a=<expr>)';
is eval("t132()"), "apz222p/bqzuq";
is eval("t132(sub { \"x\".(\$_[1] // sub{\$_[0]})->(\$_[0]).\"x\" })"),
    "xax/xbqx";
is eval("t132(sub { \"x\".(\$_[1] // sub{\$_[0]})->(\$_[0]).\"x\" }, 789)"),
    undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

sub t104($a) :method { $a || "z" }
is prototype(\&t104), '($a)';
is eval("t104()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t\d\d\d/;
is eval("t104(0)"), "z";
is eval("t104(456)"), 456;
is eval("t104(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is eval("t104(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d/;
is $a, 123;

# override prototype
sub t105($a) :prototype($) { $a || "z" }
is prototype(\&t105), '$';
is eval("t105()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t105\. Missing \$a at/;
is eval("t105(0)"), "z";
is eval("t105(456)"), 456;
is eval("t105(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t105/;
is eval("t105(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t105/;
is $a, 123;

sub t106($a) :prototype(@) { $a || "z" }
is prototype(\&t106), '@';
is eval("t106()"), undef;
like $@, qr/\ANot enough arguments for subroutine entry t106\. Missing \$a at/;
is eval("t106(0)"), "z";
is eval("t106(456)"), 456;
is eval("t106(456, 789)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d exceeding max 1 args at \(eval \d+\) line 1, near/;
is eval("t106(456, 789, 987)"), undef;
like $@, qr/\AToo many arguments for subroutine entry t\d\d\d exceeding max 1 args at \(eval \d+\) line 1, near/;
is $a, 123;

eval "#line 8 foo\n".'sub t107 :method ($a) { }';
isnt $@, "";

eval "#line 8 foo\n".'sub t108 :prototype(\$) ($a) { }';
isnt $@, "";

sub t109 { }
is prototype(\&t109), undef;
is scalar(@{[ t109() ]}), 0;
is scalar(t109()), undef;

sub t110 () { }
is prototype(\&t110), "";
is scalar(@{[ t110() ]}), 0;
is scalar(t110()), undef;

sub t111 ($a) { }
is prototype(\&t111), '($a)';
is scalar(@{[ t111(222) ]}), 0;
is scalar(t111(222)), undef;

sub t112 ($) { }
is prototype(\&t112), '$';
is scalar(@{[ t112(222) ]}), 0;
is scalar(t112(222)), undef;

sub t114 ($a = undef) { }
is prototype(\&t114), '($a?)';
is scalar(@{[ t114() ]}), 0;
is scalar(t114()), undef;
is scalar(@{[ t114(333) ]}), 0;
is scalar(t114(333)), undef;

sub t113 ($a = 222) { $a }
is prototype(\&t113), '($a=222)';
is scalar(@{[ t113() ]}), 1;
is scalar(t113()), 222;
is scalar(@{[ t113(333) ]}), 1;
is scalar(t113(333)), 333;

sub t115 ($a = do { $z++; 222 }) { }
is prototype(\&t115), '($a=<expr>)';
$z = 0;
is scalar(@{[ t115() ]}), 0;
is $z, 1;
is scalar(t115()), undef;
is $z, 2;
is scalar(@{[ t115(333) ]}), 0;
is scalar(t115(333)), undef;
is $z, 2;

sub t116 (@a) { }
is prototype(\&t116), '(@a)';
is scalar(@{[ t116() ]}), 0;
is scalar(t116()), undef;
is scalar(@{[ t116(333) ]}), 0;
is scalar(t116(333)), undef;

sub t117 (%a) { }
is prototype(\&t117), '(%a)';
is scalar(@{[ t117() ]}), 0;
is scalar(t117()), undef;
is scalar(@{[ t117(333, 444) ]}), 0;
is scalar(t117(333, 444)), undef;

sub t118 (\$a) { ++$a }
{
    is prototype(\&t118), '(\$a)';
    my $a = 222;
    is scalar(@{[ t118($a) ]}), 1;
    is scalar(t118($a)), 224;
    is $a, 224;
}

sub t119(int $a) :int { $a || 0 }
{
    is prototype(\&t119), '(int $a)', 'int $a';
    is scalar(@{[ t119(222) ]}), 1;
    is scalar(t119(222)), 222;
    eval "\$a = t119('a');";
    like $@, qr/\AType of arg \$a to t119 must be int \(not Str\) at \(eval \d+\) line 1, near "/;
}

use File::Spec::Functions;
my $keywords_file = catfile(updir,'regen','keywords.pl');
open my $kh, $keywords_file
   or die "$0 cannot open $keywords_file: $!";
while(<$kh>) {
    if (m?__END__?..${\0} and /^[+-]/) {
        chomp(my $word = $');
        # $y should be an error after $x=foo.  The exact error we get may
        # differ if this is __END__ or s or some other special keyword.
        eval 'sub ($x = ' . $word . ', $y) {}';
        local $::TODO = 'does not work yet'
          if $word =~ /^(?:chmod|chown|die|exec|glob|kill|mkdir|print
                          |printf|return|reverse|select|setpgrp|sort|split
                          |system|unlink|utime|warn)\z/x;
        isnt $@, "", "$word does not swallow trailing comma";
    }
}
close $kh;

sub t144 ($a = "abc") { $a }
is prototype(\&t144), '($a="abc")';
is scalar(t144()), "abc";
is scalar(t144("defg")), "defg";


# check that deferred default expressions don't have side-effects

{
    my $x = 100;
    sub t145 ($a = $x, $b = $x++, $c = $x, $d = $b) { "$a:$b:$c:$d" }
    is prototype(\&t145), '($a=$x, $b=<expr>, $c=<expr>, $d=<expr>)';
    is scalar(t145()),    "100:100:101:100";
    is scalar(t145(1)),   "1:101:102:101";
    is scalar(t145(1,2)), "1:2:102:2";
}

# ditto with a package var

{
    local $x = 100;
    sub t146 ($a = $x, $b = $x++, $c = $x, $d = $b) { "$a:$b:$c:$d" }
    is prototype(\&t146), '($a=$x, $b=<expr>, $c=<expr>, $d=<expr>)';
    is scalar(t146()),    "100:100:101:100";
    is scalar(t146(1)),   "1:101:102:101";
    is scalar(t146(1,2)), "1:2:102:2";
}


# check that unused default args are skipped
# the first $ param is ignored, but still mandatory

sub t147 ($, $=0, $=1, $=2, $="foo", $a="bar", $b="zoot") { "$a:$b" }
is scalar(t147(1)),                 "bar:zoot";
is scalar(t147(1,2,3,4)),           "bar:zoot";
is scalar(t147(1,2,3,4,5)),         "bar:zoot";
is scalar(t147(1,2,3,4,5,"baz")),   "baz:zoot";
is scalar(t147(1,2,3,4,5,"baz",7)), "baz:7";

# check untyped array and hash refs

sub t148 (\@a) { $a->[0] = 1 }
{
    is prototype(\&t148), '(\@a)';
    my $a = [222];
    is scalar(@{[ t148($a) ]}), 1;
    is scalar(t148($a)), 1;
    is $a->[0], 1;
    eval "t148('a');";
    like $@, qr/\AType of arg \$a to t148 must be ARRAY reference \(not PV\) at \(eval \d+\) line 1, near "/;
    eval "t148({});";
    like $@, qr/\AType of arg \$a to t148 must be ARRAY reference \(not HASH reference\) at \(eval \d+\) line 1, near "/;
}

sub t149 (\%a) { $a->{0} = 1 }
{
    is prototype(\&t149), '(\%a)';
    my $a = {0 => 222};
    is scalar(@{[ t149($a) ]}), 1;
    is scalar(t149($a)), 1;
    is $a->{0}, 1;
    eval "t149('a');";
    like $@, qr/\AType of arg \$a to t149 must be HASH reference \(not PV\) at \(eval \d+\) line 1, near "/;
    eval "t149([]);";
    like $@, qr/\AType of arg \$a to t149 must be HASH reference \(not ARRAY reference\) at \(eval \d+\) line 1, near "/;
}

# int should not bleed into @error
sub t150 (int $i, @error) { 1 }
{
    is scalar(t150(1, "")), 1, "reset tyepstash";
}

# user-type checks
sub t119a (Int $a) :int { ++$a }
{
    my int $b = 0;
    is t119a($b), 1;
    eval "t119a('a')"; # ck error (fast direct violation)
    like $@, qr/\AType of arg \$a to t119a must be Int \(not Str\) at \(eval \d+\) line 1, near "/, "Int not Str";

    @MyInt::ISA=('Int');
    my MyInt $i = 1;   # but MyInt is not a int, only a Int
    eval 't119a($i);'; # slow isa check with type_Object
    is $@, "", "MyInt isa Int, slow isa check with type_Object";
    eval 't119($i);'; # MyInt isa Int isa int
    is $@, "", "MyInt isa int, two stage type check";
    #like $@, qr/\AType of arg \$a to t119 must be int \(not MyInt\) at \(eval \d+\) line 1, near "/, "int not MyInt";

    @MyStr::ISA=('Str');
    my MyStr $s;
    # warns with use warnings 'types';
    eval 't119a($s);'; # ck error (slow isa check with type_Object)
    is $@, "", "MyStr isa Str, valid cast to int";
    #like $@, qr/\AType of arg \$a to t119a must be Int \(not MyStr\) at \(eval \d+\) line 1, near "/, "Int not MyStr";
}

# check that a sub can have 32767 parameters ...

my $code = "#line 2 foo\nsub t148 ("
            . join(',', map "\$a$_", 1..32767)
            . ") { }";
eval $code;
is $@, "", '32767 params';

# .. but not 32768

$code = "#line 2 foo\nsub t149 ("
            . join(',', map "\$a$_", 1..32768)
            . ") { }";
eval $code;
is $@, "Subroutine signature has more than 32767 parameters at foo line 2\.\n",
        '32768 params';

# Greater than 128 vars - can't use a single padrange.
# Make every param var a ref to a blessed object. If all the
# vars are correctly introduced, they should all go out of scope
# at the right point.

{
    package T150;

    sub t150 (
            $a001,$a002,$a003,$a004,$a005,$a006,$a007,$a008,
            $a009,$a010,$a011,$a012,$a013,$a014,$a015,$a016,
            $a017,$a018,$a019,$a020,$a021,$a022,$a023,$a024,
            $a025,$a026,$a027,$a028,$a029,$a030,$a031,$a032,
            $a033,$a034,$a035,$a036,$a037,$a038,$a039,$a040,
            $a041,$a042,$a043,$a044,$a045,$a046,$a047,$a048,
            $a049,$a050,$a051,$a052,$a053,$a054,$a055,$a056,
            $a057,$a058,$a059,$a060,$a061,$a062,$a063,$a064,
            $a065,$a066,$a067,$a068,$a069,$a070,$a071,$a072,
            $a073,$a074,$a075,$a076,$a077,$a078,$a079,$a080,
            $a081,$a082,$a083,$a084,$a085,$a086,$a087,$a088,
            $a089,$a090,$a091,$a092,$a093,$a094,$a095,$a096,
            $a097,$a098,$a099,$a100,$a101,$a102,$a103,$a104,
            $a105,$a106,$a107,$a108,$a109,$a110,$a111,$a112,
            $a113,$a114,$a115,$a116,$a117,$a118,$a119,$a120,
            $a121,$a122,$a123,$a124,$a125,$a126,$a127,$a128,
            $a129
    ) {}

    my $destroyed = 0;
    sub DESTROY { $destroyed = 1 }
    {
        my $x = bless {}, 'T150';

        t150(
            $x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,
            $x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,
            $x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,
            $x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,
            $x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,
            $x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,
            $x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,
            $x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,$x,
            $x
        );
        ::is $destroyed, 0, "129 params: not destroyed yet";
    }
    ::is $destroyed, 1, "129 params: destroyed now"
}

# ditto non-consecutive pad ranges

{
    package T151;

    sub t151 ($a, $b = do { my $foo; 1 }, $c = 1) {}

    my $destroyed = 0;
    sub DESTROY { $destroyed = 1 }
    {
        my $x = bless {}, 'T151';

        t151($x,$x,$x);
        ::is $destroyed, 0, "non-consec params: not destroyed yet";
    }
    ::is $destroyed, 1, "non-consec params: destroyed now"
}

# handle goto from @_ to sig
sub t147a ($, $=0, $a="bar", $b="zoot") {
  print "# t147: $a:$b\n";
  is "$a:$b", "bar:zoot";
}
sub t147_7 ($, $=0, $a="bar", $b="zoot") {
  print "# t147_7: $a:$b\n";
  is "$a:$b", "baz:7";
}
sub t147_pp {
  my $x = shift; # defeat fake_signatures
  my ($y, $a, $b) = @_;
  $a //= "bar";
  $b //= "zoot";
  print "# t147_pp: $a:$b\n";
  is "$a:$b", "baz:7";
}

sub goto1_pp2pp {
  @_ = (1,2,"baz",7);
  goto &t147_pp;
}
# handle goto with @_ as XSUB, not PP
sub goto1_pp2sig {
  @_ = (1);
  goto &t147a;
}
sub goto2_pp2sig {
  @_ = (1,2,"bar");
  goto &t147a;
}  
sub goto3_pp2sig {
  @_ = (1,2,"baz",7);
  goto &t147_7;
}
sub goto1_sig2sig ($, $=0, $a="bar", $b="zoot") {
  local @_ = (1,2,"baz",7); # ignored, should warn
  goto &t147a;
}
sub goto2_sig2sig ($x, $y, $a, $b) {
  goto &t147_7;
}

sub goto1_sig2pp ($, $=0, $a="baz", $b="7") {
  local @_ = (1,2,"baz",7); # ignored, should warn
  goto &t147_pp;
}
sub goto2_sig2pp ($x, $y, $a, $b) {
  goto &t147_pp; # #173
}

goto1_pp2pp();
goto1_pp2sig();
goto2_pp2sig();
goto3_pp2sig();

goto1_sig2sig(0);
goto2_sig2sig(0,0,"baz",7);

goto1_sig2pp(0);
goto2_sig2pp(0,0,"baz",7);

sub no_fake_sig {
    my ($self, $extra) = (@_, 1);
    $extra
}

is(no_fake_sig(''), 1, "no fake_sigs with extra args [cperl #157]");

done_testing;

1;
