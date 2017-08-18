package exact_arith;
our $VERSION = '0.01';
my $HINT_EXACT_ARITH = 0x0000010; # see perl.h

sub import {
  $^H |= $HINT_EXACT_ARITH;
  # $^H{exact_arith} = 'Math::BigInt';
}
sub unimport {
  #delete $^H{exact_arith};
  $^H &= ~$HINT_EXACT_ARITH;
}

1;
__END__

=head1 NAME

exact_arith - promote on overflow to bigint/num

=head1 SYNOPSIS

    use exact_arith;
    print 18446744073709551614 * 2; # => 36893488147419103228, a Math::BigInt object

    { no exact_arith;
      print 18446744073709551614 * 2; # => 3.68934881474191e+19
    }

=head1 DESCRIPTION

This is a new lexical user-pragma since cperl 5.32 to use exact
arithmetic, without loosing precision on all builtin integer
arithmetic ops.  As in perl6, but only for integer arithmetic and much
faster.

There's no noticible performance hit. It's much faster than
perl6, since it only does use bigint on IV/UV overflows which do
happen very seldom.

When L<Math::BigInt::GMP> is available it is preferred, otherwise it
falls back to L<Math::BigInt>.

=cut
