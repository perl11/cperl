# vim: ts=8 sw=4 expandtab:
##########################################################
# This script is part of the Devel::NYTProf distribution
#
# Copyright, contact and other information can be found
# at the bottom of this file, or by going to:
# http://metacpan.org/release/Devel-NYTProf/
#
###########################################################
package Devel::NYTProf::Util;

=head1 NAME

Devel::NYTProf::Util - general utility functions for L<Devel::NYTProf>

=head1 SYNOPSIS

  use Devel::NYTProf::Util qw(strip_prefix_from_paths);

=head1 DESCRIPTION

Contains general utility functions for L<Devel::NYTProf>

B<Note:> The documentation for this module is currently incomplete and out of date.

=head1 FUNCTIONS

=encoding ISO8859-1

=cut


use warnings;
use strict;

use base qw'Exporter';

use Carp;
use Cwd qw(getcwd);
use List::Util qw(sum);
use Devel::NYTProf::Core;

our $VERSION = '4.00';

our @EXPORT_OK = qw(
    fmt_float
    fmt_time
    fmt_incl_excl_time
    make_path_strip_editor
    strip_prefix_from_paths
    calculate_median_absolute_deviation
    get_alternation_regex
    get_abs_paths_alternation_regex
    html_safe_filename
    trace_level
);


sub get_alternation_regex {
    my ($strings, $suffix_regex) = @_;
    $suffix_regex = '' unless defined $suffix_regex;

    # sort longest string first
    my @strings = sort { length $b <=> length $a } @$strings;

    # build string regex for each string
    my $regex = join "|", map { quotemeta($_) . $suffix_regex } @strings;

    return qr/(?:$regex)/;
}


sub get_abs_paths_alternation_regex {
    my ($inc, $cwd) = @_;
    my @inc = @$inc or croak "No paths";

    # rewrite relative directories to be absolute
    # the logic here should match that in get_file_id()
    my $abs_path_regex = ($^O eq "MSWin32") ? qr,^\w:/, : qr,^/,;
    for (@inc) {
        next if $_ =~ $abs_path_regex;    # already absolute
        $_ =~ s/^\.\///;   # remove a leading './'
        $cwd ||= getcwd();
        $_ = ($_ eq '.') ? $cwd : "$cwd/$_";
    }

    return get_alternation_regex(\@inc, '/?');
}


sub make_path_strip_editor {
    my ($inc_ref, $anchor, $replacement) = @_;
    $anchor      = '^' if not defined $anchor;
    $replacement = ''  if not defined $replacement;

    my @inc = @$inc_ref
        or return;

    our %make_path_strip_editor_cache;
    my $key = join "\t", $anchor, $replacement, @inc;

    return $make_path_strip_editor_cache{$key} ||= do {

        my $inc_regex = get_abs_paths_alternation_regex(\@inc);

        # anchor at start, capture anchor
        $inc_regex = qr{($anchor)$inc_regex};

        sub { $_[0] =~ s{$inc_regex}{$1$replacement} };
    };
}


# edit @$paths in-place to remove specified absolute path prefixes
sub strip_prefix_from_paths {
    my ($inc_ref, $paths, $anchor, $replacement) = @_;

    return if not defined $paths;

    my $editor = make_path_strip_editor($inc_ref, $anchor, $replacement)
        or return;

    # strip off prefix using regex, skip any empty/undef paths
    if (UNIVERSAL::isa($paths, 'ARRAY')) {
        for my $path (@$paths) {
            if (ref $path) {    # recurse to process deeper data
                strip_prefix_from_paths($inc_ref, $path, $anchor, $replacement);
            }
            elsif ($path) {
                $editor->($path);
            }
        }
    }
    elsif (UNIVERSAL::isa($paths, 'HASH')) {
        for my $orig (keys %$paths) {
            $editor->(my $new = $orig)
                or next;
            my $value = delete $paths->{$orig};
            warn "Stripping prefix from $orig overwrites existing $new"
                if defined $paths->{$new};
            $paths->{$new} = $value;
        }
    }
    else {
        croak "Can't strip_prefix_from_paths of $paths";
    }

    return;
}


