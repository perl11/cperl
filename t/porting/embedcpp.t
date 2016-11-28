# Test if the headers can be used in a C++ project

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require "./test.pl";
}

use strict;
use Config;

my $src = <<'EOF';
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <iostream>
using namespace std;
int main() {
  cout << "ok 1 - from c++\n";
  return 0;
}
EOF

my $CC = $ENV{CXX};
if ($Config{d_cplusplus}) {
  $CC = $Config{cc};
  skip_all "$CC already a c++ compiler";
}

sub _which {
  my $which = `which $_[0]`;
  #diag "$_[0] => $which";
  if ($which) {
    chomp $which;
    return $which;
  }
  return undef;
}

if ($CC) {
  $CC = _which($CC);
}
unless ($CC) {
    for (qw(g++ c++ clang++)) {
        $CC = _which($_);
        last if $CC;
    }
}

unless ($CC) {
  if ($^O eq 'MSWin32') {
    my $inc = '-I..\lib\CORE -I..\win32\include -I..\win32';
    if ($Config{cc} =~ /^cl/) {
      $CC = "cl -TP $inc";
    }
    elsif ($Config{cc} =~ /^gcc/) {
      $CC = "g++ $inc";
    }
    # trust the extension detection to switch to C++ mode
    elsif ($Config{cc} =~ /^icc/) {
      $CC = "icc $inc";
    }
    else {
      $CC = "$Config{cc} $inc";
    }
  }
  elsif ($^O =~ /solaris|irix/) {
    $CC = _which('CC');
  }
}

unless ($CC) {
  skip_all "Unknown C++ compiler for $^O";
}
plan(1);

open my $f, '>', 'tmp.cc' or die "not ok 1 - writing to tmp.cc: $!";
print $f $src;
close $f;

my $cmd = "$CC -c -I.. -Wall tmp.cc";
my $result = `$cmd`;
if ($? >> 8) {
  diag $cmd;
  diag $result;
  if ($^O eq 'MSWin32') {
    ok(1, "TODO $cmd failed"); # [cperl #227]
  } else {
    ok(0, "$cmd failed");
  }
} else {
  ok(1, "$cmd compiled ok");
}
unlink 'tmp.cc';
