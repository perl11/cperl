#!/usr/bin/perl
#
# Regenerate (overwriting only if changed):
#
#    ext/warnings/warnings.in
#    warnings.h
#
# from information hardcoded into this script (the $tree hash), plus the
# template for warnings.in in the DATA section.
#
# When changing the number of warnings, t/op/caller.t should change to
# correspond with the value of $BYTES in lib/warnings.pm
#
# With an argument of 'tree', just dump the contents of $tree and exits.
# Also accepts the standard regen_lib -q and -v args.
#
# This script is normally invoked from regen.pl.

$VERSION = '2.00';

BEGIN {
    push @INC, 'lib', 'ext/warnings';
    require 'regen/regen_lib.pl';
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
                                    [ 5.017, DEFAULT_ON ],
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
                                    [ 5.019, DEFAULT_ON ],
                                'experimental::win32_perlio' =>
                                    [ 5.021, DEFAULT_ON ],
                                'experimental::refaliasing' =>
                                    [ 5.021, DEFAULT_ON ],
                                'experimental::re_strict' =>
                                    [ 5.021, DEFAULT_ON ],
                                'experimental::const_attr' =>
                                    [ 5.021, DEFAULT_ON ],
                                'experimental::bitwise' =>
                                    [ 5.021, DEFAULT_ON ],
                        }],

        'missing'       => [ 5.021, DEFAULT_OFF],
        'redundant'     => [ 5.021, DEFAULT_OFF],
        'locale'        => [ 5.021, DEFAULT_ON],

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
	    $ValueToName{ $index } = [ uc $name, $ver ] ;
	    $NameToValue{ uc $name } = $index ++ ;
        }
    }

    return $index ;
}

###########################################################################

sub walk
{
    my $tre = shift ;
    my @list = () ;
    my ($k, $v) ;

    foreach $k (sort keys %$tre) {
	$v = $tre->{$k};
	die "duplicate key $k\n" if defined $list{$k} ;
	die "Can't find key '$k'"
	    if ! defined $NameToValue{uc $k} ;
        push @{ $list{$k} }, $NameToValue{uc $k} ;
	die "Value associated with key '$k' is not an ARRAY reference"
	    if !ref $v || ref $v ne 'ARRAY' ;

	my ($ver, $rest) = @{ $v } ;
	if (ref $rest)
	  { push (@{ $list{$k} }, walk ($rest)) }
	elsif ($rest == DEFAULT_ON)
	  { push @def, $NameToValue{uc $k} }

	push @list, @{ $list{$k} } ;
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
	    $rv .= $prefix . "|\n" ;
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

my ($warn, $in) = map {
    open_new($_, '>', { by => 'ext/warnings_c.PL' });
} 'warnings.h', 'ext/warnings/warnings.in';

my ($index, $warn_size);

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

  die <<EOM if $index > 255 ;
Too many warnings categories -- max is 255
    rewrite packWARN* & unpackWARN* macros
EOM

  walk ($tree) ;

  $index *= 2 ;
  $warn_size = int($index / 8) + ($index % 8 != 0) ;

  my $k ;
  my $last_ver = 0;
  foreach $k (sort { $a <=> $b } keys %ValueToName) {
      my ($name, $version) = @{ $ValueToName{$k} };
      print $warn "\n/* Warnings Categories added in Perl $version */\n\n"
          if $last_ver != $version ;
      $name =~ y/:/_/;
      print $warn tab(6, "#define WARN_$name"), " $k\n" ;
      $last_ver = $version ;
  }
  print $warn "\n" ;

  print $warn tab(6, '#define WARNsize'),	" $warn_size\n" ;
  print $warn tab(6, '#define WARN_ALLstring'), ' "', ('\125' x $warn_size) , "\"\n" ;
  print $warn tab(6, '#define WARN_NONEstring'), ' "', ('\0' x $warn_size) , "\"\n" ;

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
	   ( ! specialWARN(PL_curcop->cop_warnings) &&			\
	    ( isWARNf_on(PL_curcop->cop_warnings, WARN_ALL) || 		\
	      isWARNf_on(PL_curcop->cop_warnings, unpackWARN1(x)) ||	\
	      isWARNf_on(PL_curcop->cop_warnings, unpackWARN2(x)) ||	\
	      isWARNf_on(PL_curcop->cop_warnings, unpackWARN3(x)) ||	\
	      isWARNf_on(PL_curcop->cop_warnings, unpackWARN4(x))))

/* end of file warnings.h */
EOM

  read_only_bottom_close_and_rename($warn);
}

while (<DATA>) {
    last if /^KEYWORDS$/ ;
    print $in $_ ;
}

my $last_ver = 0;
#print $in "our %Offsets = (" ;
foreach my $k (sort { $a <=> $b } keys %ValueToName) {
    my ($name, $version) = @{ $ValueToName{$k} };
    $name = lc $name;
    my $offset = $k * 2 ;
    if ( $last_ver != $version ) {
        print $in "\n";
        print $in "/* added in Perl $version */";
        print $in "\n";
    }
    my $v = $list{$k};
    my @list = sort { $a <=> $b } @$v;
    my $bits     = mkHex($warn_size, map $_ * 2 , @list);
    my $deadbits = mkHex($warn_size, map $_ * 2 + 1 , @list);
    print "$name, $offset, \"$bits\", \"$deadbits\"\n";
    $last_ver = $version;
}

read_only_bottom_close_and_rename($in);

__END__
%{
/*
  Copyright (C) 2015, cPanel Inc

=head1 NAME

ext/warnings/warnings.in - gperf input for warnings.c

=head1 DESCRIPTION

Generated warnings hash

- gperf --output-file=ext/warnings/warnings.c ext/warnings/warnings.in

- manual cleanup for inline and c89 via F<ext/warnings/warnings_c.PL>

=over 4

=item C<struct Perl_warnings>

Generated hash table with name, offsets, bits and deadbits.

=back

=head2 Functions

=over 4

=item C<static unsigned int Perl_warnings_hash(register const char *str,
register unsigned int len)>

=item C<const struct Perl_warnings * Perl_warnings_lookup(register const
char *str, register unsigned int len)>

Generated lookup function.

=back

=cut

*/

#define PERL_NO_GET_CONTEXT
#define PERL_EXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define BYTES 67

const struct Perl_warnings *
Perl_warnings_lookup(register const char *str, register unsigned int len);
%}
%language=ANSI-C
%struct-type
%define hash-function-name   Perl_warnings_hash
%define lookup-function-name Perl_warnings_lookup
%readonly-tables
%null-strings
%pic

struct Perl_warnings {
       int name,
       const unsigned byte offset,
       const char[BYTES] bits,
       const char[BYTES] deadbits,
};
%%
KEYWORDS
%%

/*
 * vim: expandtab shiftwidth=4 cinoptions='\:2=2' :
 */
