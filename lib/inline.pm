package cperl;
our $VERSION = "0.01";

sub import {
    delete $^H{'inline'};
}

sub unimport {
    $^H{'inline'} = 1;
}

1;
__END__

=head1 NAME

inline - Perl pragma to disable inlining

=head1 SYNOPSIS

    no inline;

=head1 DESCRIPTION

The cperl variant enables function inlining per default for all inlinable
functions.

With no inline you can disable this feature lexically.

See L<perlcperl>

=cut
