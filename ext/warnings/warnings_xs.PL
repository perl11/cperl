#!/usr/bin/perl
#
# Regenerate (overwriting only if changed):
#
#    warnings.h
#    ext/warnings/warnings_xs.in
#    ext/warnings/warnings.xs
#
# from information hardcoded into this script (the $tree hash), plus the
# gperf template for warnings_xs.in
#
# When changing the number of warnings, t/op/caller.t should change to
# correspond with the value of NUM_WARNINGS in warnings.h
#
# With an argument of 'tree', just dump the contents of $tree and exits.
# Also accepts the standard regen_lib -q and -v args.
#
# This script is normally invoked from make regen, regen.pl.

$VERSION = '2.01';

BEGIN {
    push @INC, '.', 'lib', 'ext/warnings';
    # fix this for non-core: close_and_rename, read_only_bottom_close_and_rename
    # for now do this only from root.
    # TODO from ext/warnings, and install warnings.h into CORE
    if (! -d 'ext/warnings' and -f 'warnings_xs.PL') {
        chdir '../..';
    }
    require './regen/regen_lib.pl';
}
use strict ;

sub DEFAULT_ON  () { 1 }
sub DEFAULT_OFF () { 2 }

my $tree = {
'all' => [ 5.008, {
        'io'            => [ 5.008, {
                                'pipe'          => [ 5.008, DEFAULT_OFF],
                                'unopened'      => [ 5.008, DEFAULT_OFF],
                                'closed'        => [ 5.008, DEFAULT_OFF],
                                'newline'       => [ 5.008, DEFAULT_OFF],
                                'exec'          => [ 5.008, DEFAULT_OFF],
                                'layer'         => [ 5.008, DEFAULT_OFF],
                                'syscalls'      => [ 5.019, DEFAULT_OFF],
                           }],
        'syntax'        => [ 5.008, {
                                'ambiguous'     => [ 5.008, DEFAULT_OFF],
                                'semicolon'     => [ 5.008, DEFAULT_OFF],
                                'precedence'    => [ 5.008, DEFAULT_OFF],
                                'bareword'      => [ 5.008, DEFAULT_OFF],
                                'reserved'      => [ 5.008, DEFAULT_OFF],
                                'digit'         => [ 5.008, DEFAULT_OFF],
                                'parenthesis'   => [ 5.008, DEFAULT_OFF],
                                'printf'        => [ 5.008, DEFAULT_OFF],
                                'prototype'     => [ 5.008, DEFAULT_OFF],
                                'qw'            => [ 5.008, DEFAULT_OFF],
                                'illegalproto'  => [ 5.011, DEFAULT_OFF],
                           }],
        'severe'        => [ 5.008, {
                                'inplace'       => [ 5.008, DEFAULT_ON],
                                'internal'      => [ 5.008, DEFAULT_OFF],
                                'debugging'     => [ 5.008, DEFAULT_ON],
                                'malloc'        => [ 5.008, DEFAULT_ON],
                           }],
        'deprecated'    => [ 5.008, DEFAULT_ON],
        'void'          => [ 5.008, DEFAULT_OFF],
        'recursion'     => [ 5.008, DEFAULT_OFF],
        'redefine'      => [ 5.008, DEFAULT_OFF],
        'numeric'       => [ 5.008, DEFAULT_OFF],
        'uninitialized' => [ 5.008, DEFAULT_OFF],
        'once'          => [ 5.008, DEFAULT_OFF],
        'misc'          => [ 5.008, DEFAULT_OFF],
        'regexp'        => [ 5.008, DEFAULT_OFF],
        'glob'          => [ 5.008, DEFAULT_ON],
        'untie'         => [ 5.008, DEFAULT_OFF],
        'substr'        => [ 5.008, DEFAULT_OFF],
        'taint'         => [ 5.008, DEFAULT_OFF],
        'signal'        => [ 5.008, DEFAULT_OFF],
        'closure'       => [ 5.008, DEFAULT_OFF],
        'overflow'      => [ 5.008, DEFAULT_OFF],
        'portable'      => [ 5.008, DEFAULT_OFF],
        'utf8'          => [ 5.008, {
                                'surrogate' => [ 5.013, DEFAULT_OFF],
                                'nonchar' => [ 5.013, DEFAULT_OFF],
                                'non_unicode' => [ 5.013, DEFAULT_OFF],
                        }],
        'exiting'       => [ 5.008, DEFAULT_OFF],
        'pack'          => [ 5.008, DEFAULT_OFF],
        'unpack'        => [ 5.008, DEFAULT_OFF],
        'threads'       => [ 5.008, DEFAULT_OFF],
        'imprecision'   => [ 5.011, DEFAULT_OFF],
        'experimental'  => [ 5.017, {
                                'experimental::lexical_subs' =>
                                    [ 5.017, DEFAULT_OFF ],
                                'experimental::regex_sets' =>
                                    [ 5.017, DEFAULT_ON ],
                                'experimental::lexical_topic' =>
                                    [ 5.017, DEFAULT_ON ],
                                'experimental::smartmatch' =>
                                    [ 5.017, DEFAULT_ON ],
                                'experimental::postderef' =>
                                    [ 5.019, DEFAULT_ON ],
                                'experimental::autoderef' =>
                                    [ 5.019, DEFAULT_ON ],
                                'experimental::signatures' =>
                                    [ 5.019, DEFAULT_OFF ],
                                'experimental::win32_perlio' =>
                                    [ 5.021, DEFAULT_ON ],
                                'experimental::refaliasing' =>
                                    [ 5.021, DEFAULT_ON ],
                                'experimental::re_strict' =>
                                    [ 5.021, DEFAULT_ON ],
                                'experimental::const_attr' =>
                                    [ 5.021, DEFAULT_OFF ],
                                'experimental::bitwise' =>
                                    [ 5.021, DEFAULT_ON ],
                                'experimental::declared_refs' =>
                                    [ 5.025, DEFAULT_ON ],
                                'experimental::script_run' =>
                                    [ 5.027, DEFAULT_ON ],
                                'experimental::alpha_assertions' =>
                                    [ 5.027, DEFAULT_ON ],
                                'experimental::private_use' =>
                                    [ 5.029, DEFAULT_ON ],
                                'experimental::uniprop_wildcards' =>
                                    [ 5.029, DEFAULT_ON ],
                                'experimental::vlb' =>
                                    [ 5.029, DEFAULT_ON ],
                        }],

        'missing'       => [ 5.021, DEFAULT_OFF],
        'redundant'     => [ 5.021, DEFAULT_OFF],
        'locale'        => [ 5.021, DEFAULT_ON],

        'types'         => [ 5.024, DEFAULT_OFF],
        'security'      => [ 5.025, DEFAULT_ON],
        'shadow'        => [ 5.027, DEFAULT_OFF],
        'ffi'           => [ 5.029, DEFAULT_OFF],

         #'default'     => [ 5.008, DEFAULT_ON ],
}]};

