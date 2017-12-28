package utf8;

$utf8::hint_bits = 0x00800000;

our $VERSION = '2.03c';

sub import {
    shift;
    $^H |= $utf8::hint_bits;
    if (@_) {
        require "utf8_heavy.pl";
        for my $s (@_) {
            if (valid_script($s)) {
                # warn for the Moderately Restrictive level profile
                if (($s eq 'Greek' and $utf8::SCRIPTS{Cyrillic})
                    or ($s eq 'Cyrillic' and $utf8::SCRIPTS{Greek}))
                {
                    my $other = $s eq 'Greek' ? 'Cyrillic' : 'Greek';
                    require warnings;
                    warnings::warnif('utf8',
                      "Invalid script $s, cannot be mixed with $other");
                }
                # if scoped (later):
                # $^H{utf8scripts}{$_} = 1;
                $utf8::SCRIPTS{$s} = !!1;
            } elsif (@aliases = script_aliases($s)) {
                for my $a (@aliases) {
                    $utf8::SCRIPTS{$a} = !!1;
                }
            } else {
                require Carp;
                Carp::croak("Unknown unicode script $s");
            }
        }
    }
}

sub unimport {
    shift;
    $^H &= ~$utf8::hint_bits;
    if (@_) {
        require "utf8_heavy.pl";
        for my $s (@_) {
            if (valid_script($s)) {
                # delete $^H{utf8scripts}{$_};
                delete $utf8::SCRIPTS{$s};
            } elsif (@aliases = script_aliases($s)) {
                for my $a (@aliases) {
                    delete $utf8::SCRIPTS{$a};
                }
            } else {
                require Carp;
                Carp::croak("Unknown unicode script $_");
            }
        }
    }
}

sub AUTOLOAD {
    require "utf8_heavy.pl";
    goto &$AUTOLOAD if defined &$AUTOLOAD;
    require Carp;
    Carp::croak("Undefined subroutine $AUTOLOAD called");
}

1;
__END__

=head1 NAME

utf8 - Perl pragma to enable/disable UTF-8 (or UTF-EBCDIC) in source code

=head1 SYNOPSIS

 use utf8;
 use utf8 'Greek', 'Arabic';  # allow mixed-scripts in identifiers
 no utf8;

 # Convert the internal representation of a Perl scalar to/from UTF-8.

 $num_octets = utf8::upgrade($string);
 $success    = utf8::downgrade($string[, $fail_ok]);

 # Change each character of a Perl scalar to/from a series of
 # characters that represent the UTF-8 bytes of each original character.

 utf8::encode($string);  # "\x{100}"  becomes "\xc4\x80"
 utf8::decode($string);  # "\xc4\x80" becomes "\x{100}"

 # Convert a code point from the platform native character set to
 # Unicode, and vice-versa.
 $unicode = utf8::native_to_unicode(ord('A')); # returns 65 on both
                                               # ASCII and EBCDIC
                                               # platforms
 $native = utf8::unicode_to_native(65);        # returns 65 on ASCII
                                               # platforms; 193 on
                                               # EBCDIC

 $flag = utf8::is_utf8($string); # since Perl 5.8.1
 $flag = utf8::valid($string);

=head1 DESCRIPTION

The C<use utf8> pragma tells the Perl parser to allow UTF-8 and
certain mixed scripts other than Latin, Common and Inherited in the
program text in the current lexical scope for identifiers (package and
symbol names, function and variable names) and literals. It doesn't
declare strings in the source to be UTF-8 encoded or unicode, see
L<feature/"The 'unicode_strings' feature"> instead.

The C<no utf8> pragma tells Perl to switch back to treating the source
text as literal bytes in the current lexical scope.  (On EBCDIC
platforms, technically it is allowing UTF-EBCDIC, and not UTF-8, but
this distinction is academic, so in this document the term UTF-8 is
used to mean both).

