#!/usr/bin/perl
#
# Regenerate (overwriting only if changed):
#
#    lib/Config.pm
#    lib/Config_heavy.pl
#    lib/Config.pod
#    ext/Config/Config_xs.in
#    ext/Config/Config_xs.out
#    ext/Config/Config.xs
#
# from the contents of the static files
#
#    ext/Config/Config_xs.in (the gperf template)
#
# and from the contents of the Configure-generated file
#
#    lib/Config_heavy.pl
#    lib/Config_git.pl
#

$VERSION = '6.00';

BEGIN {
    push @INC, 'lib', 'ext/Config';
    # fix this for non-core: close_and_rename, read_only_bottom_close_and_rename
    # for now do this only from root.
    # TODO from ext/Config
    if (! -d 'ext/Config' and -f 'Config_xs.PL') {
        chdir '../..';
    }
    require 'regen/regen_lib.pl';
}
use strict ;

###########################################################################

my $force = @ARGV ? $ARGV[0] eq '--force' : 0;
my $heavy = 'lib/Config_heavy.pl';
my $git   = 'lib/Config_git.pl';
my $xsin  = 'ext/Config/Config_xs.in';   # the key-only gperf template with empty values
my $xsout = 'ext/Config/Config_xs.out';  # gperf expanded with empty values
my $xstarg= 'ext/Config/Config.xs';      # patched with our values

my ($in, %h, $gperf_ok);

# collect all the values.
# and check if any keys had changed. need to update the gperf then.
open $in, "<", $heavy or die "Error reading '$heavy': $!";
while (<$in>) {
    last if $_ eq "\$_ = <<'!END!';\n";
}
while (<$in>) { # as in config.sh
    chomp;
    last if $_ eq '!END!';
    next if /^perl_(version|subversion|revision)=/;
    my ($k,$v) = split(/=/,$_,2);
    $v =~ s/^'//;
    $v =~ s/'$//;
    $h{$k} = $v;
} 
while (<$in>) {
    last if $_ eq "our \$Config_SH_expanded = \"\\n\$_\" . << 'EOVIRTUAL';\n";
}
while (<$in>) {
    chomp;
    last if $_ eq 'EOVIRTUAL';
    my ($k,$v) = split(/=/,$_,2);
    $v =~ s/^'//;
    $v =~ s/'$//;
    $h{$k} = $v;
}
close $in;
open $in, "<", $git or die "Error reading '$git': $!";
while (<$in>) {
    last if $_ eq "\$Config::Git_Data=<<'ENDOFGIT';\n";
}
while (<$in>) {
    chomp;
    last if $_ eq 'ENDOFGIT';
    my ($k,$v) = split(/=/,$_,2);
    $v =~ s/^'//;
    $v =~ s/'$//;
    $h{$k} = $v;
}

# postprocess the values a bit:
# reserve up to 20 config_args
for (1..20) {
    my $k = "config_arg".$_;
    $h{$k} = '' unless exists $h{$k};
}
for my $k (qw(libdb_needs_pthread malloc_cflags
              git_ancestor git_remote_branch git_unpushed)) {
    $h{$k} = '' unless exists $h{$k};
}

# Test if gperf works. if not patch xsout instead.
my $gperf_ok;
{
    local $!;
    $gperf_ok = !(system("gperf --output-file=${xsout}_tmp $xsin") >> 8);
    unlink $xsout."_tmp";
}
my $xsfile = $gperf_ok ? $xsin : $xsout;
my $xs = open_new($xsfile, '>');
open $in, "<", $xsfile or die "Error reading '$xsfile': $!";

# expand only keys within %%
while (<$in>) {
    print $xs $_;
    last if /^%%$/;
}

sub t_type ($) {
    my $v = shift;
    if ($v eq 'define') {
        return 'T_BOO';
    } elsif ($v eq 'undef') {
        return 'T_BOO';
    } elsif ($v eq '') {
        return 'T_EMP';
    } elsif ($v =~ /^-?\d+$/) {
        return 'T_INT';
    } else {
        return 'T_STR';
    }
}

my $i = ord(8);
foreach my $c (7,6,5,4,3,2,1) { $i <<= 8; $i |= ord($c); }
$h{byteorder} = join('', unpack('aaaaaaaa', pack('L!', $i)));

