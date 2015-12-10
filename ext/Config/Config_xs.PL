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
    # TODO from ext/Config to be able to put it onto CPAN
    if (! -d 'ext/Config' and -f 'Config_xs.PL') {
        chdir '../..';
    }
    require 'regen/regen_lib.pl';
    my $ptrsize = length(pack('P',""));
    my $ivsize =  length(pack('j',0));
    die "unknown pointer size" if $ptrsize != 4 && $ptrsize != 8; #POSIX.pm not available
    eval 'sub SPTR_MIN () { '.($ptrsize == 8 ? '-9223372036854775808' : '-2147483648').' } '.
    'sub SPTR_MAX () { '.($ptrsize == 8 ? '0x7FFFFFFFFFFFFFFF' : '0x7FFFFFFF').' } '.
    'sub IV_MIN () { '.($ivsize == 8 ? '-9223372036854775808' : '-2147483648').' } '.
    'sub IV_MAX () { '.($ivsize == 8 ? '0x7FFFFFFFFFFFFFFF' : '0x7FFFFFFF').' } ';
}
use strict ;
use Config ;

###########################################################################

my $force = @ARGV ? $ARGV[0] eq '--force' : 0;
shift if $force;
my $no_gperf = @ARGV ? $ARGV[0] eq '--no-gperf' : 0;
shift if $no_gperf;
my $heavy = 'lib/Config_heavy.pl';
my $git   = 'lib/Config_git.pl';
my $xsin  = 'ext/Config/Config_xs.in';   # the key-only gperf template with empty values
my $xsout = 'ext/Config/Config_xs.out';  # gperf expanded with empty values
my $xstarg= 'ext/Config/Config.xs';      # patched with our values

my ($in, %h, $gperf_ok);

# collect all the values.
# and check if any keys had changed. need to update the gperf then.
if (! -e $heavy) { # help the Makefile deps to produce Config_heavy.pl
    system("$^X -Ilib configpm");
}
open $in, "<", $heavy or die "Error reading '$heavy': $!";
while (<$in>) {
    last if $_ eq "\$_ = <<'!END!';\n";
}
while (<$in>) { # as in config.sh
    chomp;
    last if $_ eq '!END!';
    next if /^perl_(version|subversion|revision)=/;
    my ($k,$v) = split(/=/,$_,2);
    $v = substr($v, 1, length($v)-2);#strip start/end quotes, ' or "
    #$v =~ s/\\/\\\\/g;
    $h{$k} = $v;
} 
while (<$in>) {
    last if $_ eq "our \$Config_SH_expanded = \"\\n\$_\" . << 'EOVIRTUAL';\n";
}
while (<$in>) {
    chomp;
    last if $_ eq 'EOVIRTUAL';
    my ($k,$v) = split(/=/,$_,2);
    $v = substr($v, 1, length($v)-2);#strip start/end quotes, ' or "
    #$v =~ s/\\/\\\\/g;
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
    $v = substr($v, 1, length($v)-2);#strip start/end quotes, ' or "
    $h{$k} = $v;
}

# postprocess the values a bit:
# reserve up to 20 config_args
for (0..20) {
    my $k = "config_arg".$_;
    $h{$k} = '' unless exists $h{$k};
}
for my $k (qw(libdb_needs_pthread malloc_cflags
              git_ancestor git_remote_branch git_unpushed)) {
    $h{$k} = '' unless exists $h{$k};
}

# Test if gperf works. if not patch xsout instead.
unless ($no_gperf) {
    local $!;
    $gperf_ok = !(system("gperf --output-file=${xsout}_tmp $xsin") >> 8);
    if ($gperf_ok and -z $xsout."_tmp") {
        $gperf_ok = 0;
    }
    unlink $xsout."_tmp";
    print STDERR "gperf ",$gperf_ok ? "works ok\n" : "does not work\n";
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
    if ($v =~ /^-?\d+$/ && $v >= IV_MIN && $v <= IV_MAX) {
        return 'T_INT';
    } else {
        return 'T_STR';
    }
}

#code in Config_heavy.pl to compute byteorder is customized/interpolated
#for each build permutation of perl by configpm, the byteorder in the
#Config_heavy.pl database is ignored, just use Config_heavy.pl to get byteorder
#instead of copying the complicated code in configpm to here
$h{byteorder} = $Config{byteorder};

