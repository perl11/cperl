
require 5;
package Pod::Simple::XMLOutStream;
use strict;
use Carp ();
use Pod::Simple ();
use vars qw( $ATTR_PAD @ISA $VERSION $SORT_ATTRS);
use cperl;
our $VERSION = '4.35c'; # modernized
$VERSION =~ s/c$//;
BEGIN {
  @ISA = ('Pod::Simple');
  *DEBUG = \&Pod::Simple::DEBUG unless defined &DEBUG;
}

$ATTR_PAD = "\n" unless defined $ATTR_PAD;
 # Don't mess with this unless you know what you're doing.

$SORT_ATTRS = 0 unless defined $SORT_ATTRS;

sub new ($self, @args) :method {
  my $new = $self->SUPER::new(@args);
  $new->{'output_fh'} ||= *STDOUT{IO};
  $new->keep_encoding_directive(1);
  #$new->accept_codes('VerbatimFormatted');
  return $new;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub _handle_element_start ($self, $element_name, $attr) :method {
  my $fh = $self->{'output_fh'};
  my($key, $value);
  DEBUG and print STDERR "++ $element_name\n";
  print $fh "<", $element_name;
  if($SORT_ATTRS) {
    foreach my $key (sort keys %{$attr}) {
      unless($key =~ m/^~/s) {
        next if $key eq 'start_line' and $self->{'hide_line_numbers'};
        _xml_escape($value = $attr->{$key});
        print $fh $ATTR_PAD, $key, '="', $value, '"';
      }
    }
  } else { # faster
    while(($key,$value) = each %{$attr}) {
      unless($key =~ m/^~/s) {
        next if $key eq 'start_line' and $self->{'hide_line_numbers'};
        _xml_escape($value);
        print $fh $ATTR_PAD, $key, '="', $value, '"';
      }
    }
  }
  print $fh ">";
  return;
}

sub _handle_text ($self, str $text='') :method {
  DEBUG and print STDERR "== \"$text\"\n";
  if (length $text) {
    _xml_escape($text);
    print {$self->{'output_fh'}} $text;
  }
  return;
}

sub _handle_element_end ($self, str $element_name, $attr?) :method {
  DEBUG and print STDERR "-- $element_name\n";
  print {$self->{'output_fh'}} "</", $element_name, ">";
  return;
}

# . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub _xml_escape { # by-ref
  foreach my $x (@_) {
    # Escape things very cautiously:
    if ($] ge 5.007_003) {
      $x =~ s/([^-\n\t !\#\$\%\(\)\*\+,\.\~\/\:\;=\?\@\[\\\]\^_\`\{\|\}abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789])/'&#'.(utf8::native_to_unicode(ord($1))).';'/eg;
    } else { # Is broken for non-ASCII platforms on early perls
      $x =~ s/([^-\n\t !\#\$\%\(\)\*\+,\.\~\/\:\;=\?\@\[\\\]\^_\`\{\|\}abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789])/'&#'.(ord($1)).';'/eg;
    }
    # Yes, stipulate the list without a range, so that this can work right on
    #  all charsets that this module happens to run under.
  }
  return;
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
1;

__END__

=head1 NAME

Pod::Simple::XMLOutStream -- turn Pod into XML

=head1 SYNOPSIS

  perl -MPod::Simple::XMLOutStream -e \
   "exit Pod::Simple::XMLOutStream->filter(shift)->any_errata_seen" \
   thingy.pod

=head1 DESCRIPTION

Pod::Simple::XMLOutStream is a subclass of L<Pod::Simple> that parses
Pod and turns it into XML.

Pod::Simple::XMLOutStream inherits methods from
L<Pod::Simple>.


=head1 SEE ALSO

L<Pod::Simple::DumpAsXML> is rather like this class; see its
documentation for a discussion of the differences.

L<Pod::Simple>, L<Pod::Simple::DumpAsXML>, L<Pod::SAX>

L<Pod::Simple::Subclassing>

The older (and possibly obsolete) libraries L<Pod::PXML>, L<Pod::XML>


=head1 ABOUT EXTENDING POD

TODO: An example or two of =extend, then point to Pod::Simple::Subclassing

=head1 SEE ALSO

L<Pod::Simple>, L<Pod::Simple::Text>, L<Pod::Spell>

=head1 SUPPORT

Questions or discussion about POD and Pod::Simple should be sent to the
pod-people@perl.org mail list. Send an empty email to
pod-people-subscribe@perl.org to subscribe.

This module is managed in an open GitHub repository,
L<https://github.com/perl-pod/pod-simple/>. Feel free to fork and contribute, or
to clone L<git://github.com/perl-pod/pod-simple.git> and send patches!

Patches against Pod::Simple are welcome. Please send bug reports to
<bug-pod-simple@rt.cpan.org>.

=head1 COPYRIGHT AND DISCLAIMERS

Copyright (c) 2002-2004 Sean M. Burke.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=head1 AUTHOR

Pod::Simple was created by Sean M. Burke <sburke@cpan.org>.
But don't bother him, he's retired.

Pod::Simple is maintained by:

=over

=item * Allison Randal C<allison@perl.org>

=item * Hans Dieter Pearcey C<hdp@cpan.org>

=item * David E. Wheeler C<dwheeler@cpan.org>

=back

=cut