foreach my $k (sort { $a cmp $b } keys %h) {
    my $v = $h{$k};
    my $type = 'T_STR';
    if ($v eq 'define') {
        $type = 'T_BOO';
        $v = '1';
    } elsif ($v eq 'undef') {
        $type = 'T_BOO';
        $v = '0';
    } elsif ($v eq '') {
        $type = $gperf_ok ? 'T_STR' : 'T_EMP';
        # deprecated, always empty
        # Author is set for Netware to 'Guruprasad'
        if ($k =~ /^(Author|Date|Header|Id
		|Locker|Log|RCSfile|Revision
		|Source|State|submit|d_voidtty)$/x) {
            $type = 'T_EMP';
        }
    } elsif ($v =~ /^-?\d+$/) {
        $type = $k eq 'inc_version_list_init' ? 'T_STR' : 'T_INT';
    } else {
        $v =~ s/"/\\"/g;
        # $v =~ s/\\!/!/;
        $v =~ s/\\ / /g;
    }
    $h{$k} = $v;
    $v = "@@".$k."@@";
    my $tabs = "\t" x (3-((2+length($k))/8));
    printf $xs "%s,\t%s%s,\t0,\"%s\"\n", $k, $tabs, $type, $v;
}
print $xs "%%\n";

while (<$in>) {
    last if /^%%$/;
}
# and the rest after the keys
while (<$in>) {
    print $xs $_;
}
close $in;
$xs->flush if $xs->can('flush');

if ($gperf_ok and
    (close_and_rename($xs) or $force or -M $xsin < -M $xsout or !(-f $xsout)))
{
    print STDERR "gperf $xsout\n";
    system("gperf --output-file=$xsout $xsin");
    post_process_gperf($xsout);
}

# and now patch the values into Config.xs
# TODO: check for keys mismatch, missing or too many.
open $in, '<', $xsout  or die "Error reading '$xsout': $!";
open $xs, '>', $xstarg or die "Error writing '$xstarg': $!";
while (<$in>) {
    if (/0,"@@(\w+)@@"/) {
        my $k = $1;
        my $v = $h{$k};
        my $l = length $v;
        my $qr = "0,\"@@".$k."@@\"";
        my $new = "$l,\"$v\"";
        s/$qr/$new/ if $l; # we have one line per key only
        # check correct type
        my $type = t_type($v);
        # T_INT is returned for bool, skip it.
        unless (/\t$type,/) {
            unless ($type eq 'T_INT' and /\tT_BOO,/) {
                s/\tT_...,/\t$type,/;
            }
        }
    }
    print $xs $_;
}
close $in;
close $xs;
rename $xsout."_tmp", $xsout;

sub post_process_gperf {
  my $in = shift;
  my $tmp = $in.".tmp";
  open my $OUT, '>', $tmp or die "Can't write '$tmp': $!";
  local $/ = "\n\n";
  print $OUT <<'EOT';
/* ex: set ro ft=c: -*- buffer-read-only: t; mode: c; c-basic-offset: 4; -*-
  !!!!!!!   DO NOT EDIT THIS FILE   !!!!!!!
  This file is built by ext/Config/Config_xs.PL and ext/Config/Config_xs.in. */
EOT
  open my $IN, '<', $in or die "Can't read '$in': $!";

  while (<$IN>) {
    # overlong line, and don't bother bug-gnu-gperf\@gnu.org with crazy encodings
    # also c_indent.t
    # XXX add EBCDIC support, bypassing gperf (i.e. pperf)
    s/^#?error "gperf generated tables don't work with this execution character set. Please report a bug to <bug-gnu-gperf\@gnu.org>."/#  error "gperf generated tables don't work with this non ISO-646 based character set."/m;

    # skip line directives. would be nice but they are wrong with gperf version 3.0.4
    # s/^#line .*?\n//gm;

    # C++ requires full struct initializers
    s/{-1},/{-1, -1, 0, NULL},/g;

    # XXX skip inline. Note that on windows this regex fails.
    s/\Q#ifdef __GNUC__
__inline
#if defined __GNUC_STDC_INLINE__ || defined __GNUC_GNU_INLINE__
__attribute__ ((__gnu_inline__))
#endif
#endif\E//;
    s/\Q#ifdef __GNUC__
__inline
#else
#ifdef __cplusplus
inline
#endif
#endif\E//;
    s/\Q#if (defined (__STDC_VERSION__) && __STDC_VERSION__ >= 199901L) || defined(__cplusplus) || defined(__GNUC_STDC_INLINE__)
inline
#elif defined(__GNUC__)
__inline
#endif
\E//;

    # There should be at least one space between a C keyword and any subsequent open parenthesis
    s/sizeof\(/sizeof (/g;

    print $OUT $_;
  }
  close $IN;
  close $OUT;
  rename $tmp, $in;
}
