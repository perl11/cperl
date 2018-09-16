#!/usr/bin/perl
use strict;
use warnings;

=head1 NAME

have_ffi.pl - convert ffitarget.h enum ffi_abi to defines

=head1 SYNOPSIS

  miniperl have_ffi.pl

  perl have_ffi.pl -v

  perl ..\have_ffi.pl

=head1 DESCRIPTION

This program parses the platform-specific ffitarget.h for the valid ffi_abi
enums and probes for C<HAVE_FFI_$abi>.

Known ffi_targets:

    SYSV UNIX64 WIN64 STDCALL THISCALL FASTCALL MS_CDECL PASCAL REGISTER
    VFP O32 N32 N64 O32_SOFT_FLOAT N32_SOFT_FLOAT N64_SOFT_FLOAT
    AIX DARWIN
    COMPAT_SYSV COMPAT_GCC_SYSV COMPAT_LINUX64 COMPAT_LINUX
    COMPAT_LINUX_SOFT_FLOAT V9 V8

On x86 this is either 
C<SYSV STDCALL THISCALL FASTCALL MS_CDECL PASCAL REGISTER>
or C<UNIX64 WIN64>.

Writes to F<config.h>, F<config.sh> and F<have_ffi.h> (unused).

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
die "libffi incdir not found in $Config{incpth}" unless $inc;
#my $cmd = `grep "^  FFI_" $inc/ffitarget.h`;
#for (split /\n/, $cmd) {
#    if (/^\s+FFI_(FIRST|LAST|DEFAULT)_ABI/) {
#        ;
#    }
#    elsif (/^\s+FFI_(\w+)[, ]/) {
#        my $abi = $1;
#        $abi{$abi}++;
#    }
#}
open my $f,'<',"$inc/ffitarget.h" or die "$inc/ffitarget.h $!";
my ($def, $in_enum);
while (<$f>) {
    if (!$in_enum) {
        $in_enum++ if /^typedef enum ffi_abi/;
        next;
    }
    $def++ if /^\s*#\s*if/;
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
    print "Probing for HAVE_FFI_ targets...\n"
      unless defined $ENV{MAKEFLAGS} and $ENV{MAKEFLAGS} =~ /\b(s|silent|quiet)\b/;
    for my $s (sort keys %abi) {
        probe_ffi($s);
    }
}
else { # no if, can take all
    for my $s (sort keys %abi) {
        print "$s\n";
    }
}
my $splice = "/* valid libffi targets, available to :nativeconv() */\n";
my $sh = "ffi_target='";
for my $s (sort keys %abi) {
    $splice .= "#define HAVE_FFI_$s\n";
    $sh .= "$s";
}
$sh .= "'\n";

my $file = 'config.h';
my $content = read_file($file);
$content =~ s{(\tUSE_FFI\t+/\*\*/\n)}{$1$splice}m;

print "Updating $file\n"
  unless defined $ENV{MAKEFLAGS} and $ENV{MAKEFLAGS} =~ /\b(s|silent|quiet)\b/;
write_file($file,$content);

write_file('have_ffi.h',$splice);

$file = 'config.sh';
$file = '..\config.sh' if -d 'mini' and !-f $file;
if (-f $file) {
    print "Updating $file\n"
      unless defined $ENV{MAKEFLAGS} and $ENV{MAKEFLAGS} =~ /\b(s|silent|quiet)\b/;
    $content = read_file($file);
    $content =~ s{(useffi='define'\n)}{$1$sh}m;
    write_file($file,$content);
}

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

