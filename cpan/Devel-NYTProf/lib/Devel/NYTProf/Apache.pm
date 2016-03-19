# vim: ts=8 sw=4 expandtab:
##########################################################
# This script is part of the Devel::NYTProf distribution
#
# Copyright, contact and other information can be found
# at the bottom of this file, or by going to:
# http://metacpan.org/release/Devel-NYTProf/
#
###########################################################
package Devel::NYTProf::Apache;

our $VERSION = '4.00';

BEGIN {

    # Load Devel::NYTProf before loading any other modules
    # in order that $^P settings apply to the compilation
    # of those modules.

    if (!$ENV{NYTPROF}) {
        $ENV{NYTPROF} = "file=/tmp/nytprof.$$.out";
        warn "NYTPROF env var not set, so defaulting to NYTPROF='$ENV{NYTPROF}'";
    }

    require Devel::NYTProf::Core;

    DB::set_option("endatexit", 1); # for vhost with PerlOption +Parent
    DB::set_option("addpid", 1);

    require Devel::NYTProf;
}

use strict;

use constant TRACE => ($ENV{NYTPROF} =~ /\b trace = [^0] /x);
use constant MP2   => (exists $ENV{MOD_PERL_API_VERSION} && $ENV{MOD_PERL_API_VERSION} == 2);

# https://rt.cpan.org/Ticket/Display.html?id=42862
die "Threads not supported" if $^O eq 'MSWin32';

# help identify MULTIPLICITY issues
*current_perl_id = (MP2 and eval "require ModPerl::Util")
        ? \&ModPerl::Util::current_perl_id
        : sub { 0+\$$ };

sub trace {
    return unless TRACE;
    warn sprintf "NYTProf %d.%s: %s\n",
        $$, current_perl_id(), shift
}

sub child_init {
    trace("child_init(@_)") if TRACE;
    warn "Apache2::SizeLimit is loaded and will corrupt NYTProf profile if it terminates the process\n"
        if $Apache2::SizeLimit::VERSION # doubled just to avoid typo warning
        && $Apache2::SizeLimit::VERSION;
    DB::enable_profile() unless $ENV{NYTPROF} =~ m/\b start = (?: no | end ) \b/x;
}

sub child_exit {
    trace("child_exit(@_)") if TRACE;
    DB::finish_profile();
}

# arrange for the profile to be enabled in each child
# and cleanly finished when the child exits
if (MP2) {

    # For mod_perl2 we rely on profiling being active in the parent
    # and for normal fork detection to detect the new child.
    # We just need to be sure the profile is finished properly
    # and an END block works well for that (if loaded right, see docs)
    # We rely on NYTProf's own END block to finish the profile.
    #trace("adding child_exit hook") if TRACE;
    #eval q{ END { child_exit('END') } 1 } or die;
}
else {
    # the simple steps for mod_perl2 above might also be fine for mod_perl1
    # but I'm not in a position to check right now. Try it out and let me know.
    require Apache;
    if (Apache->can('push_handlers')) {
        Apache->push_handlers(PerlChildInitHandler => \&child_init);
        Apache->push_handlers(PerlChildExitHandler => \&child_exit);
        warn "$$: Apache child handlers installed" if TRACE;
    }
    else {
        Carp::carp("Apache.pm was not loaded");
    }
}

1;

__END__

=head1 NAME

Devel::NYTProf::Apache - Profile mod_perl applications with Devel::NYTProf

=head1 SYNOPSIS

  # in your Apache config file with mod_perl installed
  PerlPassEnv NYTPROF
  PerlModule Devel::NYTProf::Apache

If you're using virtual hosts with C<PerlOptions> that include either
C<+Parent> or C<+Clone> then see L</VIRTUAL HOSTS> below.

=head1 DESCRIPTION

This module allows mod_perl applications to be profiled using
C<Devel::NYTProf>. 

If the NYTPROF environment variable isn't set I<at the time
Devel::NYTProf::Apache is loaded> then Devel::NYTProf::Apache will issue a
warning and default it to:

  file=/tmp/nytprof.$$.out:addpid=1:endatexit=1

The file actually created by NTProf will also have the process id appended to
it because the C<addpid> option is enabled by default.

See L<Devel::NYTProf/"ENVIRONMENT VARIABLES"> for 
more details on the settings effected by this environment variable.

Try using C<PerlPassEnv> in your httpd.conf if you can set the NYTPROF
environment variable externally.  Note that if you set the NYTPROF environment
variable externally then the file name obviously can't include the parent
process id. For example, to set stmts=0 externally, use:

    NYTPROF=file=/tmp/nytprof.out:out:addpid=1:endatexit=1:stmts=0

Each profiled mod_perl process will need to have terminated cleanly before you can
successfully read the profile data file. The simplest approach is to start the
httpd, make some requests (e.g., 100 of the same request), then stop it and
process the profile data.

Alternatively you could send a TERM signal to the httpd worker process to
terminate that one process. The parent httpd process will start up another one
for you ready for more profiling.

=head2 Example httpd.conf

It's usually a good idea to use just one child process when profiling, which you
can do by setting the C<MaxClients> to 1 in httpd.conf.

Set C<MaxRequestsPerChild> to 0 to avoid worker processes exiting and
restarting during the profiling, which would split the profile data across
multiple files.

Using an C<IfDefine> blocks lets you leave the profile configuration in place
and enable it whenever it's needed by adding C<-D NYTPROF> to the httpd startup
command line.

  <IfDefine NYTPROF>
      MaxClients 1
      MaxRequestsPerChild 0
      PerlModule Devel::NYTProf::Apache
  </IfDefine>

With that configuration you should get two profile files, one for the parent
process and one for the worker.


=head1 VIRTUAL HOSTS

If your httpd configuration includes virtual hosts with C<PerlOptions> that
include either C<+Parent> or C<+Clone> then mod_perl2 will create a new perl
interpreter to handle requests for that virtual host.
This causes some issues for profiling.

If C<Devel::NYTProf::Apache> is loaded in the top-level configuration then
activity in any virtual hosts that use their own perl interpreter won't be
profiled. Normal virtual hosts will be profiled just fine.

You can profile a I<single> virtual host that uses its own perl interpreter by
loading C<Devel::NYTProf::Apache> I<inside the configuration for that virtual
host>. In this case I<do not> use C<PerlModule> directive. You need to use
a C<Perl> directive instead, like this:

    <VirtualHost *:1234>
        ...
        <Perl> use Devel::NYTProf::Apache; </Perl>
        ...
    </VirtualHost>

=head1 LIMITATIONS

Profiling mod_perl on Windows is not supported because NYTProf currently
doesn't support threads.

=head1 TROUBLESHOOTING

Truncated profile: Profiles for large applications can take a while to write to
the disk. Allow sufficient time after stopping apache, or check the process has
actually exited, before trying to read the profile.

Truncated profile: The mod_perl child_terminate() function terminates the child
without giving perl an opportunity to cleanup. Since C<Devel::NYTProf::Apache>
doesn't intercept the mod_perl child_terminate() function (yet) the profile
will be corrupted if it's called. You're most likely to encounter this when
using L<Apache::SizeLimit>, so you may want to disable it while profiling.

=head1 SEE ALSO

L<Devel::NYTProf>

=head1 AUTHOR

B<Adam Kaplan>, C<< <akaplan at nytimes.com> >>
B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>
B<Steve Peters>, C<< <steve at fisharerojo.org> >>

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2008 by Adam Kaplan and The New York Times Company.
  Copyright (C) 2008 by Steve Peters.
  Copyright (C) 2008-2012 by Tim Bunce.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
