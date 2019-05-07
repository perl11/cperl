#! perl

use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use Cwd;

# List explicitly here the variables you want Configure to
# generate.  Metaconfig only looks for shell variables, so you
# have to mention them as if they were shell variables, not
# %Config entries.  Thus you write
#  $startperl
# to ensure Configure will look for $Config{startperl}.
# Wanted:  $archlibexp

# This forces PL files to create target in same directory as PL file.
# This is so that make depend always knows where to find PL derivatives.
my $origdir = cwd;
chdir dirname($0);
my $file = basename($0, '.PL');
$file .= '.com' if $^O eq 'VMS';

open OUT,">",$file or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

# In this section, perl variables will be expanded during extraction.
# You can use $Config{...} to use Configure variables.

print OUT <<"!GROK!THIS!";
$Config{startperl}
    eval 'exec $Config{perlpath} -S \$0 \${1+"\$@"}'
    if \$running_under_some_shell;
--\$running_under_some_shell;
!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';

# Version 1.00, Reini Urban, 2013-02-11 09:52:10

use strict;
use warnings;
use 5.006_000;

use FileHandle;
use Config;
use Fcntl qw(:DEFAULT :flock);
use File::Temp qw(tempfile);
use File::Basename qw(basename dirname);
use File::Path qw(mkpath);
# use Cwd;
use Pod::Usage;
# Time::HiRes does not work with 5.6
use Time::HiRes qw(gettimeofday tv_interval);
our $VERSION = 1.00;
$| = 1;
eval { require B::C::Config; };
sub is_win32();

our ($logfh, $Options);

$SIG{INT} = sub { exit(); } if exists $SIG{INT}; # exit gracefully and clean up after ourselves.


# usage: vprint [level] msg args
sub vprint {
    my $level;
    if (@_ == 1) {
        $level = 1;
    } elsif ($_[0] =~ /^-?\d$/) {
        $level = shift;
    } else {
        # well, they forgot to use a number; means >0
        $level = 0;
    }
    my $msg = "@_";
    $msg .= "\n" unless substr($msg, -1) eq "\n";
    if (opt('v') > $level)
    {
	if (opt('log')) {
	    print $logfh "$0: $msg" ;
	} else {
	    print        "$0: $msg";
	}
    }
}

sub vsystem {
    if (opt('dryrun')) {
        print "@_\n";
    } else {
       system(@_);
    }
}

# parse most options thru to perlcc, just use -m|--module and -l:s|--local=path

sub parse_argv {
  $Options = {};
  if (grep /^-m$/, @ARGV) {
    $Options->{m}++;
    @ARGV = grep !/^-m$/, @ARGV;
  }
  if (my ($l) = grep /^-l(.*)$/, @ARGV) {
    if ($l) {
      $l =~ s/^=//;
      $Options->{l} = $l;
    } else {
      # check next ARGV for -
      $Options->{l} = '~/.perl5/pcc';
    }
    @ARGV = grep !/^-l(.*)$/, @ARGV;
  }
}

sub opt(*) {
    my $opt = shift;
    return exists($Options->{$opt}) && ($Options->{$opt} || 0);
}

# File spawning and error collecting
sub spawnit {
    my $command = shift;
    my (@error,@output,$errname,$errcode);
    if (opt('dryrun')) {
        print "$command\n";;
    }
    elsif ($Options->{spawn}) {
        (undef, $errname) = tempfile("pccXXXXX");
        {
	    my $pid = open (S_OUT, "$command 2>$errname |")
	      or _die("Couldn't spawn the compiler.\n");
            $errcode = $?;
            my $kid;
            do {
              $kid = waitpid($pid, 0);
            } while $kid > 0;
            @output = <S_OUT>;
        }
        open (S_ERROR, $errname) or _die("Couldn't read the error file.\n");
        @error = <S_ERROR>;
        close S_ERROR;
        close S_OUT;
        unlink $errname or _die("Can't unlink error file $errname\n");
    } else {
        @output = split /\n/, `$command`;
    }
    return (\@output, \@error, $errcode);
}

