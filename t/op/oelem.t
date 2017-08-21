#!./perl
# more than 255 fields
local($\, $", $,) = (undef, ' ', '');
print "1..6\n";
my $test = 1;

class Foo {
  has $a0;has $a1;has $a2;has $a3;has $a4;has $a5;has $a6;has $a7;has $a8;has $a9;
  has $a10;has $a11;has $a12;has $a13;has $a14;has $a15;has $a16;has $a17;has $a18;has $a19;
  has $a20;has $a21;has $a22;has $a23;has $a24;has $a25;has $a26;has $a27;has $a28;has $a29;
  has $a30;has $a31;has $a32;has $a33;has $a34;has $a35;has $a36;has $a37;has $a38;has $a39;
  has $a40;has $a41;has $a42;has $a43;has $a44;has $a45;has $a46;has $a47;has $a48;has $a49;
  has $a50;has $a51;has $a52;has $a53;has $a54;has $a55;has $a56;has $a57;has $a58;has $a59;
  has $a60;has $a61;has $a62;has $a63;has $a64;has $a65;has $a66;has $a67;has $a68;has $a69;
  has $a70;has $a71;has $a72;has $a73;has $a74;has $a75;has $a76;has $a77;has $a78;has $a79;
  has $a80;has $a81;has $a82;has $a83;has $a84;has $a85;has $a86;has $a87;has $a88;has $a89;
  has $a90;has $a91;has $a92;has $a93;has $a94;has $a95;has $a96;has $a97;has $a98;has $a99;
  has $a100;has $a101;has $a102;has $a103;has $a104;has $a105;has $a106;has $a107;has $a108;has $a109;
  has $a110;has $a111;has $a112;has $a113;has $a114;has $a115;has $a116;has $a117;has $a118;has $a119;
  has $a120;has $a121;has $a122;has $a123;has $a124;has $a125;has $a126;has $a127;has $a128;has $a129;
  has $a130;has $a131;has $a132;has $a133;has $a134;has $a135;has $a136;has $a137;has $a138;has $a139;
  has $a140;has $a141;has $a142;has $a143;has $a144;has $a145;has $a146;has $a147;has $a148;has $a149;
  has $a150;has $a151;has $a152;has $a153;has $a154;has $a155;has $a156;has $a157;has $a158;has $a159;
  has $a160;has $a161;has $a162;has $a163;has $a164;has $a165;has $a166;has $a167;has $a168;has $a169;
  has $a170;has $a171;has $a172;has $a173;has $a174;has $a175;has $a176;has $a177;has $a178;has $a179;
  has $a180;has $a181;has $a182;has $a183;has $a184;has $a185;has $a186;has $a187;has $a188;has $a189;
  has $a190;has $a191;has $a192;has $a193;has $a194;has $a195;has $a196;has $a197;has $a198;has $a199;
  has $a200;has $a201;has $a202;has $a203;has $a204;has $a205;has $a206;has $a207;has $a208;has $a209;
  has $a210;has $a211;has $a212;has $a213;has $a214;has $a215;has $a216;has $a217;has $a218;has $a219;
  has $a220;has $a221;has $a222;has $a223;has $a224;has $a225;has $a226;has $a227;has $a228;has $a229;
  has $a230;has $a231;has $a232;has $a233;has $a234;has $a235;has $a236;has $a237;has $a238;has $a239;
  has $a240;has $a241;has $a242;has $a243;has $a244;has $a245;has $a246;has $a247;has $a248;has $a249;
  has $a250;has $a251;has $a252;has $a253;has $a254;has $a255;has $a256;

  method m {
    print "ok $test # Foo->m\n"; $test++; 
    $a256 + 1
  }
  multi method mul1 (Foo $self, Int $a) {
    print "ok $test # Foo->mul1\n"; $test++;
    $a * $self->a256
  }
}
my $f = new Foo;
$f->a1;
$f->a256 = 1;
print "ok $test # oelem lval\n"; $test++;
print $f->a256 != 1 ? "not " : "", "ok $test # oelem direct\n"; $test++;
print $f->m != 2 ? "not " : "", "ok $test # oelem in method\n"; $test++;
print $f->mul1(2) != 2 ? "not " : "", "ok $test # oelem from method\n"; $test++;