B<Do not use this pragma for anything else than telling Perl that your
script is written in UTF-8.> The utility functions described below are
directly usable without C<use utf8;>.

Because it is not possible to reliably tell UTF-8 from native 8 bit
encodings, you need either a Byte Order Mark at the beginning of your
source code, or C<use utf8;>, to instruct perl.

When UTF-8 becomes the standard source format, this pragma wwithout
any argument will become effectively a no-op.

See also the effects of the C<-C> switch and its cousin, the
C<PERL_UNICODE> environment variable, in L<perlrun>.

Enabling the C<utf8> pragma has the following effect:

=over 4

=item *

Bytes in the source text that are not in the ASCII character set will
be treated as being part of a literal UTF-8 sequence.  This includes
most literals such as identifier names (packages, symbols, function
names, variable names, globs), string constants, unicode numeric
literals and constant regular expression patterns.

=back

Note that if you have non-ASCII, non-UTF-8 bytes in your script (for example
embedded Latin-1 in your string literals), C<use utf8> will be unhappy.  If
you want to have such bytes under C<use utf8>, you can disable this pragma
until the end the block (or file, if at top level) by C<no utf8;>.

=head2 Valid scripts

C<use utf8> takes any valid UCD script names as arguments. This
declares those scripts for all identifiers as valid, all others
besides 'Latin', 'Common' and 'Inherited' are invalid.  This is
currently only globally, not lexically scoped.  Being forced to declare
valid scripts disallows unicode confusables from different language
families, which might looks the same but are not. This does not affect
strings, only names, literals and numbers.

The unicode standard 9.0 defines 137 scripts, i.e. written language
families.

    perl -alne'/; (\w+) #/ && print $1' lib/unicore/Scripts.txt | \
        sort -u

Adlam Ahom Anatolian_Hieroglyphs Arabic Armenian Avestan Balinese
Bamum Bassa_Vah Batak Bengali Bhaiksuki Bopomofo Brahmi Braille
Buginese Buhid Canadian_Aboriginal Carian Caucasian_Albanian Chakma
Cham Cherokee Common Coptic Cuneiform Cypriot Cyrillic Deseret
Devanagari Duployan Egyptian_Hieroglyphs Elbasan Ethiopic Georgian
Glagolitic Gothic Grantha Greek Gujarati Gurmukhi Han Hangul Hanunoo
Hatran Hebrew Hiragana Imperial_Aramaic Inherited
Inscriptional_Pahlavi Inscriptional_Parthian Javanese Kaithi Kannada
Katakana Kayah_Li Kharoshthi Khmer Khojki Khudawadi Lao Latin Lepcha
Limbu Linear_A Linear_B Lisu Lycian Lydian Mahajani Malayalam Mandaic
Manichaean Marchen Meetei_Mayek Mende_Kikakui Meroitic_Cursive
Meroitic_Hieroglyphs Miao Modi Mongolian Mro Multani Myanmar Nabataean
New_Tai_Lue Newa Nko Ogham Ol_Chiki Old_Hungarian Old_Italic
Old_North_Arabian Old_Permic Old_Persian Old_South_Arabian Old_Turkic
Oriya Osage Osmanya Pahawh_Hmong Palmyrene Pau_Cin_Hau Phags_Pa
Phoenician Psalter_Pahlavi Rejang Runic Samaritan Saurashtra Sharada
Shavian Siddham SignWriting Sinhala Sora_Sompeng Sundanese
Syloti_Nagri Syriac Tagalog Tagbanwa Tai_Le Tai_Tham Tai_Viet Takri
Tamil Tangut Telugu Thaana Thai Tibetan Tifinagh Tirhuta Ugaritic Vai
Warang_Citi Yi

Note that this matches the UCD and is a bit different to the old-style
casing of L<Unicode::UCD/charscript()> in previous versions of
L<Unicode::UCD>.

We add some aliases for languages using multiple scripts:

   :Japanese => Katakana Hiragana Han
   :Korean   => Hangul Han
   :Hanb     => Han Bopomofo

