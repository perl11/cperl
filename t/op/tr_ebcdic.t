# tr_unicode.t
$|=1;

use utf8;

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
    skip_all("Valid only for EBCDIC") unless $::IS_EBCDIC;
    eval { eval "require unicore::Name; 1"; } or
      skip_all_if_miniperl("unicore::Name not built with miniperl");
}

plan tests => 9;

# Test literal range end point special handling

$_ = "\x89";    # is 'i'
tr/i-\N{LATIN SMALL LETTER J}//d;
is($_, "", '"\x89" should match [i-\N{LATIN SMALL LETTER J}]');
$_ = "\x8A";
tr/i-\N{LATIN SMALL LETTER J}//d;
is($_, "\x8A", '"\x8A" shouldnt match [i-\N{LATIN SMALL LETTER J}]');
$_ = "\x90";
tr/i-\N{LATIN SMALL LETTER J}//d;
is($_, "\x90", '"\x90" shouldnt match [i-\N{LATIN SMALL LETTER J}]');
$_ = "\x91";    # is 'j'
tr/i-\N{LATIN SMALL LETTER J}//d;
is($_, "", '"\x91" should match [i-\N{LATIN SMALL LETTER J}]');

# In EBCDIC 'I' is \xc9 and 'J' is \0xd1, 'i' is \x89 and 'j' is \x91.
# Yes, discontinuities.  Regardless, the \xca in the below should stay
# untouched (and not became \x8a).
{
    $_ = "I\xcaJ";

    tr/I-J/i-j/;

    is($_, "i\xcaj",    'EBCDIC discontinuity');
}

($x = 256.193.258) =~ tr/a/b/;
is(length $x, 3);
is($x, 256.193.258);

$x =~ tr/A/B/;
is(length $x, 3);
is($x, 256.194.258);

1;
