package Devel::NYTProf::Run;

# vim: ts=8 sw=4 expandtab:
##########################################################
# This script is part of the Devel::NYTProf distribution
#
# Copyright, contact and other information can be found
# at the bottom of this file, or by going to:
# http://metacpan.org/release/Devel-NYTProf/
#
###########################################################

=head1 NAME

Devel::NYTProf::Run - Invoke NYTProf on a piece of code and return the profile

=head1 SYNOPSIS

=head1 DESCRIPTION

This module is experimental and subject to change.

=cut

use warnings;
use strict;

use base qw(Exporter);

use Carp;
use Config qw(%Config);
use Devel::NYTProf::Data;

our @EXPORT_OK = qw(
    profile_this
    perl_command_words
);


my $this_perl = $^X;
$this_perl .= $Config{_exe} if $^O ne 'VMS' and $this_perl !~ m/$Config{_exe}$/i;


sub perl_command_words {
    my %opt = @_;

    my @perl = ($this_perl);
    
    # testing just $Config{usesitecustomize} isn't reliable for perl 5.11.x
    if (($Config{usesitecustomize}||'') eq 'define'
    or   $Config{ccflags} =~ /(?<!\w)-DUSE_SITECUSTOMIZE\b/
    ) {
        push @perl, '-f' if $opt{skip_sitecustomize};
    }

    return @perl;
}


# croaks on failure to execute
# carps, not croak, if process has non-zero exit status
# Devel::NYTProf::Data->new may croak, e.g., if data truncated
sub profile_this {
    my %opt = @_;

    my $out_file = $opt{out_file} || 'nytprof.out';

    my @perl = (perl_command_words(%opt), '-d:NYTProf');

    warn sprintf "profile_this() using %s with NYTPROF=%s\n",
            join(" ", @perl), $ENV{NYTPROF} || ''
        if $opt{verbose};

    # ensure child has same libs as us (e.g., if we were run with perl -Mblib)
    local $ENV{PERL5LIB} = join($Config{path_sep}, @INC);

    if (my $src_file = $opt{src_file}) {
        system(@perl, $src_file) == 0
            or carp "Exit status $? from @perl $src_file";
    }
    elsif (my $src_code = $opt{src_code}) {
        my $cmd = join ' ', map qq{"$_"}, @perl;
        open my $fh, "| $cmd"
            or croak "Can't open pipe to $cmd";
        print $fh $src_code;
        close $fh
            or carp $! ? "Error closing $cmd pipe: $!"
                       : "Exit status $? from $cmd";

    }
    else {
        croak "Neither src_file or src_code was provided";
    }

    # undocumented hack that's handy for testing
    if ($opt{htmlopen}) {
        my @nytprofhtml_open = ("perl", "nytprofhtml", "--open", "-file=$out_file");
        warn "Running @nytprofhtml_open\n";
        system @nytprofhtml_open;
    }

    my $profile = Devel::NYTProf::Data->new( { filename => $out_file } );

    unlink $out_file;

    return $profile;
}

1;
