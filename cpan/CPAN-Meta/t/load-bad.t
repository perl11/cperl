use strict;
use warnings;
use Test::More 0.88;

use CPAN::Meta;
use File::Spec;
use IO::Dir;
use Config;

sub _slurp { do { local(@ARGV,$/)=shift(@_); <> } }

my $data_dir = IO::Dir->new( 't/data-fixable' );
my @files = sort grep { /^\w/ } $data_dir->read;

sub test_files {
  for my $f ( sort @files ) {
    my $path = File::Spec->catfile('t','data-fixable',$f);
    if ($f eq '98042513-META.yml'
        # cperl uses YAML::XS as default
        and (($Config{usecperl} and !$ENV{PERL_YAML_BACKEND})
             or ($ENV{PERL_YAML_BACKEND}
                 and $ENV{PERL_YAML_BACKEND} =~ /^YAML(::XS)?$/)))
    {
      ok( $f, "SKIP $f errors with YAML::XS and YAML. TODO NonStrict" );
      next;
    }
    ok( eval { CPAN::Meta->load_file( $path ) }, "load_file('$f')" ) or diag $@;
    my $string = _slurp($path);
    my $method =  $path =~ /\.json/ ? "load_json_string" : "load_yaml_string";
    ok( eval { CPAN::Meta->$method( $string, { fix_errors => 1 } ) }, "$method(slurp('$f'))" ) or diag $@;
  }
}

# test potential other candidates
if ($ENV{PERL_JSON_BACKEND} || $ENV{PERL_YAML_BACKEND}) {
  test_files(@files);
}
delete $ENV{$_} for qw/PERL_JSON_BACKEND PERL_YAML_BACKEND/; # use defaults
test_files(@files);

# test fallbacks
if ($Config{usecperl}) {
  local $ENV{PERL_JSON_BACKEND} = 'JSON::PP';
  local $ENV{PERL_YAML_BACKEND} = 'CPAN::Meta::YAML';

  test_files(@files);
}

done_testing;
# vim: ts=2 sts=2 sw=2 et:
