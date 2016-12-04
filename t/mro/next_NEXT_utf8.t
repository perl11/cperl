#!/usr/bin/perl

use strict;
use warnings;
use NEXT;
use utf8;
use open qw( :utf8 :std );

chdir 't' if -d 't';
require './test.pl';
plan(tests => 4);

{
    package и;
    use strict;
    use warnings;
    use mro 'c3';

    sub ки { 'и::ки' }

    package Fᶽ;
    use strict;
    use warnings;
    use mro 'c3';
    use base 'и';

    sub ки { 'Fᶽ::ки => ' . (shift)->next::method }

    package BÒ;
    use strict;
    use warnings;
    use mro 'c3';
    use base 'и';

    sub ки { 'BÒ::ки => ' . (shift)->next::method }

    package Bаи;
    use strict;
    use warnings;

    use base 'BÒ', 'Fᶽ';

    sub ки { 'Bаи::ки => ' . (shift)->NEXT::ки }
}

is(и->ки, 'и::ки', '... got the right value from и->ки');
is(Fᶽ->ки, 'Fᶽ::ки => и::ки', '... got the right value from Fᶽ->ки');
is(BÒ->ки, 'BÒ::ки => и::ки', '... got the right value from BÒ->ки');

is(Bаи->ки, 'Bаи::ки => BÒ::ки => Fᶽ::ки => и::ки', '... got the right value using NEXT in a subclass of a C3 class');

