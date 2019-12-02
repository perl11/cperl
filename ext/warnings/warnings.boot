# -*- perl -*-
# miniperl compatible boot stage dummy, to be able to compile the real version
package warnings;
our $VERSION = '2.01';
sub import { $^W = 1; }
sub unimport { $^W = 0; ${^WARNING_BITS} = "0"x18; }
sub warnif { }
sub register_categories { }
sub enabled { 0 }
sub _chk { 0 }
