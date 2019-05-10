#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use utf8 qw(Thai Hangul Lao Bopomofo Mongolian Ethiopic);
use open qw( :utf8 :std );

plan 12;

@ฟ옥ʮ::ISA = "ᶶ";
*ຜ옥ㄏ::ISA = *ฟ옥ʮ::ISA;
@ฟ옥ʮ::ISA = "Ｂᐊㄗ";

ok 'ฟ옥ʮ'->isa("Ｂᐊㄗ"),
 'isa after another stash has claimed the @ISA via glob assignment';
ok 'ຜ옥ㄏ'->isa("Ｂᐊㄗ"),
 'isa on the stash that claimed the @ISA via glob assignment';
ok !ฟ옥ʮ->isa("ᶶ"),
 '!isa when another stash has claimed the @ISA via glob assignment';
ok !ຜ옥ㄏ->isa("ᶶ"),
 '!isa on the stash that claimed the @ISA via glob assignment';

@ฟ옥ʮ::ISA = "ᶶ";
*ฟ옥ʮ::ISA = ["Ｂᐊㄗ"];

ok 'ฟ옥ʮ'->isa("Ｂᐊㄗ"),
 'isa after glob-to-ref assignment when *ISA is shared';
ok 'ຜ옥ㄏ'->isa("Ｂᐊㄗ"),
 'isa after glob-to-ref assignment on another stash when *ISA is shared';
ok !ฟ옥ʮ->isa("ᶶ"),
 '!isa after glob-to-ref assignment when *ISA is shared';
ok !ຜ옥ㄏ->isa("ᶶ"),
 '!isa after glob-to-ref assignment on another stash when *ISA is shared';

@ᠠ::ISA = "ᶶ";
*ጶ::ISA = \@ᠠ::ISA;
@ᠠ::ISA = "Ｂᐊㄗ";

ok 'ᠠ'->isa("Ｂᐊㄗ"),
 'isa after another stash has claimed the @ISA via ref-to-glob assignment';
ok 'ጶ'->isa("Ｂᐊㄗ"),
 'isa on the stash that claimed the @ISA via ref-to-glob assignment';
ok !ᠠ->isa("ᶶ"),
 '!isa when another stash has claimed the @ISA via ref-to-glob assignment';
ok !ጶ->isa("ᶶ"),
 '!isa on the stash that claimed the @ISA via ref-to-glob assignment';
