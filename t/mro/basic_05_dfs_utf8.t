#!./perl

use strict;
use warnings;

use utf8;
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
    package Łi_A;
    use mro 'dfs';

    sub Ḋ { 'Łi_A::Ḋ' }
}
{
    package Łi_B;
    use base 'Łi_A';
    use mro 'dfs';

    sub Ḋ { 'Łi_B::Ḋ => ' . (shift)->SUPER::Ḋ }
}
{
    package Łi_C;
    use mro 'dfs';
    use base 'Łi_A';

}
{
    package Łi_D;
    use base ('Łi_C', 'Łi_B');
    use mro 'dfs';

    sub Ḋ { 'Łi_D::Ḋ => ' . (shift)->SUPER::Ḋ }
}

ok(eq_array(
    mro::get_linear_isa('Łi_D'),
    [ qw(Łi_D Łi_C Łi_A Łi_B) ]
), '... got the right MRO for Łi_D');

is(Łi_D->Ḋ,
   'Łi_D::Ḋ => Łi_A::Ḋ',
   '... got the right next::method dispatch path');
