package hashiter;
our $VERSION = '0.01';
sub import   { $^H{hashiter} = 1; }
sub unimport { delete $^H{hashiter}; }

1;
__END__

=head1 NAME

hashiter - allow destructive hash iterators

=head1 SYNOPSIS

    use hashiter;
    while( ($key, $val) = each %hash) { delete $hash{$key} unless $val; }
    no hashiter;

=head1 DESCRIPTION

This is a new user-pragma since cperl5.22.2 to allow destructive
changes of hash keys while iterating over the hash.

=cut