my @def ;
my %list ;
my %Value ;
my %ValueToName ;
my %NameToValue ;
my %v_list = () ;

sub valueWalk
{
    my $tre = shift ;
    my @list = () ;
    my ($k, $v) ;

    foreach $k (sort keys %$tre) {
	$v = $tre->{$k};
	die "duplicate key $k\n" if defined $list{$k} ;
	die "Value associated with key '$k' is not an ARRAY reference"
	    if !ref $v || ref $v ne 'ARRAY' ;

	my ($ver, $rest) = @{ $v } ;
	push @{ $v_list{$ver} }, $k;

	if (ref $rest)
	  { valueWalk ($rest) }

    }

}

sub orderValues
{
    my $index = 0;
    foreach my $ver ( sort { $a <=> $b } keys %v_list ) {
        foreach my $name (@{ $v_list{$ver} } ) {
	    $ValueToName{ $index } = [ $name, $ver ] ;
	    $NameToValue{ uc $name } = $index ++ ;
        }
    }

    return $index ;
}

###########################################################################

sub walk
{
    my $tre = shift;
    my @list = ();
    my ($k, $v);

    foreach $k (sort keys %$tre) {
	$v = $tre->{$k};
	die "duplicate key $k\n" if defined $list{$k};
	die "Can't find key '$k'"
	    if ! defined $NameToValue{uc $k};
        push @{ $list{$k} }, $NameToValue{uc $k};
	die "Value associated with key '$k' is not an ARRAY reference"
	    if !ref $v || ref $v ne 'ARRAY';

	my ($ver, $rest) = @{ $v };
	if (ref $rest)
	  { push (@{ $list{$k} }, walk ($rest)) }
	elsif ($rest == DEFAULT_ON)
	  { push @def, $NameToValue{uc $k} }

	push @list, @{ $list{$k} };
    }

   return @list ;
}

###########################################################################

sub mkRange
{
    my @a = @_ ;
    my @out = @a ;

    for my $i (1 .. @a - 1) {
      	$out[$i] = ".."
          if $a[$i] == $a[$i - 1] + 1
             && ($i >= @a  - 1 || $a[$i] + 1 == $a[$i + 1] );
    }
    $out[-1] = $a[-1] if $out[-1] eq "..";

    my $out = join(",",@out);

    $out =~ s/,(\.\.,)+/../g ;
    return $out;
}