These three aliases need not to be declared. They are allowed scripts
in the L<Highly Restriction
Level|http://www.unicode.org/reports/tr39/#Restriction_Level_Detection>
for identifiers.

B<Certain scripts don't need to be declared:>

We follow the B<Moderately Restrictive Level> for identifiers.
I.e. All characters in each identifier must be from a single script,
or from any of the following combinations:

Latin + Han + Hiragana + Katakana; or equivalently: Latn + Jpan

Latin + Han + Bopomofo; or equivalently: Latn + Hanb

Latin + Han + Hangul; or equivalently: Latn + Kore

Allow Latin with other Recommended or Aspirational scripts except
Cyrillic and Greek.

So these scripts need always to be declared:

Cyrillic Greek Ahom Anatolian_Hieroglyphs Avestan Balinese Bamum
Bassa_Vah Batak Brahmi Braille Buginese Buhid Carian
Caucasian_Albanian Chakma Cham Cherokee Common Coptic Cuneiform
Cypriot Deseret Duployan Egyptian_Hieroglyphs Elbasan Glagolitic
Gothic Grantha Hanunoo Hatran Imperial_Aramaic Inherited
Inscriptional_Pahlavi Inscriptional_Parthian Javanese Kaithi Kayah_Li
Kharoshthi Khojki Khudawadi Lepcha Limbu Linear_A Linear_B Lisu Lycian
Lydian Mahajani Mandaic Manichaean Meetei_Mayek Mende_Kikakui
Meroitic_Cursive Meroitic_Hieroglyphs Modi Mro Multani Nabataean
New_Tai_Lue Nko Ogham Ol_Chiki Old_Hungarian Old_Italic
Old_North_Arabian Old_Permic Old_Persian Old_South_Arabian Old_Turkic
Osmanya Pahawh_Hmong Palmyrene Pau_Cin_Hau Phags_Pa Phoenician
Psalter_Pahlavi Pau_Cin_Hau Phags_Pa Phoenician Psalter_Pahlavi Rejang
Runic Samaritan Saurashtra Sharada Shavian Siddham SignWriting
Sora_Sompeng Sundanese Syloti_Nagri Syriac Tagalog Tagbanwa Tai_Le
Tai_Tham Tai_Viet Takri Tirhuta Ugaritic Vai Warang_Citi

=head2 Utility functions

The following functions are defined in the C<utf8::> package by the
Perl core.  You do not need to say C<use utf8> to use these and in fact
you should not say that unless you really want to have UTF-8 source code.

=over 4

=item * C<$num_octets = utf8::upgrade($string)>

(Since Perl v5.8.0)
Converts in-place the internal representation of the string from an octet
sequence in the native encoding (Latin-1 or EBCDIC) to UTF-8. The
logical character sequence itself is unchanged.  If I<$string> is already
upgraded, then this is a no-op. Returns the
number of octets necessary to represent the string as UTF-8.

If your code needs to be compatible with versions of perl without
C<use feature 'unicode_strings';>, you can force Unicode semantics on
a given string:

  # force unicode semantics for $string without the
  # "unicode_strings" feature
  utf8::upgrade($string);

For example:

  # without explicit or implicit use feature 'unicode_strings'
  my $x = "\xDF";    # LATIN SMALL LETTER SHARP S
  $x =~ /ss/i;       # won't match
  my $y = uc($x);    # won't convert
  utf8::upgrade($x);
  $x =~ /ss/i;       # matches
  my $z = uc($x);    # converts to "SS"

B<Note that this function does not handle arbitrary encodings>;
use L<Encode> instead.

=item * C<$success = utf8::downgrade($string[, $fail_ok])>

