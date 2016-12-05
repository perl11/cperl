#!./perl

# Checks if identifiers with combining marks and more are properly
# NFC normalized. (cperl only)
# All possible identifiers: variables, sub, format, packages, global,
# my, our state, label, lexsubs.
# 

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    skip_all_if_miniperl("miniperl, no Unicode::Normalize");
    skip_all_without_unicode_tables();
}

use 5.025;
use cperl;
use utf8;
use Unicode::Normalize qw(NFC NFD);

# see also NormalizationTests.txt or perl6 roast S15-normalization/nfc-0.t
# but we test just all exhaustively
my @nfc;
for my $c (1 .. 1000) { # 0x10_FFFF) {
    my $s = chr($c);
    my $nfd = NFD($s);
    # all valid identifiers, which have a different NFD: marks, diacrits, ...
    if ($s =~ /\p{IDStart}/ && NFC($s) ne $nfd) {
        push @nfc, $nfd => NFC($s);
    } elsif ($s =~ /\p{IDContinue}/ && NFC($s) ne $nfd) {
        push @nfc, "A".$nfd => "A".NFC($s);
    }
}

plan (tests => 11 * (scalar(@nfc)/2));
use B;
{
    my $i = 1;
    no strict;
    while (@nfc) {
        my $from = shift @nfc;
        my $to   = shift @nfc;
        my $qfrom = join("",map{sprintf"\\x{%x}",$_}unpack"U*",$from);
        my $qto   = join("",map{sprintf"\\x{%x}",$_}unpack"U*",$to);

        # pv_uni_normalize currently used in 7 places
        local $@;
        my ($orig, $norm, $gv) = eval "\${$from} = $i; (\${$from}, \${$to}, *{$from})";
        is( $orig, $i, "orig global var \${$qfrom}" );
        is( $norm, $i, "norm global var \${$qto}" );
        my $b = B::svref_2object(\$gv);
        if (ref $b eq 'B::GV') {
            is( $b->NAME, $to, "normalized name $from => $to" );
        } else {
            is( ref $b, 'B::GV');
        }
        $i++;

        ($orig, $norm, $gv) = eval "sub $from {$i}; ($from(), $to(), *{$from})";
        is( $orig, $i, "orig sub $qfrom" );
        is( $norm, $i, "norm sub $qto" );
        #$b = B::svref_2object(\$gv);
        #is( $b->CV->NAME, $to, "normalized name $to" );
        $i++;
        
        ($orig, $norm, $gv) = eval "sub $from () {$i}; ($from(), $to(), *{$from})";
        is( $orig, $i, "orig const sub $qfrom" );
        is( $norm, $i, "norm const sub $qto" );
        #$b = B::svref_2object(\$gv);
        #is( $b->CV->NAME, $to, "normalized name $to" );
        $i++;

        # intuit_method
        ($orig, $norm, $gv) = eval "package PKG_$from; sub $from {$i};".
                                   "(PKG_$from $from, PKG_$from $to, *{$from})";
        is( $orig, $i, "orig intuit method $qfrom" );
        is( $norm, $i, "norm intuit method $qto" );
        $i++;
        
        ($orig, $norm) = eval "my \${$from}=$i; (\${$from}, \${$to})";
        is( $orig, $i, "orig lex \${$qfrom}" );
        is( $norm, $i, "norm lex \${$qto}" );
        $i++;
    }
}

# all non-mark letters which differ in NFC to NFD:
# $ unichars '\PM' \pL' 'NFC ne NFD'
