use strict;

use Test::More;
use Config;
use CPAN::Distroprefs;
use File::Spec;

eval "require YAML; 1" or plan skip_all => "YAML required";
plan tests => 3;

my %ext = (
  yml => 'YAML',
);

my $finder = CPAN::Distroprefs->find(
  './distroprefs', \%ext,
);

my $last = '0';
my @errors;
while (my $next = $finder->next) {
  if ( $next->file lt $last ) {
      push @errors, $next->file . " lt $last\n";
  }
  $last = $next->file;
}
is(scalar @errors, 0, "finder traversed alphabetically") or diag @errors;

sub find_ok {
  my ($arg, $expect, $label) = @_;
  my $finder = CPAN::Distroprefs->find(
    './distroprefs', \%ext,
  );

  isa_ok($finder, 'CPAN::Distroprefs::Iterator');

  my %arg = (
    env => \%ENV,
    perl => $^X,
    perlconfig => \%Config::Config,
    module => [],
    %$arg,
  );

  my $found;
  while (my $result = $finder->next) {
    next unless $result->is_success;
    for my $pref (@{ $result->prefs }) {
      if ($pref->matches(\%arg)) {
        $found = {
          prefs => $pref->data,
          prefs_file => $result->abs,
        };
      }
    }
  }
  is_deeply(
    $found,
    $expect,
    $label,
  );
}

find_ok(
  {
    distribution => 'HDP/Perl-Version-1',
  },
  {
    prefs => YAML::LoadFile('distroprefs/HDP.Perl-Version.yml'),
    prefs_file => File::Spec->catfile(qw/distroprefs HDP.Perl-Version.yml/),
  },
  'match .yml',
);

%ext = (
  dd  => 'Data::Dumper',
);
find_ok(
  {
    distribution => 'INGY/YAML-0.66',
  },
  {
    prefs => do 'distroprefs/INGY.YAML.dd',
    prefs_file => File::Spec->catfile(qw/distroprefs INGY.YAML.dd/),
  },
  'match .dd',
) if 0;

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
