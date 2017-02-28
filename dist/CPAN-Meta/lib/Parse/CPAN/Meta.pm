use 5.008001;
use strict;
package Parse::CPAN::Meta;
# ABSTRACT: Parse META.yml and META.json CPAN metadata files

our $VERSION = '1.5000c';
$VERSION =~ s/c$//;

use Exporter;
use Carp 'croak';

our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/Load LoadFile/;
our $permit_yaml_err = qr/(control characters are not allowed|invalid trailing UTF-8 octet)/m;

sub load_file {
  my ($class, $filename) = @_;

  if ($filename =~ /\.ya?ml$/) {
    my $backend = $class->yaml_backend();
    {
      no strict 'refs'; 
      if (exists &{"$backend\::LoadFile"} ) {
        if ($backend eq 'YAML::XS') {
          local ($YAML::XS::NonStrict, $YAML::XS::DisableCode, 
                 $YAML::XS::DisableBlessed) = (1, 1, 1);
          return YAML::XS::LoadFile($filename);
        } elsif ($backend eq 'YAML::Syck') {
          local ( $YAML::Syck::LoadCode, $YAML::Syck::UseCode,
                  $YAML::Syck::LoadBlessed, $YAML::Syck::ImplicitUnicode ) = (0,0,0,1);
          return YAML::Syck::LoadFile($filename);
        } else {
          return &{"$backend\::LoadFile"}($filename);
        }
      } else {
        my $meta = _slurp($filename);
        return $class->load_yaml_string($meta);
      }
    }
  }
  elsif ($filename =~ /\.json$/) {
    my $backend = $class->json_backend();
    if (exists &{"$backend\::LoadFile"} ) {
      local ($JSON::Syck::LoadCode, $JSON::Syck::UseCode, $JSON::Syck::LoadBlessed) = (0,0,0);
      local $JSON::Syck::ImplicitUnicode = 1;
      return &{"$backend\::LoadFile"}($filename);
    } else {
      my $meta = _slurp($filename);
      return $class->load_json_string($meta);
    }
  }
  else {
    my $meta = _slurp($filename);
    $class->load_string($meta); # try to detect yaml/json
  }
}

