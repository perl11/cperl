# tr_unicode.t
$|=1;

use utf8;

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
    eval { eval "require unicore::Name; 1"; } or
      skip_all_if_miniperl("unicore::Name not built with miniperl");
}

plan tests => 3;

eval 'tr/a/\N{KATAKANA LETTER AINU P}/;';
like $@,
     qr/\\N\{KATAKANA LETTER AINU P} must not be a named sequence in transliteration operator/,
     "Illegal to tr/// named sequence";

# before cperl NODEFAULT_SHAREKEYS the key was guaranteed to be COW. But not anymore
# ($s) = keys %{{pie => 3}};
my $x = "x" x 2_000;
my $s = $x;

SKIP: {
    if (!eval { require XS::APItest }) { skip "no XS::APItest", 2 }
    my $wasro = XS::APItest::SvIsCOW($s);
    ok $wasro, "have a COW";
    $s =~ tr/i//;
    ok( XS::APItest::SvIsCOW($s),
       "count-only tr doesn't deCOW COWs" );
}

1;