foreach my $k (sort { $a cmp $b } keys %h) {
    my $v = $h{$k};
    my $type = 'T_STR';
    if ($v eq 'define') {
        $type = 'T_BOO';
    } elsif ($v eq 'undef') {
        $type = 'T_BOO';
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
        # $v =~ s/\\ / /g;
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
        my $type = t_type($v);
        my ($qv, $l);
        if ($type eq 'T_STR') {
          if ($v eq 'define') {
            $l  = 0;
            $qv = 'VDEFINE'
          } elsif ($v eq 'undef') {
            $l  = 0;
            $qv = 'VUNDEF'
          } elsif ($v eq '') {
            $l  = 0;
            $qv = 'VEMPTY'
          } else { # a regular C string
            die "the value of Config key $k is over permitted length"
              unless length($v) <= 1<<16;
            $qv = $v;
            $qv =~ s/(\\[^nrftacx"' ])/\\$1/g; # windows paths: \\ => \\\\
            $qv =~ s/(\\[nrftacx ])/\\$1/g;  # \n => \\n, allowed escape chars
            $qv = '"'.$qv.'"';
            $l = $v =~ m/["'\\]/ ?
            # don't calculate C-style length [cperl #61], let C do it for us
            # and don't count the ending \0
              'sizeof (' . $qv . ')-1'
              : length($v)+0;
          }
        } else { # $type eq 'T_INT'
          if ($v >= SPTR_MIN && $v <= SPTR_MAX) { #can fit in a ptr
            $l = 0;
            $qv = '(char *)'.$v;
          } else {#str in C, IV in perl, will be atoi-ed, 64b IV on 32b perl
            $l = length($v);
            $qv = '"'.$v.'"';
          }
        }
        #type in gperf-less build might be different from type in canned
        #Config_xs.in due to platform differences, so dont use existing type
        #from Config_xs.in and always use recomputed one
        my $new = $type.', '. $l . ', ' . $qv ;
        s/T_\w+,	0,"\@\@$k\@\@"/$new/; # we have one line per key only
        chomp;
        print $xs $_, " /* $k */\n";
    } else {
        print $xs $_;
    }
}
close $in;
close $xs;
rename $xsout."_tmp", $xsout;

sub post_process_gperf {
  my $in = shift;
  my $tmp = $in.".tmp";
  open my $OUT, '>', $tmp or die "Can't write '$tmp': $!";
  binmode $OUT;
  local $/ = "\n\n";
  print $OUT <<'EOT';
/* ex: set ro ft=c: -*- buffer-read-only: t; mode: c; c-basic-offset: 4; -*-
  !!!!!!!   DO NOT EDIT THIS FILE   !!!!!!!
  This file is built by ext/Config/Config_xs.PL and ext/Config/Config_xs.in. */
EOT
  my $lnr = 0;
  open my $IN, '<', $in or die "Can't read '$in': $!";

  while (<$IN>) {
    # overlong line, and don't bother bug-gnu-gperf\@gnu.org with crazy encodings
    # also c_indent.t
    # XXX add EBCDIC support, bypassing gperf (i.e. pperf)
    s/^#?error "gperf generated tables don't work with this execution character set. Please report a bug to <bug-gnu-gperf\@gnu.org>."/#  error "gperf generated tables don't work with this non ISO-646 based character set."/m;

    # C++ requires full struct initializers
    s/{-1},/{XCNAME_MAX, 1, 0, NULL},/g;

    # skip inline
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

    # There should be at least one space between a C keyword and any subsequent
    # open parenthesis
    s/sizeof\(/sizeof (/g;

    # fixup U16
    s/\(int\)\(long\)\&/(U16)(long)&/g;
    s/\Qregister int o = wordlist[key].name\E/register U16 o = wordlist[key].name/;
    s/\Qif (o >= 0)\E\n/if (o != XCNAME_MAX)\n/;

    # don't delete line numbers, pointing to Config_xs.in
    # s/^#line \d+ .+$//gm;
    # but insert a #line after the wordlist in Config_lookup
    $lnr += tr/\n/\n/;
    if (/if \(len <= MAX_WORD_LENGTH/) {
      print $OUT "#line $lnr \"Config.xs\"\n";
    }

    print $OUT $_;
  }
  close $IN;
  close $OUT;
  rename $tmp, $in;
}
