#!./perl

use strict;
use warnings;
use utf8;
use open qw( :utf8 :std );

require q(./test.pl); plan(tests => 1);

=pod

=encoding UTF-8

From the parrot test t/pmc/object-meths.t, with cleaned up names

 Ả   Ɓ Ả   Ẻ
  \ /   \ /
   ƈ     Ḋ
    \   /
     \ /
      Ḟ

=cut

{
    package Ƭ::ŁiƁ::Ả; use mro 'dfs';
    package Ƭ::ŁiƁ::Ɓ; use mro 'dfs';
    package Ƭ::ŁiƁ::Ẻ; use mro 'dfs';
    package Ƭ::ŁiƁ::ƈ; use mro 'dfs'; use base ('Ƭ::ŁiƁ::Ả', 'Ƭ::ŁiƁ::Ɓ');
    package Ƭ::ŁiƁ::Ḋ; use mro 'dfs'; use base ('Ƭ::ŁiƁ::Ả', 'Ƭ::ŁiƁ::Ẻ');
    package Ƭ::ŁiƁ::Ḟ; use mro 'dfs'; use base ('Ƭ::ŁiƁ::ƈ', 'Ƭ::ŁiƁ::Ḋ');
}

ok(eq_array(
    mro::get_linear_isa('Ƭ::ŁiƁ::Ḟ'),
    [ qw(Ƭ::ŁiƁ::Ḟ Ƭ::ŁiƁ::ƈ Ƭ::ŁiƁ::Ả Ƭ::ŁiƁ::Ɓ Ƭ::ŁiƁ::Ḋ Ƭ::ŁiƁ::Ẻ) ]
), '... got the right MRO for Ƭ::ŁiƁ::Ḟ');