(Since Perl v5.8.0)
Converts in-place the internal representation of the string from UTF-8 to the
equivalent octet sequence in the native encoding (Latin-1 or EBCDIC). The
logical character sequence itself is unchanged. If I<$string> is already
stored as native 8 bit, then this is a no-op.  Can be used to make sure that
the UTF-8 flag is off, e.g. when you want to make sure that the substr() or
length() function works with the usually faster byte algorithm.

Fails if the original UTF-8 sequence cannot be represented in the
native 8 bit encoding. On failure dies or, if the value of I<$fail_ok> is
true, returns false. 

Returns true on success.

If your code expects an octet sequence this can be used to validate
that you've received one:

  # throw an exception if not representable as octets
  utf8::downgrade($string)

  # or do your own error handling
  utf8::downgrade($string, 1) or die "string must be octets";

B<Note that this function does not handle arbitrary encodings>;
use L<Encode> instead.

=item * C<utf8::encode($string)>

(Since Perl v5.8.0)
Converts in-place the character sequence to the corresponding octet
sequence in Perl's extended UTF-8. That is, every (possibly wide) character
gets replaced with a sequence of one or more characters that represent the
individual UTF-8 bytes of the character.  The UTF8 flag is turned off.
Returns nothing.

 my $x = "\x{100}"; # $x contains one character, with ord 0x100
 utf8::encode($x);  # $x contains two characters, with ords (on
                    # ASCII platforms) 0xc4 and 0x80.  On EBCDIC
                    # 1047, this would instead be 0x8C and 0x41.

Similar to:

  use Encode;
  $x = Encode::encode("utf8", $x);

B<Note that this function does not handle arbitrary encodings>;
use L<Encode> instead.

=item * C<$success = utf8::decode($string)>

(Since Perl v5.8.0)
Attempts to convert in-place the octet sequence encoded in Perl's extended
UTF-8 to the corresponding character sequence. That is, it replaces each
sequence of characters in the string whose ords represent a valid (extended)
UTF-8 byte sequence, with the corresponding single character.  The UTF-8 flag
is turned on only if the source string contains multiple-byte UTF-8
characters.  If I<$string> is invalid as extended UTF-8, returns false;
otherwise returns true.

 my $x = "\xc4\x80"; # $x contains two characters, with ords
                     # 0xc4 and 0x80
 utf8::decode($x);   # On ASCII platforms, $x contains one char,
                     # with ord 0x100.   Since these bytes aren't
                     # legal UTF-EBCDIC, on EBCDIC platforms, $x is
                     # unchanged and the function returns FALSE.

B<Note that this function does not handle arbitrary encodings>;
use L<Encode> instead.

=item * C<$unicode = utf8::native_to_unicode($code_point)>

(Since Perl v5.8.0)
This takes an unsigned integer (which represents the ordinal number of a
character (or a code point) on the platform the program is being run on) and
returns its Unicode equivalent value.  Since ASCII platforms natively use the
Unicode code points, this function returns its input on them.  On EBCDIC
platforms it converts from EBCDIC to Unicode.

A meaningless value will currently be returned if the input is not an unsigned
integer.

Since Perl v5.22.0, calls to this function are optimized out on ASCII
platforms, so there is no performance hit in using it there.

=item * C<$native = utf8::unicode_to_native($code_point)>

(Since Perl v5.8.0)
This is the inverse of C<utf8::native_to_unicode()>, converting the other
direction.  Again, on ASCII platforms, this returns its input, but on EBCDIC
platforms it will find the native platform code point, given any Unicode one.

A meaningless value will currently be returned if the input is not an unsigned
integer.

Since Perl v5.22.0, calls to this function are optimized out on ASCII
platforms, so there is no performance hit in using it there.

=item * C<$flag = utf8::is_utf8($string)>

(Since Perl 5.8.1)  Test whether I<$string> is marked internally as encoded in
UTF-8.  Functionally the same as C<Encode::is_utf8($string)>.

Typically only necessary for debugging and testing, if you need to
dump the internals of an SV, L<Devel::Peek's|Devel::Peek> Dump()
provides more detail in a compact form.

