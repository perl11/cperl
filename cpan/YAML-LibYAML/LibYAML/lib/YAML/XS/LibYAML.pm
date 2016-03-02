package YAML::XS::LibYAML;
use 5.008003;
use strict;
use warnings;

use XSLoader;
XSLoader::load 'YAML::XS::LibYAML';
use base 'Exporter';

our @EXPORT_OK = qw(Load Dump LoadFile);

1;

=head1 NAME

YAML::XS::LibYAML - A XS Wrapper Module of libyaml

=cut
