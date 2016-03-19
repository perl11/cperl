package Internals::DumpArenas;
#ABSTRACT: Dump perl memory

use 5.006_000;

$VERSION = '0.12_03';

use DynaLoader ();
sub dl_load_flags { return 0x01 }
DynaLoader::bootstrap('Internals::DumpArenas', $VERSION);

use Exporter ();
@ISA = 'Exporter';
@EXPORT_OK = qw( DumpArenas DumpArenasFd );
%EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

q{ ...A most horrible treasure, this Great Ring," said Frito.

"And a horrible burden for he who bears it," said Goodgulf, "for some
unlucky one must carry it from Sorhed's grasp into danger and certain
doom. Someone must take the ring to the Zazu Pits of Fordor, under the
evil nose of the wrathful Sorhed, yet appear so unsuited to his task
that he will not soon be found out."

Frito shivered in sympathy for such an unfortunate.

"Then the bearer should be a complete and utter dunce," he laughed
nervously.

Goodgulf glanced at Dildo, who nodded and casually flipped a small,
shining object into Frito's lap. It was a ring.

"Congratulations," said Dildo somberly. "You've just won the booby
prize"... };

__END__

=head1 NAME

Internals::DumpArenas - Dump perl memory

=head1 DESCRIPTION

Dumps all of perl's regular values. This iterates over all values
reachable by the perl's normal memory management.

=head1 PERL FUNCTIONS

=head2 DumpArenas()

Dumps everything to STDERR.

=head1 C FUNCTIONS

=head2 DumpArenas(pTHX)

A C-exportable function. This calls DumpArenasFd but defaults to
printing to STDERR. Depending on whether your perl interpreter is
threaded, accepts the interpreter context.

From gdb:

    set $context = Perl_get_context()
    if $context
        call DumpArenas($context)
    else
        call DumpArenas()
    end

=head2 DumpArenasFd(pTHX_ int fd)

An exportable function, and the basis for DumpArenas(). The C<fd>
parameter is the file descriptor to write to. This lets you choose to
write to stdout or something else convenient.

Like the above function, this also accepts the interpreter context as
an argument for threaded perl.

From gdb:

    set $context = Perl_get_context()
    if $context
        # stdout: 1
        # stderr: 2
        call DumpArenasFd($context, 1)
    else
        call DumpArenasFd(1)
    end

=head1 OUTPUT FORMAT

=head2 INDIVIDUAL VALUES

At a basic level, each and every perl value is printed using the same
facility as the core function L<Devel::Peek::Dump>. This is a
low-level, verbose way of describing perl values:

  use Devel::Peek;
  Dump("Hello world!\n");
  Dump(42);

produces the following output. You can see the values "Hello world!\n"
and 42 but also other details of perl's implementation.

  SV = PV(0x9919128) at 0x992a7d8
    REFCNT = 1
    FLAGS = (POK,READONLY,pPOK)
    PV = 0x992f638 "Hello world!\n"\0
    CUR = 13
    LEN = 16
  SV = IV(0x992a7f4) at 0x992a7f8
    REFCNT = 1
    FLAGS = (IOK,READONLY,pIOK)
    IV = 42

=head2 Arrays

Array containers also consume space and hold pointers to perl
values. The general format is:

  AvARRAY(0x1123e150) = {address,address ...}

Arrays which have more entries allocated than used will show a
doubled-up entry with the "extra" part being visible at the end. The
general format is:

  AvARRAY(0x1117f3c0) = {{addresses}{addresses}}

and a specific example:

  AvARRAY(0x1117f3c0) = {{0x104a7b98,PL_sv_undef,PL_sv_undef}{PL_sv_undef}}

=head2 Hashes

Hash containers also consume space and hold pointers to perl
values. The general format is:

  HvARRAY(address)
    [address "key value"] => address
    [address "key value"] => address
    ...

A specific example:

  ARRAY(0x1123e1e0)
    [0x814a7c0 "_percentage"] => 0x104d5b78
    [0x814a840 "_description"] => 0x104d5b90
    [0x814a780 "_treatment_id"] => 0x104d5b60

=head2 Pointers

Pointers to special addresses are displayed symbolically:

=over

=item PL_sv_undef

=item PL_sv_yes

=item PL_sv_no

=item PL_sv_placeholder

=back

=head2

=head2 ARENA MAP

Each arena map is also printed as work is begun and finished.

  START ARENA = (0xfe4f360-0x1004f340)
  ...
  END ARENA = (0xfe4f360-0x1004f340)

Empty slots in the arena maps are printed as:

  AVAILABLE(0x10abf758)

=head1 BUGS

Please report any bugs or feature requests to
C<bug-Internals-DumpArenas at rt.cpan.org>, or through the web
interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Internals-DumpArenas>.
I will be notified, and then you'll automatically be notified of
progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

  perldoc Internals::DumpArenas

You can also look for information at:

=over

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Internals-DumpArenas>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Internals-DumpArenas>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Internals-DumpArenas>

=item * Search CPAN

L<http://search.cpan.org/dist/Internals-DumpArenas/>

=back

=head1 ACKNOWLEDGEMENTS

Brian Rice, totally.

I was inspired by L<http://netjam.org/spoon/viz/> and want to make the
same thing for perl.

=head1 COPYRIGHT & LICENSE

Copyright 2009-2011 Josh Jore, all rights reserved.
Copyright 2015 cPanel Inc, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SOURCE AVAILABILITY

This source is in Github: L<http://github.com/jbenjore/internals-dumparenas.git>
and the most recent version at L<http://github.com/rurban/internals-dumparenas.git>

=head1 AUTHOR

Josh Jore
