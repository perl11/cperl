package Mu;
our $VERSION = 0.01;
#method new (); # see XS universal.c
#method CREATE (); # see XS
1;
__END__

=pod

=encoding UTF-8

=head1 NAME

Mu - The root of the cperl type hierarchy

=head1 SYNOPSIS

    class MyClass {
      has $a = 1;
    }
    my MyClass $obj = new MyClass;
    print $obj->{a}; 	# OUTPUT: «1»

=head1 DESCRIPTION

B<Mu> provides generic methods for all cperl classes. All classes
derive from B<Mu>, the last C<@ISA> entry is always C<"Mu">.  The
common prefix mu 無 means "not have", "without" in East Asian
languages.

=head1 METHODS

=over 4

=item new CLASSNAME, @ARGS

Creates a new object as avref with the declared number of fields (i.e.
number of C<has> declarations, with padix offsets stored in
C<@CLASSNAME::FIELDS>).

The array is shaped, and the field entries are initialized from the
given positional args, and if missing from the initial class value, or
if that is missing as C<undef>.

=item CREATE CLASSNAME

Creates a new object as avref with the declared number of fields (i.e.
number of C<has> declarations, with padix offsets stored in
C<@CLASSNAME::FIELDS>).
The array is shaped, but the field entries are left empty.

=back

... I<Many more methods to come>, see
L<https://docs.perl6.org/type/Mu>

=head1 SUBROUTINES

=over 4

=item defined ARGUMENT

    multi sub    defined (Mu) :Bool
    multi method defined ()   :Bool

Returns False on the type object, and True otherwise.

    say Int->defined;                # OUTPUT: «False»
    my Int $i = 42;
    say $i->defined;                 # OUTPUT: «True» 

Very few types (like Failure) override defined to return False even
for instances:

    sub fails() { die 'oh noe' };
    say fails()->defined;            # OUTPUT: «False» 

=back

... I<Many more subroutines to come>, see
L<https://docs.perl6.org/type/Mu>

=cut
