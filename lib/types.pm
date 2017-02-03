package types;
our $VERSION = '0.1';
use warnings 'types';
# use types, warns on type violations
# use types strict dies on normal, unmodern-perl type violations.
sub import {
  my (undef, $mode) = @_;
  if (!defined($mode)) {
    return;
  } elsif ($mode eq 'strict') {
    warnings->import('FATAL' => 'types');
  } else {
    # more evtl. later
    warn "Unknown argument use types '$mode'";
  }
}
# no types turns off types warnings, but not signature errors
sub unimport {
  warnings->unimport('types');
}

1;
__END__

=head1 NAME

types - warn on type violations

=head1 SYNOPSIS

    use types;       # enable compile-time type warnings
    my MyInt $i = 0; # => warning: Wrong type Int, expected MyInt

    use types;
    my int @a[5];
    $a[0] = "";      # => warning:
                     Type of scalar assignment to @a must be int (not Str)

    use types 'strict';
    my MyInt $i = 0; # => error: Wrong type Int, expected MyInt

    no types;
    my MyInt $i = 0; # ok

=head1 DESCRIPTION

This is a new lexical user-pragma since cperl 5.26 to control the
type-checker.  Currently it turns on types warnings, make them fatal or
turns them off.  Currently only implemented for assignments, not many any
other ops.

Note that types in signatures are always checked, regardless of the state of the
types pragma, i.e. the types warnings category.

strict mode also forbids the insertion of automatic type casts. Such
as e.g.  C<my num @i; $i[0] = 1;> will cast the 1 to 1.0.

See L<perltypes>.

=cut

