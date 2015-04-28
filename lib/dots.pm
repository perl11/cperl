package dots;
use cperl; # this version changed the parser directly

$VERSION = '0.01c';
use strict;

sub import {
  $^H{dots} = 1;					# enable
}
sub unimport {
  delete $^H{dots};					# disable
}

1;

__END__

=head1 NAME

dots - perl6-like dot syntax for bareword method calls

=head1 SYNOPSIS

  use dots;
  $obj.method;    # bareword only

  # but still using concat for these:
  $obj->"method"; # string
  $obj->$meth;    # scalar
  $obj. method;   # whitespace

=head1 DESCRIPTION

Enable perl6 method call syntax, dots instead of arrows for bareword
method calls only. Whitespace after the dot is not allowed.

We cannot support full arrow replacements for all method calls,
because this clashes with the concat operator, and would require
changing C<.> to C<~>.

=head1 LICENSE

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

perl6

=head1 AUTHORS

(C) by cPanel 2015.

=cut