sub version {
    require B::C::Flags;
    no warnings 'once';
    my $BC_VERSION = $B::C::Flags::VERSION . $B::C::REVISION;
    return "buildcc $VERSION, B-C-${BC_VERSION} built for $Config{perlpath} $Config{archname}\n";
}

sub helpme {
    print version(),"\n";
    if (opt('v')) {
	pod2usage( -verbose => opt('v') );
    } else {
	pod2usage( -verbose => 0 );
    }
}

sub relativize {
    my ($args) = @_;

    return() if ($args =~ m"^[/\\]");
    return("./$args");
}

sub _die {
    my @args = ("$0: ", @_);
    $logfh->print(@args) if opt('log');
    print STDERR @args;
    exit(); # should die eventually. However, needed so that a 'make compile'
            # can compile all the way through to the end for standard dist.
}

sub _usage_and_die {
    _die(<<EOU);
Usage:
$0 [-o executable] [-h] [-m] -l [path] source.pl
    buildcc -o hello hello.pl  # pass thru perlcc
    buildcc -m app.pl          # detects dependencies for app.pl, write them to app.mak,
                               # and compile all into shared modules and app
    buildcc -l -m app.pl       # use local ~/.perl5/pcc/ path
    buildcc -l=~/pcc -m app.pl # use local ~/pcc/ path
EOU
}

sub run {
    my (@commands) = @_;

    my $t0 = [gettimeofday] if opt('time');
    print interruptrun(@commands) if (!opt('log'));
    $logfh->print(interruptrun(@commands)) if (opt('log'));
    my $elapsed = tv_interval ( $t0 ) if opt('time');
    vprint -1, "r time: $elapsed" if opt('time');
}

sub interruptrun {
    my (@commands) = @_;

    my $command = join('', @commands);
    local(*FD);
    my $pid = open(FD, "$command |");
    my $text;

    local($SIG{HUP}, $SIG{INT}) if exists $SIG{HUP};
    $SIG{HUP} = $SIG{INT} = sub { kill 9, $pid; exit } if exists $SIG{HUP};

    my $needalarm =
          ($ENV{PERLCC_TIMEOUT} &&
	   exists $SIG{ALRM} &&
	  $Config{'osname'} ne 'MSWin32' &&
	  $command =~ m"(^|\s)perlcc\s");

    eval {
         local($SIG{ALRM}) = sub { die "INFINITE LOOP"; } if exists $SIG{ALRM};
         alarm($ENV{PERLCC_TIMEOUT}) if $needalarm;
	 $text = join('', <FD>);
	 alarm(0) if $needalarm;
    };

    if ($@) {
        eval { kill 'HUP', $pid };
        vprint 0, "SYSTEM TIMEOUT (infinite loop?)\n";
    }

    close(FD);
    return($text);
}

sub is_win32() { $^O =~ m/^MSWin/ }
sub is_msvc() { is_win32 && $Config{cc} =~ m/^cl/i }

__END__

=head1 NAME

buildcc - build an executable with shared modules from a perl script

=head1 SYNOPSIS

    buildcc -o hello hello.pl  # pass thru perlcc
    buildcc -m app.pl          # detects dependencies for app.pl, write them to app.mak,
                               # and compile all into shared modules and app
    buildcc -l -m app.pl       # use local ~/.perl5/pcc/ path
    buildcc -l=~/pcc -m app.pl # use local ~/pcc/ path

=head1 DESCRIPTION

F<buildcc> is a C<perlcc -m> frontend to detect and maintain perlcc compiled perl 
modules as compiled shared libraries.
It creates a F<.mak> file for the compiled script with all dependencies.

C<-l> uses a local path for all compiled shared modules. Otherwise it checks if 
F< 'sitearch'/pcc/> is writable and puts/searches the modules there if so.

All other options are passed thru to perlcc verbatim.

=head1 OPTIONS

=over 4

=item -m

Create a .mak for the module depencencies, and create the target.

=item -l [path]

Use the given local path as prefix for the created shared modules.

=back

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
!NO!SUBS!

close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
