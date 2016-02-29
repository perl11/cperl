#
# t/test.pl - from CORE

use Test::More;
use File::Spec;
use B::C::Config;

sub curr_test {
    $test = shift if @_;
    return $test;
}

sub next_test {
  my $retval = $test;
  $test = $test + 1; # don't use ++
  $retval;
}

my $cp_0037 =   # EBCDIC code page 0037
    '\x00\x01\x02\x03\x37\x2D\x2E\x2F\x16\x05\x25\x0B\x0C\x0D\x0E\x0F' .
    '\x10\x11\x12\x13\x3C\x3D\x32\x26\x18\x19\x3F\x27\x1C\x1D\x1E\x1F' .
    '\x40\x5A\x7F\x7B\x5B\x6C\x50\x7D\x4D\x5D\x5C\x4E\x6B\x60\x4B\x61' .
    '\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\x7A\x5E\x4C\x7E\x6E\x6F' .
    '\x7C\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xD1\xD2\xD3\xD4\xD5\xD6' .
    '\xD7\xD8\xD9\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xBA\xE0\xBB\xB0\x6D' .
    '\x79\x81\x82\x83\x84\x85\x86\x87\x88\x89\x91\x92\x93\x94\x95\x96' .
    '\x97\x98\x99\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xC0\x4F\xD0\xA1\x07' .
    '\x20\x21\x22\x23\x24\x15\x06\x17\x28\x29\x2A\x2B\x2C\x09\x0A\x1B' .
    '\x30\x31\x1A\x33\x34\x35\x36\x08\x38\x39\x3A\x3B\x04\x14\x3E\xFF' .
    '\x41\xAA\x4A\xB1\x9F\xB2\x6A\xB5\xBD\xB4\x9A\x8A\x5F\xCA\xAF\xBC' .
    '\x90\x8F\xEA\xFA\xBE\xA0\xB6\xB3\x9D\xDA\x9B\x8B\xB7\xB8\xB9\xAB' .
    '\x64\x65\x62\x66\x63\x67\x9E\x68\x74\x71\x72\x73\x78\x75\x76\x77' .
    '\xAC\x69\xED\xEE\xEB\xEF\xEC\xBF\x80\xFD\xFE\xFB\xFC\xAD\xAE\x59' .
    '\x44\x45\x42\x46\x43\x47\x9C\x48\x54\x51\x52\x53\x58\x55\x56\x57' .
    '\x8C\x49\xCD\xCE\xCB\xCF\xCC\xE1\x70\xDD\xDE\xDB\xDC\x8D\x8E\xDF';

my $cp_1047 =   # EBCDIC code page 1047
    '\x00\x01\x02\x03\x37\x2D\x2E\x2F\x16\x05\x15\x0B\x0C\x0D\x0E\x0F' .
    '\x10\x11\x12\x13\x3C\x3D\x32\x26\x18\x19\x3F\x27\x1C\x1D\x1E\x1F' .
    '\x40\x5A\x7F\x7B\x5B\x6C\x50\x7D\x4D\x5D\x5C\x4E\x6B\x60\x4B\x61' .
    '\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\x7A\x5E\x4C\x7E\x6E\x6F' .
    '\x7C\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xD1\xD2\xD3\xD4\xD5\xD6' .
    '\xD7\xD8\xD9\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xAD\xE0\xBD\x5F\x6D' .
    '\x79\x81\x82\x83\x84\x85\x86\x87\x88\x89\x91\x92\x93\x94\x95\x96' .
    '\x97\x98\x99\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xC0\x4F\xD0\xA1\x07' .
    '\x20\x21\x22\x23\x24\x25\x06\x17\x28\x29\x2A\x2B\x2C\x09\x0A\x1B' .
    '\x30\x31\x1A\x33\x34\x35\x36\x08\x38\x39\x3A\x3B\x04\x14\x3E\xFF' .
    '\x41\xAA\x4A\xB1\x9F\xB2\x6A\xB5\xBB\xB4\x9A\x8A\xB0\xCA\xAF\xBC' .
    '\x90\x8F\xEA\xFA\xBE\xA0\xB6\xB3\x9D\xDA\x9B\x8B\xB7\xB8\xB9\xAB' .
    '\x64\x65\x62\x66\x63\x67\x9E\x68\x74\x71\x72\x73\x78\x75\x76\x77' .
    '\xAC\x69\xED\xEE\xEB\xEF\xEC\xBF\x80\xFD\xFE\xFB\xFC\xBA\xAE\x59' .
    '\x44\x45\x42\x46\x43\x47\x9C\x48\x54\x51\x52\x53\x58\x55\x56\x57' .
    '\x8C\x49\xCD\xCE\xCB\xCF\xCC\xE1\x70\xDD\xDE\xDB\xDC\x8D\x8E\xDF';

my $cp_bc = # EBCDIC code page POSiX-BC
    '\x00\x01\x02\x03\x37\x2D\x2E\x2F\x16\x05\x15\x0B\x0C\x0D\x0E\x0F' .
    '\x10\x11\x12\x13\x3C\x3D\x32\x26\x18\x19\x3F\x27\x1C\x1D\x1E\x1F' .
    '\x40\x5A\x7F\x7B\x5B\x6C\x50\x7D\x4D\x5D\x5C\x4E\x6B\x60\x4B\x61' .
    '\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\x7A\x5E\x4C\x7E\x6E\x6F' .
    '\x7C\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xD1\xD2\xD3\xD4\xD5\xD6' .
    '\xD7\xD8\xD9\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xBB\xBC\xBD\x6A\x6D' .
    '\x4A\x81\x82\x83\x84\x85\x86\x87\x88\x89\x91\x92\x93\x94\x95\x96' .
    '\x97\x98\x99\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xFB\x4F\xFD\xFF\x07' .
    '\x20\x21\x22\x23\x24\x25\x06\x17\x28\x29\x2A\x2B\x2C\x09\x0A\x1B' .
    '\x30\x31\x1A\x33\x34\x35\x36\x08\x38\x39\x3A\x3B\x04\x14\x3E\x5F' .
    '\x41\xAA\xB0\xB1\x9F\xB2\xD0\xB5\x79\xB4\x9A\x8A\xBA\xCA\xAF\xA1' .
    '\x90\x8F\xEA\xFA\xBE\xA0\xB6\xB3\x9D\xDA\x9B\x8B\xB7\xB8\xB9\xAB' .
    '\x64\x65\x62\x66\x63\x67\x9E\x68\x74\x71\x72\x73\x78\x75\x76\x77' .
    '\xAC\x69\xED\xEE\xEB\xEF\xEC\xBF\x80\xE0\xFE\xDD\xFC\xAD\xAE\x59' .
    '\x44\x45\x42\x46\x43\x47\x9C\x48\x54\x51\x52\x53\x58\x55\x56\x57' .
    '\x8C\x49\xCD\xCE\xCB\xCF\xCC\xE1\x70\xC0\xDE\xDB\xDC\x8D\x8E\xDF';

