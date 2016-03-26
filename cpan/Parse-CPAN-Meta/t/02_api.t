#!/usr/bin/perl

delete $ENV{PERL_YAML_BACKEND};
delete $ENV{PERL_JSON_BACKEND};

# Testing of a known-bad file from an editor

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use lib 't/lib';
use File::Spec::Functions ':ALL';
use Parse::CPAN::Meta;
use Parse::CPAN::Meta::Test;
# use Test::More skip_all => 'Temporarily ignoring failing test';
use Test::More 'no_plan';

#####################################################################
# Testing that Perl::Smith config files work

my $want = {
  "abstract" => "a set of version requirements for a CPAN dist",
  "author"   => [ 'Ricardo Signes <rjbs@cpan.org>' ],
  "build_requires" => {
     "Test::More" => "0.88"
  },
  "configure_requires" => {
     "ExtUtils::MakeMaker" => "6.31"
  },
  "generated_by" => "Dist::Zilla version 2.100991",
  "license" => "perl",
  "meta-spec" => {
     "url" => "http://module-build.sourceforge.net/META-spec-v1.4.html",
     "version" => 1.4
  },
  "name" => "Version-Requirements",
  "recommends" => {},
  "requires" => {
     "Carp" => "0",
     "Scalar::Util" => "0",
     "version" => "0.77"
  },
  "resources" => {
     "repository" => "git://git.codesimply.com/Version-Requirements.git"
  },
  "version" => "0.101010",
};

my $meta_json = catfile( test_data_directory(), 'META-VR.json' );
my $meta_yaml = catfile( test_data_directory(), 'META-VR.yml' );
my $yaml_meta = catfile( test_data_directory(), 'yaml.meta' );
my $json_meta = catfile( test_data_directory(), 'json.meta' );
my $bare_yaml_meta = catfile( test_data_directory(), 'bareyaml.meta' );
my $bad_yaml_meta = catfile( test_data_directory(), 'BadMETA.yml' );

### YAML tests
{
  local $ENV{PERL_YAML_BACKEND}; # ensure we get YAML::XS

  is(Parse::CPAN::Meta->yaml_backend(), 'YAML::XS', 'yaml_backend(): YAML::XS');
  my $from_yaml = Parse::CPAN::Meta->load_file( $meta_yaml );
  is_deeply($from_yaml, $want, "load from YAML file results in expected data");
}

{
  local $ENV{PERL_YAML_BACKEND}; # ensure we get YAML::XS

  note '';
  is(Parse::CPAN::Meta->yaml_backend(), 'YAML::XS', 'yaml_backend(): YAML::XS');
  my $from_yaml = Parse::CPAN::Meta->load_file( $yaml_meta );
  is_deeply($from_yaml, $want, "load from YAML .meta file results in expected data");
}

{
  local $ENV{PERL_YAML_BACKEND}; # ensure we get YAML::XS

  note '';
  is(Parse::CPAN::Meta->yaml_backend(), 'YAML::XS', 'yaml_backend(): YAML::XS');
  my $from_yaml = Parse::CPAN::Meta->load_file( $bare_yaml_meta );
  is_deeply($from_yaml, $want, "load from bare YAML .meta file results in expected data");
}

{
  local $ENV{PERL_YAML_BACKEND}; # ensure we get YAML::XS

  note '';
  is(Parse::CPAN::Meta->yaml_backend(), 'YAML::XS', 'yaml_backend(): YAML::XS');
  my $yaml   = load_ok( 'META-VR.yml', $meta_yaml, 100);
  my $from_yaml = Parse::CPAN::Meta->load_yaml_string( $yaml );
  is_deeply($from_yaml, $want, "load from YAML str results in expected data");
}

{
  local $ENV{PERL_YAML_BACKEND}; # ensure we get YAML::XS

  note '';
  is(Parse::CPAN::Meta->yaml_backend(), 'YAML::XS', 'yaml_backend(): YAML::XS');
  my @yaml   = Parse::CPAN::Meta::LoadFile( $bad_yaml_meta );
  is($yaml[0]{author}[0], 'Olivier Mengu\xE9', "Bad UTF-8 is replaced");
}

{
  local $ENV{PERL_YAML_BACKEND} = 'CPAN::Meta::YAML';

  is(Parse::CPAN::Meta->yaml_backend(), 'CPAN::Meta::YAML', 'yaml_backend(): CPAN::Meta::YAML');
  my $yaml   = load_ok( 'META-VR.yml', $meta_yaml, 100);
  my $from_yaml = Parse::CPAN::Meta->load_yaml_string( $yaml );
  is_deeply($from_yaml, $want, "load_yaml_string using PERL_YAML_BACKEND");
}

SKIP: {
  note '';
  skip "YAML module not installed", 2
    unless eval "require YAML; 1";
  local $ENV{PERL_YAML_BACKEND} = 'YAML';

  is(Parse::CPAN::Meta->yaml_backend(), 'YAML', 'yaml_backend(): YAML');
  my $yaml   = load_ok( 'META-VR.yml', $meta_yaml, 100);
  my $from_yaml = Parse::CPAN::Meta->load_yaml_string( $yaml );
  is_deeply($from_yaml, $want, "load_yaml_string using YAML");
}

