#!./perl

# Checks if all identifiers with combining marks are properly
# NFC normalized. (cperl only)
#
# All possible parsed identifiers: variables, sub, format, packages, global,
# my, our state, label, lexsubs.
# Also checks strict names, the valid_ident API.
# 

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    skip_all_if_miniperl("miniperl, no Unicode::Normalize");
    skip_all_without_unicode_tables();
}

use 5.025;
use cperl;
use utf8 'Greek';
use Unicode::Normalize qw(NFC NFD);
use B;
utf8->import(keys %utf8::VALID_SCRIPTS);

# 866 non-mark letters which differ in NFC to NFD:
# $ unichars '\PM' '\pL' 'NFC ne NFD'

# see also NormalizationTests.txt or perl6 roast S15-normalization/nfc-0.t
# but we test just all exhaustively
my @nfc;
#for my $c (1) {
#for my $c (980 .. 1025) {
for my $c (1 .. 0x10FFFF) {
    my $s = chr($c);
    my $nfd = NFD($s);
    # all valid identifiers, which have a different NFD: marks, diacrits, ...
    if ($s =~ /\p{IDStart}/ && NFC($s) ne $nfd) {
        push @nfc, $nfd => NFC($s);
    } elsif ($s =~ /\p{IDContinue}/ && NFC($s) ne $nfd) {
        push @nfc, "A".$nfd => "A".NFC($s);
    }
    # => 12076 confusables
}

plan (tests => 24 + (scalar(@nfc)/2));
my $i = 1;

# first check if _is_utf8_decomposed() catches all characters for pv_uni_normalize.
no strict;
while (@nfc) {
    my $from  = shift @nfc;
    my $to    = shift @nfc;
    my $qfrom = join("",map{sprintf"\\x{%X}",$_}unpack"U*",$from);
    my $qto   = join("",map{sprintf"\\x{%X}",$_}unpack"U*",$to);
    my $norm = 0;
    # ϔ => ϔ \x3d2\x308 (cf 92, cc 88) => \x3d4 (cf 94) (\317\222 \314\210 => \317\224)
    # Ѐ => Ѐ   \x415\x300 (d0 95, cc 80) => \x400         (\320\225 \314\200 => \320\200)
    eval "\$$from=$i;\$norm=\$$to";
    is( $norm, $i, "normalized \$$qfrom => \$$qto")
      or diag "\$$from=$i;\$norm=\$$to";
    $i++;
}

{
    # Then check all 24 places in the lexer for identifiers
    # where pv_uni_normalize is called.
    # E\314\201 (E\x301 45cc81) => \303\211 (\xc9 c389)
    no strict;
    local $@;
    my $from = "É"; # decomposed \x45 \x301
    my $to   = "É"; # composed   \xc9
    my $qfrom = join("",map{sprintf"\\x{%x}",$_}unpack"U*",$from);
    my $qto   = join("",map{sprintf"\\x{%x}",$_}unpack"U*",$to);

    my ($orig, $norm, $gv, $cv);
    ${É} = $i; ($orig, $norm, $gv) = (${É}, ${É}, *É);
    is( $orig, $i, "orig global var \${$qfrom}" );
    is( $norm, $i, "norm global var \${$qto}" );
    my $b = B::svref_2object(\$gv);
    is( $b->NAME, $to, "normalize E+COMBINING ACUTE ACCENT => E WITH ACUTE" );
    $i++;

    $É = $i; ($orig, $norm, $gv) = ($É, $É, *É);
    is( $orig, $i, "orig global var \$$qfrom" );
    is( $norm, $i, "norm global var \$$qto" );
    my $b = B::svref_2object(\$gv);
    is( $b->NAME, $to, "normalize GV E+COMBINING ACUTE ACCENT => E WITH ACUTE" );
    $i++;

    sub É {$i}; $orig = É(); $norm = É(); $cv = \&É;
    is( $orig, $i, "orig sub $qfrom" );
    is( $norm, $i, "norm sub $qto" );
  TODO: {
      local $TODO = "B::CV->NAME_HEK of \\&";
      $b = B::svref_2object($cv);
      is( $b->NAME_HEK, $to, "normalize CV NAME to E WITH ACUTE" );
    }
    $i++;

    # if the parser accepted both names as valid subs
    sub aÉ {$i}; ($orig, $norm) = (aÉ, aÉ);
    is( $orig, $i, "without parens" );
    is( $norm, $i );

    sub bÉ () {$i}; ($orig, $norm, $cv) = (bÉ(), bÉ(), \&bÉ);
    is( $orig, $i, "orig const sub $qfrom" );
    is( $norm, $i, "norm const sub $qto" );
    $b = B::svref_2object($cv);
    is( $b->NAME_HEK, "b".$to, "normalize CV NAME to E WITH ACUTE" );
    $i++;

    sub PKG_É::É {$i};
    $orig = É PKG_É;
    $norm = É PKG_É;
    is( $orig, $i, "orig intuit method $qfrom" );
    is( $norm, $i, "norm intuit method $qto" );
    $i++;
    
    sub PKG_É::É {$i};
    $orig = PKG_É->É;
    $norm = PKG_É->É;
    is( $orig, $i, "orig method $qfrom" );
    is( $norm, $i, "norm method $qto" );

    my $dÉ = $i; $orig = $dÉ; $norm = $dÉ;
    is( $orig, $i, "orig lex \${$qfrom}" );
    is( $norm, $i, "norm lex \${$qto}" );
    $i++;

    ${"eÉ"} = $i; ${"eÉ"} = 0; ($orig, $norm) = (${"eÉ"}, ${"eÉ"});
    if ($] < 5.027001) {
        is( $orig, $i, "dynamic string ref \${\"$qfrom\"}");
    } else {
        # The rv2sv symbol is now also normalized since 5.27.1
        is( $orig, 0, "dynamic string ref \${\"$qto\"} normalized");
    }
    is( $norm, 0,  "normalized");
}

# almost illegal unicode: double combiners
my $qfrom = join("",map{sprintf"\\x{%x}",$_}unpack"U*","É́");
my $qto   = join("",map{sprintf"\\x{%x}",$_}unpack"U*","É́");
# correctly normalized, but shouldn't this warn?
${É́} = $i; ($orig, $norm) = (${É́}, ${É́});
is( $orig, $i, "orig global var \${$qfrom}" );
is( $norm, $i, "norm global var \${$qto}" );
