package fake_signatures;
our $VERSION = '0.01';
sub unimport { $^H{no_fake_signatures} = 1; }
sub import { delete $^H{no_fake_signatures}; }

1;
__END__

=head1 NAME

fake_signatures - disallow fake signature optimizations

=head1 SYNOPSIS

    no fake_signatures;
    sub inc_arg { my ($self, $arg) = @_; $arg++ }

=head1 DESCRIPTION

This is a new lexical user-pragma since cperl 5.24 to disable the
compiler optimization converting normal functions to fake signatures,
when the first line in the body is like C<my ($vars...) = @_;>.

This might be needed if the function is also processed by source
filters, e.g.  L<Test::Base> with L<Spiffy>.

=head2 Diagnostics

Use C<-Dk> with a DEBUGGING perl to see if a subroutine is converted or not,
or check via L<B::Concise>.

These cases B<are> automatically converted:

    my ($self) = @_;
    my ($self, $arg) = @_;
    my ($self, $arg, @slurp) = @_;
    my @args = @_;
    my %args = @_;

These cases are B<not> automatically converted:

    my ($self) = shift;

    my ($self, $extra) = (@_, 0);
    my ($self, @slurp, $arg) = @_;
    my ($self, %opts, $arg) = @_;

    my $self = shift;
    my $arg = shift;

=cut
