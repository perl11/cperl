#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
    skip_all_without_unicode_tables();
}

plan tests => 7;

use utf8 qw( Mongolian Georgian );
use open qw( :utf8 :std );

# [perl #19566]: sv_gets writes directly to its argument via
# TARG. Test that we respect SvREADONLY.
use constant roref=>\2;
eval { for (roref) { $_ = <Fʜ> } };
like($@, qr/Modification of a read-only value attempted/, '[perl #19566]');

# [perl #21628]
{
  my $file = tempfile();
  open Ạ,'+>',$file; $a = 3;
  is($a .= <Ạ>, 3, '#21628 - $a .= <A> , A eof');
  close Ạ; $a = 4;
  is($a .= <Ạ>, 4, '#21628 - $a .= <A> , A closed');
}

use strict;
my $err;
{ # ᕝ => ᠠ
  open ᠠ, '.' and binmode ᠠ and sysread ᠠ, $_, 1;
  $err = $! + 0;
  close ᠠ;
}

SKIP: {
  skip "you can read directories as plain files", 2 unless( $err );

  $!=0;
  open ᠠ, '.' and $_=<ᠠ>;
  ok( $!==$err && !defined($_) => 'readline( DIRECTORY )' );
  close ᠠ;

  $!=0;
  { local $/;
    open ᠠ, '.' and $_=<ᠠ>;
    ok( $!==$err && !defined($_) => 'readline( DIRECTORY ) slurp mode' );
    close ᠠ;
  }
}

my $obj = bless [], "Ȼლ"; # ᔆ
$obj .= <DATA>;
like($obj, qr/Ȼლ=ARRAY.*world/u, 'rcatline and refs');

{
    my $file = tempfile();
    open my $out_fh, ">", $file;
    print { $out_fh } "Data\n";
    close $out_fh;

    open Føø, "<", $file;
    is( scalar(<Føø>), "Data\n", "readline() works correctly on UTF-8 filehandles" );
    close Føø;
}

__DATA__
world
