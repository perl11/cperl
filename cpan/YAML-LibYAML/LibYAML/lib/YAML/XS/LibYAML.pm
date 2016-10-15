package YAML::XS::LibYAML;
use 5.008003;
our $VERSION = '0.75';

use XSLoader;
XSLoader::load 'YAML::XS::LibYAML';
use base 'Exporter';

our @EXPORT_OK = qw(Load Dump DumpFile LoadFile);

1;

=head1 NAME

YAML::XS::LibYAML - An XS Wrapper Module of libyaml

=cut
