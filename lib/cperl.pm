package cperl;
our $VERSION = "0.01";
use Config ();

# Verify that we're called correctly so that strictures will work.
unless ( __FILE__ =~ /(^|[\/\\])\Q${\__PACKAGE__}\E\.pmc?$/ ) {
    # Can't use Carp, since Carp uses us!
    my (undef, $f, $l) = caller;
    die("Incorrect use of pragma '${\__PACKAGE__}' at $f line $l.\n");
}

sub import {
    shift;
    my (undef, $f, $l) = caller;
    die "This perl is no cperl at $f line $l.\n" unless $Config::Config{usecperl};
    eval "use v5.20;"; # XXX there must be a better way to import these features and set the strictures
}

sub unimport {
    shift;
    warn "Useless use of no cperl";
}

1;
__END__

=head1 NAME

cperl - Perl pragma to protect from using unsupported cperl syntax

=head1 SYNOPSIS

    use cperl;

    sub func(int $a, ...) { otherfunc(...) }

=head1 DESCRIPTION

The cperl variant defines some syntax extensions which are not yet
supported by perl upstream. This pragma will prevent the perl5
interpreter from using this code by some descriptive error message.

=over 6

=item type in signatures in prefix position

use cperl if you use types in the prefix position with signatures.
types as attributes do not need the cperl pragma;

    sub func(int $a)  # requires cperl
    sub func($a :int) # does not

=item :const with other types than anonsubs

use cperl if you use the :const attribute with other types than anon subs.

    sub func :const { # requires cperl
    sub :const {      # does not

    my $a :const = 1;           # requires cperl
    my $h :const = { a => $b }; # requires cperl
    my @a :const = ( 1, $b );   # requires cperl

=back

See L<perlcperl>

=cut