If you still think you need this outside of debugging, testing or
dealing with filenames, you should probably read L<perlunitut> and
L<perlunifaq/What is "the UTF8 flag"?>.

Don't use this flag as a marker to distinguish character and binary
data, that should be decided for each variable when you write your
code.

To force unicode semantics in code portable to perl 5.8 and 5.10, call
C<utf8::upgrade($string)> unconditionally.

=item * C<$flag = utf8::valid($string)>

[INTERNAL] Test whether I<$string> is in a consistent state regarding
UTF-8.  Will return true if it is well-formed Perl extended UTF-8 and has the
UTF-8 flag
on B<or> if I<$string> is held as bytes (both these states are 'consistent').
Main reason for this routine is to allow Perl's test suite to check
that operations have left strings in a consistent state.

=item * C<$bool = utf8::valid_script($script)>

Check if C<$script> is a valid Unicode Script property for an
identifier.  Aliases are not. Old-style script names with a lowercase
character following the C<_> are not. Checks are
case-sensitive. Abbrevated script names are also not valid.  TR39
Table 4 "Candidate Characters for Exclusion from Identifiers" are not
automatically allowed, and need to be explicitly declared.

=item * C<@scripts = utf8::script_aliases($alias)>

Return the list of scripts for an $alias.
E.g. C<script_aliases(':Japanese') => ('Katakana' 'Hiragana' 'Han')>
An alias must start with the ':' character.

=item * C<add_script_alias($alias, @scripts)>

Add a custom alias (language) for multiple scripts, for languages
which commonly use mixed scripts.
An alias must start with the ':' character, and all scripts must be valid
Unicode Script property names.

E.g.

    BEGIN {
      use utf8; # to load add_script_alias()
      utf8::add_script_alias(':Ethiopic_Runic', # define it
                             'Ethiopic' 'Runic');
      use utf8 ':Ethiopic_Runic'; # use it
    }

as abbrevation for C<use utf8 'Ethiopic', 'Runic';>

Predefined are C<':Japanese' => qw(Katakana Hiragana Han)> (Han
standing for Kanji here) and C<':Korean' => qw(Hangul Han)> for mixing old
chinese symbols.

=back

C<utf8::encode> is like C<utf8::upgrade>, but the UTF8 flag is
cleared.  See L<perlunicode>, and the C API
functions C<L<sv_utf8_upgrade|perlapi/sv_utf8_upgrade>>,
C<L<perlapi/sv_utf8_downgrade>>, C<L<perlapi/sv_utf8_encode>>,
and C<L<perlapi/sv_utf8_decode>>, which are wrapped by the Perl functions
C<utf8::upgrade>, C<utf8::downgrade>, C<utf8::encode> and
C<utf8::decode>.  Also, the functions C<utf8::is_utf8>, C<utf8::valid>,
C<utf8::encode>, C<utf8::decode>, C<utf8::upgrade>, and C<utf8::downgrade> are
actually internal, and thus always available, without a C<require utf8>
statement.

=head1 BUGS

Some filesystems may not support UTF-8 file names, or they may be supported
incompatibly with Perl.  Therefore UTF-8 names that are visible to the
filesystem, such as module names may not work.

perl5 upstream allows mixed script confusables as described in
L<http://www.unicode.org/reports/tr39/> since 5.16 and is therefore
considered insecure.

perl5 upstream does not normalize its unicode identifiers as described in
L<http://www.unicode.org/reports/tr15/> since 5.16 and is therefore
considered insecure. See L<http://www.unicode.org/reports/tr36/> for the security
risks.

=head1 SEE ALSO

L<perlunitut>, L<perluniintro>, L<perlrun>, L<bytes>, L<perlunicode>.

L<http://www.unicode.org/reports/tr36/#Mixed_Script_Spoofing>,
L<http://unicode.org/reports/tr39/#Mixed_Script_Confusables>.

=cut