sub load_string {
  my ($class, $string) = @_;
  if ( $string =~ /^---/ ) { # looks like YAML
    return $class->load_yaml_string($string);
  }
  elsif ( $string =~ /^\s*\{/ ) { # looks like JSON
    return $class->load_json_string($string);
  }
  else { # maybe doc-marker-free YAML
    return $class->load_yaml_string($string);
  }
}

sub load_yaml_string {
  my ($class, $string) = @_;
  my $backend = $class->yaml_backend();
  my $data;
  if ($backend eq 'YAML::XS') {
    local ($YAML::XS::NonStrict, $YAML::XS::DisableCode, 
           $YAML::XS::DisableBlessed) = (1, 1, 1);
    $data = eval { YAML::XS::Load($string); };
  } elsif ($backend eq 'YAML::Syck') {
    local ($YAML::Syck::LoadCode, $YAML::Syck::UseCode,
           $YAML::Syck::LoadBlessed, $YAML::Syck::ImplicitUnicode)
        = (0,0,0,1);
    $data = YAML::Syck::Load($string);
  } else {
    $data = eval { no strict 'refs'; &{"$backend\::Load"}($string) };
  }
  # Make some libyaml parse errors are non-fatal.
  # match YAML::Tiny and CPAN::Meta::YAML behavior, which accepts broken YAML
  if ($@) {
    my $err = $@;
    if ($backend =~ /^YAML(::XS)?$/ and $err =~ $permit_yaml_err) {
      warn $err;
    } else {
      croak $err;
    }
  }
  return $data || {}; # in case document was valid but empty
}

sub load_json_string {
  my ($class, $string) = @_;
  my $backend =  $class->json_backend();
  my $data;
  if ($backend eq 'JSON::PP') {
    require Encode;
    # load_json_string takes characters, ->decode expects bytes
    my $encoded = Encode::encode('UTF-8', $string, Encode::PERLQQ());
    $data = eval { $backend->new->utf8->decode($encoded) };
  } elsif ($backend->can('decode_json')) { # takes correct utf8
    no strict 'refs';
    $data = eval { &{$backend."::decode_json"}($string) };
    # or not
    $data = eval { $backend->new->decode($string) } if $@;
  } elsif ($backend =~ /^(JSON::MaybeXS|Mojo::JSON)$/) {
    no strict 'refs';
    $data = eval { &{$backend."::from_json"}($string) };
  } elsif ($backend eq 'JSON::Syck') {
    # Syck security
    local ($JSON::Syck::LoadCode, $JSON::Syck::UseCode, $JSON::Syck::LoadBlessed) = (0,0,0);
    local $JSON::Syck::ImplicitUnicode = 1;
    $data = eval { JSON::Syck::Load($string) };
  } elsif ($backend->can('utf8')) {
    require Encode;
    my $encoded = Encode::encode('UTF-8', $string, Encode::PERLQQ());
    $data = eval { $backend->new->utf8->decode($encoded) };
  } else {
    $data = eval { $backend->new->decode($string) };
  }
  croak "$backend: $@" if $@;
  return $data || {};
}

sub yaml_backend {
  my $backend = $ENV{PERL_YAML_BACKEND};
  if (! defined $backend ) {
    if (_can_load( 'YAML::XS', 0.73 )) {
      return "YAML::XS";
    } else {
      $backend = 'CPAN::Meta::YAML';
    }
  }
  _can_load( $backend )
    or croak "Could not load PERL_YAML_BACKEND '$backend'\n";
  $backend->can("Load")
    or croak "PERL_YAML_BACKEND '$backend' does not implement Load()\n";
  return $backend;
}

sub json_decoder {
  if (my $decoder = $ENV{CPAN_META_JSON_DECODER}) {
    _can_load( $decoder )
      or croak "Could not load CPAN_META_JSON_DECODER '$decoder'\n";
    $decoder->can('decode_json')
      or croak "No decode_json sub provided by CPAN_META_JSON_DECODER '$decoder'\n";
    return $decoder;
  }
  return $_[0]->json_backend;
}

sub json_backend {
  my $backend = $ENV{PERL_JSON_BACKEND};
  if (! $backend or $backend eq 'Cpanel::JSON::XS') {
    if (_can_load( 'Cpanel::JSON::XS' => 3.0218 )) {
      return 'Cpanel::JSON::XS';
    } else {
      $backend = 'JSON::PP';
    }
  }
  if ($backend eq "1") { # oh my
    _can_load( 'JSON' => 2.5 )
      or croak  "JSON 2.5 is required for " .
                "\$ENV{PERL_JSON_BACKEND} = '$backend'\n";
    return "JSON";
  }
  elsif ($backend) {
    _can_load( $backend )
      or croak "Could not load PERL_JSON_BACKEND '$backend'\n";
    if ($backend =~ /^(JSON::MaybeXS|Mojo::JSON)$/) {
      $backend->can("from_json")
        or croak "PERL_JSON_BACKEND '$backend' does not implement from_json()\n";
      return $backend;
    }
    elsif ($backend eq 'JSON::Syck') {
      $backend->can("Load")
        or croak "PERL_JSON_BACKEND '$backend' does not implement Load()\n";
      return $backend;
    }
    $backend->can("decode")
      or croak "PERL_JSON_BACKEND '$backend' does not implement decode()\n";
    return $backend;
  }
  else {
    _can_load( 'JSON::PP' => 2.27300 )
      or croak  "JSON:PP 2.27300 is required for " .
                "\$ENV{PERL_JSON_BACKEND} = '$backend'\n";
    return "JSON::PP";
  }
}

sub _slurp {
  require Encode;
  #open my $fh, "<:encoding(UTF-8)", "$_[0]" ## no critic
  # permit double encoded UTF-8  and other nonsense
  open my $fh, "<:raw", "$_[0]" ## no critic
    or die "can't open $_[0] for reading: $!";
  my $content = do { local $/; <$fh> };
  $content = Encode::decode('UTF-8', $content, Encode::PERLQQ());
  return $content;
}
  
sub _can_load {
  my ($module, $version) = @_;
  (my $file = $module) =~ s{::}{/}g;
  $file .= ".pm";
  return 1 if $INC{$file};
  return 0 if exists $INC{$file}; # prior load failed
  eval { require $file; 1 }
    or return 0;
  if ( defined $version ) {
    eval { $module->VERSION($version); 1 }
      or return 0;
  }
  return 1;
}

# Kept for backwards compatibility only
# Create an object from a file
sub LoadFile ($) { ## no critic
  return Load(_slurp(shift));
}

# Parse a document from a string.
sub Load ($) { ## no critic
  my $backend = __PACKAGE__->yaml_backend();
  my $object;
  eval { require $backend; };
  if ($backend =~ /^YAML(::XS)?$/) {
    # set YAML::Tiny/YAML::Syck compatible options:
    local ($YAML::XS::NonStrict, $YAML::XS::DisableBlessed, $YAML::XS::DisableCode)
          = (1,1,1);
    #local $YAML::XS::QuoteNumericStrings = 0;
    $object = eval { no strict 'refs'; &{"$backend\::Load"}(shift) };
    # Make some parse errors are non-fatal.
    # Match YAML::Tiny and CPAN::Meta::YAML behavior, which accepts broken YAML
    if ($@) {
      my $err = $@;
      if ($err =~ $permit_yaml_err) {
        warn $err;
      } else {
        croak $err;
      }
    }
    return $object || {};
  } else {
    $object = eval { no strict 'refs'; &{"$backend\::Load"}(shift) };
    croak $@ if $@;
  }
  return $object;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Parse::CPAN::Meta - Parse META.yml and META.json CPAN metadata files

=head1 VERSION

version 1.5000c

=head1 SYNOPSIS

    #############################################
    # In your file
    
    ---
    name: My-Distribution
    version: 1.23
    resources:
      homepage: "http://example.com/dist/My-Distribution"
    
    
    #############################################
    # In your program
    
    use Parse::CPAN::Meta;
    
    my $distmeta = Parse::CPAN::Meta->load_file('META.yml');
    
    # Reading properties
    my $name     = $distmeta->{name};
    my $version  = $distmeta->{version};
    my $homepage = $distmeta->{resources}{homepage};

=head1 DESCRIPTION

B<Parse::CPAN::Meta> is a parser for F<META.json> and F<META.yml> files, using
L<Cpanel::JSON::XS> and/or L<YAML::XS>, with slow fallbacks to L<CPAN::Meta::YAML>
and L<JSON::PP>.

B<Parse::CPAN::Meta> provides three methods: C<load_file>, C<load_json_string>,
and C<load_yaml_string>.  These will read and deserialize CPAN metafiles, and
are described below in detail.

B<Parse::CPAN::Meta> provides a legacy API of only two functions,
based on the YAML functions of the same name. Wherever possible,
identical calling semantics are used.  These may only be used with YAML sources.

All error reporting is done with exceptions (die'ing).

Note that META files are expected to be in UTF-8 encoding, only.  When
converted string data, it must first be decoded from UTF-8.

=begin Pod::Coverage




=end Pod::Coverage

=head1 METHODS

=head2 load_file

  my $metadata_structure = Parse::CPAN::Meta->load_file('META.json');

  my $metadata_structure = Parse::CPAN::Meta->load_file('META.yml');

This method will read the named file and deserialize it to a data structure,
determining whether it should be JSON or YAML based on the filename.
The file will be read using the ":utf8" IO layer.

=head2 load_yaml_string

  my $metadata_structure = Parse::CPAN::Meta->load_yaml_string($yaml_string);

This method deserializes the given string of YAML and returns the first
document in it.  (CPAN metadata files should always have only one document.)
If the source was UTF-8 encoded, the string must be decoded before calling
C<load_yaml_string>.

=head2 load_json_string

  my $metadata_structure = Parse::CPAN::Meta->load_json_string($json_string);

This method deserializes the given string of JSON and the result.  
If the source was UTF-8 encoded, the string must be decoded before calling
C<load_json_string>.

=head2 load_string

  my $metadata_structure = Parse::CPAN::Meta->load_string($some_string);

If you don't know whether a string contains YAML or JSON data, this method
will use some heuristics and guess.  If it can't tell, it assumes YAML.

=head2 yaml_backend

  my $backend = Parse::CPAN::Meta->yaml_backend;

Returns the module name of the YAML serializer. See L</ENVIRONMENT>
for details.

=head2 json_backend

  my $backend = Parse::CPAN::Meta->json_backend;

Returns the module name of the JSON serializer.  This will either
be L<Cpanel::JSON::XS> or L<JSON::PP>.  Even if C<PERL_JSON_BACKEND> is set,
this will return L<JSON> as further delegation is handled by
the L<JSON> module.  See L</ENVIRONMENT> for details.

Note that C<CPAN_META_JSON_BACKEND> and C<CPAN_META_YAML_BACKEND> are ignored.

=head2 json_decoder

  my $decoder = Parse::CPAN::Meta->json_decoder;

Returns the module name of the JSON decoder.  Unlike L</json_backend>, this
is not necessarily a full L<JSON>-style module, but only something that will
provide a C<decode_json> subroutine.  If C<CPAN_META_JSON_DECODER> is set,
this will be whatever that's set to.  If not, this will be whatever has
been selected as L</json_backend>.  See L</ENVIRONMENT> for more notes.

=head1 FUNCTIONS

For maintenance clarity, no functions are exported by default.  These functions
are available for backwards compatibility only and are best avoided in favor of
C<load_file>.

=head2 Load

  my @yaml = Parse::CPAN::Meta::Load( $string );

Parses a string containing a valid YAML stream into a list of Perl data
structures.

=head2 LoadFile

  my @yaml = Parse::CPAN::Meta::LoadFile( 'META.yml' );

Reads the YAML stream from a file instead of a string.

=head1 ENVIRONMENT

=head2 PERL_JSON_BACKEND

By default, L<Cpanel::JSON::XS> will be used for deserializing JSON
data. If the C<PERL_JSON_BACKEND> environment variable exists, is true
and is not "Cpanel::JSON::XS", then the L<JSON::PP> module (version
2.27300 or greater) will be loaded and used to interpret
C<PERL_JSON_BACKEND>.  If L<JSON::PP> is not installed or is too old, an
exception will be thrown.

=head2 PERL_YAML_BACKEND

By default, L<YAML:XS> will be used for deserializing YAML data. If
the C<PERL_YAML_BACKEND> environment variable is defined, then it is
interpreted as a module to use for deserialization.  The given module
must be installed, must load correctly and must implement the
C<Load()> function or an exception will be thrown.

C<YAML::XS> is much stricter than the previous default YAML parser
L<CPAN::Meta::YAML> (i.e. based on C<YAML::Tiny>), so the following
fatal YAML::XS errors are unfatalized:
"control characters are not allowed", "invalid trailing UTF-8 octet"

=head2 CPAN_META_JSON_BACKEND

is only accepted in C<json_decoder>,

=head2 CPAN_META_YAML_BACKEND

is ignored.

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/Perl-Toolchain-Gang/Parse-CPAN-Meta/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/Perl-Toolchain-Gang/Parse-CPAN-Meta>

  git clone https://github.com/Perl-Toolchain-Gang/Parse-CPAN-Meta.git

=head1 AUTHORS

=over 4

=item *

Adam Kennedy <adamk@cpan.org>

=item *

David Golden <dagolden@cpan.org>

=back

=head1 CONTRIBUTORS

=for stopwords Graham Knop Joshua ben Jore Karen Etheridge Neil Bowers Ricardo Signes Steffen Mueller

=over 4

=item *

Graham Knop <haarg@haarg.org>

=item *

Joshua ben Jore <jjore@cpan.org>

=item *

Karen Etheridge <ether@cpan.org>

=item *

Neil Bowers <neil@bowers.com>

=item *

Ricardo Signes <rjbs@cpan.org>

=item *

Steffen Mueller <smueller@cpan.org>

=item *

Reini Urban <rurban@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Adam Kennedy and Contributors.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