###########################################################################
sub warningsTree
{
    my $tre = shift ;
    my $prefix = shift ;
    my ($k, $v) ;

    my $max = (sort {$a <=> $b} map { length $_ } keys %$tre)[-1] ;
    my @keys = sort keys %$tre ;

    my $rv = '';

    while ($k = shift @keys) {
	$v = $tre->{$k};
	die "Value associated with key '$k' is not an ARRAY reference"
	    if !ref $v || ref $v ne 'ARRAY' ;

        my $offset ;
	if ($tre ne $tree) {
	    # $rv .= $prefix . "|\n" ;
	    $rv .= $prefix . "+- $k" ;
	    $offset = ' ' x ($max + 4) ;
	}
	else {
	    $rv .= $prefix . "$k" ;
	    $offset = ' ' x ($max + 1) ;
	}

	my ($ver, $rest) = @{ $v } ;
	if (ref $rest)
	{
	    my $bar = @keys ? "|" : " ";
	    $rv .= " -" . "-" x ($max - length $k ) . "+\n" ;
	    $rv .= warningsTree ($rest, $prefix . $bar . $offset )
	}
	else
	  { $rv .= "\n" }
    }

    return $rv;
}

###########################################################################

sub mkHexOct
{
    my ($f, $max, @a) = @_ ;
    my $mask = "\x00" x $max ;
    my $string = "" ;

    foreach (@a) {
	vec($mask, $_, 1) = 1 ;
    }

    foreach (unpack("C*", $mask)) {
        if ($f eq 'x') {
            $string .= '\x' . sprintf("%2.2x", $_)
        }
        else {
            $string .= '\\' . sprintf("%o", $_)
        }
    }
    return $string ;
}

sub mkHex
{
    my($max, @a) = @_;
    return mkHexOct("x", $max, @a);
}

sub mkOct
{
    my($max, @a) = @_;
    return mkHexOct("o", $max, @a);
}

###########################################################################

if (@ARGV && $ARGV[0] eq "tree")
{
    print warningsTree($tree, "    ") ;
    exit ;
}

my $force = @ARGV ? $ARGV[0] eq '--force' : 0;
my $warn = open_new('warnings.h', '>', { by => 'ext/warnings/warnings_xs.PL' });
my $xsin = 'ext/warnings/warnings_xs.in';
my $xsout = 'ext/warnings/warnings.xs';
my $xs = open_new($xsin, '>');
my ($index, $warn_size, $max_bytes);

{
  # generate warnings.h

  print $warn <<'EOM';

#define Off(x)			((x) / 8)
#define Bit(x)			(1 << ((x) % 8))
#define IsSet(a, x)		((a)[Off(x)] & Bit(x))


#define G_WARN_OFF		0 	/* $^W == 0 */
#define G_WARN_ON		1	/* -w flag and $^W != 0 */
#define G_WARN_ALL_ON		2	/* -W flag */
#define G_WARN_ALL_OFF		4	/* -X flag */
#define G_WARN_ONCE		8	/* set if 'once' ever enabled */
#define G_WARN_ALL_MASK		(G_WARN_ALL_ON|G_WARN_ALL_OFF)

#define pWARN_STD		NULL
#define pWARN_ALL		(((STRLEN*)0)+1)    /* use warnings 'all' */
#define pWARN_NONE		(((STRLEN*)0)+2)    /* no  warnings 'all' */

#define specialWARN(x)		((x) == pWARN_STD || (x) == pWARN_ALL ||	\
				 (x) == pWARN_NONE)

/* if PL_warnhook is set to this value, then warnings die */
#define PERL_WARNHOOK_FATAL	(&PL_sv_placeholder)
EOM

  my $offset = 0 ;

  valueWalk ($tree) ;
  $index = orderValues();
  my $num_warnings = $index;

  $max_bytes = 32; # 256 = 32 * 8
  die <<EOM if $index > 255 ;
Too many warnings categories -- max is 255
    rewrite packWARN* & unpackWARN* macros
