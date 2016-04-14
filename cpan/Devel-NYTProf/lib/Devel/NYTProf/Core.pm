# vim: ts=8 sw=4 expandtab:
##########################################################
# This script is part of the Devel::NYTProf distribution
#
# Copyright, contact and other information can be found
# at the bottom of this file, or by going to:
# http://metacpan.org/release/Devel-NYTProf/
#
###########################################################
package Devel::NYTProf::Core;


use XSLoader;

our $VERSION = '6.03';    # increment with XS changes too

XSLoader::load('Devel::NYTProf', $VERSION);

# Fudging for https://rt.cpan.org/Ticket/Display.html?id=82256
$Devel::NYTProf::StrEvalTestPad = ($] <= 5.017004) ? ";\n" : "";

if (my $NYTPROF = $ENV{NYTPROF}) {
    for my $optval ( $NYTPROF =~ /((?:[^\\:]+|\\.)+)/g) {
        my ($opt, $val) = $optval =~ /^((?:[^\\=]+|\\.)+)=((?:[^\\=]+|\\.)+)\z/;
        s/\\(.)/$1/g for $opt, $val;

        if ($opt eq 'sigexit') {
            # Intercept sudden process exit caused by signals
            my @sigs = ($val eq '1') ? qw(INT HUP PIPE BUS SEGV) : split(/,/, $val);
            $SIG{uc $_} = sub { DB::finish_profile(); exit 1; } for @sigs;
            next; # no need to tell the XS code about this
        }

        if ($opt eq 'posix_exit') {
            # Intercept sudden process exit caused by POSIX::_exit() call.
            # Should only be needed if subs=0.  We delay till after profiling
            # has probably started to minimize the effect on the profile.
            eval q{ INIT {
                require POSIX;
                my $orig = \&POSIX::_exit;
                local $^W = 0; # avoid sub redef warning
                *POSIX::_exit = sub { DB::finish_profile(); $orig->(@_) };
            } 1 } or die if $val;
            next; # no need to tell the XS code about this
        }

        DB::set_option($opt, $val);
    }
}

1;

__END__

=head1 NAME

Devel::NYTProf::Core - load internals of Devel::NYTProf

=head1 DESCRIPTION

This module is not meant to be used directly.
See L<Devel::NYTProf>, L<Devel::NYTProf::Data>, and L<Devel::NYTProf::Reader>.

While it's not meant to be used directly, it is a handy place to document some
internals.

=head1 SUBROUTINE PROFILER

The subroutine profiler intercepts the C<entersub> opcode which perl uses to
invoke a subroutine, both XS subs (henceforth xsubs) and pure perl subs.

The following sections outline the way the subroutine profiler works:

=head2 Before the subroutine call

The profiler records the current time, the current value of
cumulative_subr_secs (as initial_subr_secs), and the current
cumulative_overhead_ticks (as initial_overhead_ticks).

The statement profiler measures time at the start and end of processing for
each statement (so time spent in the profiler, writing to the file for example,
is excluded.) It accumulates the measured overhead into the
cumulative_overhead_ticks variable.

In a similar way, the subroutine profiler measures the I<exclusive> time spent
in subroutines and accumulates it into the cumulative_subr_secs global.

=head2 Make the subroutine call

The call is made by executing the original perl internal code for the
C<entersub> opcode.

=head3 Calling a perl subroutine

If the sub being called is a perl sub then when the entersub opcode returns,
back into the subroutine profiler, the subroutine has been 'entered' but the
first opcode of the subroutine hasn't been executed yet.
Crucially though, a new scope has been entered by the entersub opcode.

The subroutine profiler then pushes a destructor onto the context stack.
The destructor is effectively just I<inside> the sub, like a C<local>, and so will be
triggered when the subroutine exits by I<any> means. Also, because it was the
first thing push onto the context stack, it will be triggered I<after> any
activity caused by the subroutines scope exiting.

When the destructor is invoked it calls a function which completes the
measurement of the time spent in the sub (see below).

In this way the profiling of perl subroutines is very accurate and robust.

=head3 Calling an xsub

If the sub being called is an xsub, then control doesn't return from the
entersub opcode until the xsub has returned. The profiler detects this and
calls the function which completes the measurement of the time spent in the
xsub.

So far so good, but there's a problem. What if the xsub doesn't return normally
but throws an exception instead?

In that case (currently) the profiler acts as if the xsub was never called.
Time spent inside the xsub will be allocated to the calling sub.

=head2 Completing the measurement

The function which completes the timing of a subroutine call does the following:

It calculates the time spent in the statement profiler:

    overhead_ticks  = cumulative_overhead_ticks - initial_overhead_ticks

and subtracts that from the total time spent 'inside' the subroutine:

    incl_subr_sec = (time now - time call was made) - overhead_ticks

That gives us an accurate I<inclusive> time. To get the I<exclusive> time
it calculates the time spent in subroutines called from the subroutine call
we're measuring:

    called_sub_secs = cumulative_subr_secs - initial_subr_secs

and subtracts that from the incl_subr_sec:

    excl_subr_sec = incl_subr_sec - called_sub_secs

To make that easier to follow, consider a call to a sub that calls no others.
In that case cumulative_subr_secs remains unchanged during the call, so
called_sub_secs is zero, and excl_subr_sec is the same as incl_subr_sec.

Finally, it adds the exclusive time to the cumulative exclusive time:

    cumulative_subr_secs += excl_subr_sec

=head1 AUTHOR

B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2008, 2009 by Tim Bunce.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
