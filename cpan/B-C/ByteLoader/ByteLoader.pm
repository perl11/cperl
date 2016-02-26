package ByteLoader;

use XSLoader ();
our $VERSION = '0.11';
# XSLoader problem:
# ByteLoader version 0.0601 required--this is only version 0.06_01 at ./bytecode2.plc line 2.
# on use ByteLoader $ByteLoader::VERSION;
# Fixed with use ByteLoader '$ByteLoader::VERSION';
# Next problem on perl-5.8.3: invalid floating constant suffix _03"

if ($] < 5.009004) {
  # Need to check if ByteLoader is not already linked statically.
  # Before 5.6 byterun was in CORE, so we have no name clash.
  require Config; Config->import();
  if ($Config{static_ext} =~ /\bByteLoader\b/) {
    # We overrode the static module with our site_perl version. Which version? 
    # We can only check the perl version and guess from that. From Module::CoreList
    $VERSION = '0.03' if $] >= 5.006;
    $VERSION = '0.04' if $] >= 5.006001;
    $VERSION = '0.05' if $] >= 5.008001;
    $VERSION = '0.06' if $] >= 5.009003;
    $VERSION = '0.06' if $] >= 5.008008 and $] < 5.009;
  } else {
    XSLoader::load 'ByteLoader'; # fake the old backwards compatible version
  }
} else {
  XSLoader::load 'ByteLoader', $VERSION;
}

1;
__END__

=head1 NAME

ByteLoader - load byte compiled perl code

=head1 SYNOPSIS

  use ByteLoader;
  <byte code>

  perl -MByteLoader bytecode_file.plc

  perl -MO=Bytecode,-H,-ofile.plc file.pl
  ./file.plc

=head1 DESCRIPTION

This module is used to load byte compiled perl code as produced by
C<perl -MO=Bytecode=...>. It uses the source filter mechanism to read
the byte code and insert it into the compiled code at the appropriate point.

=head1 AUTHOR

Tom Hughes <tom@compton.nu> based on the ideas of Tim Bunce and others.
Many changes by Enache Adrian <enache@rdslink.ro> 2003 a.d.
and Reini Urban <rurban@cpan.org> 2008-2013.

=head1 SEE ALSO

perl(1).

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
