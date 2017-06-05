use strict;
use warnings;
no warnings 'once';
use Test::More;

plan skip_all => 'These tests only run in core'
  unless $ENV{PERL_CORE};

my @mods = qw[
Module::CoreList
Module::CoreList::TieHashDelta
Module::CoreList::Utils
];

plan tests => 2 + scalar @mods;

my %vers;

foreach my $mod ( @mods ) {
  use_ok($mod);
  $vers{ $mod->VERSION }++;
}

is( scalar keys %vers, 1, 'All Module-CoreList modules should have the same $VERSION' );

# Check that there is a release entry for the current perl version
my $curver = $];
$curver .= 'c' if $^V =~ /c$/;
my $released = $Module::CoreList::released{ $curver };
# duplicate fetch to avoid 'used only once: possible typo' warning
$released = $Module::CoreList::released{ $curver };
ok( defined $released, "There is a released entry for $curver" );
#like( $released, qr!^\d{4}\-\d{2}\-\d{2}$!, 'It should be a date in YYYY-MM-DD format' );
