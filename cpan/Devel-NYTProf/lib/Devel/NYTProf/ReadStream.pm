package Devel::NYTProf::ReadStream;

use warnings;
use strict;

our $VERSION = '4.00';

use base 'Exporter';
our @EXPORT_OK = qw(
     for_chunks
);

use Devel::NYTProf::Data;

sub for_chunks (&%) {
    my($cb, %opts) = @_;
    Devel::NYTProf::Data->new( {
        %opts,
	callback => $cb,
    });
}

1;

__END__

=head1 NAME

Devel::NYTProf::ReadStream - Read Devel::NYTProf data file as a stream

=head1 SYNOPSIS

  use Devel::NYTProf::ReadStream qw(for_chunks);

  for_chunks {
      my $tag = shift;
      print "$tag\n";
      # examine @_
      ....
  }

  # quickly dump content of a file
  use Data::Dump;
  for_chunks(\&dd);

=head1 DESCRIPTION

This module provide a low level interface for reading the contents of
F<nytprof.out> files (Devel::NYTProf data files) as a stream of chunks.

Currently the module only provide a single function:

=over

=item for_chunks( \&callback, %opts )

This function will read the F<nytprof.out> file and invoke the
given callback function for each chunk in the file.

The first argument passed to the callback is the chunk tag.  The rest
of the arguments passed depend on the tag.  See L</"Chunks"> for the
details.  The return value of the callback function is ignored.

The for_chunks() function will croak if the file can't be opened or if
the file format isn't recognized.  The global C<$.> variable is made
to track the chunk sequence numbers and can be inspected in the
callback.

The behaviour of the function can be modified by passing key/value
pairs after the callback. The contents of %opts are passed to
L<Devel::NYTProf::Data/new>.

The function is prototyped as C<(&%)> which means that it can be invoked with a
bare block representing the callback function.  In that case there should be no
comma before any options.  Example:

  for_chunk { say $_[0] } filename => "myprof.out";

=back

=head2 Chunks

The F<nytprof.out> file contains a sequence of tagged chunks that are
streamed out as the profiled program runs.  This documents how the
chunks appear when presented to the callback function of the
for_chunks() function for version 4.0 of the file format.

I<Note that the chunks and their arguments are liable to change
between versions as NYTProf evolves.>

=over

=item VERSION => $major, $minor

The first chunk in the file declare what version of the file format
was used for the current file.

=item COMMENT => $text

This chunk is just some textual content that can be ignored.

=item ATTRIBUTE => $key, $value

This chunk type is repeated at the beginning of the file and used to
declare various facts about the profiling run.  The only one that's
really interesting is C<ticks_per_sec> that tell you how to convert
the $ticks values into seconds.

The attributes reported are:

=over

=item basetime => $time

The time (epoch based) when the profiled perl process started.
It's the same value as C<$^T>.

=item xs_version => $ver

The version of the Devel::NYTProf used for profiling.

=item perl_version => $ver

The version of perl used for profiling.  This is a string like "5.10.1".

=item clock_id => $num

What kind of clock was used to profile the program.  Will be C<-1> for
the default clock.

=item ticks_per_sec => $num

Divide the $ticks values in TIME_BLOCK/TIME_LINE by this number to
convert the time to seconds.

=item nv_size => 8

The $Config{nv_size} of the perl that wrote this file.  This value
must match for the perl that reads the file as well.

=item application => $string

The path to the program that ran; same as C<$0> in the program itself.

=back

=item OPTION => $key, $value

This chunk type is repeated at the beginning of the file and used to record the
options, e.g. set via the NYTPROF env var, that were effect during the
profiling run.

=item START_DEFLATE

This chunk just say that from now on all chunks have been compressed
in the file.

=item PID_START => $pid, $parent_pid, $start_time

The process with the given $pid starts running (under the profiler).

Dates from the way forking used to be supported. Likely to get
deprecated when we get better support for tracking the time the sub
profiler and statement profiler were actually active. (Which is needed
to calculate percentages.)

=item NEW_FID => $fid, $eval_fid, $eval_line, $flags, $size, $mtime, $name

Files are represented by integers called 'fid' (File IDs) and this chunk declares
the mapping between these numbers and file path names.

=item TIME_BLOCK => $ticks, $fid, $line, $block_line, $sub_line

=item TIME_LINE => $ticks, $fid, $line

A TIME_BLOCK or TIME_LINE chunk is output each time the execution of
the program leaves a statement.

=item DISCOUNT

Indicates that the next TIME_BLOCK or TIME_LINE should not increment the
"number of times the statement was executed". See the 'leave' option.

=item SUB_INFO => $fid, $first_line, $last_line, $name

At the end of the run the profiler will output chunks that report on
the perl subroutines defined in all the files visited while profiling.
See also C<%DB::sub> in L<perldebguts>.

=item SUB_CALLERS => $fid, $line, $count, $incl_time, $excl_time, $reci_time, $rec_depth, $name, $caller_name

At the end of the run the profiler will output chunks that report on
where subroutines were called from.

=item SRC_LINE => $fid, $line, $text

Used to reproduce the source code of the files and evals profiled.
Requires perl 5.8.9+ or 5.10.1+ or 5.12 or later. For earlier versions of perl
the source code of C<< perl -e '...' >> and C<< perl - >> 'files' is available
if the C<use_db_sub=1> option was used when profiling.

=item PID_END => $pid, $end_time

The process with the given $pid is done running.  See the description
of PID_START above.

=back

=head1 SEE ALSO

L<Devel::NYTProf>, L<Devel::NYTProf::Data>

=head1 AUTHOR

B<Gisle Aas>

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2008 by Adam Kaplan and The New York Times Company.
 Copyright (C) 2008 by Tim Bunce, Ireland.
 Copyright (C) 2008 by Gisle Aas

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