my $straight =  # Avoid ranges
    '\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F' .
    '\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F' .
    '\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F' .
    '\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F' .
    '\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F' .
    '\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F' .
    '\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F' .
    '\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F' .
    '\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F' .
    '\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F' .
    '\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF' .
    '\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF' .
    '\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF' .
    '\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\xDD\xDE\xDF' .
    '\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF' .
    '\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF';

# The following 2 functions allow tests to work on both EBCDIC and
# ASCII-ish platforms.  They convert string scalars between the native
# character set and the set of 256 characters which is usually called
# Latin1.
#
# These routines don't work on UTF-EBCDIC and UTF-8.

sub native_to_latin1($) {
    my $string = shift;

    return $string if ord('^') == 94;   # ASCII, Latin1
    my $cp;
    if (ord('^') == 95) {    # EBCDIC 1047
        $cp = \$cp_1047;
    }
    elsif (ord('^') == 106) {   # EBCDIC POSIX-BC
        $cp = \$cp_bc;
    }
    elsif (ord('^') == 176)  {   # EBCDIC 037 */
        $cp = \$cp_0037;
    }
    else {
        die "Unknown native character set";
    }

    eval '$string =~ tr/' . $$cp . '/' . $straight . '/';
    return $string;
}

sub latin1_to_native($) {
    my $string = shift;

    return $string if ord('^') == 94;   # ASCII, Latin1
    my $cp;
    if (ord('^') == 95) {    # EBCDIC 1047
        $cp = \$cp_1047;
    }
    elsif (ord('^') == 106) {   # EBCDIC POSIX-BC
        $cp = \$cp_bc;
    }
    elsif (ord('^') == 176)  {   # EBCDIC 037 */
        $cp = \$cp_0037;
    }
    else {
        die "Unknown native character set";
    }

    eval '$string =~ tr/' . $straight . '/' . $$cp . '/';
    return $string;
}

sub ord_latin1_to_native {
    # given an input code point, return the platform's native
    # equivalent value.  Anything above latin1 is itself.

    my $ord = shift;
    return $ord if $ord > 255;
    return ord latin1_to_native(chr $ord);
}

sub ord_native_to_latin1 {
    # given an input platform code point, return the latin1 equivalent value.
    # Anything above latin1 is itself.

    my $ord = shift;
    return $ord if $ord > 255;
    return ord native_to_latin1(chr $ord);
}

sub _where {
    my @caller = caller($Level);
    return "at $caller[1] line $caller[2]";
}

# runperl - Runs a separate perl interpreter.
# Arguments :
#   switches => [ command-line switches ]
#   nolib    => 1 # don't use -I../lib (included by default)
#   prog     => one-liner (avoid quotes)
#   progs    => [ multi-liner (avoid quotes) ]
#   progfile => perl script
#   stdin    => string to feed the stdin
#   stderr   => redirect stderr to stdout
#   args     => [ command-line arguments to the perl program ]
#   verbose  => print the command line

my $is_mswin    = $^O eq 'MSWin32';
my $is_netware  = $^O eq 'NetWare';
my $is_macos    = $^O eq 'MacOS';
my $is_vms      = $^O eq 'VMS';
my $is_cygwin   = $^O eq 'cygwin';

sub _quote_args {
    my ($runperl, $args) = @_;

    foreach (@$args) {
	# In VMS protect with doublequotes because otherwise
	# DCL will lowercase -- unless already doublequoted.
        $_ = q(").$_.q(") if $is_vms && !/^\"/ && length($_) > 0;
	$$runperl .= ' ' . $_;
    }
}

