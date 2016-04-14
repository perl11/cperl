# vim: ts=8 sw=2 sts=0 noexpandtab:
##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://metacpan.org/release/Devel-NYTProf/
##
###########################################################
package Devel::NYTProf;

our $VERSION = '6.03'; # also change in Devel::NYTProf::Core

package    # hide the package from the PAUSE indexer
    DB;

# Enable specific perl debugger flags (others may be set later).
# Set the flags that influence compilation ASAP so we get full details
# (sub line ranges etc) of modules loaded as a side effect of loading
# Devel::NYTProf::Core (ie XSLoader, strict, Exporter etc.)
# See "perldoc perlvar" for details of the $^P ($PERLDB) flags
$^P = 0x010     # record line range of sub definition
    | 0x100     # informative "file" names for evals
    | 0x200;    # informative names for anonymous subroutines

require Devel::NYTProf::Core;    # loads XS and sets options

# XXX hack, need better option handling e.g., add DB::get_option('use_db_sub')
my $use_db_sub = ($ENV{NYTPROF} && $ENV{NYTPROF} =~ m/\buse_db_sub=1\b/);
if ($use_db_sub) {                     # install DB::DB sub
    *DB = ($] < 5.008008)
        ? sub { goto &DB_profiler }    # workaround bug in old perl versions (slow)
        : \&DB_profiler;
}

# DB::sub shouldn't be called, but needs to exist for perl <5.8.7 (<perl@24265)
# Could be called in obscure cases, e.g. if "perl -d" (not -d:NYTProf)
# was used with Devel::NYTProf loaded some other way
sub sub { die "DB::sub called unexpectedly" }

sub CLONE { DB::disable_profiler }

init_profiler();                       # provides true return value for module

# put nothing here!

__END__

=head1 NAME

Devel::NYTProf - Powerful fast feature-rich Perl source code profiler

=head1 SYNOPSIS

  # profile code and write database to ./nytprof.out
  perl -d:NYTProf some_perl.pl

  # convert database into a set of html files, e.g., ./nytprof/index.html
  # and open a web browser on the nytprof/index.html file
  nytprofhtml --open

  # or into comma separated files, e.g., ./nytprof/*.csv
  nytprofcsv

I give talks on profiling perl code, including a detailed look at how to use
NYTProf and how to optimize your code, every year. A video of my YAPC::NA 2014
talk can be found at L<http://perltv.org/v/performance-profiling-with-develnytprof>


=head1 DESCRIPTION

Devel::NYTProf is a powerful, fast, feature-rich perl source code profiler.

=over

=item *

Performs per-line statement profiling for fine detail

=item *

Performs per-subroutine statement profiling for overview

=item *

Performs per-opcode profiling for slow perl builtins

=item *

Performs per-block statement profiling (the first profiler to do so)

=item *

Accounts correctly for time spent after calls return

=item *

Performs inclusive and exclusive timing of subroutines

=item *

Subroutine times are per calling location (a powerful feature)

=item *

Can profile compile-time activity, just run-time, or just END time

=item *

Uses novel techniques for efficient profiling

=item *

Sub-microsecond (100ns) resolution on supported systems

=item *

Very fast - the fastest statement and subroutine profilers for perl

=item *

Handles applications that fork, with no performance cost

=item *

Immune from noise caused by profiling overheads and I/O

=item *

Program being profiled can stop/start the profiler

=item *

Generates richly annotated and cross-linked html reports

=item *

Captures source code, including string evals, for stable results

=item *

Trivial to use with mod_perl - add one line to httpd.conf

=item *

Includes an extensive test suite

=item *

Tested on very large codebases

=back

NYTProf is effectively two profilers in one: a statement profiler, and a
subroutine profiler.

=head2 Statement Profiling

The statement profiler measures the time between entering one perl statement
and entering the next. Whenever execution reaches a new statement, the time
since entering the previous statement is calculated and added to the time
associated with the line of the source file that the previous statement starts on.

By default the statement profiler also determines the first line of the current
block and the first line of the current statement, and accumulates times
associated with those.

Another innovation unique to NYTProf is automatic compensation for a problem
inherent in simplistic statement-to-statement timing. Consider a statement that
calls a subroutine and then performs some other work that doesn't execute new
statements, for example:

  foo(...) + mkdir(...);

In all other statement profilers the time spent in remainder of the expression
(mkdir in the example) will be recorded as having been spent I<on the last
statement executed in foo()>! Here's another example:

  while (<>) {
     ...
     1;
  }

