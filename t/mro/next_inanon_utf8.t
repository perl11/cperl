#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use open qw( :utf8 :std );
require q(./test.pl); plan(tests => 2);

=pod

This tests the successful handling of a next::method call from within an
anonymous subroutine.

=cut

{
    package ки;
    use mro 'c3';

    sub Bаи {
      return 'ки::Bаи';
    }

    sub FÒÒ {
      return 'ки::FÒÒ';
    }
}

{
    package Ḃ;
    use base 'ки';
    use mro 'c3';

    sub Bаи {
      my $code = sub {
        return 'Ḃ::Bаи => ' . (shift)->next::method();
      };
      return (shift)->$code;
    }

    sub FÒÒ {
      my $code1 = sub {
        my $code2 = sub {
          return 'Ḃ::FÒÒ => ' . (shift)->next::method();
        };
        return (shift)->$code2;
      };
      return (shift)->$code1;
    }
}

is(Ḃ->Bаи, "Ḃ::Bаи => ки::Bаи",
   'method resolved inside anonymous sub');

is(Ḃ->FÒÒ, "Ḃ::FÒÒ => ки::FÒÒ",
   'method resolved inside nested anonymous subs');