sub _create_runperl { # Create the string to qx in runperl().
    my %args = @_;
    my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
    #- this allows, for example, to set PERL_RUNPERL_DEBUG=/usr/bin/valgrind
    if ($ENV{PERL_RUNPERL_DEBUG}) {
	$runperl = "$ENV{PERL_RUNPERL_DEBUG} $runperl";
    }
    unless ($args{nolib}) {
	if ($is_macos) {
	    $runperl .= ' -I::lib';
	    # Use UNIX style error messages instead of MPW style.
	    $runperl .= ' -MMac::err=unix' if $args{stderr};
	}
	else {
	    $runperl .= ' "-I../lib"'; # doublequotes because of VMS
	}
    }
    if ($args{switches}) {
	local $Level = 2;
	die "test.pl:runperl(): 'switches' must be an ARRAYREF " . _where()
	    unless ref $args{switches} eq "ARRAY";
	_quote_args(\$runperl, $args{switches});
    }
    if (defined $args{prog}) {
	die "test.pl:runperl(): both 'prog' and 'progs' cannot be used " . _where()
	    if defined $args{progs};
        $args{progs} = [$args{prog}]
    }
    if (defined $args{progs}) {
	die "test.pl:runperl(): 'progs' must be an ARRAYREF " . _where()
	    unless ref $args{progs} eq "ARRAY";
        foreach my $prog (@{$args{progs}}) {
            if ($is_mswin || $is_netware || $is_vms) {
                $runperl .= qq ( -e "$prog" );
            }
            else {
                $runperl .= qq ( -e '$prog' );
            }
        }
    } elsif (defined $args{progfile}) {
	$runperl .= qq( "$args{progfile}");
    } else {
	# You probaby didn't want to be sucking in from the upstream stdin
	die "test.pl:runperl(): none of prog, progs, progfile, args, "
	    . " switches or stdin specified"
	    unless defined $args{args} or defined $args{switches}
		or defined $args{stdin};
    }
    if (defined $args{stdin}) {
	# so we don't try to put literal newlines and crs onto the
	# command line.
	$args{stdin} =~ s/\n/\\n/g;
	$args{stdin} =~ s/\r/\\r/g;

	if ($is_mswin || $is_netware || $is_vms) {
	    $runperl = qq{$^X -e "print qq(} .
		$args{stdin} . q{)" | } . $runperl;
	}
	elsif ($is_macos) {
	    # MacOS can only do two processes under MPW at once;
	    # the test itself is one; we can't do two more, so
	    # write to temp file
	    my $stdin = qq{$^X -e 'print qq(} . $args{stdin} . qq{)' > teststdin; };
	    if ($args{verbose}) {
		my $stdindisplay = $stdin;
		$stdindisplay =~ s/\n/\n\#/g;
		print STDERR "# $stdindisplay\n";
	    }
	    `$stdin`;
	    $runperl .= q{ < teststdin };
	}
	else {
	    $runperl = qq{$^X -e 'print qq(} .
		$args{stdin} . q{)' | } . $runperl;
	}
    }
    if (defined $args{args}) {
	_quote_args(\$runperl, $args{args});
    }
    $runperl .= ' 2>&1'          if  $args{stderr} && !$is_mswin && !$is_macos;
    $runperl .= " \xB3 Dev:Null" if !$args{stderr} && $is_macos;
    if ($args{verbose}) {
	my $runperldisplay = $runperl;
	$runperldisplay =~ s/\n/\n\#/g;
	print STDERR "# $runperldisplay\n";
    }
    return $runperl;
}

sub runperl {
    die "test.pl:runperl() does not take a hashref"
	if ref $_[0] and ref $_[0] eq 'HASH';
    my $runperl = &_create_runperl;
    # ${^TAINT} is invalid in perl5.00505
    my $tainted;
    eval '$tainted = ${^TAINT};' if $] >= 5.006;
    my %args = @_;
    exists $args{switches} && grep m/^-T$/, @{$args{switches}} and $tainted = $tainted + 1;

    if ($tainted) {
	# We will assume that if you're running under -T, you really mean to
	# run a fresh perl, so we'll brute force launder everything for you
	my $sep;

	eval "require Config; Config->import";
	if ($@) {
	    warn "test.pl had problems loading Config: $@";
	    $sep = ':';
	} else {
	    $sep = $Config{path_sep};
	}

	my @keys = grep {exists $ENV{$_}} qw(CDPATH IFS ENV BASH_ENV);
	local @ENV{@keys} = ();
	# Untaint, plus take out . and empty string:
	local $ENV{'DCL$PATH'} = $1 if $is_vms && ($ENV{'DCL$PATH'} =~ /(.*)/s);
	$ENV{PATH} =~ /(.*)/s;
	local $ENV{PATH} =
	    join $sep, grep { $_ ne "" and $_ ne "." and -d $_ and
		($is_mswin or $is_vms or !(stat && (stat _)[2]&0022)) }
		    split quotemeta ($sep), $1;
	$ENV{PATH} .= "$sep/bin" if $is_cygwin;  # Must have /bin under Cygwin

	$runperl =~ /(.*)/s;
	$runperl = $1;

        my ($err,$result,$stderr) = run_cmd($runperl, $args{timeout});
	$result =~ s/\n\n/\n/ if $is_vms; # XXX pipes sometimes double these
	return $result;
    } else {
        my ($err,$result,$stderr) = run_cmd($runperl, $args{timeout});
	$result =~ s/\n\n/\n/ if $is_vms; # XXX pipes sometimes double these
	return $result;
    }
}

*run_perl = \&runperl; # Nice alias.

sub DIE {
    print STDERR "# @_\n";
    exit 1;
}

# A somewhat safer version of the sometimes wrong $^X.
my $Perl;
sub which_perl {
    unless (defined $Perl) {
	$Perl = $^X;

	# VMS should have 'perl' aliased properly
	return $Perl if $^O eq 'VMS';

	my $exe;
	eval "require Config; Config->import";
	if ($@) {
	    warn "test.pl had problems loading Config: $@";
	    $exe = '';
	} else {
	    $exe = $Config{exe_ext};
	}
       $exe = '' unless defined $exe;

	# This doesn't absolutize the path: beware of future chdirs().
	# We could do File::Spec->abs2rel() but that does getcwd()s,
	# which is a bit heavyweight to do here.

	if ($Perl =~ /^perl\Q$exe\E$/i) {
	    my $perl = "perl$exe";
	    eval "require File::Spec";
	    if ($@) {
		warn "test.pl had problems loading File::Spec: $@";
		$Perl = "./$perl";
	    } else {
		$Perl = File::Spec->catfile(File::Spec->curdir(), $perl);
	    }
	}

	# Build up the name of the executable file from the name of
	# the command.

	if ($Perl !~ /\Q$exe\E$/i) {
	    $Perl .= $exe;
	}

	warn "which_perl: cannot find $Perl from $^X" unless -f $Perl;

	# For subcommands to use.
	$ENV{PERLEXE} = $Perl;
    }
    return $Perl;
}
sub unlink_all {
    my $count = 0;
    foreach my $file (@_) {
        1 while unlink $file;
	if( -f $file ){
	    print STDERR "# Couldn't unlink '$file': $!\n";
	}else{
	    ++$count;
	}
    }
    $count;
}

my %tmpfiles;
END { unlink_all keys %tmpfiles }

# A regexp that matches the tempfile names
$::tempfile_regexp = 'tmp\d+[A-Z][A-Z]?';

# Avoid ++, avoid ranges, avoid split //
my @letters = qw(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z);
sub tempfile {
    my $count = 0;
    do {
	my $temp = $count;
	my $try = "tmp$$";
	do {
	    $try = $try . $letters[$temp % 26];
	    $temp = int ($temp / 26);
	} while $temp;
	# Need to note all the file names we allocated, as a second request may
	# come before the first is created.
	if (!-e $try && !$tmpfiles{$try}) {
	    # We have a winner
	    $tmpfiles{$try} = 1;
	    return $try;
	}
	$count = $count + 1;
    } while $count < 26 * 26;
    die "Can't find temporary file name starting 'tmp$$'";
}

# This is the temporary file for _fresh_perl
my $tmpfile = tempfile();

#
# _fresh_perl
#
# The $resolve must be a subref that tests the first argument
# for success, or returns the definition of success (e.g. the
# expected scalar) if given no arguments.
#

sub _fresh_perl {
    my($prog, $resolve, $runperl_args, $name) = @_;

    $runperl_args ||= {};
    $runperl_args->{progfile} = $tmpfile;
    $runperl_args->{stderr} = 1;

    open TEST, ">", $tmpfile or die "Cannot open $tmpfile: $!";

    # VMS adjustments
    if( $^O eq 'VMS' ) {
        $prog =~ s#/dev/null#NL:#;

        # VMS file locking
        $prog =~ s{if \(-e _ and -f _ and -r _\)}
                  {if (-e _ and -f _)}
    }

    print TEST $prog;
    close TEST or die "Cannot close $tmpfile: $!";

    my $results = runperl(%$runperl_args);
    my $status = $?;

    # Clean up the results into something a bit more predictable.
    $results =~ s/\n+$//;
    $results =~ s/at\s+misctmp\d+\s+line/at - line/g;
    $results =~ s/of\s+misctmp\d+\s+aborted/of - aborted/g;

    # bison says 'parse error' instead of 'syntax error',
    # various yaccs may or may not capitalize 'syntax'.
    $results =~ s/^(syntax|parse) error/syntax error/mig;

    if ($^O eq 'VMS') {
        # some tests will trigger VMS messages that won't be expected
        $results =~ s/\n?%[A-Z]+-[SIWEF]-[A-Z]+,.*//;

        # pipes double these sometimes
        $results =~ s/\n\n/\n/g;
    }

    my $pass = $resolve->($results);
    unless ($pass) {
        diag "# PROG: \n$prog\n";
        diag "# EXPECTED:\n", $resolve->(), "\n";
        diag "# GOT:\n$results\n";
        diag "# STATUS: $status\n";
    }

    # Use the first line of the program as a name if none was given
    unless( $name ) {
        ($first_line, $name) = $prog =~ /^((.{1,50}).*)/;
        $name .= '...' if length $first_line > length $name;
    }

    ok($pass, "fresh_perl - $name");
}

#
# fresh_perl_is
#
# Combination of run_perl() and is().
#

sub fresh_perl_is {
    my($prog, $expected, $runperl_args, $name) = @_;
    local $Level = 2;
    _fresh_perl($prog,
		sub { @_ ? $_[0] eq $expected : $expected },
		$runperl_args, $name);
}

#
# fresh_perl_like
#
# Combination of run_perl() and like().
#

sub fresh_perl_like {
    my($prog, $expected, $runperl_args, $name) = @_;
    local $Level = 2;
    _fresh_perl($prog,
		sub { @_ ?
			  $_[0] =~ (ref $expected ? $expected : /$expected/) :
		          $expected },
		$runperl_args, $name);
}

# now my new B::C functions

sub run_cmd {
    my ($cmd, $timeout) = @_;

    my ($result, $out, $err) = (0, '', '');
    if ( ! defined $IPC::Run::VERSION ) {
	local $@;
	if (ref($cmd) eq 'ARRAY') {
            $cmd = join " ", @$cmd;
        }
	# No real way to trap STDERR?
        $cmd .= " 2>&1" if $^O !~ /^MSWin32|VMS/;
        warn $cmd."\n" if $ENV{TEST_VERBOSE};
	$out = `$cmd`;
        warn "# $out\n" if $ENV{TEST_VERBOSE};
	$result = $?;
    }
    else {
	my $in;
        # XXX TODO this fails with spaces in path. pass and check ARRAYREF then
	my @cmd = ref($cmd) eq 'ARRAY' ? @$cmd : split /\s+/, $cmd;
        warn join(" ", @cmd)."\n" if $ENV{TEST_VERBOSE};

	eval {
            # XXX TODO hanging or stacktrace'd children are not killed on cygwin
	    my $h = IPC::Run::start(\@cmd, \$in, \$out, \$err);
	    if ($timeout) {
		my $secs10 = $timeout/10;
		for (1..$secs10) {
		    if(!$h->pumpable) {
			last;
		    }
		    else {
			$h->pump_nb;
			diag sprintf("waiting %d[s]",$_*10) if $_ > 30;
			sleep 10;
		    }
		}
		if($h->pumpable) {
		    $h->kill_kill;
		    $err .= "Timed out waiting for process exit";
		}
	    }
	    $h->finish or die "cmd returned $?";
	    $result = $h->result(0);
	};
        warn $out."\n" if $ENV{TEST_VERBOSE};
	$err .= "\$\@ = $@" if($@);
        warn $err."\n" if $ENV{TEST_VERBOSE};
    }
    return ($result, $out, $err);
}

sub Mblib {
    if ($ENV{PERL_CORE}) {
        $^O eq 'MSWin32' ? '-I..\..\lib'
                         : '-I../../lib';
    } else {
        $^O eq 'MSWin32' ? '-Iblib\arch -Iblib\lib'
                         : '-Iblib/arch -Iblib/lib';
    }
}

sub perlcc {
    if ($ENV{PERL_CORE}) {
        $^O eq 'MSWin32' ? 'script\perlcc -I..\.. -L..\..'
                         : 'script/perlcc -I../.. -L../..';
    } else {
        $^O eq 'MSWin32' ? 'blib\script\perlcc'
                         : 'blib/script/perlcc';
    }
}

sub cc_harness {
    if ($ENV{PERL_CORE} ) {
        $^O eq 'MSWin32' ? 'script\cc_harness'
                         : 'script/cc_harness';
    } else {
        $^O eq 'MSWin32' ? 'blib\script\cc_harness'
                         : 'blib/script/cc_harness';
    }
}

sub tests {
    my $in = shift || "t/TESTS";
    $in = "TESTS" unless -f $in;
    undef $/;
    open TEST, "< $in" or die "Cannot open $in";
    my @tests = split /\n####+.*##\n/, <TEST>;
    close TEST;
    delete $tests[$#tests] unless $tests[$#tests];
    @tests;
}

sub run_cc_test {
    my ($cnt, $backend, $script, $expect, $keep_c, $keep_c_fail, $todo) = @_;
    my ($opt, $got);
    local($\, $,);   # guard against -l and other things that screw with
                     # print
    $expect =~ s/\n$//;
    my ($out,$result,$stderr) = ('');
    my $fnbackend = lc($backend); #C,-O2
    ($fnbackend,$opt) = $fnbackend =~ /^(cc?)(,-o.)?/;
    $opt =~ s/,-/_/ if $opt;
    $opt = '' unless $opt;
    #if ($] > 5.021006 and $fnbackend eq 'cc') { print "ok $cnt # skip CC for 5.22 WIP\n"; return 1; }
    use Config;
    require B::C::Config;
    # note that the smokers run the c.t and c_o3.t tests in parallel, with possible
    # interleaving file writes even for the .pl.
    my $test = $fnbackend."code".$cnt.$opt.".pl";
    my $cfile = $fnbackend."code".$cnt.$opt.".c";
    my @obj;
    @obj = ($fnbackend."code".$cnt.$opt.".obj",
            $fnbackend."code".$cnt.$opt.".ilk",
            $fnbackend."code".$cnt.$opt.".pdb")
      if $Config{cc} =~ /^cl/i; # MSVC uses a lot of intermediate files
    my $exe = $fnbackend."code".$cnt.$opt.$Config{exe_ext};
    unlink ($test, $cfile, $exe, @obj);
    open T, ">", $test; print T $script; close T;
    # Being able to test also the CORE B in older perls
    my $Mblib = $] >= 5.009005 ? Mblib() : "";
    my $useshrplib = $Config{useshrplib} eq 'true';
    unless ($Mblib) {           # check for -Mblib from the testsuite
        if (grep { m{blib(/|\\)arch$} } @INC) {
            $Mblib = Mblib();  # forced -Mblib via cmdline without
            					# printing to stderr
            $backend = "-qq,$backend,-q" if !$ENV{TEST_VERBOSE} and $] > 5.007;
        }
    } else {
        $backend = "-qq,$backend,-q" if !$ENV{TEST_VERBOSE} and $] > 5.007;
    }
    $backend .= ",-fno-warnings" if $] >= 5.013005;
    $backend .= ",-fno-fold" if $] >= 5.013009;
    $got = run_perl(switches => [ "$Mblib -MO=$backend,-o${cfile}" ],
                    verbose  => $ENV{TEST_VERBOSE}, # for debugging
                    nolib    => $ENV{PERL_CORE} ? 0 : 1, # include ../lib only in CORE
                    stderr   => 1, # to capture the "ccode.pl syntax ok"
		    timeout  => 120,
                    progfile => $test);
    if (! $? and -s $cfile) {
	use ExtUtils::Embed ();
	my $coredir = $ENV{PERL_CORE} ? File::Spec->catdir('..', '..')
                         : File::Spec->catdir($Config{installarchlib}, "CORE");
	my $command = ExtUtils::Embed::ccopts;
        $command = $Config{ccflags}." -I".$coredir if $ENV{PERL_CORE};
	$command .= " -DHAVE_INDEPENDENT_COMALLOC "
	  if $B::C::Config::have_independent_comalloc;
	$command .= " -o $exe $cfile ".$B::C::Config::extra_cflags . " ";
        if ($Config{cc} eq 'cl') {
            if ($^O eq 'MSWin32' and $Config{ccversion} eq '12.0.8804' and $Config{cc} eq 'cl') {
                $command =~ s/ -opt:ref,icf//;
            }
            my $obj = $obj[0];
            $command =~ s/ \Q-o $exe\E / -c -Fo$obj /;
            my $cmdline = "$Config{cc} $command";
            diag ($cmdline) if $ENV{TEST_VERBOSE} and $ENV{TEST_VERBOSE} == 2;
            run_cmd($cmdline, 20);
            $command = '';
        }
	my $libdir  = File::Spec->catdir($Config{prefix}, "lib");
        my $so = $Config{so};
        my $linkargs = $ENV{PERL_CORE}
          ? ExtUtils::Embed::_ccdlflags." ".ExtUtils::Embed::_ldflags()
           ." -L../.. -lperl ".$Config{libs}
          : ExtUtils::Embed::ldopts('-std');
        # At least cygwin gcc-4.3 crashes with 2x -fstack-protector
        $linkargs =~ s/-fstack-protector\b//
          if $linkargs !~ /-fstack-protector-strong\b/
          and $command =~ /-fstack-protector\b/
          and $linkargs =~ /-fstack-protector\b/;
	if ( -e "$coredir/$Config{libperl}" and $Config{libperl} !~ /\.$so$/) {
	    $command .= $linkargs;
	} elsif ( $useshrplib and (-e "$libdir/$Config{libperl}" or -e "/usr/lib/$Config{libperl}")) {
            # debian: /usr/lib/libperl.so.5.10.1 and broken ExtUtils::Embed::ldopts
            if ($Config{libperl} =~ /\.$so$/) {
                my $libperl = File::Spec->catfile($coredir, $Config{libperl});
                $linkargs =~ s|-lperl |$libperl |; # link directly
            }
	    $command .= $linkargs;
	} else {
	    $command .= $linkargs;
	    $command .= " -lperl" if $command !~ /(-lperl|CORE\/libperl5)/ and $^O ne 'MSWin32';
	}
	$command .= $B::C::Config::extra_libs;
        my $NULL = $^O eq 'MSWin32' ? '' : '2>/dev/null';
        my $cmdline = "$Config{cc} $command $NULL";
        if ($Config{cc} eq 'cl') {
            $cmdline = "$Config{ld} $linkargs -out:$exe $obj[0] $command";
        }
	diag ($cmdline) if $ENV{TEST_VERBOSE} and $ENV{TEST_VERBOSE} == 2;
        run_cmd($cmdline, 20);
        unless (-e $exe) {
            print "not ok $cnt $todo failed $cmdline\n";
            print STDERR "# ",system("$Config{cc} $command"), "\n";
            #unlink ($test, $cfile, $exe, @obj) unless $keep_c_fail;
            return 0;
        }
        $exe = "./".$exe unless $^O eq 'MSWin32';
	# system("/bin/bash -c ulimit -d 1000000") if -e "/bin/bash";
        ($result,$out,$stderr) = run_cmd($exe, 5);
        if (defined($out) and !$result) {
            if ($out =~ /^$expect$/) {
                print "ok $cnt", $todo eq '#' ? "\n" : " $todo\n";
                unlink ($test, $cfile, $exe, @obj) unless $keep_c;
                return 1;
            } else {
                # cc test failed, double check uncompiled
                $got = run_perl(verbose  => $ENV{TEST_VERBOSE}, # for debugging
                                nolib    => $ENV{PERL_CORE} ? 0 : 1, # include ../lib only in CORE
                                stderr   => 1, # to capture the "ccode.pl syntax ok"
                                timeout  => 10,
                                progfile => $test);
                if (! $? and $got =~ /^$expect$/) {
                    print "not ok $cnt $todo wanted: \"$expect\", got: \"$out\"\n";
                } else {
                    print "ok $cnt # skip also fails uncompiled\n";
                    return 1;
                }
                unlink ($test, $cfile, $exe, @obj) unless $keep_c_fail;
                return 0;
            }
        } else {
            $out = '';
        }
    }
    print "not ok $cnt $todo wanted: \"$expect\", \$\? = $?, got: \"$out\"\n";
    if ($stderr) {
	$stderr =~ s/\n./\n# /xmsg;
	print "# $stderr\n";
    }
    unlink ($test, $cfile, $exe, @obj) unless $keep_c_fail;
    return 0;
}