# eg normalize the width/precision so that the tables look good.
sub fmt_float {
    my ($val, $precision) = @_;
    $precision ||= 5;
    if ($val < 10 ** -($precision - 1) and $val > 0) {
	# Give the same width as a larger value formatted with the %f below.
	# This gives us 2 digits of precision for $precision == 5
        $val = sprintf("%." . ($precision - 4) . "e", $val);
	# But our exponents will always be e-05 to e-09, never e-10 or smaller
	# so remove the leading zero to make these small numbers stand out less
	# on the table.
	$val =~ s/e-0/e-/;
    }
    elsif ($val != int($val)) {
        $val = sprintf("%.${precision}f", $val);
    }
    return $val;
}


# XXX undocumented hack that may become to an option one day
# Useful for making the time data more easily parseable
my $fmt_time_opt = $ENV{NYTPROF_FMT_TIME}; # e.g., '%f' for 'raw' times

sub fmt_time {
    my ($sec, $width) = @_;
    $width = '' unless defined $width;
    return undef if not defined $sec;
    return '-'.fmt_time(-$sec, $width) if $sec < 0; # negative value, can happen
    return sprintf $fmt_time_opt, $sec if $fmt_time_opt;
    return sprintf "%$width.0fs", 0    unless $sec;
    return sprintf "%$width.0fns",                              $sec * 1e9 if $sec < 1e-6;
    return sprintf "%$width.0fµs",                              $sec * 1e6 if $sec < 1e-3;
    return sprintf "%$width.*fms", 3 - length(int($sec * 1e3)), $sec * 1e3 if $sec < 1;
    return sprintf "%$width.*fs",  3 - length(int($sec      )), $sec       if $sec < 100;
    return sprintf "%$width.0fs", $sec;
}


sub fmt_incl_excl_time {
    my ($incl, $excl) = @_;
    my $diff = $incl - $excl;
    return fmt_time($incl) unless $diff;
    $_ = fmt_time($_) for $incl, $excl, $diff;
    if ($incl =~ /(\D+)$/) {
	# no need to repeat the unit if it's the same for all time stamps
	my $unit = $1;
	my $offset = -length($unit);
	for ($excl, $diff) {
	    if (/(\D+)$/) {
		substr($_, $offset) = "" if $1 eq $unit
	    }
	}
    }
    return sprintf "%s (%s+%s)", $incl, $excl, $diff;
}


## Given a ref to an array of numeric values
## returns median distance from the median value, and the median value.
## See http://en.wikipedia.org/wiki/Median_absolute_deviation
sub calculate_median_absolute_deviation {
    my $values_ref = shift;
    my ($ignore_zeros) = @_;
    croak "No array ref given" unless ref $values_ref eq 'ARRAY';

    my @values = ($ignore_zeros) ? grep {$_} @$values_ref : @$values_ref;
    my $median_value = [sort { $a <=> $b } @values]->[@values / 2];

    return [0, 0] if not defined $median_value;    # no data

    my @devi = map { abs($_ - $median_value) } @values;
    my $median_devi = [sort { $a <=> $b } @devi]->[@devi / 2];

    return [$median_devi, $median_value];
}


sub html_safe_filename {
    my ($fname) = @_;
    # replace / and \ with html safe '-', we also do a bunch of other
    # chars, especially ':' for Windows, to make the namer simpler and safer
    # also remove dots to keep VMS happy
    $fname =~ s{  [-/\\:\*\?"'<>|.]+ }{-}xg;
    # remove any leading or trailing '-' chars
    $fname =~ s{^-}{};
    $fname =~ s{-$}{};
    if($^O eq 'VMS'){
        # ODS-2 is limited to 39.39 chars (39 filename, 39 extension)
	# Reader.pm appends -LEVEL onto html safe filename so must
	# subtract 1 + max length of (sub block line), so 6.
        $fname = substr($fname,-33);
    }
    return $fname;
}

1;

__END__

=head1 SEE ALSO

L<Devel::NYTProf> and L<Devel::NYTProf::Data>

=head1 AUTHOR

B<Adam Kaplan>, C<< <akaplan at nytimes.com> >>
B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>
B<Steve Peters>, C<< <steve at fisharerojo.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008 by Tim Bunce, Ireland.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
