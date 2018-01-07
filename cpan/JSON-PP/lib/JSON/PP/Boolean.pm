package JSON::PP::Boolean;

use strict;
use overload ();

BEGIN {
  local $^W; # silence redefine warnings. no warnings 'redefine' does not help
  &overload::import( 'overload', # workaround 5.6 reserved keyword warning
    "0+"     => sub { ${$_[0]} },
    "++"     => sub { $_[0] = ${$_[0]} + 1 },
    "--"     => sub { $_[0] = ${$_[0]} - 1 },
    '""'     => sub { ${$_[0]} == 1 ? '1' : '0' }, # GH 29
    'eq'     => sub {
      my ($obj, $op) = ref ($_[0]) ? ($_[0], $_[1]) : ($_[1], $_[0]);
      if ($op eq 'true' or $op eq 'false') {
        return "$obj" eq '1' ? 'true' eq $op : 'false' eq $op;
      }
      else {
        return $obj ? 1 == $op : 0 == $op;
      }
    },
    fallback => 1);
}

$JSON::PP::Boolean::VERSION = '2.97001_04';

1;

__END__

=head1 NAME

JSON::PP::Boolean - dummy module providing JSON::PP::Boolean

=head1 SYNOPSIS

 # do not "use" yourself

=head1 DESCRIPTION

This module exists only to provide overload resolution for Storable and similar modules. See
L<JSON::PP> for more info about this class.

=head1 AUTHOR

This idea is from L<JSON::XS::Boolean> written by Marc Lehmann <schmorp[at]schmorp.de>
The implementation is from L<Cpanel::JSON::XS::Boolean> from cperl.

=cut