sub prepare_c_tests {
    BEGIN {
        use Config;
        if ($^O eq 'VMS') {
            print "1..0 # skip - B::C doesn't work on VMS\n";
            exit 0;
        }
        if (($Config{'extensions'} !~ /\bB\b/) ) {
            print "1..0 # Skip -- Perl configured without B module\n";
            exit 0;
        }
        # with 5.10 and 5.8.9 PERL_COPY_ON_WRITE was renamed to PERL_OLD_COPY_ON_WRITE
        if ($Config{ccflags} =~ /-DPERL_OLD_COPY_ON_WRITE/) {
            print "1..0 # skip - no OLD COW for now\n";
            exit 0;
        }
    }
}

sub run_c_tests {
    my $backend = $_[0];
    my @todo = @{$_[1]};
    my @skip = @{$_[2]};

    use Config;
    my $AUTHOR     = (-d ".git" and !$ENV{NO_AUTHOR}) ? 1 : 0;
    my $keep_c      = 0;	  # set it to keep the pl, c and exe files
    my $keep_c_fail = 1;          # keep on failures

    my %todo = map { $_ => 1 } @todo;
    my %skip = map { $_ => 1 } @skip;
    my @tests = tests();

    # add some CC specific tests after 100
    # perl -lne "/^\s*sub pp_(\w+)/ && print \$1" lib/B/CC.pm > ccpp
    # for p in `cat ccpp`; do echo -n "$p "; grep -m1 " $p[(\[ ]" *.concise; done
    #
    # grep -A1 "coverage: ny" lib/B/CC.pm|grep sub
    # pp_stub pp_cond_expr pp_dbstate pp_reset pp_stringify pp_ncmp pp_preinc
    # pp_formline pp_enterwrite pp_leavewrite pp_entergiven pp_leavegiven
    # pp_dofile pp_grepstart pp_mapstart pp_grepwhile pp_mapwhile
    if ($backend =~ /^CC/) {
        local $/;
        my $cctests = <<'CCTESTS';
my ($r_i,$i_i,$d_d)=(0,2,3.0); $r_i=$i_i*$i_i; $r_i*=$d_d; print $r_i;
>>>>
12
######### 101 - CC types and arith ###############
if ($x eq "2"){}else{print "ok"}
>>>>
ok
######### 102 - CC cond_expr,stub,scope ############
require B; my $x=1e1; my $s="$x"; print ref B::svref_2object(\$s)
>>>>
B::PV
######### 103 - CC stringify srefgen ############
@a=(1..4);while($a=shift@a){print $a;}continue{$a=~/2/ and reset q(a);}
>>>>
12
######### 104 CC reset ###############################
use blib;use B::CC;my int $r;my $i:int=2;our double $d=3.0; $r=$i*$i; $r*=$d; print $r;
>>>>
12
######### 105 CC attrs ###############################
my $s=q{ok};END{print $s}END{$x = 0}
>>>>
ok
######### 106 CC 296/297 ###############################
CCTESTS

        my $i = 100;
        for (split /\n####+.*##\n/, $cctests) {
            next unless $_;
            $tests[$i] = $_;
            $i++;
        }
    }

    print "1..".(scalar @tests)."\n";

    my $cnt = 1;
    for (@tests) {
        my $todo = $todo{$cnt} ? "#TODO" : "#";
        # skip empty CC holes to have the same test indices in STATUS and t/testcc.sh
        unless ($_) {
            print sprintf("ok %d # skip hole for CC\n", $cnt);
            $cnt++;
            next;
        }
        # only once. skip subsequent tests 29 on MSVC. 7:30min!
        if ($cnt == 29 and !$AUTHOR) {
            $todo{$cnt} = $skip{$cnt} = 1;
        }
        if ($todo{$cnt} and $skip{$cnt} and
            # those are currently blocking the system
            # do not even run them at home if TODO+SKIP
            (!$AUTHOR
             or ($cnt==15 and $backend eq 'C,-O1')   # hanging
             or ($cnt==103 and $backend eq 'CC,-O2') # hanging
            ))
        {
            print sprintf("ok %d # skip\n", $cnt);
        } else {
            my ($script, $expect) = split />>>+\n/;
	    die "Invalid empty t/TESTS" if !$script or $expect eq '';
            if ($cnt == 4 and $] >= 5.017005) {
                $expect = 'zzz2y2y2';
            }
            run_cc_test($cnt, $backend.($cnt == 46 ? ',-fstash' : ''),
			$script, $expect, $keep_c, $keep_c_fail, $todo);
        }
        $cnt++;
    }
}

