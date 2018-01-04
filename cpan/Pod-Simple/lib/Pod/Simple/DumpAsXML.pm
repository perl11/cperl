
require 5;
package Pod::Simple::DumpAsXML;
use cperl;
our $VERSION = '4.36c'; # modernized
$VERSION =~ s/c$//;
use Pod::Simple ();
BEGIN {@ISA = ('Pod::Simple')}

use strict;

use Carp ();
use Text::Wrap qw(wrap);

BEGIN { *DEBUG = \&Pod::Simple::DEBUG unless defined &DEBUG }

sub new ($self, @args) :method {
  my $new = $self->SUPER::new(@args);
  $new->{'output_fh'} ||= *STDOUT{IO};
  $new->accept_codes('VerbatimFormatted');
  $new->keep_encoding_directive(1);
  return $new;
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

sub _handle_element_start ($self, $element_name, $attr?) :method {
  my $fh = $self->{'output_fh'};
  my($key, $value);
  DEBUG and print STDERR "++ $element_name\n";
  
  print $fh   '  ' x ($self->{'indent'} || 0),  "<", $element_name;

  foreach my $key (sort keys %{$attr}) {
    unless($key =~ m/^~/s) {
      next if $key eq 'start_line' and $self->{'hide_line_numbers'};
      _xml_escape($value = $attr->{$key});
      print $fh ' ', $key, '="', $value, '"';
    }
  }


  print $fh ">\n";
  $self->{'indent'}++;
  return;
}

sub _handle_text ($self, str $text='') :method {
  DEBUG and print STDERR "== \"$text\"\n";
  if(length $text) {
    my $indent = '  ' x $self->{'indent'};
    _xml_escape($text);
    local $Text::Wrap::huge = 'overflow';
    $text = wrap('', $indent, $text);
    print {$self->{'output_fh'}} $indent, $text, "\n";
  }
  return;
}

sub _handle_element_end ($self, str $element_name, $attr?) :method {
  DEBUG and print STDERR "-- $element_name\n";
  print {$self->{'output_fh'}}
   '  ' x --$self->{'indent'}, "</", $element_name, ">\n";
  return;
}

# . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

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

Pod::Simple::DumpAsXML -- turn Pod into XML

=head1 SYNOPSIS

  perl -MPod::Simple::DumpAsXML -e \
   "exit Pod::Simple::DumpAsXML->filter(shift)->any_errata_seen" \
   thingy.pod

=head1 DESCRIPTION

Pod::Simple::DumpAsXML is a subclass of L<Pod::Simple> that parses Pod
and turns it into indented and wrapped XML.  This class is of
interest to people writing Pod formatters based on Pod::Simple.

Pod::Simple::DumpAsXML inherits methods from
L<Pod::Simple>.


=head1 SEE ALSO

L<Pod::Simple::XMLOutStream> is rather like this class.
Pod::Simple::XMLOutStream's output is space-padded in a way
that's better for sending to an XML processor (that is, it has
no ignorable whitespace). But
Pod::Simple::DumpAsXML's output is much more human-readable, being
(more-or-less) one token per line, with line-wrapping.

L<Pod::Simple::DumpAsText> is rather like this class,
except that it doesn't dump with XML syntax.  Try them and see
which one you like best!

L<Pod::Simple>, L<Pod::Simple::DumpAsXML>

The older libraries L<Pod::PXML>, L<Pod::XML>, L<Pod::SAX>

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

Copyright (c) 2002 Sean M. Burke.

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
