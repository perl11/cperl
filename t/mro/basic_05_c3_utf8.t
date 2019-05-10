#!./perl

use strict;
use warnings;
use utf8 qw( Mongolian Runic Myanmar );
use open qw( :utf8 :std );

require q(./test.pl); plan(tests => 2);

=pod

This tests a strange bug found by Matt S. Trout
while building DBIx::Class. Thanks Matt!!!!

   <A>
  /   \
<C>   <B>
  \   /
   <D>

=cut

{
    package Ｄiᚪၚd_A;
    use mro 'c3';

    sub ᠠ { 'Ｄiᚪၚd_A::ᠠ' } # ᕘ
}
{
    package Ｄiᚪၚd_B;
    use base 'Ｄiᚪၚd_A';
    use mro 'c3';

    sub ᠠ { 'Ｄiᚪၚd_B::ᠠ => ' . (shift)->SUPER::ᠠ }
}
{
    package Ｄiᚪၚd_C;
    use mro 'c3';
    use base 'Ｄiᚪၚd_A';

}
{
    package Ｄiᚪၚd_D;
    use base ('Ｄiᚪၚd_C', 'Ｄiᚪၚd_B');
    use mro 'c3';

    sub ᠠ { 'Ｄiᚪၚd_D::ᠠ => ' . (shift)->SUPER::ᠠ }
}

ok(eq_array(
    mro::get_linear_isa('Ｄiᚪၚd_D'),
    [ qw(Ｄiᚪၚd_D Ｄiᚪၚd_C Ｄiᚪၚd_B Ｄiᚪၚd_A) ]
), '... got the right MRO for Ｄiᚪၚd_D');

is(Ｄiᚪၚd_D->ᠠ,
   'Ｄiᚪၚd_D::ᠠ => Ｄiᚪၚd_B::ᠠ => Ｄiᚪၚd_A::ᠠ',
   '... got the right next::method dispatch path');