sub plctestok {
    my ($num, $base, $script, $todo) =  @_;
    plctest($num,'^ok', $base, $script, $todo);
}

sub plctest {
    my ($num, $expected, $base, $script, $todo) =  @_;

    if ($] > 5.021006 and !$B::C::Config::have_byteloader) {
        ok(1, "SKIP perl5.22 broke ByteLoader");
        return 1;
    }
    my $name = $base."_$num";
    unlink($name, "$name.plc", "$name.pl", "$name.exe");
    open F, ">", "$base.pl";
    print F $script;
    print F "\n";
    close F;

    my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
    # we don't want to change STDOUT/STDERR on STDOUT/STDERR tests, so no -qq
    my $nostdoutclobber = $base !~ /^ccode93i/;
    my $b = ($] > 5.008 and $nostdoutclobber) ? "-qq,Bytecode" : "Bytecode";
    my $Mblib = Mblib;
    my $cmd = "$runperl $Mblib -MO=$b,-o$name.plc $base.pl";
    diag($cmd) if $ENV{TEST_VERBOSE} and $ENV{TEST_VERBOSE} > 1;
    system $cmd;
    # $out =~ s/^$base.pl syntax OK\n//m;
    unless (-e "$name.plc") {
        ok(0, '#B::Bytecode failed');
        return 1;
    }
    $cmd = "$runperl $Mblib -MByteLoader $name.plc";
    diag($cmd) if $ENV{TEST_VERBOSE} and $ENV{TEST_VERBOSE} > 1;
    my $out = qx($cmd);
    chomp $out;
    my $ok = $out =~ /$expected/;
    if ($todo and $todo =~ /TODO/) {
	$todo =~ s/TODO //;
      TODO: {
	    local $TODO = $todo;
	    ok($ok);
	}
    } else {
	ok($ok, $todo ? "$todo" : '');
    }
    if ($ok) {
        unlink("$name.plc", "$base.pl");
    }
}

