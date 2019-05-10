#!./perl

BEGIN {
    unless (-d 'blib') {
        chdir 't' if -d 't';
    }
    require q(./test.pl);
    set_up_inc('../lib');
}

use strict;
use warnings;
use utf8 qw(Hangul Cyrillic Bengali Georgian Hiragana Thai Tamil Bopomofo
            Gujarati Lao Katakana Runic Phags_Pa Armenian Malayalam
            Mongolian Ethiopic Oriya Ogham Buhid Devanagari );
use open qw( :utf8 :std );

plan(tests => 24);

use mro;

sub i {
 my @args = @_;
 @_
  = (
     join(" ", sort @{mro::get_isarev $args[0]}),
     join(" ", sort @args[1..$#args-1]),
     pop @args
    );
 goto &is;
}

# Basic isarev updating, when @ISA changes
@팟tРṉ::ISA = "B옫yპt::ぅงலҬ";
@S추ঋ::ISA    = "B옫yპt::ぅงலҬ";
@B옫yპt::ぅงலҬ::ISA = "B옫yპt";
i B옫yპt => qw [ B옫yპt::ぅงலҬ 팟tРṉ S추ঋ ],
 'subclasses and subsubclasses are added to isarev';
@팟tРṉ::ISA = ();
i B옫yპt => qw [ B옫yპt::ぅงலҬ S추ঋ ],
 'single deletion from isarev';
@B옫yპt::ぅงலҬ::ISA = ();
i B옫yპt => qw [ ], 'recursive deletion from isarev';
                      # except underneath it is not actually recursive


# More complicated tests that move packages around

@훗ㄎએỲ::ISA = "독";
@독::ISA = "ㄘა읻";
@ວlƑ::ISA = "ㄘა읻";
@솜ｪ::ƀ란ƌ::ᚿamㅔ::ISA = "독::ㄅ";
@독::ㄅ::ISA = "TﾚӔṪ";
@Frȇe::팀ẽ::ISA = "TﾚӔṪ";
@Ｍy촐ꡙʳ::ISA = "독::ցളŔ::Leaʇhㄦ";
@독::ցളŔ::Leaʇhㄦ::ISA = "ցളŔ";
@AŇℴtḫeᠠ::ցളŔ::ISA = "ցളŔ";
*팈ዕ:: = *독::;
delete $::{"독::"};
i ㄘა읻=>qw[ ວlƑ 팈ዕ ],
 "deleting a stash elem updates isarev entries";
i TﾚӔṪ=>qw[ Frȇe::팀ẽ 팈ዕ::ㄅ ],
 "deleting a nested stash elem updates isarev entries";
i ցളŔ=>qw[ AŇℴtḫeᠠ::ցളŔ 팈ዕ::ցളŔ::Leaʇhㄦ ],
 "deleting a doubly nested stash elem updates isarev entries";

@ごଅｔ::ISA = "ぅงலҬ";
@ごଅｔ::DଐɾẎ::ISA = "ごଅｔ";
@ごଅｔ::DଐɾẎ::Ⱦ옥ゲᠠƃᚒḠ::ISA = "ごଅｔ::DଐɾẎ";
@웨ɪrƌ::ጢᶯᵷ::ISA = "ｇ";
*ｇ:: = *ごଅｔ::;
i ごଅｔ => qw[ ごଅｔ::DଐɾẎ ごଅｔ::DଐɾẎ::Ⱦ옥ゲᠠƃᚒḠ 웨ɪrƌ::ጢᶯᵷ ],
 "isarev includes subclasses of aliases";
delete $::{"ｇ::"};
i ぅงலҬ => qw[ ごଅｔ ごଅｔ::DଐɾẎ ごଅｔ::DଐɾẎ::Ⱦ옥ゲᠠƃᚒḠ ],
 "deleting an alias to a package updates isarev entries";
i"ごଅｔ" => qw[ ごଅｔ::DଐɾẎ ごଅｔ::DଐɾẎ::Ⱦ옥ゲᠠƃᚒḠ ],
 "deleting an alias to a package updates isarev entries of nested stashes";
i"ごଅｔ::DଐɾẎ" => qw[ ごଅｔ::DଐɾẎ::Ⱦ옥ゲᠠƃᚒḠ ],
 "deleting an stash alias updates isarev entries of doubly nested stashes";
i ｇ => qw [ 웨ɪrƌ::ጢᶯᵷ ],
 "subclasses of the deleted alias become part of its isarev";

@챂린ẽ::ISA = "Hഓf엗::맘말";
@챂린ẽ::DଐɾẎ::ISA = "챂린ẽ";
@챂린ẽ::DଐɾẎ::Obｪʶ핫l::ISA = "챂린ẽ::DଐɾẎ";
@ẂhaƮᵋቭȓ::ISA = "챂린ẽ";
*챂릳:: = *챂린ẽ::;
*챂린ẽ:: = *ㄔɘvレ::;
i"Hഓf엗::맘말" => qw[ 챂릳 ],
 "replacing a stash updates isarev entries";
i ㄔɘvレ => qw[ 챂릳::DଐɾẎ ẂhaƮᵋቭȓ ],
 "replacing nested stashes updates isarev entries";

@ᛑiስアsઍ::ｪᠠ::ISA = "ᛑiስアsઍ";
@ᛑiስアsઍ::ｪᠠ::Iṇᚠctĭo웃::ISA = "ᛑiስアsઍ::ｪᠠ";
@Kㄦat옻oǌ운ctᝁヸቲᠠ::ISA = "ᛑiስアsઍ::Opɥt할및::Iṇᚠctĭo웃";
*ᛑiስアsઍ::Opɥt할및:: = *ᛑiስアsઍ::ｪᠠ::;
{package 솜e_란돔_new_symbol::Iṇᚠctĭo웃} # autovivify
*ᛑiስアsઍ::Opɥt할및:: = *솜e_란돔_new_symbol::;
i ᛑiስアsઍ => qw[ ᛑiስアsઍ::ｪᠠ ᛑiስアsઍ::ｪᠠ::Iṇᚠctĭo웃 ],
 "replacing an alias of a stash updates isarev entries";
i"ᛑiስアsઍ::ｪᠠ" => qw[ ᛑiስアsઍ::ｪᠠ::Iṇᚠctĭo웃 ],
 "replacing an alias of a stash containing another updates isarev entries";
i"솜e_란돔_new_symbol::Iṇᚠctĭo웃" => qw[ Kㄦat옻oǌ운ctᝁヸቲᠠ ],
 "replacing an alias updates isarev of stashes nested in the replacement";

# Globs ending with :: have autovivified stashes in them by default. We
# want one without a stash.
undef *Eṁpｔᠠ::;
@눌Ļ::ISA = "Eṁpｔᠠ";
@눌Ļ::눌Ļ::ISA = "Eṁpｔᠠ::Eṁpｔᠠ";
{package ዚlcᠠ::Eṁpｔᠠ} # autovivify it
*Eṁpｔᠠ:: = *ዚlcᠠ::;
i ዚlcᠠ => qw[ 눌Ļ ], "assigning to an empty spot updates isarev";
i"ዚlcᠠ::Eṁpｔᠠ" => qw[ 눌Ļ::눌Ļ ],
 "assigning to an empty spot updates isarev of nested packages";

# Classes inheriting from multiple classes that get moved in a single
# assignment.
@ᠠ::ISA = ("ᵇ", "ᵇ::ᵇ");
{package अ::ᵇ}
my $अ = \%अ::;     # keep a ref
*अ:: = 'whatever'; # clobber it
*ᵇ:: = $अ;         # assign to two superclasses of ᠠ at the same time
# There should be no अ::ᵇ isarev entry.
i"अ::ᵇ" => qw [], 'assigning to two superclasses at the same time';
ok !ᠠ->isa("अ::ᵇ"),
 "A class must not inherit from its superclass’s former name";

# undeffing globs
@а::ISA = 'xᠠ';
$_ = \*а::ISA;    # hang on to the glob
undef *а::ISA;
i xᠠ => qw [], "undeffing an ISA glob deletes isarev entries";
@aᠠ::ISA = '붘ㆉ';
$_ = \*aᠠ::ISA;
undef *aᠠ::;
i 붘ㆉ => qw [], "undeffing a package glob deletes isarev entries";

# Package aliasing/clobbering when the clobbered package has grandchildren
# by inheritance.
@Ƚ::ISA = 'ภɵ';
@숩Ȼl았A::ISA = "숩Ȼl았Ƃ";
@숩Ȼl았Ƃ::ISA = "Ƚ";
*Ƚ:: = *bᚪᶼ::;
i ภɵ => qw [],
 'clobbering a class w/multiple layers of subclasses updates its parent';

@ᠠ랕::ISA = 'S민';
%ᠠ랕:: = ();
i S민 => qw [], '%Package:: list assignment';