After the first time around the loop, any further time spent evaluating the
condition (waiting for input in this example) would be recorded as having
been spent I<on the last statement executed in the loop>! (Until perl bug
#60954 is fixed this problem still applies to some loops. For more information
see L<http://rt.perl.org/rt3/Ticket/Display.html?id=60954>)

NYTProf avoids these problems by intercepting the opcodes which indicate that
control is returning into some previous statement and adjusting the profile
accordingly.

The statement profiler naturally generates a lot of data which is streamed out
to a file in a very compact format. NYTProf takes care to not include the
measurement and writing overheads in the profile times (some profilers produce
'noisy' data due to periodic stdio flushing).

=head2 Subroutine Profiling

The subroutine profiler measures the time between entering a subroutine and
leaving it. It then increments a call count and accumulates the duration.
For each subroutine called, separate counts and durations are stored I<for each
location that called the subroutine>.

Subroutine entry is detected by intercepting the C<entersub> opcode. Subroutine
exit is detected via perl's internal save stack. As a result the subroutine
profiler is both fast and robust.

=head3 Subroutine Recursion

For subroutines that recurse directly or indirectly, such as Error::try,
the inclusive time is only measured for the outer-most call.

The inclusive times of recursive calls are still measured and are accumulated
separately. Also the 'maximum recursion depth' per calling location is recorded.

=head3 Goto &Subroutine

Perl implements a C<goto &destination> as a C<return> followed by a call to
C<&destination>, so that's how it will appear in the report.

The C<goto> will be shown with a very short time because it's effectively just
a C<return>. The C<&destination> sub will show a call I<not> from the location
of the C<goto> but from the location of the call to the sub that performed the C<goto>.

=head3 accept()

The perl built-in accept() function waits listening for a connection on a
socket, and so is a key part of pure-perl network service applications.

The time spent waiting for a remotely initiated connection can be relatively
high but is not relevant to the performance of the application. So the accept()
function is treated as a special case. The subroutine profiler discounts the
time spent in the accept() function. It does this in a way that also discounts
that time from all the callers up the call stack. The effect on the reports is
that all accept() calls appear to be instant.

The I<statement> profiler still shows the time actually spent in the statement
that executed the accept() call.

=head2 Application Profiling

NYTProf records extra information in the data file to capture details that may
be useful when analyzing the performance. It also records the filename and line
ranges of all the subroutines.

NYTProf can profile applications that fork, and does so with no loss of
performance.
NYTProf detects the fork and starts writing a new profile file with the pid
appended to the filename. Since L<nytprofhtml> only works with a single profile
file you may want to merge multiple files using L<nytprofmerge>.

=head2 Fast Profiling

The NYTProf profiler is written almost entirely in C and great care has been
taken to ensure it's very efficient.

=head2 Apache Profiling

Just add one line near the start of your httpd.conf file:

  PerlModule Devel::NYTProf::Apache

By default you'll get a F</tmp/nytprof.$$.out> file for the parent process and
a F</tmp/nytprof.$parent.out.$$> file for each worker process.

NYTProf takes care to detect when control is returning back from perl to
mod_perl so time spent in mod_perl (such as waiting for the next request)
does not get allocated to the last statement executed.

Works with mod_perl 1 and 2. See L<Devel::NYTProf::Apache> for more information.

=head1 PROFILING

Usually you'd load Devel::NYTProf on the command line using the perl -d option:

  perl -d:NYTProf some_perl.pl

To save typing the ':NYTProf' you could set the PERL5DB env var 

  PERL5DB='use Devel::NYTProf'

and then just perl -d would work:

  perl -d some_perl.pl

Or you can avoid the need to add the -d option at all by using the C<PERL5OPT> env var:

  PERL5OPT=-d:NYTProf

That's also very handy when you can't alter the perl command line being used to
run the script you want to profile. Usually you'll want to enable the
L</addpid=1> option to ensure any nested invocations of perl don't overwrite the profile.

=head1 NYTPROF ENVIRONMENT VARIABLE

The behavior of Devel::NYTProf may be modified by setting the 
environment variable C<NYTPROF>.  It is possible to use this environment
variable to effect multiple setting by separating the values with a C<:>.  For
example:

  export NYTPROF=trace=2:start=init:file=/tmp/nytprof.out

Any colon or equal characters in a value can be escaped by preceding them with
a backslash.

=head2 addpid=1

Append the current process id to the end of the filename.

This avoids concurrent, or consecutive, processes from overwriting the same file.
If a fork is detected during profiling then the child process will automatically
add the process id to the filename.

=head2 addtimestamp=1

Append the current time, as integer epoch seconds, to the end of the filename.

=head2 trace=N

Set trace level to N. 0 is off (the default). Higher values cause more detailed
trace output. Trace output is written to STDERR or wherever the L</log=F>
option has specified.

=head2 log=F

Specify the name of the file that L</trace=N> output should be written to.

=head2 start=...

Specify at which phase of program execution the profiler should be enabled:

  start=begin - start immediately (the default)
  start=init  - start at beginning of INIT phase (after compilation/use/BEGIN)
  start=end   - start at beginning of END phase
  start=no    - don't automatically start

The start=no option is handy if you want to explicitly control profiling
by calling DB::enable_profile() and DB::disable_profile() yourself.
See L</RUN-TIME CONTROL OF PROFILING>.

The start=init option is handy if you want to avoid profiling the loading and
initialization of modules.

=head2 optimize=0

Disable the perl optimizer.

By default NYTProf leaves perl's optimizer enabled.  That gives you more
accurate profile timing overall, but can lead to I<odd> statement counts for
individual sets of lines. That's because the perl's peephole optimizer has
effectively rewritten the statements but you can't see what the rewritten
version looks like.

For example:

  1     if (...) {
  2         return;
  3     }

may be rewritten as

  1    return if (...)

so the profile won't show a statement count for line 2 in your source code
because the C<return> was merged into the C<if> statement on the preceding line.

Also 'empty' statements like C<1;> are removed entirely.  Such statements are
empty because the optimizer has already removed the pointless constant in void
context. It then goes on to remove the now empty statement (in perl >= 5.13.7).

Using the C<optimize=0> option disables the optimizer so you'll get lower
overall performance but more accurately assigned statement counts.

If you find any other examples of the effect of optimizer on NYTProf output
(other than performance, obviously) please let us know.

=head2 subs=0

Set to 0 to disable the collection of subroutine caller and timing details.

=head2 blocks=1

Set to 1 to enable the determination of block and subroutine location per statement.
This makes the profiler about 50% slower (as of July 2008) and produces larger
output files, but you gain some valuable insight in where time is spent in the
blocks within large subroutines and scripts.

=head2 stmts=0

Set to 0 to disable the statement profiler. (Implies C<blocks=0>.)
The reports won't contain any statement timing detail.

This significantly reduces the overhead of the profiler and can also be useful
for profiling large applications that would normally generate a very large
profile data file.

=head2 calls=N

This option is I<new and experimental>.

With calls=1 (the default) subroutine call I<return> events are emitted into
the data stream as they happen.  With calls=2 subroutine call I<entry> events
are also emitted. With calls=0 no subroutine call events are produced.
This option depends on the C<subs> option being enabled, which it is by default.

The L<nytprofcalls> utility can be used to process this data. It too is I<new
and experimental> and so likely to change.

The subroutine profiler normally gathers data in memory and outputs a summary
when the profile data is being finalized, usually when the program has finished.
The summary contains aggregate information for all the calls from one location
to another, but the details of individual calls have been lost.
The calls option enables the recording of individual call events and thus
more detailed analysis and reporting of that data.

=head2 leave=0

Set to 0 to disable the extra work done by the statement profiler
to allocate times accurately when
returning into the middle of statement. For example leaving a subroutine
and returning into the middle of statement, or re-evaluating a loop condition.

This feature also ensures that in embedded environments, such as mod_perl,
the last statement executed doesn't accumulate the time spent 'outside perl'.

=head2 findcaller=1

Force NYTProf to recalculate the name of the caller of the each sub instead of
'inheriting' the name calculated when the caller was entered. (Rarely needed,
but might be useful in some odd cases.)

=head2 use_db_sub=1

Set to 1 to enable use of the traditional DB::DB() subroutine to perform
profiling, instead of the faster 'opcode redirection' technique that's used by
default. Also effectively sets C<leave=0> (see above).

The default 'opcode redirection' technique can't profile subroutines that were
compiled before NYTProf was loaded. So using use_db_sub=1 can be useful in
cases where you can't load the profiler early in the life of the application.

Another side effect of C<use_db_sub=1> is that it enables recording of the
source code of the C<< perl -e '...' >> and C<< perl - >> input for old
versions of perl. See also L</savesrc=0>.

=head2 savesrc=0

Disable the saving of source code.

By default NYTProf saves a copy of all source code into the profile data file.
This makes the file self-contained, so the reporting tools no longer depend on
having the unmodified source code files available.

With C<savesrc=0> some source code is still saved: the arguments to the
C<perl -e> option, the script fed to perl via STDIN when using C<perl ->,
and the source code of string evals.

Saving the source code of string evals requires perl version 5.8.9+, 5.10.1+,
or 5.12 or later.

Saving the source code of the C<< perl -e '...' >> or C<< perl - >> input
requires either a recent perl version, as above, or setting the L</use_db_sub=1> option.

=head2 slowops=N

Profile perl opcodes that can be slow. These include opcodes that make system
calls, such as C<print>, C<read>, C<sysread>, C<socket> etc., plus regular
expression opcodes like C<subst> and C<match>.

If C<N> is 0 then slowops profiling is disabled.

If C<N> is 1 then all the builtins are treated as being defined in the C<CORE>
package. So times for C<print> calls from anywhere in your code are merged and
accounted for as calls to an xsub called C<CORE::print>.

If C<N> is 2 (the default) then builtins are treated as being defined in the
package that calls them. So calls to C<print> from package C<Foo> are treated
as calls to an xsub called C<Foo::CORE:print>. Note the single colon after CORE.

The opcodes are currently profiled using their internal names, so C<printf> is C<prtf>
and the C<-x> file test is C<fteexec>. This may change in future.

Opcodes that call subroutines, perhaps by triggering a FETCH from a tied
variable, currently appear in the call tree as the caller of the sub. This is
likely to change in future.

=head2 usecputime=1

This option has been removed. Profiling won't be enabled if set.

Use the L</clock=N> option to select a high-resolution CPU time clock, if
available on your system, instead. That will give you higher resolution and work
for the subroutine profiler as well.

=head2 file=...

Specify the output file to write profile data to (default: './nytprof.out').

=head2 compress=...

Specify the compression level to use, if NYTProf is compiled with compression
support. Valid values are 0 to 9, with 0 disabling compression. The default is
6 as higher values yield little extra compression but the cpu cost starts to
rise significantly. Using level 1 still gives you a significant reduction in file size.

If NYTProf was not compiled with compression support, this option is silently ignored.

=head2 clock=N

Systems which support the C<clock_gettime()> system call typically
support several clocks. By default NYTProf uses CLOCK_MONOTONIC.

This option enables you to select a different clock by specifying the
integer id of the clock (which may vary between operating system types).
If the clock you select isn't available then CLOCK_REALTIME is used.

See L</CLOCKS> for more information.

=head2 sigexit=1

When perl exits normally it runs any code defined in C<END> blocks.
NYTProf defines an END block that finishes profiling and writes out the final
profile data.

If the process ends due to a signal then END blocks are not executed so the
profile will be incomplete and unusable.  The C<sigexit> option tells NYTProf
to catch some signals (e.g. INT, HUP, PIPE, SEGV, BUS) and ensure a usable
profile by executing:

    DB::finish_profile();
    exit 1;

You can also specify which signals to catch in this way by listing them,
separated by commas, as the value of the option (case is not significant):

    sigexit=int,hup

=head2 posix_exit=1

The NYTProf subroutine profiler normally detects calls to C<POSIX::_exit()>
(which exits the process without running END blocks) and automatically calls
C<DB::finish_profile()> for you, so NYTProf 'just works'.

When using the C<subs=0> option to disable the subroutine profiler the
C<posix_exit> option can be used to tell NYTProf to take other steps to arrange
for C<DB::finish_profile()> to be called before C<POSIX::_exit()>.

=head2 libcexit=1

Arranges for L</finish_profile> to be called via the C library C<atexit()> function.
This may help some tricky cases where the process may exit without perl
executing the C<END> block that NYTProf uses to call /finish_profile().

=head2 endatexit=1

Sets the PERL_EXIT_DESTRUCT_END flag in the PL_exit_flags of the perl interpreter.
This makes perl run C<END> blocks in perl_destruct() instead of perl_run()
which may help in cases, like Apache, where perl is embedded but perl_run()
isn't called.

=head2 forkdepth=N

When a perl process that is being profiled executes a fork() the child process
is also profiled. The forkdepth option can be used to control this. If
forkdepth is zero then profiling will be disabled in the child process.

If forkdepth is greater than zero then profiling will be enabled in the child
process and the forkdepth value in that process is decremented by one.

If forkdepth is -1 (the default) then there's no limit on the number of
generations of children that are profiled.

=head2 nameevals=0

The 'file name' of a string eval is normally a string like "C<(eval N)>", where
C<N> is a sequence number. By default NYTProf asks perl to give evals more
informative names like "C<(eval N)[file:line]>", where C<file> and C<line> are
the file and line number where the string C<eval> was executed.

The C<nameevals=0> option can be used to disable the more informative names and
return to the default behaviour. This may be need in rare cases where the
application code is sensitive to the name given to a C<eval>. (The most common
case in when running test suites undef NYTProf.)

The downside is that the NYTProf reporting tools are less useful and may get
confused if this option is used.

=head2 nameanonsubs=0

The name of a anonymous subroutine is normally "C<__ANON__>".  By default
NYTProf asks perl to give anonymous subroutines more informative names like
"C<__ANON__[file:line]>", where C<file> and C<line> are the file and line
number where the anonymous subroutine was defined.

The C<nameanonsubs=0> option can be used to disable the more informative names
and return to the default behaviour. This may be need in rare cases where the
application code is sensitive to the name given to a anonymous subroutines.
(The most common case in when running test suites undef NYTProf.)

The downside is that the NYTProf reporting tools are less useful and may get
confused if this option is used.

=head1 RUN-TIME CONTROL OF PROFILING

You can profile only parts of an application by calling DB::disable_profile()
to stop collecting profile data, and calling DB::enable_profile() to start
collecting profile data.

Using the C<start=no> option lets you leave the profiler disabled initially
until you call DB::enable_profile() at the right moment. You still need to
load Devel::NYTProf as early as possible, even if you don't call
DB::enable_profile() until much later. That's because any code that's compiled
before Devel::NYTProf is loaded will not be profiled by default. See also
L</use_db_sub=1>.

The profile output file can't be used until it's been properly completed and
closed.  Calling DB::disable_profile() doesn't do that.  To make a profile file
usable before the profiled application has completed you can call
DB::finish_profile(). Alternatively you could call DB::enable_profile($newfile).

Always call the DB::enable_profile(), DB::disable_profile() or
DB::finish_profile() function with the C<DB::> prefix as shown because you
can't import them. They're provided automatically when NYTProf is in use.

=head2 disable_profile

  DB::disable_profile()

Stops collection of profile data until DB:enable_profile() is called.

Subroutine calls which were made while profiling was enabled and are still on
the call stack (have not yet exited) will still have their profile data
collected when they exit. Compare with L</finish_profile> below.

=head2 enable_profile

  DB::enable_profile($newfile)
  DB::enable_profile()

Enables collection of profile data. If $newfile is specified the profile data will be
written to $newfile (after completing and closing the previous file, if any).
If $newfile already exists it will be deleted first.
If DB::enable_profile() is called without a filename argument then profile data
will continue to be written to the current file (nytprof.out by default).

=head2 finish_profile

  DB::finish_profile()

Calls DB::disable_profile(), then completes the profile data file by writing
subroutine profile data, and then closes the file. The in memory subroutine
profile data is then discarded.

Normally NYTProf arranges to call finish_profile() for you via an END block.

=head1 DATA COLLECTION AND INTERPRETATION

NYTProf tries very hard to gather accurate information.  The nature of the
internals of perl mean that, in some cases, the information that's gathered is
accurate but surprising. In some cases it can appear to be misleading.
(Of course, in some cases it may actually be plain wrong. Caveat lector.)

=head2 If Statement and Subroutine Timings Don't Match

NYTProf has two profilers: a statement profiler that's invoked when perl moves
from one perl statement to another, and a subroutine profiler that's invoked
when perl calls or returns from a subroutine.

The individual statement timings for a subroutine usually add up to slightly
less than the exclusive time for the subroutine. That's because the handling of
the subroutine call and return overheads is included in the exclusive time for
the subroutine. The difference may only be a few microseconds but that may
become noticeable for subroutines that are called hundreds of thousands of times.

The statement profiler keeps track how much time was spent on overheads, like
writing statement profile data to disk. The subroutine profiler subtracts the
overheads that have accumulated between entering and leaving the subroutine in
order to give a more accurate profile.  The statement profiler is generally
very fast because most writes get buffered for zip compression so the profiler
overhead per statement tends to be very small, often a single 'tick'.
The result is that the accumulated overhead is quite noisy. This becomes more
significant for subroutines that are called frequently and are also fast.
This may be another, smaller, contribution to the discrepancy between statement
time and exclusive times.

=head2 If Headline Subroutine Timings Don't Match the Called Subs

Overall subroutine times are reported with a headline like C<spent 10s (2+8) within ...>.
In this example, 10 seconds were spent inside the subroutine (the "inclusive
time") and, of that, 8 seconds were spent in subroutines called by this one.
That leaves 2 seconds as the time spent in the subroutine code itself (the
"exclusive time", sometimes also called the "self time").

The report shows the source code of the subroutine. Lines that make calls to
other subroutines are annotated with details of the time spent in those calls.

Sometimes the sum of the times for calls made by the lines of code in the
subroutine is less than the inclusive-exclusive time reported in the headline
(10-2 = 8 seconds in the example above).

What's happening here is that calls to other subroutines are being made but
NYTProf isn't able to determine the calling location correctly so the calls
don't appear in the report in the correct place.

Using an old version of perl is one cause (see below). Another is calling
subroutines that exit via C<goto &sub;> - most frequently encountered in
AUTOLOAD subs and code using the L<Memoize> module.

In general the overall subroutine timing is accurate and should be trusted more
than the sum of statement or nested sub call timings.

=head2 Perl 5.10.1+ (or else 5.8.9+) is Recommended

These versions of perl yield much more detailed information about calls to
BEGIN, CHECK, INIT, and END blocks, the code handling tied or overloaded
variables, and callbacks from XS code.

Perl 5.12 will hopefully also fix an inaccuracy in the timing of the last
statement and the condition clause of some kinds of loops:
L<http://rt.perl.org/rt3/Ticket/Display.html?id=60954>

=head2 eval $string

Perl treats each execution of a string eval (C<eval $string;> not C<eval { ...  }>)
as a distinct file, so NYTProf does as well. The 'files' are given names with
this structure:

	(eval $sequence)[$filename:$line]

for example "C<(eval 93)[/foo/bar.pm:42]>" would be the name given to the
93rd execution of a string eval by that process and, in this case, the 93rd
eval happened to be one at line 42 of "/foo/bar.pm".

Nested string evals can give rise to file names like

	(eval 1047)[(eval 93)[/foo/bar.pm:42]:17]

=head3 Merging Evals

Some applications execute a great many string eval statements. If NYTProf generated
a report page for each one it would not only slow report generation but also
make the overall report less useful by scattering performance data too widely.
On the other hand, being able to see the actual source code executed by an
eval, along with the timing details, is often I<very> useful.

To try to balance these conflicting needs, NYTProf currently I<merges
uninteresting string eval siblings>.

What does that mean? Well, for each source code line that executed any string
evals, NYTProf first gathers the corresponding eval 'files' for that line
(known as the 'siblings') into groups keyed by distinct source code.

Then, for each of those groups of siblings, NYTProf will 'merge' a group
that shares the same source code and doesn't execute any string evals itself.
Merging means to pick one sibling as the survivor and merge and delete all
the data from the others into it.

If there are a large number of sibling groups then the data for all of them are
merged into one regardless.

The report annotations will indicate when evals have been merged together.

=head3 Merging Anonymous Subroutines

Anonymous subroutines defined within string evals have names like this:

	main::__ANON__[(eval 75)[/foo/bar.pm:42]:12]

That anonymous subroutine was defined on line 12 of the source code executed by
the string eval on line 42 of F</foo/bar.pm>. That was the 75th string eval
executed by the program.

Anonymous subroutines I<defined on the same line of sibling evals that get
merged> are also merged. That is, the profile information is merged into
one and the others are discarded.

=head3 Timing

Care should be taken when interpreting the report annotations associated with a
string eval statement.  Normally the report annotations embedded into the
source code related to timings from the I<subroutine> profiler. This isn't
(currently) true of annotations for string eval statements.

This makes a significant different if the eval defines any subroutines that get
called I<after> the eval has returned. Because the time shown for a string eval
is based on the I<statement> times it will include time spent executing
statements within the subs defined by the eval.

In future NYTProf may involve the subroutine profiler in timings evals and so
be able to avoid this issue.

=head2 Calls from XSUBs and Opcodes

Calls record the current filename and line number of the perl code at the time
the call was made. That's fine and accurate for calls from perl code. For calls
that originate from C code however, such as an XSUB or an opcode, the filename and
line number recorded are still those of the last I<perl> statement executed.

For example, a line that calls an xsub will appear in reports to also have also
called any subroutines that that xsub called. This can be construed as a feature.

As an extreme example, the first time a regular expression that uses character
classes is executed on a unicode string you'll find profile data like this:

      # spent 1ms within main::BEGIN@4 which was called
      #    once (1ms+0s) by main::CORE:subst at line 0
  4   s/ (?: [A-Z] | [\d] )+ (?= [\s] ) //x;
      # spent  38.8ms making 1 call to main::CORE:subst
      # spent  25.4ms making 2 calls to utf8::SWASHNEW, avg 12.7ms/call
      # spent  12.4ms making 1 call to utf8::AUTOLOAD

=for comment
No doubt more odd cases will be added here over time.

=head1 MAKING NYTPROF FASTER

You can reduce the cost of profiling by adjusting some options. The trade-off
is reduced detail and/or accuracy in reports.

If you don't need statement-level profiling then you can disable it via L</stmts=0>.
To further boost statement-level profiling performance try L</leave=0> but note that
I<will> apportion timings for some kinds of statements less accurate).

If you don't need call stacks or flamegraph then disable it via L</calls=0>.
If you don't need subroutine profiling then you can disable it via L</subs=0>.
If you do need it but don't need timings for perl opcodes then set L</slowops=0>.

Generally speaking, setting calls=0 and slowops=0 will give you a useful boost
with the least loss of detail.

Another approach is to only enable NYTProf in the sections of code that
interest you. See L</RUN-TIME CONTROL OF PROFILING> for more details.

To speed up L<nytprofhtml> try using the --minimal (-m) or --no-flame options.

=head1 REPORTS

The L<Devel::NYTProf::Data> module provides a low-level interface for loading
the profile data.

The L<Devel::NYTProf::Reader> module provides an interface for generating
arbitrary reports.  This means that you can implement your own output format in
perl. (Though the module is in a state of flux and may be deprecated soon.)

Included in the bin directory of this distribution are some scripts which
turn the raw profile data into more useful formats:

=head2 nytprofhtml

Creates attractive, richly annotated, and fully cross-linked html
reports (including statistics, source code and color highlighting).
This is the main report generation tool for NYTProf.

=head2 nytprofcg

Translates a profile into a format that can be loaded into KCachegrind
L<http://kcachegrind.github.io/>

=head2 nytprofcalls

Reads a profile and processes the calls events it contains.

=head2 nytprofmerge

Reads multiple profile data files and writes out a new file containing the merged profile data.

=head1 LIMITATIONS

=head2 Threads and Multiplicity

C<Devel::NYTProf> is not currently thread safe or multiplicity safe.
If you'd be interested in helping to fix that then please get in
touch with us. Meanwhile, profiling is disabled when a thread is created, and
NYTProf tries to ignore any activity from perl interpreters other than the
first one that loaded it.

=head2 Coro

The C<Devel::NYTProf> subroutine profiler gets confused by the stack gymnastics
performed by the L<Coro> module and aborts. When profiling applications that
use Coro you should disable the subroutine profiler using the L</subs=0> option.

=head2 FCGI::Engine

Using C<open('-|')> in code running under L<FCGI::Engine> causes a panic in nytprofcalls.
See https://github.com/timbunce/devel-nytprof/issues/20 for more information.

=head2 For perl < 5.8.8 it may change what caller() returns

For example, the L<Readonly> module croaks with "Invalid tie" when profiled with
perl versions before 5.8.8. That's because L<Readonly> explicitly checking for
certain values from caller(). The L<NEXT> module is also affected.

=head2 For perl < 5.10.1 it can't see some implicit calls and callbacks

For perl versions prior to 5.8.9 and 5.10.1, some implicit subroutine calls
can't be seen by the I<subroutine> profiler. Technically this affects calls
made via the various perl C<call_*()> internal APIs.

For example, BEGIN/CHECK/INIT/END blocks, the C<TIE>I<whatever> subroutine
called by C<tie()>, all calls made via operator overloading, and callbacks from
XS code, are not seen.

The effect is that time in those subroutines is accumulated by the
subs that triggered the call to them. So time spent in calls invoked by
perl to handle overloading are accumulated by the subroutines that trigger
overloading (so it is measured, but the cost is dispersed across possibly many
calling locations).

Although the calls aren't seen by the subroutine profiler, the individual
I<statements> executed by the code in the called subs are profiled by the
statement profiler.

=head2 #line directives

The reporting code currently doesn't handle #line directives, but at least it
warns about them. Patches welcome.

=head2 Freed values in @_ may be mutated

Perl has a class of bugs related to the fact that values placed in the stack
are not reference counted. Consider this example:

  @a = (1..9);  sub s { undef @a; print $_ for @_ }  s(@a);

The C<undef @a> frees the values that C<@_> refers to. Perl can sometimes
detect when a freed value is accessed and treats it as an undef. However, if
the freed value is assigned some new value then @_ is effectively corrupted.

NYTProf allocates new values while it's profiling, in order to record program
activity, and so may appear to corrupt C<@_> in this (rare) situation.  If this
happens, NYTProf is simply exposing an existing problem in the code.

=head2 Lvalue subroutines aren't profiled when using use_db_sub=1

Currently 'lvalue' subroutines (subs that can be assigned to, like C<foo() =
42>) are not profiled when using use_db_sub=1.

=head1 CLOCKS

Here we discuss the way NYTProf gets high-resolution timing information from
your system and related issues.

=head2 POSIX Clocks

These are the clocks that your system may support if it supports the POSIX
C<clock_gettime()> function. Other clock sources are listed in the
L</Other Clocks> section below.

The C<clock_gettime()> interface allows clocks to return times to nanosecond
precision. Of course few offer nanosecond I<accuracy> but the extra precision
helps reduce the cumulative error that naturally occurs when adding together
many timings. When using these clocks NYTProf outputs timings as a count of 100
nanosecond ticks.

=head3 CLOCK_MONOTONIC

CLOCK_MONOTONIC represents the amount of time since an unspecified point in
the past (typically system start-up time).  It increments uniformly
independent of adjustments to 'wallclock time'. NYTProf will use this clock by
default, if available.

=head3 CLOCK_REALTIME

CLOCK_REALTIME is typically the system's main high resolution 'wall clock time'
source.  The same source as used for the gettimeofday() call used by most kinds
of perl benchmarking and profiling tools.

The problem with real time is that it's far from simple. It tends to drift and
then be reset to match 'reality', either sharply or by small adjustments (via the
adjtime() system call).

Surprisingly, it can also go backwards, for reasons explained in
http://preview.tinyurl.com/5wawnn so CLOCK_MONOTONIC is preferred.

=head3 CLOCK_VIRTUAL

CLOCK_VIRTUAL increments only when the CPU is running in user mode on behalf of the calling process.

=head3 CLOCK_PROF

CLOCK_PROF increments when the CPU is running in user I<or> kernel mode.

=head3 CLOCK_PROCESS_CPUTIME_ID

CLOCK_PROCESS_CPUTIME_ID represents the amount of execution time of the process associated with the clock.

=head3 CLOCK_THREAD_CPUTIME_ID

CLOCK_THREAD_CPUTIME_ID represents the amount of execution time of the thread associated with the clock.

=head3 Finding Available POSIX Clocks

On unix-like systems you can find the CLOCK_* clocks available on you system
using a command like:

  grep -r 'define *CLOCK_' /usr/include

Look for a group that includes CLOCK_REALTIME. The integer values listed are
the clock ids that you can use with the C<clock=N> option.

A future version of NYTProf should be able to list the supported clocks.

=head2 Other Clocks

This section lists other clock sources that NYTProf may use.

If your system doesn't support clock_gettime() then NYTProf will use
gettimeofday(), or the nearest equivalent,

=head3 gettimeofday

This is the traditional high resolution time of day interface for most
unix-like systems.  With this clock NYTProf outputs timings as a count of 1
microsecond ticks.

=head3 mach_absolute_time

On Mac OS X the mach_absolute_time() function is used. With this clock NYTProf
outputs timings as a count of 100 nanosecond ticks.

=head3 Time::HiRes

On systems which don't support other clocks, NYTProf falls back to using the
L<Time::HiRes> module.  With this clock NYTProf outputs timings as a count of 1
microsecond ticks.

=head2 Clock References

Relevant specifications and manual pages:

  http://www.opengroup.org/onlinepubs/000095399/functions/clock_getres.html
  http://linux.die.net/man/3/clock_gettime

Why 'realtime' can appear to go backwards:

  http://preview.tinyurl.com/5wawnn

The PostgreSQL pg_test_timing utility documentation has a good summary of timing issues:

  http://www.postgresql.org/docs/9.2/static/pgtesttiming.html

=for comment
http://preview.tinyurl.com/5wawnn redirects to:
http://groups.google.com/group/comp.os.linux.development.apps/tree/browse_frm/thread/dc29071f2417f75f/ac44671fdb35f6db?rnum=1&_done=%2Fgroup%2Fcomp.os.linux.development.apps%2Fbrowse_frm%2Fthread%2Fdc29071f2417f75f%2Fc46264dba0863463%3Flnk%3Dst%26rnum%3D1%26

=for comment - these links seem broken
http://webnews.giga.net.tw/article//mailing.freebsd.performance/710
http://sean.chittenden.org/news/2008/06/01/

=head1 CAVEATS

=head2 SMP Systems

On systems with multiple processors, which includes most modern machines,
(from Linux docs though applicable to most SMP systems):

  The CLOCK_PROCESS_CPUTIME_ID and CLOCK_THREAD_CPUTIME_ID clocks are realized on
  many platforms using timers from the CPUs (TSC on i386, AR.ITC on Itanium).
  These registers may differ between CPUs and as a consequence these clocks may
  return bogus results if a process is migrated to another CPU.

  If the CPUs in an SMP system have different clock sources then there is no way
  to maintain a correlation between the timer registers since each CPU will run
  at a slightly different frequency. If that is the case then
  clock_getcpuclockid(0) will return ENOENT to signify this condition. The two
  clocks will then only be useful if it can be ensured that a process stays on a
  certain CPU.

  The processors in an SMP system do not start all at exactly the same time and
  therefore the timer registers are typically running at an offset. Some
  architectures include code that attempts to limit these offsets on bootup.
  However, the code cannot guarantee to accurately tune the offsets. Glibc
  contains no provisions to deal with these offsets (unlike the Linux Kernel).
  Typically these offsets are small and therefore the effects may be negligible
  in most cases.

In summary, SMP systems are likely to give 'noisy' profiles.
Setting a L<Processor Affinity> may help.

=head3 Processor Affinity

Processor affinity is an aspect of task scheduling on SMP systems.
"Processor affinity takes advantage of the fact that some remnants of a process
may remain in one processor's state (in particular, in its cache) from the last
time the process ran, and so scheduling it to run on the same processor the
next time could result in the process running more efficiently than if it were
to run on another processor." (From http://en.wikipedia.org/wiki/Processor_affinity)

Setting an explicit processor affinity can avoid the problems described in
L</SMP Systems>.

Processor affinity can be set using the C<taskset> command on Linux.

Note that processor affinity is inherited by child processes, so if the process
you're profiling spawns cpu intensive sub processes then your process will be
impacted by those more than it otherwise would.

=head3 Windows

B<THIS SECTION DOESN'T MATCH THE CODE>

On Windows NYTProf uses Time::HiRes which uses the windows
QueryPerformanceCounter() API with some extra logic to adjust for the current
clock speed and try to resync the raw counter to wallclock time every so often
(every 30 seconds or if the timer drifts by more than 0.5 of a seconds).
This extra logic may lead to occasional spurious results.

(It would be great if someone could contribute a patch to NYTProf to use
QueryPerformanceCounter() directly and avoid the overheads and resyncing
behaviour of Time::HiRes.)

=head2 Virtual Machines

I recommend you don't do performance profiling while running in a
virtual machine.  If you do you're likely to find inexplicable spikes
of real-time appearing at unreasonable places in your code. You should pay
less attention to the statement timings and rely more on the subroutine
timings. They will still be noisy but less so than the statement times.

You could also try using the C<clock=N> option to select a high-resolution
I<cpu-time> clock instead of a real-time one. That should be much less
noisy, though you will lose visibility of wait-times due to network
and disk I/O, for example.

=head1 BUGS

Possibly. All complex software has bugs. Let me know if you find one.

=head1 SEE ALSO

Screenshots of L<nytprofhtml> v2.01 reports can be seen at
L<http://timbunce.files.wordpress.com/2008/07/nytprof-perlcritic-index.png> and
L<http://timbunce.files.wordpress.com/2008/07/nytprof-perlcritic-all-perl-files.png>.
A writeup of the new features of NYTProf v2 can be found at
L<http://blog.timbunce.org/2008/07/15/nytprof-v2-a-major-advance-in-perl-profilers/>
and the background story, explaining the "why", can be found at
L<http://blog.timbunce.org/2008/07/16/nytprof-v2-the-background-story/>.

Mailing list and discussion at L<http://groups.google.com/group/develnytprof-dev>

Blog posts L<http://blog.timbunce.org/tag/nytprof/>

Public SVN Repository and hacking instructions at L<http://code.google.com/p/perl-devel-nytprof/>

L<nytprofhtml> is a script included that produces html reports.
L<nytprofcsv> is another script included that produces plain text CSV reports.

L<Devel::NYTProf::Reader> is the module that powers the report scripts.  You
might want to check this out if you plan to implement a custom report (though
it's very likely to be deprecated in a future release).

L<Devel::NYTProf::ReadStream> is the module that lets you read a profile data
file as a stream of chunks of data.

Other tools:

DTrace L<https://speakerdeck.com/mrallen1/perl-dtrace-and-you>

=head1 TROUBLESHOOTING

=head2 "Profile data incomplete, ..." or "Profile format error: ..."

This error message means the file doesn't contain all the expected data
or the data has been corrupted in some way.
That may be because it was truncated (perhaps the filesystem was full) or,
more commonly, because the all the expected data hasn't been written.

NYTProf writes some important data to the data file when I<finishing> profiling.
If you read the file before the profiling has finished you'll get this error.

If the process being profiled is still running you'll need to wait until it
exits cleanly (runs C<END> blocks or L</finish_profile> is called explicitly).

If the process being profiled has exited then it's likely that it met with a
sudden and unnatural death that didn't give NYTProf a chance to finish the
profile.  If the sudden death was due to a signal, like SIGTERM, or a SIGINT
from pressing Ctrl-C, then the L</sigexit=1> option may help.

If the sudden death was due to calling C<POSIX::_exit($status)> then you'll
need to call L</finish_profile> before calling C<POSIX::_exit>.

You'll also get this error if the code trying to read the profile is itself
being profiled. That's most likely to happen if you enable profiling via the
C<PERL5OPT> environment variable and have forgotten to unset it.

If you've encountered this error message, and you're sure you've understood the
concerns described above, and you're sure they don't apply in your case, then
please open an issue.  Be sure to include sufficient information so I can see
how you've addressed these likely causes.

=head2 Some source files don't have profile information

This is usually due to NYTProf being initialized after some perl files have
already been compiled.

If you can't alter the command line to add "C<-d:NYTProf>" you could try using
the C<PERL5OPT> environment variable. See L</PROFILING>.

You could also try using the L</use_db_sub=1> option.

=head2 Eval ... has unknown invoking fid

When using the statement profiler you may see a warning message like this:

  Eval '(eval 2)' (fid 9, flags:viastmt,savesrc) has unknown invoking fid 10
 
Notice that the eval file id (fid 9 in this case) is lower than the file id
that invoked the eval (fid 10 in this case). This is a known problem caused by
the way perl works and how the profiler assigns and outputs the file ids.
The invoking fid is known but gets assigned a fid and output after the fid for
the eval, and that causes the warning when the file is read.

=head2 Warning: %d subroutine calls had negative time

There are two likely causes for this: clock instability, or accumulated timing
errors.

Clock instability, if present on your system, is most likely to be noticeable on
very small/fast subroutines that are called very few times.

Accumulated timing errors can arise because the subroutine profiler uses
floating point values (NVs) to store the times.  They are most likely to be
noticed on subroutines that are called a few times but which make a large
number of calls to very fast subroutines (such as opcodes). In this case the
accumulated time apparently spent making those calls can be greater than the
time spent in the calling subroutine.

If you rerun nytprofhtml (etc.) with the L</trace=N> option set >0 you'll see
trace messages like  "%s call has negative time: incl %fs, excl %fs" for each
affected subroutine.

Try profiling with the L</slowops=N> option set to 0 to disable the profiling
of opcodes. Since opcodes often execute in a few microseconds they are a common
cause of this warning.

You could also try recompiling perl to use 'long doubles' for the NV floating
point type (use Configure -Duselongdouble). If you try this please let me know.
I'd also happily take a patch to use long doubles, if available, by default.

=head2 panic: buffer overflow ...

You have unusually long subroutine names in your code. You'll need to rebuild
Devel::NYTProf with the NYTP_MAX_SUB_NAME_LEN environment variable set to a
value longer than the longest subroutine names in your code.

=head1 AUTHORS AND CONTRIBUTORS

B<Tim Bunce> (L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>)
leads the project and has done most of the development work thus far.

B<Nicholas Clark> contributed zip compression and C<nytprofmerge>.
B<Chia-liang Kao> contributed C<nytprofcg>.
B<Peter (Stig) Edwards> contributed the VMS port.
B<Jan Dubois> contributed the Windows port.
B<Gisle Aas> contributed the Devel::NYTProf::ReadStream module.
B<Steve Peters> contributed greater perl version portability and use of POSIX
high-resolution clocks.
Other contributors are noted in the Changes file.

Many thanks to B<Adam Kaplan> who created C<NYTProf> initially by forking
C<Devel::FastProf> adding reporting from C<Devel::Cover> and a test suite.
For more details see L</HISTORY> below.

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2008 by Adam Kaplan and The New York Times Company.
  Copyright (C) 2008-2016 by Tim Bunce, Ireland.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=head2 Background

Subroutine-level profilers:

  Devel::DProf        | 1995-10-31 | ILYAZ
  Devel::AutoProfiler | 2002-04-07 | GSLONDON
  Devel::Profiler     | 2002-05-20 | SAMTREGAR
  Devel::Profile      | 2003-04-13 | JAW
  Devel::DProfLB      | 2006-05-11 | JAW
  Devel::WxProf       | 2008-04-14 | MKUTTER

Statement-level profilers:

  Devel::SmallProf    | 1997-07-30 | ASHTED
  Devel::FastProf     | 2005-09-20 | SALVA
  Devel::NYTProf      | 2008-03-04 | AKAPLAN
  Devel::Profit       | 2008-05-19 | LBROCARD

Devel::NYTProf is a (now distant) fork of Devel::FastProf, which was itself an
evolution of Devel::SmallProf.

Adam Kaplan forked Devel::FastProf and added html report generation (based on
Devel::Cover) and a test suite - a tricky thing to do for a profiler.
Meanwhile Tim Bunce had been extending Devel::FastProf to add novel
per-sub and per-block timing, plus subroutine caller tracking.

When Devel::NYTProf was released Tim switched to working on Devel::NYTProf
because the html report would be a good way to show the extra profile data, and
the test suite made development much easier and safer.

Then Tim went a little crazy and added a slew of new features, in addition to
per-sub and per-block timing and subroutine caller tracking. These included the
'opcode interception' method of profiling, ultra-fast and robust inclusive
subroutine timing, doubling performance, plus major changes to html reporting
to display all the extra profile call and timing data in richly annotated and
cross-linked reports.

Steve Peters came on board along the way with patches for portability and to
keep NYTProf working with the latest development perl versions. Nicholas Clark
added zip compression, many optimizations, and C<nytprofmerge>.
Jan Dubois contributed Windows support.

Adam's work was sponsored by The New York Times Co. L<http://open.nytimes.com>.
Tim's work was partly sponsored by Shopzilla L<http://www.shopzilla.com> during 2008
but hasn't been sponsored since then.

For the record, Tim has never worked for the New York Times nor has he received any
kind of sponsorship or support from them in relation to NYTProf. The name of
this module is simply result of the history outlined above, which can be
summarised as: Adam forked an existing module when he added his enhancements
and Tim didn't.

=cut