SKIP: {
  note '';
  skip "YAML::Syck module not installed", 2
    unless eval "require YAML::Syck; 1";
  local $ENV{PERL_YAML_BACKEND} = 'YAML::Syck';

  is(Parse::CPAN::Meta->yaml_backend(), 'YAML::Syck', 'yaml_backend(): YAML::Syck');
  my $yaml   = load_ok( 'META-VR.yml', $meta_yaml, 100);
  my $from_yaml = Parse::CPAN::Meta->load_yaml_string( $yaml );
  is_deeply($from_yaml, $want, "load_yaml_string using YAML::Syck");
}

### JSON tests
{
  # JSON tests with Cpanel::JSON::XS
  local $ENV{PERL_JSON_BACKEND}; # ensure we get Cpanel::JSON::XS

  note '';
  is(Parse::CPAN::Meta->json_backend(), 'Cpanel::JSON::XS', 'json_backend(): Cpanel::JSON::XS');
  my $from_json = Parse::CPAN::Meta->load_file( $meta_json );
  is_deeply($from_json, $want, "load from JSON file results in expected data");
}

{
  # JSON tests with Cpanel::JSON::XS
  local $ENV{PERL_JSON_BACKEND}; # ensure we get Cpanel::JSON::XS

  note '';
  is(Parse::CPAN::Meta->json_backend(), 'Cpanel::JSON::XS', 'json_backend(): Cpanel::JSON::XS');
  my $from_json = Parse::CPAN::Meta->load_file( $json_meta );
  is_deeply($from_json, $want, "load from JSON .meta file results in expected data");
}

{
  # JSON tests with Cpanel::JSON::XS
  local $ENV{PERL_JSON_BACKEND}; # ensure we get Cpanel::JSON::XS

  note '';
  is(Parse::CPAN::Meta->json_backend(), 'Cpanel::JSON::XS', 'json_backend(): Cpanel::JSON::XS');
  my $json   = load_ok( 'META-VR.json', $meta_json, 100);
  my $from_json = Parse::CPAN::Meta->load_json_string( $json );
  is_deeply($from_json, $want, "load from JSON str results in expected data");
}

{
  # JSON tests with Cpanel::JSON::XS, take 2
  local $ENV{PERL_JSON_BACKEND} = 0; # request Cpanel::JSON::XS

  note '';
  is(Parse::CPAN::Meta->json_backend(), 'Cpanel::JSON::XS', 'json_backend(): Cpanel::JSON::XS');
  my $json   = load_ok( 'META-VR.json', $meta_json, 100);
  my $from_json = Parse::CPAN::Meta->load_json_string( $json );
  is_deeply($from_json, $want, "load_json_string with PERL_JSON_BACKEND = 0");
}

{
  # JSON tests with Cpanel::JSON::XS, take 3
  local $ENV{PERL_JSON_BACKEND} = 'Cpanel::JSON::XS'; # request Cpanel::JSON::XS

  note '';
  is(Parse::CPAN::Meta->json_backend(), 'Cpanel::JSON::XS', 'json_backend(): Cpanel::JSON::XS');
  my $json   = load_ok( 'META-VR.json', $meta_json, 100);
  my $from_json = Parse::CPAN::Meta->load_json_string( $json );
  is_deeply($from_json, $want, "load_json_string with PERL_JSON_BACKEND = 'Cpanel::JSON::XS'");
}

{
  # JSON tests with JSON::PP
  local $ENV{PERL_JSON_BACKEND} = 'JSON::PP';

  note '';
  {
    local $^W;  # silence redefine warnings
    is(Parse::CPAN::Meta->json_backend(), 'JSON::PP', 'json_backend(): JSON::PP');
  }
  my $json   = load_ok( 'META-VR.json', $meta_json, 100);
  my $from_json = Parse::CPAN::Meta->load_json_string( $json );
  is_deeply($from_json, $want, "load_json_string with PERL_JSON_BACKEND = 'JSON::PP'");
}

SKIP: {
  note '';
  skip "JSON module version 2.5 not installed", 2
    unless eval "require JSON; JSON->VERSION(2.5); 1";
  local $ENV{PERL_JSON_BACKEND} = 1;

  is(Parse::CPAN::Meta->json_backend(), 'JSON', 'json_backend(): JSON');
  my $json   = load_ok( 'META-VR.json', $meta_json, 100);
  my $from_json = Parse::CPAN::Meta->load_json_string( $json );
  is_deeply($from_json, $want, "load_json_string with PERL_JSON_BACKEND = 1");
}

SKIP: {
  note '';
  skip "JSON::XS module not installed", 2
    unless eval "require JSON::XS; JSON::XS->VERSION(2.5); 1";
  local $ENV{PERL_JSON_BACKEND} = 'JSON::XS';

  is(Parse::CPAN::Meta->json_backend(), 'JSON::XS', 'json_backend(): JSON::XS');
  my $json   = load_ok( 'META-VR.json', $meta_json, 100);
  my $from_json = Parse::CPAN::Meta->load_json_string( $json );
  is_deeply($from_json, $want, "load_json_string with PERL_JSON_BACKEND = JSON::XS");
}

SKIP: {
  note '';
  skip "JSON::Syck module not installed", 2
    unless eval "require JSON::Syck; 1";
  local $ENV{PERL_JSON_BACKEND} = 'JSON::Syck';

  is(Parse::CPAN::Meta->json_backend(), 'JSON::Syck', 'json_backend(): JSON::Syck');
  my $json   = load_ok( 'META-VR.json', $meta_json, 100);
  my $from_json = Parse::CPAN::Meta->load_json_string( $json );
  is_deeply($from_json, $want, "load_json_string with PERL_JSON_BACKEND = JSON::Syck");
}
