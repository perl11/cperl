#!./perl

BEGIN {
    unless (-d 'blib') {
        chdir 't' if -d 't';
    }
    require './test.pl';
    set_up_inc('../lib');
}

use utf8 qw( Hangul Mongolian Ethiopic Runic );
use open qw( :utf8 :std );
use strict;
use warnings;
no warnings 'redefine'; # we do a lot of this
no warnings 'prototype'; # we do a lot of this

{
    package MC텟ᵀ::Bᠠᶓ;
    sub ᠠ { return $_[1]+1 };

    package MC텟ᵀ::ድ리ᠠᛞ;
    our @ISA = qw/MC텟ᵀ::Bᠠᶓ/;

    package Ƒｏｏ; our @ƑＯＯ = qw//;
}

# These are various ways of re-defining MC텟ᵀ::Bᠠᶓ::ᠠ and checking whether the method is cached when it shouldn't be
my @testsubs = (
    sub { is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 1); },
    sub { eval 'sub MC텟ᵀ::Bᠠᶓ::ᠠ { return $_[1]+2 }'; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 2); },
    sub { eval 'sub MC텟ᵀ::Bᠠᶓ::ᠠ($) { return $_[1]+3 }'; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 3); },
    sub { eval 'sub MC텟ᵀ::Bᠠᶓ::ᠠ($) { 4 }'; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 4); },
    sub { *MC텟ᵀ::Bᠠᶓ::ᠠ = sub { $_[1]+5 }; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 5); },
    sub { local *MC텟ᵀ::Bᠠᶓ::ᠠ = sub { $_[1]+6 }; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 6); },
    sub { is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 5); },
    sub { sub FFF { $_[1]+7 }; local *MC텟ᵀ::Bᠠᶓ::ᠠ = *FFF; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 7); },
    sub { is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 5); },
    sub { sub DḊƋ { $_[1]+8 }; *MC텟ᵀ::Bᠠᶓ::ᠠ = *DḊƋ; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 8); },
    sub { *ǎXɗＦ::앗ｄƑ = sub { $_[1]+9 }; *MC텟ᵀ::Bᠠᶓ::ᠠ = \&ǎXɗＦ::앗ｄƑ; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 9); },
    sub { undef *MC텟ᵀ::Bᠠᶓ::ᠠ; eval { MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0) }; like($@, qr/locate object method/); },
    sub { eval 'sub MC텟ᵀ::Bᠠᶓ::ᠠ($);'; *MC텟ᵀ::Bᠠᶓ::ᠠ = \&ǎXɗＦ::앗ｄƑ; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 9); },
    sub { *Xƴƶ = sub { $_[1]+10 }; ${MC텟ᵀ::Bᠠᶓ::}{ᠠ} = \&Xƴƶ; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 10); },
    sub { ${MC텟ᵀ::Bᠠᶓ::}{ᠠ} = sub { $_[1]+11 }; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 11); },

    sub { undef *MC텟ᵀ::Bᠠᶓ::ᠠ; eval { MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0) }; like($@, qr/locate object method/); },
    sub { eval 'package MC텟ᵀ::Bᠠᶓ; sub ᠠ { $_[1]+12 }'; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 12); },
    sub { eval 'package ᛎᛎᛎ; sub ᠠ { $_[1]+13 }'; *MC텟ᵀ::Bᠠᶓ::ᠠ = \&ᛎᛎᛎ::ᠠ; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 13); },
    sub { ${MC텟ᵀ::Bᠠᶓ::}{ᠠ} = sub { $_[1]+14 }; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 14); },
    # 5.8.8 fails this one
    sub { undef *{MC텟ᵀ::Bᠠᶓ::}; eval { MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0) }; like($@, qr/locate object method/); },
    sub { eval 'package MC텟ᵀ::Bᠠᶓ; sub ᠠ { $_[1]+15 }'; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 15); },
    sub { undef %{MC텟ᵀ::Bᠠᶓ::}; eval { MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0) }; like($@, qr/locate object method/); },
    sub { eval 'package MC텟ᵀ::Bᠠᶓ; sub ᠠ { $_[1]+16 }'; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 16); },
    sub { %{MC텟ᵀ::Bᠠᶓ::} = (); eval { MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0) }; like($@, qr/locate object method/); },
    sub { eval 'package MC텟ᵀ::Bᠠᶓ; sub ᠠ { $_[1]+17 }'; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 17); },
    # 5.8.8 fails this one too
#TODO: This fails due to the tokenizer not being clean, rather than mro.
    sub { *{MC텟ᵀ::Bᠠᶓ::} = *{Ƒｏｏ::}; eval { MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0) }; like($@, qr/locate object method/); },
    sub { *MC텟ᵀ::ድ리ᠠᛞ::ᠠ = \&MC텟ᵀ::Bᠠᶓ::ᠠ; eval { MC텟ᵀ::ድ리ᠠᛞ::ᠠ(0,0) }; ok(!$@); undef *MC텟ᵀ::ድ리ᠠᛞ::ᠠ },
    sub { eval 'package MC텟ᵀ::Bᠠᶓ; sub ᠠ { $_[1]+18 }'; is(MC텟ᵀ::ድ리ᠠᛞ->ᠠ(0), 18); },
);

plan(tests => scalar(@testsubs));

$_->() for (@testsubs);
