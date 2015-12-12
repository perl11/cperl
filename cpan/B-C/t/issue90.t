#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=90
# Magic Tie::Named::Capture <=> *main::+ main::*- and Errno vs !
# op/leaky-magic.t: defer loading of Tie::Named::Capture and Errno to run-time
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 15;
use B::C ();
use Config;

my $i=0;
sub test3 {
  my $name = shift;
  my $script = shift;
  my $cmt = join('',@_);
  my ($todobc,$todocc) = ("","");
  $todobc = 'TODO ' if $name eq 'ccode90i_c';
  # passes BC threaded 5.10-16
  $todobc = '' if $name eq 'ccode90i_c'
    and $] >= 5.010 and $Config{'useithreads'};
  if ($name eq 'ccode90i_c' and ($B::C::VERSION lt '1.42_61')) {
    $todocc = 'TODO '; #3 CC %+ includes Tie::Hash::NamedCapture
  } elsif ($name eq 'ccode90i_ca' and $] >= 5.010) {
    $todocc = ''; #6 CC @+ fixed with 1.44
  #} elsif ($name eq 'ccode90i_er' and $] >= 5.010 and $Config{'useithreads'}) {
  #  $todocc = 'TODO '; #12 CC Errno loaded automagically. fixed with 1.48
  }
  plctestok($i*3+1, $name, $script, $todobc."BC ".$cmt);
  ctestok($i*3+2, "C,-O3", $name, $script, "C $cmt");
  ctestok($i*3+3, "CC", $name, $script, $todocc."CC $cmt");
  $i++;
}

SKIP: {
  skip "Tie::Named::Capture requires Perl v5.10", 3 if $] < 5.010;

  test3('ccode90i_c', <<'EOF', '%+ includes Tie::Hash::NamedCapture');
my $s = 'test string';
$s =~ s/(?<first>test) (?<second>string)/\2 \1/g;
print q(o) if $s eq 'string test';
'test string' =~ /(?<first>\w+) (?<second>\w+)/;
print q(k) if $+{first} eq 'test';
EOF
}

test3('ccode90i_ca', <<'EOF', '@+');
"abc" =~ /(.)./; print "ok" if "21" eq join"",@+;
EOF

test3('ccode90i_es', <<'EOF', '%! magic');
my %errs = %!; # t/op/magic.t Errno compiled in
print q(ok) if defined ${"!"}{ENOENT};
EOF

# %{"!"} detected at compile-time
test3('ccode90i_er', <<'EOF', 'Errno loaded automagically');
my %errs = %{"!"}; # t/op/magic.t Errno to be loaded at run-time
print q(ok) if defined ${"!"}{ENOENT};
EOF

test3('ccode90i_ep', <<'EOF', '%! pure IV');
print FH "foo"; print "ok" if $! == 9;
EOF
