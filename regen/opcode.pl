#!/usr/bin/perl -w
# 
# Regenerate (overwriting only if changed):
#
#    opcode.h     - initialized structs, see PERL_GLOBAL_STRUCT_INIT
#    opnames.h    - pure static data
#    pp_proto.h
#    lib/B/Op_private.pm
#
# from:
#  * information stored in regen/opcodes;
#  * information stored in regen/op_private (which is actually perl code);
#  * the values hardcoded into this script in @raw_alias.
#
# Accepts the standard regen_lib -q and -v args.
#
# This script is normally invoked from regen.pl.

use strict;

BEGIN {
    # Get function prototypes
    require './regen/regen_lib.pl';
}
use Config;

my $oc = open_new('opcode.h', '>',
		  {by => 'regen/opcode.pl', from => 'its data',
		   file => 'opcode.h', style => '*',
		   copyright => [1993 .. 2015]});

my $on = open_new('opnames.h', '>',
		  { by => 'regen/opcode.pl', from => 'its data', style => '*',
		    file => 'opnames.h', copyright => [1999 .. 2008] });

my $oprivpm = open_new('lib/B/Op_private.pm', '>',
		  { by => 'regen/opcode.pl',
                    from => "data in\nregen/op_private "
                           ."and pod embedded in regen/opcode.pl",
                    style => '#',
		    file => 'lib/B/Op_private.pm',
                    copyright => [2014 .. 2015] });

# Read 'opcodes' data.

my %seen;
my (@ops, %desc, %check, %ckname, %flags, %args, %opnum, %type);

open OPS, '<', 'regen/opcodes' or die $!;