EOM

  walk ($tree) ;

  $index *= 2;
  $warn_size = int($index / 8) + ($index % 8 != 0);
  my $k ;
  my $last_ver = 0;
  foreach $k (sort { $a <=> $b } keys %ValueToName) {
      my ($name, $version) = @{ $ValueToName{$k} };
      if ($last_ver != $version) {
          print $warn "\n/* Warnings Categories added in Perl $version */\n\n";
      }
      $name = uc $name;
      $name =~ y/:/_/;
      print $warn tab(6, "#define WARN_$name"), " $k\n";
      $last_ver = $version;
  }
  print $warn "\n\n";

  print $warn tab(6, "#define NUM_WARNINGS"),   " $num_warnings\n";
  print $warn tab(6, '#define WARN_LAST_BIT'),	" $index\n";
  print $warn tab(6, '#define WARNsize'),	" $warn_size\n";
  print $warn tab(6, '#define WARN_MAX_BYTES'),	" $max_bytes\n";
  print $warn tab(6, '#define WARN_ALLstring'), ' "', '\125' x $warn_size, "\"\n";
  print $warn tab(6, '#define WARN_DEADALLstring'), ' "', '\252' x $warn_size, "\"\n";
  print $warn tab(6, '#define WARN_NONEstring'), ' "', ('\0' x $max_bytes), "\"\n";
  print $warn tab(6, '/*'), ' [', mkRange(@def), "] */\n";
  print $warn tab(6, '#define WARN_DEFAULTstring'), ' "',  mkOct($max_bytes, map $_ * 2, @def) , "\"\n" ;
  #print $warn "\n/* constants for warnings.in */\n";
  #foreach $k (sort { $a <=> $b } keys %ValueToName) {
  #    my ($name, $version) = @{ $ValueToName{$k} };
  #    next if $name eq 'all';
  #    $name =~ y/:/_/;
  #    print $warn tab(6, "#define WARN_${name}string"), " ", mkOct($max_bytes, map $_ * 2, @def), "\n";
  #}
  print $warn "\n\n";

  print $warn <<'EOM';

#define isLEXWARN_on 	(PL_curcop->cop_warnings != pWARN_STD)
#define isLEXWARN_off	(PL_curcop->cop_warnings == pWARN_STD)
#define isWARN_ONCE	(PL_dowarn & (G_WARN_ON|G_WARN_ONCE))
#define isWARN_on(c,x)	(IsSet((U8 *)(c + 1), 2*(x)))
#define isWARNf_on(c,x)	(IsSet((U8 *)(c + 1), 2*(x)+1))

#define DUP_WARNINGS(p)		\
    (specialWARN(p) ? (STRLEN*)(p)	\
    : (STRLEN*)CopyD(p, PerlMemShared_malloc(sizeof(*p)+*p), sizeof(*p)+*p, \
		     			     char))

/*

=head1 Warning and Dieing

=for apidoc Am|bool|ckWARN|U32 w

Returns a boolean as to whether or not warnings are enabled for the warning
category C<w>.  If the category is by default enabled even if not within the
scope of S<C<use warnings>>, instead use the L</ckWARN_d> macro.

=for apidoc Am|bool|ckWARN_d|U32 w

Like C<L</ckWARN>>, but for use if and only if the warning category is by
default enabled even if not within the scope of S<C<use warnings>>.

=for apidoc Am|bool|ckWARN2|U32 w1|U32 w2

Like C<L</ckWARN>>, but takes two warnings categories as input, and returns
TRUE if either is enabled.  If either category is by default enabled even if
not within the scope of S<C<use warnings>>, instead use the L</ckWARN2_d>
macro.  The categories must be completely independent, one may not be
subclassed from the other.

=for apidoc Am|bool|ckWARN2_d|U32 w1|U32 w2

Like C<L</ckWARN2>>, but for use if and only if either warning category is by
default enabled even if not within the scope of S<C<use warnings>>.

=for apidoc Am|bool|ckWARN3|U32 w1|U32 w2|U32 w3

Like C<L</ckWARN2>>, but takes three warnings categories as input, and returns
TRUE if any is enabled.  If any of the categories is by default enabled even
if not within the scope of S<C<use warnings>>, instead use the L</ckWARN3_d>
macro.  The categories must be completely independent, one may not be
subclassed from any other.

=for apidoc Am|bool|ckWARN3_d|U32 w1|U32 w2|U32 w3

Like C<L</ckWARN3>>, but for use if and only if any of the warning categories
is by default enabled even if not within the scope of S<C<use warnings>>.

=for apidoc Am|bool|ckWARN4|U32 w1|U32 w2|U32 w3|U32 w4

Like C<L</ckWARN3>>, but takes four warnings categories as input, and returns
TRUE if any is enabled.  If any of the categories is by default enabled even
if not within the scope of S<C<use warnings>>, instead use the L</ckWARN4_d>
macro.  The categories must be completely independent, one may not be
subclassed from any other.

=for apidoc Am|bool|ckWARN4_d|U32 w1|U32 w2|U32 w3|U32 w4

Like C<L</ckWARN4>>, but for use if and only if any of the warning categories
is by default enabled even if not within the scope of S<C<use warnings>>.

=cut

*/

