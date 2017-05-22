#!/usr/bin/perl
# These two should go upon release to make the script Perl 5.005 compatible
use strict;
use warnings;

=head1 NAME

have_ffi.pl - convert ffitarget enum to defines

=head1 SYNOPSIS

  miniperl have_ffi.pl

  perl have_ffi.pl

=head1 DESCRIPTION

This program parses the platform-specific ffitarget.h for the valid ffi_abi
enums and creates HAVE_FFI_$abi defines for each.
Writes to F<config.h>.

=head1 AUTHOR

Reini Urban

=head1 COPYRIGHT

Same terms as Perl itself.

=cut

use Config;
our $opt_v = scalar grep $_ eq '-v', @ARGV;
exit unless $Config{useffi};

my ($inc, %abi);
for (reverse(split ' ', $Config{incpth})) {
  if (/libffi/) {
    if (-e "$_/ffitarget.h") {
      $inc = $_; last;
    }
  }
  if (-e "$_/ffitarget.h") {
    $inc = $_; last;
  }
}
die "libffi incdir not found" unless $inc;
#my $cmd = `grep "^  FFI_" $inc/ffitarget.h`;
#for (split /\n/, $cmd) {
#  if (/^\s+FFI_(FIRST|LAST|DEFAULT)_ABI/) {
#    ;
#  }
#  elsif (/^\s+FFI_(\w+)[, ]/) {
#    my $abi = $1;
#    $abi{$abi}++;
#  }
#}
open my $f,'<',"$inc/ffitarget.h";
my ($def, $in_enum);
while (<$f>) {
  if (!$in_enum) {
    $in_enum++ if /^typedef enum ffi_abi/;
    next;
  }
  $def++ if /^#if/;
  if (/^\s+FFI_(FIRST|LAST|DEFAULT)_ABI/) {
    ;
  }
  elsif (/^\s+FFI_(\w+)[, ]/) {
    $abi{$1}++;
  }
  last if /^} ffi_abi;/
}
close $f;
unless (%abi) { # easiest case 
  write_file('have_ffi.h', "/* only default ffi_abi */");
  exit;
}

if ($def) { # need to probe all values
  for my $s (sort keys %abi) {
    probe_ffi($s);
  }
}
my $splice;
for my $s (sort keys %abi) {
  $splice .= "#define HAVE_FFI_$s\n";
}

my $file = 'config.h';
my $content = read_file($file);
$content =~ s{(	D_LIBFFI        /\*\*/\n)}{$1$splice}m;

print "Updating $file\n"
  unless defined $ENV{MAKEFLAGS} and $ENV{MAKEFLAGS} =~ /\b(s|silent|quiet)\b/;

write_file($file,$content);
write_file('have_ffi.h',$splice);

sub probe_ffi {
  my $s = shift;
  my $p = <<EOF;
#include <ffi.h>
int main() {
   ffi_abi abi = FFI_$s;
}
EOF
  open my $f, '>', '_tmp.c';
  print $f $p;
  close $f;
  my $stderr = $opt_v ? "" : $^O eq 'MSWin32' ? '>NUL' : '2>/dev/null';
  my $err = system("$Config{cc} $Config{ccflags} -c _tmp.c $stderr");
  unlink '_tmp.c', '_tmp.o', '_tmp.obj';
  if ($err > 0) {
    delete $abi{$s};
  }
  print "$s $err\n";
}

sub read_file {
    my $file = shift;
    return "" unless -e $file;
    open my $fh, '<', $file
        or die "Failed to open for read '$file':$!";
    return do { local $/; <$fh> };
}

sub write_file {
    my ($file, $content) = @_;
    open my $fh, '>', $file
        or die "Failed to open for write '$file':$!";
    print $fh $content;
    close $fh;
}

