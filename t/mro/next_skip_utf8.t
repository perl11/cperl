#!/usr/bin/perl

use strict;
use warnings;

require q(./test.pl); plan(tests => 10);

use utf8;
use open qw( :utf8 :std );

=pod

This tests the classic diamond inheritance pattern.

   <A>
  /   \
<B>   <C>
  \   /
   <D>

=cut

{
    package FÒÒ_A;
    use mro 'c3';
    sub ᴮaȐ { 'FÒÒ_A::ᴮaȐ' }
    sub ки { 'FÒÒ_A::ки' }
}
{
    package FÒÒ_B;
    use base 'FÒÒ_A';
    use mro 'c3';
    sub ки { 'FÒÒ_B::ки => ' . (shift)->next::method() }
}
{
    package FÒÒ_C;
    use mro 'c3';
    use base 'FÒÒ_A';
    sub Bаи { 'FÒÒ_C::Bаи' }
    sub buƵ { 'FÒÒ_C::buƵ' }

    sub woｚ { 'FÒÒ_C::woｚ' }
    sub maybé { 'FÒÒ_C::maybé' }
}
{
    package FÒÒ_D;
    use base ('FÒÒ_B', 'FÒÒ_C');
    use mro 'c3';
    sub Bаи { 'FÒÒ_D::Bаи => ' . (shift)->next::method() }
    sub ᴮaȐ { 'FÒÒ_D::ᴮaȐ => ' . (shift)->next::method() }
    sub buƵ { 'FÒÒ_D::buƵ => ' . (shift)->ки() }
    sub fuz { 'FÒÒ_D::fuz => ' . (shift)->next::method() }

    sub woｚ { 'FÒÒ_D::woｚ can => ' . ((shift)->next::can() ? 1 : 0) }
    sub noz { 'FÒÒ_D::noz can => ' . ((shift)->next::can() ? 1 : 0) }

    sub maybé { 'FÒÒ_D::maybé => ' . ((shift)->maybe::next::method() || 0) }
    sub Noël { 'FÒÒ_D::Noël => ' .    ((shift)->maybe::next::method() || 0) }

}

ok(eq_array(
    mro::get_linear_isa('FÒÒ_D'),
    [ qw(FÒÒ_D FÒÒ_B FÒÒ_C FÒÒ_A) ]
), '... got the right MRO for FÒÒ_D');

is(FÒÒ_D->Bаи, 'FÒÒ_D::Bаи => FÒÒ_C::Bаи', '... skipped B and went to C correctly');
is(FÒÒ_D->ᴮaȐ, 'FÒÒ_D::ᴮaȐ => FÒÒ_A::ᴮaȐ', '... skipped B & C and went to A correctly');
is(FÒÒ_D->ки, 'FÒÒ_B::ки => FÒÒ_A::ки', '... called B method, skipped C and went to A correctly');
is(FÒÒ_D->buƵ, 'FÒÒ_D::buƵ => FÒÒ_B::ки => FÒÒ_A::ки', '... called D method dispatched to , different method correctly');
eval { FÒÒ_D->fuz };
like($@, qr/^No next::method 'fuz' found for FÒÒ_D/u, '... cannot re-dispatch to a method which is not there');
is(FÒÒ_D->woｚ, 'FÒÒ_D::woｚ can => 1', '... can re-dispatch figured out correctly');
is(FÒÒ_D->noz, 'FÒÒ_D::noz can => 0', '... cannot re-dispatch figured out correctly');

is(FÒÒ_D->maybé, 'FÒÒ_D::maybé => FÒÒ_C::maybé', '... redispatched D to C when it exists');
is(FÒÒ_D->Noël, 'FÒÒ_D::Noël => 0', '... quietly failed redispatch from D');