#define ckWARN(w)		Perl_ckwarn(aTHX_ packWARN(w))

/* The w1, w2 ... should be independent warnings categories; one shouldn't be
 * a subcategory of any other */

#define ckWARN2(w1,w2)		Perl_ckwarn(aTHX_ packWARN2(w1,w2))
#define ckWARN3(w1,w2,w3)	Perl_ckwarn(aTHX_ packWARN3(w1,w2,w3))
#define ckWARN4(w1,w2,w3,w4)	Perl_ckwarn(aTHX_ packWARN4(w1,w2,w3,w4))

#define ckWARN_d(w)		Perl_ckwarn_d(aTHX_ packWARN(w))
#define ckWARN2_d(w1,w2)	Perl_ckwarn_d(aTHX_ packWARN2(w1,w2))
#define ckWARN3_d(w1,w2,w3)	Perl_ckwarn_d(aTHX_ packWARN3(w1,w2,w3))
#define ckWARN4_d(w1,w2,w3,w4)	Perl_ckwarn_d(aTHX_ packWARN4(w1,w2,w3,w4))

#define WARNshift		8

#define packWARN(a)		(a                                      )

/* The a, b, ... should be independent warnings categories; one shouldn't be
 * a subcategory of any other */

#define packWARN2(a,b)		((a) | ((b)<<8)                         )
#define packWARN3(a,b,c)	((a) | ((b)<<8) | ((c)<<16)             )
#define packWARN4(a,b,c,d)	((a) | ((b)<<8) | ((c)<<16) | ((d) <<24))

#define unpackWARN1(x)		((x)        & 0xFF)
#define unpackWARN2(x)		(((x) >>8)  & 0xFF)
#define unpackWARN3(x)		(((x) >>16) & 0xFF)
#define unpackWARN4(x)		(((x) >>24) & 0xFF)

#define ckDEAD(x)							\
	   ( PL_curcop && !specialWARN(PL_curcop->cop_warnings) &&	\
	    ( isWARNf_on(PL_curcop->cop_warnings, WARN_ALL) || 		\
	      isWARNf_on(PL_curcop->cop_warnings, unpackWARN1(x)) ||	\
	      isWARNf_on(PL_curcop->cop_warnings, unpackWARN2(x)) ||	\
	      isWARNf_on(PL_curcop->cop_warnings, unpackWARN3(x)) ||	\
	      isWARNf_on(PL_curcop->cop_warnings, unpackWARN4(x))))

/* end of file warnings.h */
EOM

  read_only_bottom_close_and_rename($warn);
}

my $in;
open $in, "<", $xsin or die "Error reading '$xsin': $!";

# expand only keys within %%
while (<$in>) {
    print $xs $_;
    last if /^%%$/;
}

foreach my $k (sort { $a <=> $b } keys %ValueToName) {
    my ($name, $version) = @{ $ValueToName{$k} };
    # Note: keeping the proper case
    my $offset = $k * 2;
    if ($name eq 'all') {
      print $xs "$name, WARN_ALLstring, WARN_DEADALLstring, 0, $warn_size\n";
    } else {
      my $v = $list{$name};
      my @list = sort { $a <=> $b } @$v;
      my $bits     = mkOct($warn_size, map $_ * 2 , @list);
      my $deadbits = mkOct($warn_size, map $_ * 2 + 1 , @list);
      print $xs "$name, \"$bits\", \"$deadbits\", $offset, $warn_size\n";
    }
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

if (close_and_rename($xs) or $force or -M $xsin < -M $xsout) {
    print STDERR "gperf $xsout\n";
    system("gperf --output-file=$xsout $xsin");
    post_process_gperf($xsout);
}

sub post_process_gperf {
  my $in = shift;
  my $tmp = $in.".tmp";
  open my $OUT, '>', $tmp or die "Can't write '$tmp': $!";
  local $/ = "\n\n";
  print $OUT <<'EOT';
/* ex: set ro ft=c: -*- buffer-read-only: t; mode: c; c-basic-offset: 4; -*-
  !!!!!!!   DO NOT EDIT THIS FILE   !!!!!!!
  This file is built by ext/warnings/warnings_xs.PL and ext/warnings/warnings_xs.in. */
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
    s/{-1},/{-1, NULL, NULL, 0, 0},/g;

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