while (<OPS>) {
    chop;
    next unless $_;
    next if /^#/;
    my ($key, @split) = split(/\s+/, $_);
    my ($desc, $check, $flags, $args, $type);
    my $i = 0;
  SPLIT:
    for (@split) {
        if (/^ck_/) { # collapse desc: find ck_
            $desc = join(" ", @split[0 .. $i-1]);
            $check = $_;
            $flags = $split[$i+1];
            my $j = $i+2;
            # collapse args, find type
            for (@split[$j .. $#split]) {
                if (/^"/) { # args are optional
                    $type = substr($_, 1, -1);
                    $args = join(" ", @split[$i+2 .. $j-1]);
                    last SPLIT;
                }
                $j++;
            }
            $args = join(" ", @split[$i+2 .. $#split]); # no type
            $type = '';
            last SPLIT;
        }
        $i++;
    }
    $args = '' unless defined $args;
    $type = '' unless defined $type;

    warn qq[Description "$desc" duplicates $seen{$desc}\n]
     if $seen{$desc} and $key !~ "concat|transr|(?:intro|clone)cv|lvref";
    die qq[Opcode "$key" duplicates $seen{$key}\n] if $seen{$key};
    die qq[Opcode "freed" is reserved for the slab allocator\n]
	if $key eq 'freed';
    $seen{$desc} = qq[description of opcode "$key"];
    $seen{$key} = qq[opcode "$key"];

    push(@ops, $key);
    $opnum{$key} = $#ops;
    $desc{$key} = $desc;
    $check{$key} = $check;
    $ckname{$check}++;
    $flags{$key} = $flags;
    $args{$key} = $args;
    $type{$key} = $type;
}

# Set up aliases, and alternative funcs

my (%alias, %alts);

# Format is "this function" => "does these op names"
my @raw_alias = (
		 Perl_do_kv => [qw( keys values )], # ouch
		 Perl_unimplemented_op => [qw(padany custom)],
		 # All the ops with a body of { return NORMAL; }
		 Perl_pp_null => [qw(scalar regcmaybe lineseq scope)],

		 Perl_pp_goto => ['dump'],
		 Perl_pp_require => ['dofile'],
		 Perl_pp_untie => ['dbmclose'],
		 Perl_pp_sysread => {read => '', recv => '#ifdef HAS_SOCKET'},
		 Perl_pp_sysseek => ['seek'],
		 Perl_pp_ioctl => ['fcntl'],
		 Perl_pp_ssockopt => {gsockopt => '#ifdef HAS_SOCKET'},
		 Perl_pp_getpeername => {getsockname => '#ifdef HAS_SOCKET'},
		 Perl_pp_stat => ['lstat'],
		 Perl_pp_ftrowned => [qw(fteowned ftzero ftsock ftchr ftblk
					 ftfile ftdir ftpipe ftsuid ftsgid
 					 ftsvtx)],
		 Perl_pp_fttext => ['ftbinary'],
		 Perl_pp_gmtime => ['localtime'],
		 Perl_pp_semget => [qw(shmget msgget)],
		 Perl_pp_semctl => [qw(shmctl msgctl)],
		 Perl_pp_ghostent => [qw(ghbyname ghbyaddr)],
		 Perl_pp_gnetent => [qw(gnbyname gnbyaddr)],
		 Perl_pp_gprotoent => [qw(gpbyname gpbynumber)],
		 Perl_pp_gservent => [qw(gsbyname gsbyport)],
		 Perl_pp_gpwent => [qw(gpwnam gpwuid)],
		 Perl_pp_ggrent => [qw(ggrnam ggrgid)],
		 Perl_pp_ftis => [qw(ftsize ftmtime ftatime ftctime)],
		 Perl_pp_chown => [qw(unlink chmod utime kill)],
		 Perl_pp_link => ['symlink'],
		 Perl_pp_ftrread => [qw(ftrwrite ftrexec fteread ftewrite
 					fteexec)],
		 Perl_pp_shmwrite => [qw(shmread msgsnd msgrcv semop)],
		 Perl_pp_syswrite => {send => '#ifdef HAS_SOCKET'},
		 Perl_pp_defined => [qw(dor dorassign)],
                 Perl_pp_and => ['andassign'],
		 Perl_pp_or => ['orassign'],
		 Perl_pp_ucfirst => ['lcfirst'],
		 Perl_pp_s_le => [qw(s_lt s_gt s_ge)],
		 Perl_pp_print => ['say'],
		 Perl_pp_index => ['rindex'],
		 Perl_pp_oct => ['hex'],
		 Perl_pp_shift => ['pop'],
		 Perl_pp_sin => [qw(cos exp log sqrt)],
		 Perl_pp_bit_or => ['bit_xor'],
		 Perl_pp_i_bit_or => ['i_bit_xor'],
		 Perl_pp_s_bit_or => ['s_bit_xor'],
		 Perl_pp_rv2av => ['rv2hv'],
		 Perl_pp_akeys => ['avalues'],
		 Perl_pp_trans => [qw(trans transr)],
		 Perl_pp_chop => [qw(chop chomp)],
		 Perl_pp_schop => [qw(schop schomp)],
		 Perl_pp_bind => {connect => '#ifdef HAS_SOCKET'},
		 Perl_pp_preinc => ['i_preinc'],
		 Perl_pp_predec => ['i_predec'],
		 Perl_pp_postinc => ['i_postinc'],
		 Perl_pp_postdec => ['i_postdec'],
		 Perl_pp_ehostent => [qw(enetent eprotoent eservent
					 spwent epwent sgrent egrent)],
		 Perl_pp_shostent => [qw(snetent sprotoent sservent)],
		 Perl_pp_aelemfast => ['aelemfast_lex'],
		 Perl_pp_grepstart => ['mapstart'],

		 Perl_pp_int_aelem  => ['num_aelem', 'str_aelem'],
		 Perl_pp_i_aelem    => ['n_aelem', 's_aelem'],
		 Perl_pp_aelem_u    => ['i_aelem_u', 'n_aelem_u', 's_aelem_u'],
		 Perl_pp_int_aelem_u => ['num_aelem_u', 'str_aelem_u'],
		 Perl_pp_const       => ['int_const', 'uint_const', 'str_const', 'num_const'],
		 Perl_pp_int_padsv   => ['uint_padsv', 'str_padsv', 'num_padsv'],
		 Perl_pp_int_sassign => ['uint_sassign', 'str_sassign', 'num_sassign'],

		 # 2 i_modulo mappings: 2nd is alt, needs 1st (explicit default) to not override the default
		 Perl_pp_i_modulo  => ['i_modulo'],
		 Perl_pp_i_modulo_glibc_bugfix => {
                     'i_modulo' =>
                         '#if defined(__GLIBC__) && IVSIZE == 8 '.
                         ' && ( __GLIBC__ < 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ < 8))' },
		 );
# see exceptions for those below:
#push @raw_alias, (
#		 Perl_pp_add         => ['u_add'],
#		 Perl_pp_subtract    => ['u_subtract'],
#		 Perl_pp_multiply    => ['u_multiply']
#  ) if $Config{ivsize} < 8;


# cperl changes: harmonized type prefices, for readable type promotion.
# not strictly required, but it makes more sense.
my @cperl_changes =
  (
   ncmp    => 'cmp',
   i_ncmp  => 'i_cmp',
   slt     => 's_lt',
   sgt     => 's_gt',
   sle     => 's_le',
   sge     => 's_ge',
   seq     => 's_eq',
   sne     => 's_ne',
   scmp    => 's_cmp',
   nbit_and  => 'i_bit_and',
   nbit_xor  => 'i_bit_xor',
   nbit_or   => 'i_bit_or',
   sbit_and  => 's_bit_and',
   sbit_xor  => 's_bit_xor',
   sbit_or   => 's_bit_or',
   ncomplement => 'i_complement',
   scomplement => 's_complement'
   );

while (my ($func, $names) = splice @raw_alias, 0, 2) {
    if (ref $names eq 'ARRAY') {
	foreach (@$names) {
            defined $alias{$_}
            ? $alts{$_} : $alias{$_} = [$func, ''];
	}
    } else {
	while (my ($opname, $cond) = each %$names) {
            defined $alias{$opname}
            ? $alts{$opname} : $alias{$opname} = [$func, $cond];
	}
    }
}

foreach my $sock_func (qw(socket bind listen accept shutdown
			  ssockopt getpeername)) {
    $alias{$sock_func} = ["Perl_pp_$sock_func", '#ifdef HAS_SOCKET'],
}
# u_ ops are aliased for 32bit IVSIZE==4 only. on IVSIZE==8 they use the native u_ ops
#foreach my $u_func (qw(add subtract multiply)) {
#    $alias{"u_".$u_func} = ["Perl_pp_$u_func", '#if IVSIZE<=4'],
#}

# =================================================================
#
# Functions for processing regen/op_private data.
#
# Put them in a separate package so that croak() does the right thing

package OP_PRIVATE;

use Carp;


# the vars holding the global state built up by all the calls to addbits()


# map OPpLVAL_INTRO => LVINTRO
my %LABELS;


# the numeric values of flags - what will get output as a #define
my %DEFINES;

# %BITFIELDS: the various bit field types. The key is the concatenation of
# all the field values that make up a bit field hash; the values are bit
# field hash refs.  This allows us to de-dup identical bit field defs
# across different ops, and thus make the output tables more compact (esp
# important for the C version)
my %BITFIELDS;

# %FLAGS: the main data structure. Indexed by op name, then bit index:
# single bit flag:
#   $FLAGS{rv2av}{2} = 'OPpSLICEWARNING';
# bit field (bits 5 and 6):
#   $FLAGS{rv2av}{5} = $FLAGS{rv2av}{6} = { .... };
my %FLAGS;


# do, with checking, $LABELS{$name} = $label

sub add_label {
    my ($name, $label) = @_;
    if (exists $LABELS{$name} and $LABELS{$name} ne $label) {
        croak "addbits(): label for flag '$name' redefined:\n"
        .  "  was '$LABELS{$name}', now '$label'";
    }
    $LABELS{$name} = $label;
}

#
# do, with checking, $DEFINES{$name} = $val

sub add_define {
    my ($name, $val) = @_;
    if (exists $DEFINES{$name} && $DEFINES{$name} != $val) {
        croak "addbits(): value for flag '$name' redefined:\n"
        .  "  was $DEFINES{$name}, now $val";
    }
    $DEFINES{$name} = $val;
}


# intended to be called from regen/op_private; see that file for details

sub ::addbits {
    my @args = @_;

    croak "too few arguments for addbits()" unless @args >= 3;
    my $op = shift @args;
    croak "invalid op name: '$op'" unless exists $opnum{$op};

    while (@args) {
        my $bits = shift @args;
        if ($bits =~ /^[0-7]$/) {
            # single bit
            croak "addbits(): too few arguments for single bit flag"
                unless @args >= 2;
            my $flag_name   = shift @args;
            my $flag_label  = shift @args;
            add_label($flag_name, $flag_label);
            croak "addbits(): bit $bits of $op already specified ($FLAGS{$op}{$bits})"
                if defined $FLAGS{$op}{$bits};
            $FLAGS{$op}{$bits} = $flag_name;
            add_define($flag_name, (1 << $bits));
        }
        elsif ($bits =~ /^([0-7])\.\.([0-7])$/) {
            # bit range
            my ($bitmin, $bitmax) = ($1,$2);

            croak "addbits(): min bit > max bit in bit range '$bits'"
                unless $bitmin <= $bitmax;
            croak "addbits(): bit field argument missing"
                unless @args >= 1;

            my $arg_hash = shift @args;
            croak "addbits(): arg to $bits must be a hash ref"
                unless defined $arg_hash and ref($arg_hash) =~ /HASH/;

            my %valid_keys;
            @valid_keys{qw(baseshift_def bitcount_def mask_def label enum)} = ();
            for (keys %$arg_hash) {
                croak "addbits(): unrecognised bifield key: '$_'"
                    unless exists $valid_keys{$_};
            }

            my $bitmask = 0;
            $bitmask += (1 << $_) for $bitmin..$bitmax;

            my $enum_id ='';

            if (defined $arg_hash->{enum}) {
                my $enum = $arg_hash->{enum};
                croak "addbits(): arg to enum must be an array ref"
                    unless defined $enum and ref($enum) =~ /ARRAY/;
                croak "addbits(): enum list must be in triplets"
                    unless @$enum % 3 == 0;

                my $max_id = (1 << ($bitmax - $bitmin + 1)) - 1;

                my @e = @$enum;
                while (@e) {
                    my $enum_ix     = shift @e;
                    my $enum_name   = shift @e;
                    my $enum_label  = shift @e;
                    croak "addbits(): enum index must be a number: '$enum_ix'"
                        unless $enum_ix =~ /^\d+$/;
                    croak "addbits(): enum index too big: '$enum_ix'"
                        unless $enum_ix  <= $max_id;
                    add_label($enum_name, $enum_label);
                    add_define($enum_name, $enum_ix << $bitmin);
                    $enum_id .= "($enum_ix:$enum_name:$enum_label)";
                }
            }

            # id is a fingerprint of all the content of the bit field hash
            my $id = join ':', map defined() ? $_ : "-undef-",
                $bitmin, $bitmax,
                $arg_hash->{label},
                $arg_hash->{mask_def},
                $arg_hash->{baseshift_def},
                $arg_hash->{bitcount_def},
                $enum_id;

            unless (defined $BITFIELDS{$id}) {

                if (defined $arg_hash->{mask_def}) {
                    add_define($arg_hash->{mask_def}, $bitmask);
                }

                if (defined $arg_hash->{baseshift_def}) {
                    add_define($arg_hash->{baseshift_def}, $bitmin);
                }

                if (defined $arg_hash->{bitcount_def}) {
                    add_define($arg_hash->{bitcount_def}, $bitmax-$bitmin+1);
                }

                # create deep copy

                my $copy = {};
                for (qw(baseshift_def  bitcount_def mask_def label)) {
                    $copy->{$_} = $arg_hash->{$_} if defined $arg_hash->{$_};
                }
                if (defined $arg_hash->{enum}) {
                    $copy->{enum} = [ @{$arg_hash->{enum}} ];
                }

                # and add some extra fields

                $copy->{bitmask} = $bitmask;
                $copy->{bitmin} = $bitmin;
                $copy->{bitmax} = $bitmax;

                $BITFIELDS{$id} = $copy;
            }

            for my $bit ($bitmin..$bitmax) {
                croak "addbits(): bit $bit of $op already specified ($FLAGS{$op}{$bit})"
                    if defined $FLAGS{$op}{$bit};
                $FLAGS{$op}{$bit} = $BITFIELDS{$id};
            }
        }
        else {
            croak "addbits(): invalid bit specifier '$bits'";
        }
    }
}


# intended to be called from regen/op_private; see that file for details

sub ::ops_with_flag {
    my $flag = shift;
    return grep $flags{$_} =~ /\Q$flag/, sort keys %flags;
}


# intended to be called from regen/op_private; see that file for details

sub ::ops_with_check {
    my $c = shift;
    return grep $check{$_} eq $c, sort keys %check;
}


# intended to be called from regen/op_private; see that file for details

sub ::ops_with_arg {
    my ($i, $arg_type) = @_;
    my @ops;
    for my $op (sort keys %args) {
        my @args = split(' ',$args{$op});
        push @ops, $op if defined $args[$i] and $args[$i] eq $arg_type;
    }
    @ops;
}


# output '#define OPpLVAL_INTRO 0x80' etc

sub print_defines {
    my $fh = shift;

    for (sort { $DEFINES{$a} <=> $DEFINES{$b} || $a cmp $b } keys %DEFINES) {
        printf $fh "#define %-23s 0x%02x\n", $_, $DEFINES{$_};
    }
}


# Generate the content of B::Op_private

sub print_B_Op_private {
    my $fh = shift;

    my $header = <<'EOF';
@=head1 NAME
@
@B::Op_private -  OP op_private flag definitions
@
@=head1 SYNOPSIS
@
@    use B::Op_private;
@
@    # flag details for bit 7 of OP_AELEM's op_private:
@    my $name  = $B::Op_private::bits{aelem}{7}; # OPpLVAL_INTRO
@    my $value = $B::Op_private::defines{$name}; # 128
@    my $label = $B::Op_private::labels{$name};  # LVINTRO
@
@    # the bit field at bits 5..6 of OP_AELEM's op_private:
@    my $bf  = $B::Op_private::bits{aelem}{6};
@    my $mask = $bf->{bitmask}; # etc
@
@=head1 DESCRIPTION
@
@This module provides four global hashes:
@
@    %B::Op_private::bits
@    %B::Op_private::defines
@    %B::Op_private::labels
@    %B::Op_private::ops_using
@
@which contain information about the per-op meanings of the bits in the
@op_private field.
@
@=head2 C<%bits>
@
@This is indexed by op name and then bit number (0..7). For single bit flags,
@it returns the name of the define (if any) for that bit:
@
@   $B::Op_private::bits{aelem}{7} eq 'OPpLVAL_INTRO';
@
@For bit fields, it returns a hash ref containing details about the field.
@The same reference will be returned for all bit positions that make
@up the bit field; so for example these both return the same hash ref:
@
@    $bitfield = $B::Op_private::bits{aelem}{5};
@    $bitfield = $B::Op_private::bits{aelem}{6};
@
@The general format of this hash ref is
@
@    {
@        # The bit range and mask; these are always present.
@        bitmin        => 5,
@        bitmax        => 6,
@        bitmask       => 0x60,
@
@        # (The remaining keys are optional)
@
@        # The names of any defines that were requested:
@        mask_def      => 'OPpFOO_MASK',
@        baseshift_def => 'OPpFOO_SHIFT',
@        bitcount_def  => 'OPpFOO_BITS',
@
@        # If present, Concise etc will display the value with a 'FOO='
@        # prefix. If it equals '-', then Concise will treat the bit
@        # field as raw bits and not try to interpret it.
@        label         => 'FOO',
@
@        # If present, specifies the names of some defines and the
@        # display labels that are used to assign meaning to particu-
@        # lar integer values within the bit field; e.g. 3 is dis-
@        # played as 'C'.
@        enum          => [ qw(
@                             1   OPpFOO_A  A
@                             2   OPpFOO_B  B
@                             3   OPpFOO_C  C
@                         )],
@
@    };
@
@
@=head2 C<%defines>
@
@This gives the value of every C<OPp> define, e.g.
@
@    $B::Op_private::defines{OPpLVAL_INTRO} == 128;
@
@=head2 C<%labels>
@
@This gives the short display label for each define, as used by C<B::Concise>
@and C<perl -Dx>, e.g.
@
@    $B::Op_private::labels{OPpLVAL_INTRO} eq 'LVINTRO';
@
@If the label equals '-', then Concise will treat the bit as a raw bit and
@not try to display it symbolically.
@
@=head2 C<%ops_using>
@
@For each define, this gives a reference to an array of op names that use
@the flag.
@
@    @ops_using_lvintro = @{ $B::Op_private::ops_using{OPp_LVAL_INTRO} };
@
@=cut

package B::Op_private;

our %bits;

EOF
    # remove podcheck.t-defeating leading char
    $header =~ s/^\@//gm;
    print $fh $header;
    my $v = (::perl_version())[3];
    print $fh qq{\nour \$VERSION = "$v";\n\n};

    my %ops_using;

    # for each flag/bit combination, find the ops which use it
    my %combos;
    for my $op (sort keys %FLAGS) {
        my $entry = $FLAGS{$op};
        for my $bit (0..7) {
            my $e = $entry->{$bit};
            next unless defined $e;
            next if ref $e; # bit field, not flag
            push @{$combos{$e}{$bit}}, $op;
            push @{$ops_using{$e}}, $op;
        }
    }

    # dump flags used by multiple ops
    for my $flag (sort keys %combos) {
        for my $bit (sort keys %{$combos{$flag}}) {
            my $ops = $combos{$flag}{$bit};
            next unless @$ops > 1;
            my @o = sort @$ops;
            print $fh "\$bits{\$_}{$bit} = '$flag' for qw(@o);\n";
        }
    }

    # dump bit field definitions

    my %bitfield_ix;
    {
        my %bitfields;
        # stringified-ref to ref mapping
        $bitfields{$_} = $_ for values %BITFIELDS;
        my $ix = -1;
        my $s = "\nmy \@bf = (\n";
        for my $bitfield_key (sort keys %BITFIELDS) {
            my $bitfield = $BITFIELDS{$bitfield_key};
            $ix++;
            $bitfield_ix{$bitfield} = $ix;

            $s .= "    {\n";
            for (qw(label mask_def baseshift_def bitcount_def)) {
                next unless defined $bitfield->{$_};
                $s .= sprintf "        %-9s => '%s',\n",
                            $_,  $bitfield->{$_};
            }
            for (qw(bitmin bitmax bitmask)) {
                croak "panic" unless defined $bitfield->{$_};
                $s .= sprintf "        %-9s => %d,\n",
                            $_,  $bitfield->{$_};
            }
            if (defined $bitfield->{enum}) {
                $s .= "        enum      => [\n";
                my @enum = @{$bitfield->{enum}};
                while (@enum) {
                    my $i     = shift @enum;
                    my $name  = shift @enum;
                    my $label = shift @enum;
                    $s .= sprintf "            %d, %-10s, %s,\n",
                            $i, "'$name'", "'$label'";
                }
                $s .= "        ],\n";
            }
            $s .= "    },\n";

        }
        $s .= ");\n";
        print $fh "$s\n";
    }

    # dump bitfields and remaining labels

    for my $op (sort keys %FLAGS) {
        my @indices;
        my @vals;
        my $entry = $FLAGS{$op};
        my $bit;

        for ($bit = 7; $bit >= 0; $bit--) {
            next unless defined $entry->{$bit};
            my $e = $entry->{$bit};
            if (ref $e) {
                my $ix = $bitfield_ix{$e};
                for (reverse $e->{bitmin}..$e->{bitmax}) {
                    push @indices,  $_;
                    push @vals, "\$bf[$ix]";
                }
                $bit = $e->{bitmin};
            }
            else {
                next if @{$combos{$e}{$bit}} > 1;  # already output
                push @indices, $bit;
                push @vals, "'$e'";
            }
        }
        if (@indices) {
            my $s = '';
            $s = '@{' if @indices > 1;
            $s .= "\$bits{$op}";
            $s .= '}' if @indices > 1;
            $s .= '{' . join(',', @indices) . '} = ';
            $s .= '(' if @indices > 1;
            $s .= join ', ', @vals;
            $s .= ')' if @indices > 1;
            print $fh "$s;\n";
        }
    }

    # populate %defines and %labels

    print  $fh "\n\nour %defines = (\n";
    printf $fh "    %-23s  => %3d,\n", $_ , $DEFINES{$_} for sort keys %DEFINES;
    print  $fh ");\n\nour %labels = (\n";
    printf $fh "    %-23s  => '%s',\n", $_ , $LABELS{$_}  for sort keys %LABELS;
    print  $fh ");\n";

    # %ops_using
    print  $fh "\n\nour %ops_using = (\n";
    # Save memory by using the same array wherever possible.
    my %flag_by_op_list;
    my $pending = '';
    for my $flag (sort keys %ops_using) {
        my $op_list = $ops_using{$flag} = "@{$ops_using{$flag}}";
        if (!exists $flag_by_op_list{$op_list}) {
            $flag_by_op_list{$op_list} = $flag;
            printf $fh "    %-23s  => %s,\n", $flag , "[qw($op_list)]"
        }
        else {
            $pending .= "\$ops_using{$flag} = "
                      . "\$ops_using{$flag_by_op_list{$op_list}};\n";
        }
    }
    print  $fh ");\n\n$pending";

}



# output the contents of the assorted PL_op_private_*[] tables

sub print_PL_op_private_tables {
    my $fh = shift;

    my $PL_op_private_labels     = '';
    my $PL_op_private_valid      = '';
    my $PL_op_private_bitdef_ix  = '';
    my $PL_op_private_bitdefs    = '';
    my $PL_op_private_bitfields  = '';

    my %label_ix;
    my %bitfield_ix;

    # generate $PL_op_private_labels

    {
        my %labs;
        $labs{$_} = 1 for values %LABELS; # de-duplicate labels
        # add in bit field labels
        for (values %BITFIELDS) {
            next unless defined $_->{label};
            $labs{$_->{label}} = 1;
        }

        my $labels = '';
        for my $lab (sort keys %labs) {
            $label_ix{$lab} = length $labels;
            $labels .= "$lab\0";
            $PL_op_private_labels .=
                  "    "
                . join(',', map("'$_'", split //, $lab))
                . ",'\\0',\n";
        }
    }


    # generate PL_op_private_bitfields

    {
        my %bitfields;
        # stringified-ref to ref mapping
        $bitfields{$_} = $_ for values %BITFIELDS;

        my $ix = 0;
        for my $bitfield_key (sort keys %BITFIELDS) {
            my $bf = $BITFIELDS{$bitfield_key};
            $bitfield_ix{$bf} = $ix;

            my @b;
            push @b, $bf->{bitmin},
                defined $bf->{label} ? $label_ix{$bf->{label}} : -1;
            my $enum = $bf->{enum};
            if (defined $enum) {
                my @enum = @$enum;
                while (@enum) {
                    my $i     = shift @enum;
                    my $name  = shift @enum;
                    my $label = shift @enum;
                    push @b, $i, $label_ix{$label};
                }
            }
            push @b, -1; # terminate enum list

            $PL_op_private_bitfields .= "    " .  join(', ', @b) .",\n";
            $ix += @b;
        }
    }


    # generate PL_op_private_bitdefs, PL_op_private_bitdef_ix

    {
        my $bitdef_count = 0;

        my %not_seen = %FLAGS;
        my @seen_bitdefs;
        my %seen_bitdefs;

        my $opnum = -1;
        for my $op (sort { $opnum{$a} <=> $opnum{$b} } keys %opnum) {
            $opnum++;
            die "panic: opnum misorder: opnum=$opnum opnum{op}=$opnum{$op}"
                unless $opnum == $opnum{$op};
            delete $not_seen{$op};

            my @bitdefs;
            my $entry = $FLAGS{$op};
            my $bit;
            my $index;

            for ($bit = 7; $bit >= 0; $bit--) {
                my $e = $entry->{$bit};
                next unless defined $e;

                my $ix;
                if (ref $e) {
                    $ix = $bitfield_ix{$e};
                    die "panic: \$bit =\= $e->{bitmax}"
                        unless $bit == $e->{bitmax};

                    push @bitdefs, ( ($ix << 5) | ($bit << 2) | 2 );
                    $bit = $e->{bitmin};
                }
                else {
                    $ix = $label_ix{$LABELS{$e}};
                    die "panic: no label ix for '$e'" unless defined $ix;
                    push @bitdefs, ( ($ix << 5) | ($bit << 2));
                }
                if ($ix > 2047) {
                    die "Too many labels or bitfields (ix=$ix): "
                    . "maybe the type of PL_op_private_bitdefs needs "
                    . "expanding from U16 to U32???";
                }
            }
            if (@bitdefs) {
                $bitdefs[-1] |= 1; # stop bit
                my $key = join(', ', map(sprintf("0x%04x", $_), @bitdefs));
                if (!$seen_bitdefs{$key}) {
                    $index = $bitdef_count;
                    $bitdef_count += @bitdefs;
                    push @seen_bitdefs,
                         $seen_bitdefs{$key} = [$index, $key];
                }
                else {
                    $index = $seen_bitdefs{$key}[0];
                }
                push @{$seen_bitdefs{$key}}, $op;
            }
            else {
                $index = -1;
            }
            $PL_op_private_bitdef_ix .= sprintf "    %4d, /* %s */\n", $index, $op;
        }
        if (%not_seen) {
            die "panic: unprocessed ops: ". join(',', keys %not_seen);
        }
        for (@seen_bitdefs) {
            local $" = ", ";
            $PL_op_private_bitdefs .= "    $$_[1], /* @$_[2..$#$_] */\n";
        }
    }


    # generate PL_op_private_valid

    for my $op (@ops) {
        my $last;
        my @flags;
        for my $bit (0..7) {
            next unless exists $FLAGS{$op};
            my $entry = $FLAGS{$op}{$bit};
            next unless defined $entry;
            if (ref $entry) {
                # skip later entries for the same bit field
                next if defined $last and $last == $entry;
                $last = $entry;
                push @flags,
                    defined $entry->{mask_def}
                        ? $entry->{mask_def}
                        : $entry->{bitmask};
            }
            else {
                push @flags, $entry;
            }
        }

        # all bets are off
        @flags = '0xff' if $op eq 'null' or $op eq 'custom';

        $PL_op_private_valid .= sprintf "    /* %-10s */ (%s),\n", uc($op),
                                    @flags ? join('|', @flags): '0';
    }

    print $fh <<EOF;

START_EXTERN_C

#ifndef PERL_GLOBAL_STRUCT_INIT

#  ifndef DOINIT

/* data about the flags in op_private */

EXTCONST I16  PL_op_private_bitdef_ix[];
EXTCONST U16  PL_op_private_bitdefs[];
EXTCONST char PL_op_private_labels[];
EXTCONST I16  PL_op_private_bitfields[];
EXTCONST U8   PL_op_private_valid[];

#  else


/* PL_op_private_labels[]: the short descriptions of private flags.
 * All labels are concatenated into a single char array
 * (separated by \\0's) for compactness.
 */

EXTCONST char PL_op_private_labels[] = {
$PL_op_private_labels
};



/* PL_op_private_bitfields[]: details about each bit field type.
 * Each definition consists of the following list of words:
 *    bitmin
 *    label (index into PL_op_private_labels[]; -1 if no label)
 *    repeat for each enum entry (if any):
 *       enum value
 *       enum label (index into PL_op_private_labels[])
 *    -1
 */

EXTCONST I16 PL_op_private_bitfields[] = {
$PL_op_private_bitfields
};


/* PL_op_private_bitdef_ix[]: map an op number to a starting position
 * in PL_op_private_bitdefs.  If -1, the op has no bits defined */

EXTCONST I16  PL_op_private_bitdef_ix[] = {
$PL_op_private_bitdef_ix
};



/* PL_op_private_bitdefs[]: given a starting position in this array (as
 * supplied by PL_op_private_bitdef_ix[]), each word (until a stop bit is
 * seen) defines the meaning of a particular op_private bit for a
 * particular op. Each word consists of:
 *  bit  0:     stop bit: this is the last bit def for the current op
 *  bit  1:     bitfield: if set, this defines a bit field rather than a flag
 *  bits 2..4:  unsigned number in the range 0..7 which is the bit number
 *  bits 5..15: unsigned number in the range 0..2047 which is an index
 *              into PL_op_private_labels[]    (for a flag), or
 *              into PL_op_private_bitfields[] (for a bit field)
 */

EXTCONST U16  PL_op_private_bitdefs[] = {
$PL_op_private_bitdefs
};


/* PL_op_private_valid: for each op, indexed by op_type, indicate which
 * flags bits in op_private are legal */

EXTCONST U8 PL_op_private_valid[] = {
$PL_op_private_valid
};

#  endif /* !DOINIT */
#endif /* !PERL_GLOBAL_STRUCT_INIT */

END_EXTERN_C


EOF

}


# =================================================================


package main;

# read regen/op_private data
#
# This file contains Perl code that builds up some data structures
# which define what bits in op_private have what meanings for each op.
# It populates %LABELS, %DEFINES, %FLAGS, %BITFIELDS.

require './regen/op_private';

#use Data::Dumper;
#print Dumper \%LABELS, \%DEFINES, \%FLAGS, \%BITFIELDS;


# Emit defines.

print $oc    "#ifndef PERL_GLOBAL_STRUCT_INIT\n\n";

{
    my $last_cond = '';
    my @unimplemented;

    sub unimplemented {
	if (@unimplemented) {
	    print $oc "#else\n";
	    foreach (@unimplemented) {
		print $oc "#define $_ Perl_unimplemented_op\n";
	    }
	    print $oc "#endif\n";
	    @unimplemented = ();
	}

    }

    for (@ops) {
	my ($impl, $cond) = @{$alias{$_} || ["Perl_pp_$_", '']};
	my $op_func = "Perl_pp_$_";

	if ($cond ne $last_cond) {
            # A change in condition. (including to or from no condition)
            # u_ ops are implemented
            unimplemented() unless /^u_/;
	    $last_cond = $cond;
	    if ($last_cond) {
		print $oc "$last_cond\n";
	    }
	}
        push @unimplemented, $op_func if $last_cond and !/^u_/;
	print $oc "#define $op_func $impl\n" if $impl ne $op_func;
        print $oc "#endif\n" if $last_cond and /^u_/;
    }
    # If the last op was conditional, we need to close it out:
    unimplemented();
}

print $on "typedef enum opcode {\n";

my $i = 0;
for (@ops) {
      print $on "\t", tab(3,"OP_\U$_"), " = ", $i++, ",\n";
}
print $on "\t", tab(3,"OP_max"), "\n";
print $on "} opcode;\n";
print $on "\n#define MAXO ", scalar @ops, "\n";
print $on "#define OP_FREED MAXO\n\n";

print $oc <<'END';

START_EXTERN_C

#ifndef DOINIT
EXTCONST char* const PL_op_name[];
#else
EXTCONST char* const PL_op_name[] = {
END

$i = 0;
for (@ops) {
    print $oc qq(\t"$_",\t/* $i: $desc{$_} */\n);
    $i++;
}

print $oc <<"END";
	"freed",	/* $i: freed op */
};
#endif

#ifndef DOINIT
EXTCONST char* const PL_op_desc[];
#else
EXTCONST char* const PL_op_desc[] = {
END

$i = 0;
for (@ops) {
    my($safe_desc) = $desc{$_};

    # Have to escape double quotes and escape characters.
    $safe_desc =~ s/([\\"])/\\$1/g;

    print $oc qq(\t"$safe_desc",\t/* $i: $_ */\n);
    $i++;
}

print $oc <<"END";
	\"freed op\",	/* $i: freed */
};
#endif
END

print $on <<"END";

/* core types */

typedef enum {
    type_none = 0,
END

$i = 0;
my @coretypes =
  ("", qw( int uint num str Int UInt Num Str
           Bool Numeric Scalar
           Ref Sub Regexp Object Array Hash List
           Any Void ));
my %coretype = map { $_ => $i++ } @coretypes;
$coretype{Void} = 0xff;

for (@coretypes) {
    if ($_ ne "") {
        printf $on (qq(    type_%s = %d), $_, $coretype{$_});
        printf $on ($_ ne "Void" ? ",\n" : "\n");
    }
}

print $on <<"END";
} core_types_t;

#ifdef PERL_IN_OP_C
static const char* const
core_types_n[] = {
END

for (@coretypes) {
    printf $on qq(    "%s",\n), $_;
}
print $on <<'END';
};
#endif /* PERL_IN_OP_C */

END

print $oc <<"END";

#if defined(PERL_IN_OP_C) && defined(DEBUGGING)
static const char* const
PL_op_type_str[] = {
END

$i = 0;
for (@ops) {
    printf $oc qq(\t"%s",\t/* %d: %s */\n), $type{$_}, $i, $_;
    $i++;
}
print $oc <<"END";
	\"\",	/* $i: freed */
};
#endif /* DEBUGGING PERL_IN_OP_C */

END

sub CORETYPE_OR_UNDEF ()   { 0b01100000 } # 5 bit
sub CORETYPE_LIST_AGGR ()  { 0b10100000 } # 5 bit
sub CORETYPE_ARRAY_AGGR () { 0b00100000 } # 5 bit
sub CORETYPE_HASH_AGGR ()  { 0b11000000 } # 5 bit, 31 scalar coretypes
sub CORETYPE_OPTIONAL ()   { 0b11100000 } # 4 bit, max 15 <Array

printf $oc qq(#define CORETYPE_OR_UNDEF\t0x%02x\n),   CORETYPE_OR_UNDEF();
printf $oc qq(#define CORETYPE_LIST_AGGR\t0x%02x\n),  CORETYPE_LIST_AGGR();
printf $oc qq(#define CORETYPE_ARRAY_AGGR\t0x%02x\n), CORETYPE_ARRAY_AGGR();
printf $oc qq(#define CORETYPE_HASH_AGGR\t0x%02x\n),  CORETYPE_HASH_AGGR();
printf $oc qq(#define CORETYPE_OPTIONAL\t0x%02x\n),   CORETYPE_OPTIONAL();

sub type_encode ($) {
    my $type = shift;
    if (exists $coretype{$type}) {
        return $coretype{$type};
    } elsif ($type =~ /^\?/ and exists $coretype{substr($type,1)}) {
        my $t = 0+$coretype{substr($type,1)};
        die "Invalid $type | Undef type" if $t >= 31;
        return $t | CORETYPE_OR_UNDEF;
    } elsif ($type =~ /\?$/ and exists $coretype{substr($type,0,-1)}) {
        my $t = 0+$coretype{substr($type,0,-1)};
        die "Invalid optional type $type" if $t >= 15;
        return $t | CORETYPE_OPTIONAL;
    } elsif ($type =~ /(List|Array|Hash)\(:(.+)\)/
             and exists $coretype{$1}
             and exists $coretype{$2}) {
        my $t = 0+$coretype{$2};
        die "Invalid aggregate subtype $2" if $t >= 31;
        if ($1 eq 'List') {
            return $t | CORETYPE_LIST_AGGR;
        } elsif ($1 eq 'Array') {
            return $t | CORETYPE_ARRAY_AGGR;
        } elsif ($1 eq 'Hash') {
            return $t | CORETYPE_HASH_AGGR;
        }
    }
}

# last byte for the return type
# the first 3 bytes for max 3 args
# "(:Int,:Int):Int" => 0x0505ff05
sub sig_encode ($) {
    my $s = shift;
    my $i = 0xffffff00;
    if ($s) {
        my ($args, $ret) = ($s =~ /^\(:?(.*)\):(.*)/);
        my $retenc = type_encode $ret;
        die "Invalid return type declaration $ret" unless defined $retenc;
        $i |= $retenc;
        my $j = 0;
        if ($args) {
            use integer;
            for my $arg (split /,:/, $args) {
                my $enc = type_encode $arg;
                if (defined $enc) {
                    my $off = 8*(3-$j);
                    my $mask = ~(0xff << $off);
                    $i &= $mask;
                    my $argenc = $enc << $off;
                    $i |= $argenc;
                } else {
                    warn "Unknown arg type declaration $arg";
                }
                $j++;
                die if $j > 3;
            }
            $i & 0xffffffff
        } else { # ():Type
            # or maybe just 0xff, no arg
            ($i | $coretype{Void} << 24) & 0xffffffff;
        }
    } else {
        $i # untyped
    }
}

print $oc <<"END";

#ifndef DOINIT
EXTCONST U32 PL_op_type[];
#else
EXTCONST U32 PL_op_type[] = {
END

# encode the types into bytes, max 4.
$i = 0;
for (@ops) {
    my $type = sig_encode $type{$_};
    printf $oc qq(\t0x%08x,\t/* %d: %s "%s" */\n), $type, $i, $_, $type{$_};
    $i++;
}
print $oc <<"END";
	0xffffffff,	/* $i: freed "" */
};
#endif

END

print $oc <<"END";

/* This encodes the offsets as signed char of the typed variants for each op.
 * The first byte is the number of following bytes, max 8.
 * variants: u_ i_ n_ s_ int_ uint_ num_ str_
 * Note that currently only forward types to upgrade to are stored, no negative offsets
 * for downgrading types.
 */
#ifndef DOINIT
EXTCONST signed char PL_op_type_variants[][8];
#else
EXTCONST signed char PL_op_type_variants[][8] = {
END

# find typed variants, max 8 bytes
# puts the number of variants into the first byte.
# also adds negative offsets for each downgrading variant
$i = 0;
for my $o (@ops) {
  my (@a, @s);
  my $type = $type{$o};
  my $found;
  my $op = $opnum{$o};
  printf $oc "\t/* %3d %-16s */ {", $i, $o;
  my $s = "";
  for my $p (qw(u_ i_ n_ s_ int_ uint_ num_ str_)) {
    # encode the distance as signed byte (-127 + 128)
    # positive to upgrade, negative to downgrade.
    # upgrade to typed
    if (exists $opnum{$p.$o}) {
      my $diff = $opnum{$p.$o} - $op;
      die "$p$o\[$opnum{$p.$o}] .. $o\[$op]: 0>$diff>128 too far away, 0-127." if $diff < 0 or $diff > 127;
      push @a, "$p$o:".$opnum{$p.$o};
      push @s, $diff;
      $found++;
    # upgrade typed to native
    } elsif ($o =~ /^(u|i|n|s)_/ and $p !~ /^(?:u|i|n|s)_/) {
      my $s = substr($o, 2);
      my $i1 = $1;
      # forbid n => int but allow int => uint and i => uint
      if (exists $opnum{$p.$s} and
          (($i1 eq 'i' and $p =~ /^[iu]i?nt_/)
          or
          ($i1 ne 'i' and $p =~ /^$i1.._/)))
      {
        my $diff = $opnum{$p.$s} - $op;
        die "$p$o\[$opnum{$p.$o}] .. $o\[$op]: 0>$diff>128 too far away, 0-127." if $diff < 0 or $diff > 127;
        push @a, "$p$s:".$opnum{$p.$s};
        push @s, $diff;
        $found++;
      }
    # downgrade native to typed (or untyped? usually typed is enough)
    } elsif ($p eq 'u_' and $o =~ /^(?:u?int|str|num)_(.*)$/) { # only the first $p
      my $b = $1;
      my $t = substr($o,0,1);
      if (exists $opnum{$t."_".$b}) {
        $b = $t."_".$b;
      } elsif (!exists $opnum{$b}) {
        die "no base $b for native $o";
      }
      my $diff = $opnum{$b} - $op;
      die "$b\[$opnum{$b}] .. $o\[$op]: -127>$diff>0 too far away, -127-0." if $diff > 0 || $diff < -127;
      push @a, "$b:".$opnum{$b};
      push @s, $diff;
      $found++;
    }
  }
  unshift @s, scalar(@s);
  print $oc join(",",@s);
  print $oc "},\t/* @a */\n";
  $i++;
}
print $oc <<"END";
	/* $i: freed */	{ 0 }
};
#endif

END_EXTERN_C

#endif /* !PERL_GLOBAL_STRUCT_INIT */
END

print $oc <<'END';

#define NUM_OP_TYPE_VARIANTS(op) PL_op_type_variants[op][0]

/* for 1 to num */
#define OP_TYPE_VARIANT(op, _j) \
  (PL_op_type_variants[(op)][(_j)] \
    ? (op) + PL_op_type_variants[(op)][(_j)] \
    : 0)
#define OP_TYPE_UPVARIANT(op, _j) \
  (PL_op_type_variants[(op)][(_j)] && PL_op_type_variants[(op)][(_j)]>0 \
    ? (op) + PL_op_type_variants[(op)][(_j)] \
    : 0)
#define OP_TYPE_DOWNVARIANT(op, _j) \
  (PL_op_type_variants[(op)][(_j)] && PL_op_type_variants[(op)][(_j)]<0 \
    ? (op) + PL_op_type_variants[(op)][(_j)] \
    : 0)

#define OP_TYPE_RET(op)   (PL_op_type[(op)->op_type] & 0xff)
#define OpTYPE_RET(type)  (PL_op_type[(type)] & 0xff)
#define OpTYPE_ARG(type)  (PL_op_type[(type)] & 0xffffff00)

/* The ppcode switch array */

START_EXTERN_C

#ifdef PERL_GLOBAL_STRUCT_INIT
#  define PERL_PPADDR_INITED
static const Perl_ppaddr_t Gppaddr[]
#elif !defined(PERL_GLOBAL_STRUCT)
#  define PERL_PPADDR_INITED
EXT Perl_ppaddr_t PL_ppaddr[] /* or perlvars.h */
#endif /* PERL_GLOBAL_STRUCT */
#if (defined(DOINIT) && !defined(PERL_GLOBAL_STRUCT)) || defined(PERL_GLOBAL_STRUCT_INIT)
#  define PERL_PPADDR_INITED
= {
END

for (@ops) {
    my $op_func = "Perl_pp_$_";
    my $name = $alias{$_};
    print $oc "\t$op_func,";
    if ($name && $name->[0] ne $op_func) {
        # u_ ops are implemented, but aliased to generic on 32bit IV
        if (/^u_/) {
            print $oc "\t/* on 32bit IV implemented by $name->[0] */\n";
        } else {
            print $oc "\t/* implemented by $name->[0] */\n";
        }
    }
    else {
	print $oc "\n";
    }
}

print $oc <<'END';
}
#endif
#ifdef PERL_PPADDR_INITED
;
#endif

#ifdef PERL_GLOBAL_STRUCT_INIT
#  define PERL_CHECK_INITED
static const Perl_check_t Gcheck[]
#elif !defined(PERL_GLOBAL_STRUCT)
#  define PERL_CHECK_INITED
EXT Perl_check_t PL_check[] /* or perlvars.h */
#endif
#if (defined(DOINIT) && !defined(PERL_GLOBAL_STRUCT)) || defined(PERL_GLOBAL_STRUCT_INIT)
#  define PERL_CHECK_INITED
= {
END

for (@ops) {
    print $oc "\t", tab(3, "Perl_$check{$_},"), "\t/* $_ */\n";
}

print $oc <<'END';
}
#endif
#ifdef PERL_CHECK_INITED
;
#endif /* #ifdef PERL_CHECK_INITED */

#ifndef PERL_GLOBAL_STRUCT_INIT

#ifndef DOINIT
EXTCONST U32 PL_opargs[];
#else
EXTCONST U32 PL_opargs[] = {
END

# Emit allowed argument types.

my $ARGBITS = 32;

my %argnum = (
    'S',  1,		# scalar
    'L',  2,		# list
    'A',  3,		# array value
    'H',  4,		# hash value
    'C',  5,		# code value
    'F',  6,		# file value
    'R',  7,		# scalar reference
    'I',  8,		# unboxed int or uint
    'Z',  9,		# unboxed ASCIIZ str
    'N',  10,		# unboxed double (num, 64-bit only)
);

my %opclass = (
    '0',  0,		# baseop
    '1',  1,		# unop
    '2',  2,		# binop
    '|',  3,		# logop
    '@',  4,		# listop
    '/',  5,		# pmop
    '$',  6,		# svop_or_padop
    '"',  7,		# pvop_or_svop
    '{',  8,		# loop
    ';',  9,		# cop
    '%',  10,		# baseop_or_unop
    '-',  11,		# filestatop
    '}',  12,		# loopexop
    '.',  13,		# methop
    '+',  14,		# unop_aux
);

# stricter argument types are encoded into PL_op_type, see PL_op_type_str.
# esp. i to return :Int, and return native types.
my %opflags = (
    'm' =>   1,		# needs stack mark
    'f' =>   2,		# fold constants
    's' =>   4,		# always produces scalar
    't' =>   8,		# needs target scalar
    'T' =>  8|16,	# ... which may be lexical
    'i' =>   0,		# always produces integer (unused since e7311069)
    'I' =>  32,		# has corresponding int op
    'd' =>  64,		# danger, make temp copy in list assignment
    'u' => 128,		# defaults to $_
    'p' => 256,		# is pure
    'b' => 512,         # has boxret, can box in the op
);

my @opflag_names = (
    'MARK'      => 'm',
    'FOLDCONST' => 'f',
    'RETSCALAR' => 's',
    'TARGET'    => 't',
    'TARGLEX'   => 'T',
    'OTHERINT'  => 'I',
    'DANGEROUS' => 'd',
    'DEFGV'     => 'u',
    'PURE'      => 'p',
    'BOXRET'    => 'b',
);

my $OCSHIFT = (scalar keys %opflags) - 1; # i is unused
my $OASHIFT = $OCSHIFT + 4;

print $on <<EOF;
/* PL_opargs encoding */

/* Lowest $OCSHIFT bits of PL_opargs */
EOF
while (@opflag_names) {
    my $k = shift @opflag_names;
    my $v = shift @opflag_names;
    print $on "#define OA_$k\t", $opflags{$v},"\n";
}
print $on <<EOF;

/* The next 4 bits ($OCSHIFT..${\($OCSHIFT+3)}) encode op class information */
#define OCSHIFT $OCSHIFT

/* Each remaining 4bit nybbles of PL_opargs (i.e. bits ${\($OCSHIFT+4)}..${\($OCSHIFT+7)}, ${\($OCSHIFT+8)}..${\($OCSHIFT+11)} etc)
 * encode the type for each arg */
#define OASHIFT $OASHIFT

/* arg types */
#define OA_SCALAR  1
#define OA_LIST    2
#define OA_AVREF   3
#define OA_HVREF   4
#define OA_CVREF   5
#define OA_FILEREF 6
#define OA_SCALARREF 7
#define OA_OPTIONAL 8

/* 0b0011_1100_0000_0000 / 0xf000 */
#define OA_CLASS_MASK (0xf << OCSHIFT)

#define OA_BASEOP 	(0 << OCSHIFT)
#define OA_UNOP 	(1 << OCSHIFT)
#define OA_BINOP 	(2 << OCSHIFT)
#define OA_LOGOP 	(3 << OCSHIFT)
#define OA_LISTOP 	(4 << OCSHIFT)
#define OA_PMOP 	(5 << OCSHIFT)
#define OA_SVOP 	(6 << OCSHIFT)
#define OA_PVOP_OR_SVOP (7 << OCSHIFT)
#define OA_LOOP 	(8 << OCSHIFT)
#define OA_COP 		(9 << OCSHIFT)
#define OA_BASEOP_OR_UNOP (10 << OCSHIFT)
#define OA_FILESTATOP 	(11 << OCSHIFT)
#define OA_LOOPEXOP 	(12 << OCSHIFT)
#define OA_METHOP 	(13 << OCSHIFT)
#define OA_UNOP_AUX 	(14 << OCSHIFT)

EOF

my %OP_HAS_BOXRET;	# /b/
my %OP_HAS_LIST;	# /L/
my %OP_IS_SOCKET;	# /Fs/
my %OP_IS_FILETEST;	# /F-/
my %OP_IS_FT_ACCESS;	# /F-+/
my %OP_IS_NUMCOMPARE;	# /S</
my %OP_IS_DIRHOP;	# /Fd/
my %OP_IS_INFIX_BIT;	# /S\|/
my %OP_IS_PADVAR;	# /^pad/
my %OP_IS_ITER;		# /^iter/

for my $op (@ops) {
    my $argsum = 0;
    my $flags = $flags{$op};
    for my $flag (keys %opflags) {
	if ($flags =~ s/$flag//) {
	    die "Flag collision for '$op' ($flags{$op}, $flag)\n"
		if $argsum & $opflags{$flag};
	    $argsum |= $opflags{$flag};
            if ($flag eq 'b') {
                $OP_HAS_BOXRET{$op} = $opnum{$op};
            }
	}
    }
    die qq[Opcode '$op' has no class indicator ($flags{$op} => $flags)\n]
	unless exists $opclass{$flags};
    if ($op =~ /^pad(av|hv|sv|any)$/) { # but NOT padcv
        $OP_IS_PADVAR{$op} = $opnum{$op};
    }
    if ($op =~ /^iter/) {
        $OP_IS_ITER{$op} = $opnum{$op};
    }
    $argsum |= $opclass{$flags} << $OCSHIFT;
    my $argshift = $OASHIFT;
    for my $arg (split(' ',$args{$op})) {
	if ($arg =~ s/^D//) {
	    # handle 1st, just to put D 1st.
	    $OP_IS_DIRHOP{$op}   = $opnum{$op};
	}
	if ($arg =~ /^F/) {
	    # record opnums of these opnames
	    $OP_IS_SOCKET{$op}   = $opnum{$op} if $arg =~ s/s//;
	    $OP_IS_FILETEST{$op} = $opnum{$op} if $arg =~ s/-//;
	    $OP_IS_FT_ACCESS{$op} = $opnum{$op} if $arg =~ s/\+//;
        }
	elsif ($arg =~ /^S./) {
	    $OP_IS_NUMCOMPARE{$op} = $opnum{$op} if $arg =~ s/<//;
	    $OP_IS_INFIX_BIT {$op} = $opnum{$op} if $arg =~ s/\|//;
	}
	elsif ($arg =~ /^L/) {
            $OP_HAS_LIST{$op} = $opnum{$op};
        }
        # OA_OPTIONAL
	my $argnum = ($arg =~ s/\?//) ? 8 : 0;
        die "op = $op, arg = $arg does not exist in \%argnum\n"
	    unless exists $argnum{$arg};
	$argnum += $argnum{$arg};
	die "Argument overflow for '$op' $argnum/$argshift\n"
	    if $argshift >= $ARGBITS ||
	       $argnum > ((1 << ($ARGBITS - $argshift)) - 1);
	$argsum += $argnum << $argshift;
	$argshift += 4;
    }
    $argsum = sprintf("0x%08x", $argsum);
    print $oc "\t", tab(3, "$argsum,"), "/* $op */\n";
}

print $oc <<'END';
};
#endif

#endif /* !PERL_GLOBAL_STRUCT_INIT */

END_EXTERN_C
END

# Emit OP_IS_* macros

print $on <<'EO_OP_IS_COMMENT';

#define OP_HAS_TARGLEX(ot) ((PL_opargs[ot] & OA_TARGLEX) == OA_TARGLEX)

#define OpCLASS(ot)      (PL_opargs[(ot)] & OA_CLASS_MASK)
#define OP_IS_BASEOP(ot) (OpCLASS(ot) == OA_BASEOP || OpCLASS(ot) == OA_BASEOP_OR_UNOP)
#define OP_IS_UNOP(ot)   (OpCLASS(ot) == OA_UNOP || OpCLASS(ot) == OA_BASEOP_OR_UNOP)
#define OP_IS_BINOP(ot)  OpCLASS(ot) == OA_BINOP
#define OP_IS_LOGOP(ot)  OpCLASS(ot) == OA_LOGOP
#define OP_IS_LISTOP(ot) OpCLASS(ot) == OA_LISTOP
#define OP_IS_PMOP(ot)   OpCLASS(ot) == OA_PMOP
#define OP_IS_SVOP(ot)   (OpCLASS(ot) == OA_SVOP || OpCLASS(ot) == OA_PVOP_OR_SVOP)
#ifdef USE_ITHREADS
# define OP_IS_PADOP(ot)  OP_IS_SVOP(ot)
#endif
#define OP_IS_LOOP(ot)   OpCLASS(ot) == OA_LOOP
#define OP_IS_COP(ot)    OpCLASS(ot) == OA_COP
#define OP_IS_FILESTATOP(ot) OpCLASS(ot) == OA_FILESTATOP
#define OP_IS_METHOP(ot) OpCLASS(ot) == OA_METHOP

/* The other OP_IS_* macros are optimized to a simple range check because
   all the member OPs are contiguous in regen/opcodes table.
   regen/opcode.pl verifies the range contiguity, or generates an OR-equals
   expression */
EO_OP_IS_COMMENT

# XXX need to detect two ranges
#gen_op_is_macro( \%OP_HAS_BOXRET, 'OP_HAS_BOXRET');
gen_op_is_macro( \%OP_HAS_LIST, 'OP_HAS_LIST');
gen_op_is_macro( \%OP_IS_SOCKET, 'OP_IS_SOCKET');
gen_op_is_macro( \%OP_IS_FILETEST, 'OP_IS_FILETEST');
gen_op_is_macro( \%OP_IS_FT_ACCESS, 'OP_IS_FILETEST_ACCESS');
gen_op_is_macro( \%OP_IS_NUMCOMPARE, 'OP_IS_NUMCOMPARE');
gen_op_is_macro( \%OP_IS_DIRHOP, 'OP_IS_DIRHOP');
gen_op_is_macro( \%OP_IS_INFIX_BIT, 'OP_IS_INFIX_BIT');
gen_op_is_macro( \%OP_IS_PADVAR, 'OP_IS_PADVAR');
gen_op_is_macro( \%OP_IS_ITER, 'OP_IS_ITER');

sub gen_op_is_macro {
    my ($op_is, $macname) = @_;
    if (keys %$op_is) {

	# get opnames whose numbers are lowest and highest
	my ($first, @rest) = sort {
	    $op_is->{$a} <=> $op_is->{$b}
	} keys %$op_is;

	my $last = pop @rest;	# @rest slurped, get its last
	die "Invalid range of ops: $first .. $last\n" unless $last;

	print $on "\n#define $macname(ot)	\\\n\t(";

	# verify that op-ct matches 1st..last range (and fencepost)
	# (we know there are no dups)
	if ( $op_is->{$last} - $op_is->{$first} == scalar @rest + 1) {
	    # contiguous ops -> optimized version
	    print $on "(ot) >= OP_" . uc($first)
		. " && (ot) <= OP_" . uc($last);
	}
	else {
	    print $on join(" || \\\n\t ",
			   map { "(ot) == OP_" . uc() } sort keys %$op_is);
	}
	print $on ")\n";
    }
}

print $on "\n/* backcompat old Perl 5 names: */\n";
print $on "#if 1\n";
my @bak = @cperl_changes;
while (my ($old, $new) = splice @cperl_changes, 0, 2) {
    print $on "#define ",tab(3,"OP_\U$old"), " OP_\U$new","\n";
}
print $on "\n";
@cperl_changes = @bak;
while (my ($old, $new) = splice @cperl_changes, 0, 2) {
    print $on "#define ",tab(3,"Perl_pp_$old"), " Perl_pp_$new","\n";
}
print $on "#endif\n";

my $pp = open_new('pp_proto.h', '>',
		  { by => 'opcode.pl', from => 'its data' });

{
    my %funcs;
    for (@ops) {
	my $name = $alias{$_} ? $alias{$_}[0] : "Perl_pp_$_";
        # u_ ops are implemented and not aliased on 64bit
	++$funcs{"Perl_pp_$_"} if /^u_/;
	++$funcs{$name};
    }
    print $pp "PERL_CALLCONV OP *$_(pTHX);\n" foreach sort keys %funcs;

    print $pp "\n/* alternative functions */\n" if keys %alts;
    for my $fn (sort keys %alts) {
        my ($x, $cond) = @{$alts{$fn}};
        print $pp "$cond\n" if $cond;
        print $pp "PERL_CALLCONV OP *$x(pTHX);\n";
        print $pp "#endif\n" if $cond;
    }
}

print $oc "\n\n";
OP_PRIVATE::print_defines($oc);
OP_PRIVATE::print_PL_op_private_tables($oc);

OP_PRIVATE::print_B_Op_private($oprivpm);

foreach ($oc, $on, $pp, $oprivpm) {
    read_only_bottom_close_and_rename($_);
}

