package hashiter;
our $VERSION = '0.02';
sub import   { $^H{unsafe_hashiter} = 1; }
sub unimport { delete $^H{unsafe_hashiter}; }

1;
__END__

=head1 NAME

hashiter - allow destructive hash iterators

=head1 SYNOPSIS

    use hashiter;
    while (($key, $val)=each %hash){ delete $hash{$key} unless $val; }
    no hashiter;

=head1 DESCRIPTION

This is a new user-pragma since cperl-5.29.0 to allow destructive
changes of hash keys while iterating over the hash.

Without use hashiter, deletion and insertion of hash keys during
iteration over this hash is forbidden, even the old perl lazydel scheme.

=cut
