use lib '.';
use t::TestYAMLTests tests => 1;

my $yaml = <<"...";
---
bar: \xC3\x83\xC2\xB6
foo: \xC3\xB6
...

my $hash = {
    foo => "\xF6",    # LATIN SMALL LETTER O WITH DIAERESIS U+00F6
    bar => "\xC3\xB6" # LATIN SMALL LETTER O WITH DIAERESIS U+00F6 (UTF-8)
};

is Dump($hash), $yaml, 'Dumping native characters works';

