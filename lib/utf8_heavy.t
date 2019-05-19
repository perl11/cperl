#!./perl 

my $has_perlio;

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require './test.pl'; require './charset_tools.pl';
    unless ($has_perlio = find PerlIO::Layer 'perlio') {
	print <<EOF;
# Since you don't have perlio you might get failures with UTF-8 locales.
EOF
    }
}

plan(8);

use strict;
use warnings;
use utf8 'Katakana'; # loads reset_scripts et al

eval <<'END';
use utf8;
my $ЀЀ = 1;
END
chomp($@);
::is($@, "", "Allow single script Cyrillic");

{
    BEGIN { utf8::reset_scripts(); }
    use utf8;
    my $Ѐ = 1;
    ::ok(1, "Allow single script Cyrillic after reset");
    BEGIN { utf8::reset_scripts(); }
}

{
    my @w;
    local $SIG{__WARN__} = sub { push @w, $_[0]; };
    # Cyrillic \x{400} Ѐ and Greek \x{395} Ε
    eval q{
      use utf8 'Greek', 'Cyrillic';
      my $ЀΕ = 1;
    };
    # first warning with declaration, 2nd with usage.
    ::is(scalar @w, 2, "Nr of warnings with mixed scripts Greek + Cyrillic");
    ::is(substr($w[0],0,51), "Invalid script Greek, cannot be mixed with Cyrillic",
         "Correct decl warning");
    @w = ();
    eval q{
      no warnings 'utf8';
      use utf8 'Greek', 'Cyrillic';
      my $ЀΕ = 1;
    };
    ::is(scalar @w, 0, "no warnings 'utf8' with mixed scripts Greek + Cyrillic");
    BEGIN { utf8::reset_scripts(); }
}

{
    BEGIN { utf8::reset_scripts(); }
    eval <<'END';
use utf8;
my $ᭅ = 1; # \x{1b45} BALINESE LETTER KAF SASAK
END
    chomp($@);
    ::like($@, qr/Invalid script Balinese in identifier/, "LIMITED_SCRIPT Balinese");
    BEGIN { utf8::reset_scripts(); }
}

# check SCRIPTS
# all scripts:
# perl -anle '/^sc ;/ && print $F[4]' lib/unicore/PropValueAliases.txt
# get Exclusion scripts and Limited_Use scripts from lib/unicore/security/IdentifierType.txt
#
my (%ALL_SCRIPTS, $fh);
open $fh, "../lib/unicore/PropValueAliases.txt";
while (<$fh>) {
  if ($_ and $_ =~ /^sc ; \w+\s+; (\w+)/) {
    $ALL_SCRIPTS{$1}++;
  }
}
close $fh;

#open $fh, "../lib/unicore/security/IdentifierType.txt";
#my ($got);
#while (<$fh>) {
#  if (/^#\s+IdentifierType:\s+Limited_Use/) {
#    $got++;
#  }
#}
#close $fh;

my ($limited_scripts, $excluded_scripts) = (0,0);
for (sort keys %utf8::LIMITED_SCRIPTS) {
  if ($utf8::VALID_SCRIPTS{$_}) {
    ok(0, "LIMITED_SCRIPT $_ in VALID_SCRIPTS");
    $limited_scripts++;
  }
}
is($limited_scripts, 0, "no LIMITED_SCRIPTS in VALID_SCRIPTS");

for (sort keys %utf8::EXCLUDED_SCRIPTS) {
  unless ($utf8::VALID_SCRIPTS{$_}) {
    ok(0, "EXCLUDED_SCRIPT $_ not in VALID_SCRIPTS");
    $excluded_scripts++;
  }
}
is($excluded_scripts, 0, "all EXCLUDED_SCRIPTS in VALID_SCRIPTS");

for (sort keys %ALL_SCRIPTS) {
  if (!exists $utf8::VALID_SCRIPTS{$_} && !exists $utf8::LIMITED_SCRIPTS{$_}) {
    ok(0, "$_ is not in VALID_SCRIPTS nor in LIMITED_SCRIPTS");
  }
}
