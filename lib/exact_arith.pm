package exact_arith;
our $VERSION = '0.01';
sub unimport { delete $^H{exact_arith}; }
sub import { $^H{exact_arith} = 1; }

1;
__END__

=head1 NAME

exact_arith - promote on overflow to bigint/num

=head1 SYNOPSIS

    use exact_arith;
    print 18446744073709551614 * 2; # => 36893488147419103228, a bigint object

    { no exact_arith;
      print 18446744073709551614 * 2; # => 3.68934881474191e+19
    }

=head1 DESCRIPTION

This is a new lexical user-pragma since cperl5.24 to use exact
arithmetic, without loosing precision on all builtin arithmetic ops.
As in perl6.

It is of course a bit slower, than without.

=cut
