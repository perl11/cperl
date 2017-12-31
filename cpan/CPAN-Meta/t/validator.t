use strict;
use warnings;
use Test::More 0.88;

use CPAN::Meta;
use CPAN::Meta::Validator;
use File::Spec;
use IO::Dir;
use Parse::CPAN::Meta 1.4400;
use Config;

delete $ENV{CPAN_META_JSON_BACKEND};
delete $ENV{CPAN_META_JSON_DECODER};

my $defaults_json = $Config{usecperl} ? 'Cpanel::JSON::XS' : 'JSON::PP';
my $defaults_yaml = $Config{usecperl} ? 'YAML::XS' : 'CPAN::Meta::YAML';
my @fallbacks_json = qw(JSON::PP Cpanel::JSON::XS JSON::Syck JSON::XS);
my @fallbacks_yaml = qw(CPAN::Meta::YAML YAML YAML::Syck);

# test potential other candidates
if (($ENV{PERL_JSON_BACKEND} and $ENV{PERL_JSON_BACKEND} ne $defaults_json)
    or ($ENV{PERL_YAML_BACKEND} and $ENV{PERL_YAML_BACKEND} ne $defaults_yaml))
{
  test_files();
}

# test defaults
delete $ENV{$_} for qw/PERL_JSON_BACKEND PERL_YAML_BACKEND/;
test_files();

# test fallbacks. with perl5 proper the fallbacks are the defaults
for (@fallbacks_json) {
  next if $_ eq $defaults_json;
  eval "require $_;" or next;
  local $ENV{PERL_JSON_BACKEND} = $_;
  test_files('json');
}
for (@fallbacks_yaml) {
  next if $_ eq $defaults_yaml;
  eval "require $_;" or next;
  local $ENV{PERL_YAML_BACKEND} = $_;
  test_files('yml');
}

sub test_files {

  my $what = shift;
  my @files = sort map {
    my $d = $_;
    map { "$d/$_" } grep { substr($_,0,1) ne '.' } IO::Dir->new($d)->read
  } qw( t/data-fail t/data-fixable );

  if ($what) { @files = grep {/\.$what$/} @files; }

  for my $f ( @files ) {
    # TODO: YAML::XS::NonStrict,
    # CPAN::Meta::YAML i.e. YAML::Tiny and Syck silently convert empty failures to undef
    if ($f eq 't/data-fixable/98042513-META.yml'
        # cperl uses YAML::XS as default
        and (($Config{usecperl} and !$ENV{PERL_YAML_BACKEND})
             or ($ENV{PERL_YAML_BACKEND}
                 and $ENV{PERL_YAML_BACKEND} =~ /^YAML(::XS)?$/)))
    {
      ok( $f, "SKIP $f errors with YAML::XS and YAML. TODO NonStrict" );
      next;
    }
    my $meta = Parse::CPAN::Meta->load_file( File::Spec->catfile($f) );
    my $backend = ($f =~ /\.ya?ml$/ ? Parse::CPAN::Meta->yaml_backend()
                                  : Parse::CPAN::Meta->json_backend());
    my $cmv = CPAN::Meta::Validator->new({%$meta});
    ok( ! $cmv->is_valid, "$f shouldn't validate with $backend" );
    note 'validation error: ', $_ foreach $cmv->errors;
  }

  @files = sort map {
        my $d = $_;
        map { "$d/$_" } grep { substr($_,0,1) ne '.' } IO::Dir->new($d)->read
  } qw( t/data-test t/data-valid );
  if ($what) { @files = grep {/\.$what$/} @files; }

  for my $f ( @files ) {
    my $meta = Parse::CPAN::Meta->load_file( File::Spec->catfile($f) );
    my $cmv = CPAN::Meta::Validator->new({%$meta});
    my $backend = ($f =~ /\.ya?ml$/ ? Parse::CPAN::Meta->yaml_backend()
                                    : Parse::CPAN::Meta->json_backend());
    ok( $cmv->is_valid, "$f validates with $backend" )
      or diag( "ERRORS:\n" . join( "\n", $cmv->errors ) );
  }
}

done_testing;
# vim: ts=2 sts=2 sw=2 et :