sub ctestok {
    my ($num, $backend, $base, $script, $todo) =  @_;
    my $qr = '^ok'; # how lame
    ctest($num, $qr, $backend, $base, $script, $todo);
}

sub ctest {
    my ($num, $expected, $backend, $base, $script, $todo) =  @_;
    my $name = $base."_$num";
    my $b = $backend; # protect against parallel test name clashes
    #if ($] > 5.021006 and $backend =~ /^CC/i) { ok(1, "skip CC for 5.22 WIP"); return 1; } # temp 5.22
    $b =~ s/-(D.*|f.*|v),//g;
    $b =~ s/-/_/g;
    $b =~ s/[, ]//g;
    $b = lc($b);
    $name .= $b;
    unlink($name, "$name.c", "$name.pl", "$name.exe");
    open F, ">", "$name.pl";
    print F $script;
    close F;

    my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
    # we don't want to change STDOUT/STDERR on STDOUT/STDERR tests, so no -qq
    my $nostdoutclobber = $base !~ /^ccode93i/;
    my $post = '';
    my $Mblib = Mblib();
    $b = ($] > 5.008 and $nostdoutclobber) ? "-qq,$backend" : "$backend";
    ($b, $post) = split(" ", $b);
    $post = '' unless $post;
    $b .= q(,-fno-fold,-fno-warnings) if $] >= 5.013005 and $b !~ /-(O3|ffold|fwarnings)/;
    diag("$runperl $Mblib -MO=$b,-o$name.c $post $name.pl")
      if $ENV{TEST_VERBOSE} and $ENV{TEST_VERBOSE} > 1;
    system "$runperl $Mblib -MO=$b,-o$name.c $post $name.pl";
    unless (-e "$name.c") {
        ok (undef, "$todo B::$backend failed to compile");
        return 1;
    }
    my $cc_harness = cc_harness();
    my $cmd = "$runperl $Mblib $cc_harness -q -o $name $name.c";
    if ($ENV{TEST_VERBOSE} and $ENV{TEST_VERBOSE} > 1) {
        $cmd =~ s/ -q / /;
        diag("$cmd");
    }
    system "$cmd";
    my $exe = $name.$Config{exe_ext};
    unless (-e $exe) {
	if ($todo and $todo =~ /TODO/) {
	    $todo =~ s/TODO //;
          TODO: {
                local $TODO = $todo;
                ok(undef, "failed to compile");
            }
        } else {
            ok(undef, "failed to compile $todo");
        }
        return;
    }
    $exe = "./".$exe unless $^O eq 'MSWin32';
    ($result,$out,$stderr) = run_cmd($exe, 5);
    my $ok;
    if (defined($out) and !$result) {
        chomp $out;
        $ok = $out =~ /$expected/;
	diag($out) if $ENV{TEST_VERBOSE};
	unless ($ok) { #crosscheck uncompiled
            my $out1 = `$runperl $name.pl`;
            unless ($out1 =~ /$expected/) {
                ok(1, "skip also fails uncompiled $todo");
                return 1;
            }
        }
	if ($todo and $todo =~ /TODO/) {
	    $todo =~ s/TODO //;
          TODO: {
                local $TODO = $todo;
                ok ($out =~ /$expected/);
		diag($out) if $ENV{TEST_VERBOSE};
            }
        } else {
            ok ($out =~ /$expected/, $todo);
        }
    } else {
	if ($todo and $todo =~ /TODO/) {
	    $todo =~ s/TODO //;
          TODO: {
                local $TODO = $todo;
                ok (undef);
            }
	} else {
	    #crosscheck uncompiled
	    my $out1 = `$runperl $name.pl`;
            unless ($out1 =~ /$expected/) {
                ok(1, "skip also fails uncompiled");
                return $ok;
            }
	    ok (undef, $todo);
	}
    }
    unlink("$name.pl");
    if ($ok) {
        unlink($name, "$name.c", "$name.exe");
    }
    $ok
}

