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
        ᓕᵮꡠＦᚖᶭ 
         ^    ^
        /      \
   SㄣチenŦ    빞엗ᱞ
      ^          ^
      |          |
 ᕟ텔li겐ț  Hʉ만ӫ읻
       ^        ^
        \      /
         ቩᓪ찬

 define class <SㄣチenŦ> (<life-form>) end class;
 define class <빞엗ᱞ> (<life-form>) end class;
 define class <ᕟ텔li겐ț> (<SㄣチenŦ>) end class;
 define class <Hʉ만ӫ읻> (<빞엗ᱞ>) end class;
 define class <ቩᓪ찬> (<ᕟ텔li겐ț>, <Hʉ만ӫ읻>) end class;

=cut

{
    use utf8 qw(Canadian_Aboriginal Hangul);
    package 옵젳Ṯ;
    use mro 'dfs';

    use utf8 qw(Phags_Pa Ogham);
    package ᓕᵮꡠＦᚖᶭ;
    use mro 'dfs';
    use base '옵젳Ṯ';

    use utf8 qw(Bopomofo Katakana);
    package SㄣチenŦ;
    use mro 'dfs';
    use base 'ᓕᵮꡠＦᚖᶭ';

    use utf8 qw(Ol_Chiki);
    package 빞엗ᱞ;
    use mro 'dfs';    
    use base 'ᓕᵮꡠＦᚖᶭ';

    package ᕟ텔li겐ț;
    use mro 'dfs';    
    use base 'SㄣチenŦ';

    use utf8 qw(Cyrillic);
    package Hʉ만ӫ읻;
    use mro 'dfs';    
    use base '빞엗ᱞ';

    use utf8 qw(Ethiopic);
    package ቩᓪ찬;
    use mro 'dfs';    
    use base ('ᕟ텔li겐ț', 'Hʉ만ӫ읻');
}

ok(eq_array(
    mro::get_linear_isa('ቩᓪ찬'),
    [ qw(ቩᓪ찬 ᕟ텔li겐ț SㄣチenŦ ᓕᵮꡠＦᚖᶭ 옵젳Ṯ Hʉ만ӫ읻 빞엗ᱞ) ]
), '... got the right MRO for the ቩᓪ찬 Dylan Example');  
