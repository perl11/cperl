#!./perl

use strict;
use warnings;
use utf8;
use open qw( :utf8 :std );
require q(./test.pl); plan(tests => 1);


=pod

=encoding UTF-8

example taken from: L<http://www.opendylan.org/books/drm/Method_Dispatch>

         옵젳Ṯ
           ^
           |
        ᠠᵮꡠＦᚖᶭ 
         ^    ^
        /      \
   SㄣチenŦ    빞엗ᠠ
      ^          ^
      |          |
 ᠠ텔li겐ț  Hʉ만ӫ읻
       ^        ^
        \      /
         ቩᠠ찬

 define class <SㄣチenŦ> (<life-form>) end class;
 define class <빞엗ᠠ> (<life-form>) end class;
 define class <ᠠ텔li겐ț> (<SㄣチenŦ>) end class;
 define class <Hʉ만ӫ읻> (<빞엗ᠠ>) end class;
 define class <ቩᠠ찬> (<ᠠ텔li겐ț>, <Hʉ만ӫ읻>) end class;

=cut

{
    use utf8 qw(Mongolian Hangul);
    package 옵젳Ṯ;
    use mro 'dfs';

    use utf8 qw(Phags_Pa Ogham);
    package ᠠᵮꡠＦᚖᶭ; # ᠠ
    use mro 'dfs';
    use base '옵젳Ṯ';

    use utf8 qw(Bopomofo Katakana);
    package SㄣチenŦ;
    use mro 'dfs';
    use base 'ᠠᵮꡠＦᚖᶭ';

    package 빞엗ᠠ;
    use mro 'dfs';    
    use base 'ᠠᵮꡠＦᚖᶭ';

    package ᠠ텔li겐ț; # ᠠ
    use mro 'dfs';    
    use base 'SㄣチenŦ';

    use utf8 qw(Cyrillic);
    package Hʉ만ӫ읻;
    use mro 'dfs';    
    use base '빞엗ᠠ';

    use utf8 qw(Ethiopic);
    package ቩᠠ찬; # ᠠ
    use mro 'dfs';    
    use base ('ᠠ텔li겐ț', 'Hʉ만ӫ읻');
}

ok(eq_array(
    mro::get_linear_isa('ቩᠠ찬'),
    [ qw(ቩᠠ찬 ᠠ텔li겐ț SㄣチenŦ ᠠᵮꡠＦᚖᶭ 옵젳Ṯ Hʉ만ӫ읻 빞엗ᠠ) ]
), '... got the right MRO for the ቩᠠ찬 Dylan Example');  