sub ccompileok {
    my ($num, $backend, $base, $script, $todo) =  @_;
    my $name = $base."_$num";
    unlink($name, "$name.c", "$name.pl", "$name.exe");
    open F, ">", "$name.pl";
    print F $script;
    close F;

    my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
    my $b = $] > 5.008 ? "-qq,$backend" : "$backend";
    my $Mblib = Mblib();
    system "$runperl $Mblib -MO=$b,-o$name.c $name.pl";
    unless (-e "$name.c") {
        ok (undef, "#B::$backend failed");
        return 1;
    }
    my $cc_harness = cc_harness();
    system "$runperl $Mblib $cc_harness -q -o $name $name.c";
    my $ok = -e $name or -e "$name.exe";
    if ($todo and $todo =~ /TODO/) {
      TODO: {
	    $todo =~ s/TODO //;
            local $TODO = $todo;
            ok($ok);
        }
    } else {
        ok($ok, $todo);
    }
    unlink("$name.pl");
    if ($ok) {
        unlink($name, "$name.c", "$name.exe");
    }
}

sub todo_tests_default {
    my $what = shift;
    my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
    my $ITHREADS  = ($Config{useithreads});

    my @todo  = ();
    # no IO::Scalar
    push @todo, (15)  if $] < 5.007;
    # broken by fbb32b8bebe8ad C: revert *-,*+,*! fetch magic, assign all core GVs to their global symbols
    push @todo, (42..43) if $] < 5.012;
    if ($what =~ /^c(|_o[1-4])$/) {
        # a regression
	push @todo, (41)  if $] < 5.007; #regressions
        push @todo, (12)  if $what eq 'c_o3' and !$ITHREADS and $] >= 5.008009 and $] < 5.010;

        push @todo, (48) if $] >= 5.018; # opfree
        push @todo, (48) if $what eq 'c_o4' and $] < 5.021 and $ITHREADS;
        push @todo, (8,18,19,25,26,28)  if $what eq 'c_o4' and !$ITHREADS;
        push @todo, (13,18,29,34) if $] >= 5.021006 and $ITHREADS;
        push @todo, (10,15,27,41,42,43,44,45,49,50)
          if $] >= 5.021006 and $what eq 'c_o4';
        push @todo, (13,18,29,34)
          if $] >= 5.021006 and $what eq 'c_o4' and $ITHREADS;
        push @todo, (12,14,38)
          if $] >= 5.021006 and $what eq 'c_o4' and !$ITHREADS;
    } elsif ($what =~ /^cc/) {
	push @todo, (21,30,105,106);
	push @todo, (22,41,45,103) if $] < 5.007; #regressions
	push @todo, (104,105) if $] < 5.007; # leaveloop, no cxstack
        push @todo, (42,43)   if $] > 5.008 and $] <= 5.008005 and !$ITHREADS;

	#push @todo, (33,45) if $] >= 5.010 and $] < 5.012;
	push @todo, (10,16,50) if $what eq 'cc_o2';
	push @todo, (29)    if $] < 5.008008;
	push @todo, (22)    if $] < 5.010 and !$ITHREADS;
	push @todo, (46); # HvKEYS(%Exporter::) is 0 unless Heavy is included also
	# solaris also. I suspected nvx<=>cop_seq_*
	push @todo, (12)    if $^O eq 'MSWin32' and $Config{cc} =~ /^cl/i;
	push @todo, (26)    if $what =~ /^cc_o[12]/;
        push @todo, (27)    if $] > 5.008008 and $] < 5.009;
	#push @todo, (27)    if $] > 5.008008 and $] < 5.009 and $what eq 'cc_o2';
        push @todo, (103)   if ($] >= 5.012 and $] < 5.014 and !$ITHREADS);
        push @todo, (12,19,25) if $] >= 5.019;
        push @todo, (25)    if $] >= 5.021006 and !$Config{usecperl};
	push @todo, (29)    if $] >= 5.021006 and $what eq 'cc_o1';
	push @todo, (24,29) if $] >= 5.021006 and $what eq 'cc_o2';
    }
    push @todo, (48)   if $] > 5.007 and $] < 5.009 and $^O =~ /MSWin32|cygwin/i;
    return @todo;
}

1;

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 78
# End:
# vim: expandtab shiftwidth=4:
