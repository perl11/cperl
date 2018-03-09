#      CC.pm
#
#      Copyright (c) 1996, 1997, 1998 Malcolm Beattie
#      Copyright (c) 2009, 2010, 2011 Reini Urban
#      Copyright (c) 2010 Heinz Knutzen
#      Copyright (c) 2012-2017 cPanel Inc
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.

=head1 NAME

B::CC - Perl compiler's optimized C translation backend

=head1 SYNOPSIS

	perl -MO=CC[,OPTIONS] foo.pl

=head1 DESCRIPTION

This compiler backend takes Perl source and generates C source code
corresponding to the flow of your program with unrolled ops and optimised
stack handling and lexicals variable types. In other words, this backend is
somewhat a "real" compiler in the sense that many people think about
compilers. Note however that, currently, it is a very poor compiler in that
although it generates (mostly, or at least sometimes) correct code, it
performs relatively few optimisations.  This will change as the compiler and
the types develops. The result is that running an executable compiled with
this backend may start up more quickly than running the original Perl program
(a feature shared by the B<C> compiler backend--see L<B::C>) and may also
execute slightly faster. This is by no means a good optimising compiler--yet.

=head1 OPTIONS

If there are any non-option arguments, they are taken to be
names of objects to be saved (probably doesn't work properly yet).
Without extra arguments, it saves the main program.

=over 4

=item B<-ofilename>

Output to filename instead of STDOUT

=item B<-c>

Check and abort.

Compiles and prints only warnings, but does not emit C code.

=item B<-v>

Verbose compilation (prints a few compilation stages).

=item B<-->

Force end of options

=item B<-uPackname>

Force apparently unused subs from package Packname to be compiled.
This allows programs to use eval "foo()" even when sub foo is never
seen to be used at compile time. The down side is that any subs which
really are never used also have code generated. This option is
necessary, for example, if you have a signal handler foo which you
initialise with C<$SIG{BAR} = "foo">.  A better fix, though, is just
to change it to C<$SIG{BAR} = \&foo>. You can have multiple B<-u>
options. The compiler tries to figure out which packages may possibly
have subs in which need compiling but the current version doesn't do
it very well. In particular, it is confused by nested packages (i.e.
of the form C<A::B>) where package C<A> does not contain any subs.

=item B<-UPackname>  "unuse" skip Package

Ignore all subs from Package to be compiled.

Certain packages might not be needed at run-time, even if the pessimistic
walker detects it.

=item B<-mModulename>

Instead of generating source for a runnable executable, generate
source for an XSUB module. The boot_Modulename function (which
DynaLoader can look for) does the appropriate initialisation and runs
the main part of the Perl source that is being compiled.

=item B<-nInitname>

Provide a different init name for additional objects added via cmdline.

=item B<-strict>

With a DEBUGGING perl compile-time errors for range and flip without
compile-time context are only warnings.
With C<-strict> these warnings are fatal, otherwise only run-time errors occur.

=item B<-On>

Optimisation level (n = 0, 1, 2). B<-O> means B<-O1>.

The following L<B::C> optimisations are applied automatically:

optimize_warn_sv save_data_fh av-init2|av_init save_sig destruct
pv_copy_on_grow

B<-O1> sets B<-ffreetmps-each-bblock>.

B<-O2> adds B<-ffreetmps-each-loop>, C<-faelem> and B<-fno-destruct> from L<B::C>.

The following options must be set explicitly:

  B<-fno-taint> or B<-fomit-taint>,

  B<-fslow-signals>,

  B<-no-autovivify>,

  B<-fno-magic>.

=item B<-f>C<OPTIM>

Force optimisations on or off one at a time.
Unknown optimizations are passed down to L<B::C>.

=item B<-ffreetmps-each-bblock>

Delays FREETMPS from the end of each statement to the end of the each
basic block.

Enabled with B<-O1>.

=item B<-ffreetmps-each-loop>

Delays FREETMPS from the end of each statement to the end of the group
of basic blocks forming a loop. At most one of the freetmps-each-*
options can be used.

Enabled with B<-O2>.

=item B<-faelem>

Enable array element access optimizations, allowing unchecked
fast access under certain circumstances.

Enabled with B<-O2> and not-threaded perls only.

=item B<-fno-inline-ops>

Do not inline calls to certain small pp ops.

Most of the inlinable ops were already inlined.
Turns off inlining for some new ops.

AUTOMATICALLY inlined:

pp_null pp_stub pp_unstack pp_and pp_andassign pp_or pp_orassign pp_cond_expr
pp_padsv pp_const pp_nextstate pp_dbstate pp_rv2gv pp_sort pp_gv pp_gvsv
pp_aelemfast pp_ncmp pp_add pp_subtract pp_multiply pp_divide pp_modulo
pp_left_shift pp_right_shift pp_i_add pp_i_subtract pp_i_multiply pp_i_divide
pp_i_modulo pp_eq pp_ne pp_lt pp_gt pp_le pp_ge pp_i_eq pp_i_ne pp_i_lt
pp_i_gt pp_i_le pp_i_ge pp_scmp pp_slt pp_sgt pp_sle pp_sge pp_seq pp_sne
pp_sassign pp_preinc pp_pushmark pp_list pp_entersub pp_formline pp_goto
pp_enterwrite pp_leavesub pp_leavewrite pp_entergiven pp_leavegiven
pp_entereval pp_dofile pp_require pp_entertry pp_leavetry pp_grepstart
pp_mapstart pp_grepwhile pp_mapwhile pp_return pp_range pp_flip pp_flop
pp_enterloop pp_enteriter pp_leaveloop pp_next pp_redo pp_last pp_subst
pp_substcont

DONE with -finline-ops:

pp_enter pp_reset pp_regcreset pp_stringify

TODO with -finline-ops:

pp_anoncode pp_wantarray pp_srefgen pp_refgen pp_ref pp_trans pp_schop pp_chop
pp_schomp pp_chomp pp_not pp_sprintf pp_anonlist pp_shift pp_once pp_lock
pp_rcatline pp_close pp_time pp_alarm pp_av2arylen: no lvalue, pp_length: no
magic

=item B<-fomit-taint>

Omits generating code for handling perl's tainting mechanism.

=item B<-fslow-signals>

Add PERL_ASYNC_CHECK after every op as in the old Perl runloop before 5.13.

perl "Safe signals" check the state of incoming signals after every op.
See L<http://perldoc.perl.org/perlipc.html#Deferred-Signals-(Safe-Signals)>
We trade safety for more speed and delay the execution of non-IO signals
(IO signals are already handled in PerlIO) from after every single Perl op
to the same ops as used in 5.14.

Only with -fslow-signals we get the old slow and safe behaviour.

=item B<-fno-name-magic>

With the default C<-fname-magic> we infer the SCALAR type for specially named
locals vars and most ops use C vars then, not the perl vars.
Arithmetic and comparison is inlined. Scalar magic is bypassed.

With C<-fno-name-magic> do not infer a local variable type from its name:

  B<_i> suffix for int, B<_d> for double/num, B<_ir> for register int

See the experimental C<-ftype-attr> type attributes.
Currently supported are B<int> and B<num> only. See </load_pad>.

=item B<-ftype-attr> (DOES NOT WORK YET)

Experimentally support B<type attributes> for B<int> and B<num>,
SCALAR only so far.
For most ops new C vars are used then, not the fat perl vars.
Very awkward to use until the basic type classes are supported from
within core or use types.

Enabled with B<-O2>. See L<TYPES> and </load_pad>.

=item B<-fno-autovivify>

Do not vivify array and soon also hash elements when accessing them.
Beware: Vivified elements default to undef, unvivified elements are
invalid.

This is the same as the pragma "no autovivification" and allows
very fast array accesses, 4-6 times faster, without the overhead of
L<autovivification>.

=item B<-fno-magic>

Assume certain data being optimized is never tied or is holding other magic.
This mainly holds for arrays being optimized, but in the future hashes also.

=item B<-D>

Debug options (concatenated or separate flags like C<perl -D>).
Verbose debugging options are crucial, because the interactive
debugger L<Od> adds a lot of ballast to the resulting code.

=item B<-Dr>

Writes debugging output to STDERR just as it's about to write to the
program's runtime (otherwise writes debugging info as comments in
its C output).

=item B<-DO>

Outputs each OP as it's compiled

=item B<-DT>

Outputs the contents of the B<stack> at each OP.
Values are B::Stackobj objects.

=item B<-Dc>

Outputs the contents of the loop B<context stack>, the @cxstack.

=item B<-Dw>

Outputs the contents of the B<shadow> stack at each OP.

=item B<-Da>

Outputs the contents of the shadow pad of lexicals as it's loaded for
each sub or the main program.

=item B<-Dq>

Outputs the name of each fake PP function in the queue as it's about
to process it.

=item B<-Dl>

Output the filename and line number of each original line of Perl
code as it's processed (C<pp_nextstate>).

=item B<-Dt>

Outputs timing information of compilation stages.

=item B<-DF>

Add Flags info to the code.

=back

=head1 NOTABLE FUNCTIONS

=cut


package B::CC;

our $VERSION = '1.16_02';

# Start registering the L<types> namespaces.
use strict;
our %Config;
BEGIN {
  require B::C::Config;
  *Config = \%B::C::Config::Config;
  # make it a restricted hash
  Internals::SvREADONLY(%Config, 1) if $] >= 5.008004;
}
unless ($Config{usecperl}) {
  eval '$main::int::B_CC = $main::num::B_CC = $main::str::B_CC = $main::double::B_CC = $main::string::B_CC = $VERSION;';
}

#use 5.008;
use B qw(main_start main_root comppadlist peekop svref_2object
  timing_info init_av end_av sv_undef
  OPf_WANT_VOID OPf_WANT_SCALAR OPf_WANT_LIST OPf_WANT
  OPf_MOD OPf_STACKED OPf_SPECIAL OPpLVAL_DEFER OPpLVAL_INTRO
  OPpASSIGN_BACKWARDS OPpLVAL_INTRO OPpDEREF_AV OPpDEREF_HV
  OPpDEREF OPpFLIP_LINENUM G_VOID G_SCALAR G_ARRAY);
#CXt_NULL CXt_SUB CXt_EVAL CXt_SUBST CXt_BLOCK
use B::C qw(save_unused_subs objsym init_sections mark_unused mark_skip
  output_all output_boilerplate output_main output_main_rest fixup_ppaddr save_sig
  svop_or_padop_pv inc_cleanup curcv set_curcv);
use B::Bblock qw(find_leaders);
use B::Stackobj qw(:types :flags);
use B::C::Config;
# use attributes qw(get reftype);

@B::OP::ISA = qw(B);                    # support -Do
@B::LISTOP::ISA = qw(B::BINOP B);       # support -Do
push @B::OP::ISA, 'B::NULLOP' if exists $main::B::{'NULLOP'};

# These should probably be elsewhere
# Flags for $op->flags

my $module;         # module name (when compiled with -m)
my %done;          # hash keyed by $$op of leaders of basic blocks
                    # which have already been done.
my $leaders;        # ref to hash of basic block leaders. Keys are $$op
                    # addresses, values are the $op objects themselves.
my @bblock_todo;  # list of leaders of basic blocks that need visiting
                    # sometime.
my @cc_todo;       # list of tuples defining what PP code needs to be
                    # saved (e.g. CV, main or PMOP repl code). Each tuple
                    # is [$name, $root, $start, @padlist]. PMOP repl code
                    # tuples inherit padlist.
my %cc_pp_sub;     # hashed names of pp_sub functions already saved
my @stack;         # shadows perl's stack when contents are known.
                    # Values are objects derived from class B::Stackobj
my @pad;           # Lexicals in current pad as Stackobj-derived objects
my @padlist;       # Copy of current padlist so PMOP repl code can find it
my @cxstack;       # Shadows the (compile-time) cxstack for next,last,redo
		    # This covers only a small part of the perl cxstack
my $labels;         # hashref to array of op labels
my %constobj;      # OP_CONST constants as Stackobj-derived objects
                    # keyed by $$sv.
my $need_freetmps = 0;	# We may postpone FREETMPS to the end of each basic
			# block or even to the end of each loop of blocks,
			# depending on optimisation options.
my $know_op       = 0;	# Set when C variable op already holds the right op
			# (from an immediately preceding DOOP(ppname)).
my $errors        = 0;	# Number of errors encountered
my $op_count      = 0;	# for B::compile_stats on verbose
my %no_stack;		# PP names which don't need save pp restore stack
my %skip_stack;	# PP names which don't need write_back_stack (empty)
my %skip_lexicals;	# PP names which don't need write_back_lexicals
my %skip_invalidate;	# PP names which don't need invalidate_lexicals
my %ignore_op;		# ops which do nothing except returning op_next
my %need_curcop;	# ops which need PL_curcop
my $package_pv;         # sv->pv of previous op for method_named

my %lexstate;           # state of padsvs at the start of a bblock
my ( $verbose, $check );
my ( $entertry_defined, $vivify_ref_defined );
my ( $init_name, %debug, $strict );

# Optimisation options. On the command line, use hyphens instead of
# underscores for compatibility with gcc-style options. We use
# underscores here because they are OK in (strict) barewords.
# Disable with -fno-
my ( $freetmps_each_bblock, $freetmps_each_loop, $inline_ops, $opt_taint, $opt_omit_taint,
     $opt_slow_signals, $opt_name_magic, $opt_type_attr, $opt_autovivify, $opt_magic,
     $opt_aelem, %c_optimise );
$inline_ops = 1 unless $^O eq 'MSWin32'; # Win32 cannot link to unexported pp_op() XXX
$opt_name_magic = 1;
my %optimise = (
  freetmps_each_bblock => \$freetmps_each_bblock, # -O1
  freetmps_each_loop   => \$freetmps_each_loop,	  # -O2
  aelem                => \$opt_aelem,	          # -O2
  inline_ops 	       => \$inline_ops,	  	  # not on Win32
  omit_taint           => \$opt_omit_taint,
  taint                => \$opt_taint,
  slow_signals         => \$opt_slow_signals,
  name_magic           => \$opt_name_magic,
  type_attr            => \$opt_type_attr,
  autovivify           => \$opt_autovivify,
  magic                => \$opt_magic,
);
my %async_signals = map { $_ => 1 } # 5.14 ops which do PERL_ASYNC_CHECK
  qw(wait waitpid nextstate and cond_expr unstack or subst dorassign);
$async_signals{$_} = 1 for # more 5.16 ops which do PERL_ASYNC_CHECK
  qw(substcont next redo goto leavewhen);
# perl patchlevel to generate code for (defaults to current patchlevel)
my $patchlevel = int( 0.5 + 1000 * ( $] - 5 ) );    # XXX unused?
my $MULTI      = $Config{usemultiplicity};
my $ITHREADS   = $Config{useithreads};
my $PERL510    = ( $] >= 5.009005 );
my $PERL512    = ( $] >= 5.011 );

my $SVt_PVLV = $PERL510 ? 10 : 9;
my $SVt_PVAV = $PERL510 ? 11 : 10;
# use sub qw(CXt_LOOP_PLAIN CXt_LOOP);
BEGIN {
  if ($PERL512) {
    sub CXt_LOOP_PLAIN {5} # CXt_LOOP_FOR CXt_LOOP_LAZYSV CXt_LOOP_LAZYIV
  } else {
    sub CXt_LOOP {3}
  }
  sub CxTYPE_no_LOOP  {
    $PERL512
      ? ( $_[0]->{type} < 4 or $_[0]->{type} > 7 )
        : $_[0]->{type} != 3
  }
  if ($] < 5.008) {
    eval "sub SVs_RMG {0x8000};";
  } else {
    B->import('SVs_RMG');
  }
  if ($] <= 5.010) {
    eval "sub PMf_ONCE() {0xff}; # unused";
  } elsif ($] >= 5.018) { # PMf_ONCE not exported
    eval q[sub PMf_ONCE(){ 0x10000 }];
  } elsif ($] >= 5.014) {
    eval q[sub PMf_ONCE(){ 0x8000 }];
  } elsif ($] >= 5.012) {
    eval q[sub PMf_ONCE(){ 0x0080 }];
  } else { # 5.10. not used with <= 5.8
    eval q[sub PMf_ONCE(){ 0x0002 }];
  }
}

# Could rewrite push_runtime() and output_runtime() to use a
# temporary file if memory is at a premium.
my $ppname;    	     # name of current fake PP function
my $runtime_list_ref;
my $declare_ref;     # Hash ref keyed by C variable type of declarations.

my @pp_list;        # list of [$ppname, $runtime_list_ref, $declare_ref]
		     # tuples to be written out.

my ( $init, $decl );

sub init_hash {
  map { $_ => 1 } @_;
}

# Initialise the hashes for the default PP functions where we can avoid
# either stack save/restore,write_back_stack, write_back_lexicals or invalidate_lexicals.
# XXX We should really take some of this info from Opcodes (was: CORE opcode.pl)
#
# no args and no return value = Opcodes::argnum 0
%no_stack         = init_hash qw(pp_unstack pp_break pp_continue);
				# pp_enter pp_leave, use/change global stack.
#skip write_back_stack (no args)
%skip_stack       = init_hash qw(pp_enter pp_leave pp_nextstate pp_dbstate);
# which ops do not read pad vars
%skip_lexicals   = init_hash qw(pp_enter pp_enterloop pp_leave pp_nextstate pp_dbstate);
# which ops no not write to pad vars
%skip_invalidate = init_hash qw(pp_enter pp_enterloop pp_leave pp_nextstate pp_dbstate
  pp_return pp_leavesub pp_list pp_pushmark 
  pp_anonlist
  );

%need_curcop     = init_hash qw(pp_rv2gv pp_bless pp_repeat pp_sort pp_caller
  pp_reset pp_rv2cv pp_entereval pp_require pp_dofile
  pp_entertry pp_enterloop pp_enteriter pp_entersub pp_entergiven
  pp_enter pp_method);
%ignore_op = init_hash qw(pp_scalar pp_regcmaybe pp_lineseq pp_scope pp_null);

{ # block necessary for caller to work
  my $caller = caller;
  if ( $caller eq 'O' ) {
    require XSLoader;
    XSLoader::load('B::C'); # for r-magic only
  }
}

sub debug {
  if ( $debug{runtime} ) {
    # TODO: fix COP to callers line number
    warn(@_) if $verbose;
  }
  else {
    my @tmp = @_;
    runtime( map { chomp; "/* $_ */" } @tmp );
  }
}

sub declare {
  my ( $type, $var ) = @_;
  push( @{ $declare_ref->{$type} }, $var );
}

sub push_runtime {
  push( @$runtime_list_ref, @_ );
  warn join( "\n", @_ ) . "\n" if $debug{runtime};
}

sub save_runtime {
  push( @pp_list, [ $ppname, $runtime_list_ref, $declare_ref ] );
}

sub output_runtime {
  my $ppdata;
  print qq(\n#include "cc_runtime.h"\n);
  # CC coverage: 12, 32

  # Perls >=5.8.9 have a broken PP_ENTERTRY. See PERL_FLEXIBLE_EXCEPTIONS in cop.h
  # Fixed in CORE with 5.11.4
  print'
#undef PP_ENTERTRY
#define PP_ENTERTRY(label)  	        \
	STMT_START {                    \
	    int ret;			\
	    JMPENV_PUSH(ret);		\
	    switch (ret) {		\
		case 1: JMPENV_POP; JMPENV_JUMP(1);\
		case 2: JMPENV_POP; JMPENV_JUMP(2);\
		case 3: JMPENV_POP; SPAGAIN; goto label;\
	    }                                      \
	} STMT_END' 
    if $entertry_defined and $] < 5.011004;
  # XXX need to find out when PERL_FLEXIBLE_EXCEPTIONS were actually active.
  # 5.6.2 not, 5.8.9 not. coverage 32

  # test 12. Used by entereval + dofile
  if ($PERL510 or $MULTI) {
    # Threads error Bug#55302: too few arguments to function
    # CALLRUNOPS()=>CALLRUNOPS(aTHX)
    # fixed with 5.11.4
    print '
#undef  PP_EVAL
#define PP_EVAL(ppaddr, nxt) do {		\
	int ret;				\
        PUTBACK;				\
	JMPENV_PUSH(ret);			\
	switch (ret) {				\
	case 0:					\
	    PL_op = ppaddr(aTHX);		\\';
    if ($PERL510) {
      # pp_leaveeval sets: retop = cx->blk_eval.retop
      print '
	    cxstack[cxstack_ix].blk_eval.retop = Nullop; \\';
    } else {
      # up to 5.8 pp_entereval did set the retstack to next.
      # nullify that so that we can now exec the rest of this bblock.
      # (nextstate .. leaveeval)
      print '
	    PL_retstack[PL_retstack_ix - 1] = Nullop;  \\';
    }
    print '
	    if (PL_op != nxt) CALLRUNOPS(aTHX);	\
	    JMPENV_POP;				\
	    break;				\
	case 1: JMPENV_POP; JMPENV_JUMP(1);	\
	case 2: JMPENV_POP; JMPENV_JUMP(2);	\
	case 3:					\
            JMPENV_POP; 			\
	    if (PL_restartop && PL_restartop != nxt) \
		JMPENV_JUMP(3);			\
        }                                       \
	PL_op = nxt;                            \
	SPAGAIN;                                \
    } while (0)
';
  }

  # Perl_vivify_ref not exported on MSWin32
  # coverage: 18
  if ($PERL510 and $^O eq 'MSWin32') {
    # CC coverage: 18, 29
    print << '__EOV' if $vivify_ref_defined;

/* Code to take a scalar and ready it to hold a reference */
#  ifndef SVt_RV
#    define SVt_RV   SVt_IV
#  endif
#  define prepare_SV_for_RV(sv)						\
    STMT_START {							\
		    if (SvTYPE(sv) < SVt_RV)				\
			sv_upgrade(sv, SVt_RV);				\
		    else if (SvPVX_const(sv)) {				\
			SvPV_free(sv);					\
			SvLEN_set(sv, 0);				\
                        SvCUR_set(sv, 0);				\
		    }							\
		 } STMT_END

#if (PERL_VERSION > 15) || ((PERL_VERSION == 15) && (PERL_SUBVERSION >= 2))
SV*
#else
void
#endif
Perl_vivify_ref(pTHX_ SV *sv, U32 to_what)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) {
	if (SvREADONLY(sv))
	    Perl_croak(aTHX_ "%s", PL_no_modify);
	prepare_SV_for_RV(sv);
	switch (to_what) {
	case OPpDEREF_SV:
	    SvRV_set(sv, newSV(0));
	    break;
	case OPpDEREF_AV:
	    SvRV_set(sv, newAV());
	    break;
	case OPpDEREF_HV:
	    SvRV_set(sv, newHV());
	    break;
	}
	SvROK_on(sv);
	SvSETMAGIC(sv);
    }
}

__EOV

  }

    print '

OP *Perl_pp_aelem_nolval(pTHXx);
#ifndef SVfARG
# define SVfARG(x) (void *)x
#endif
#ifndef MUTABLE_AV
# define MUTABLE_AV(av) av
#endif
PP(pp_aelem_nolval)
{
    dSP;
    SV** svp;
    SV* const elemsv = POPs;
    IV elem = SvIV(elemsv);
    AV *const av = MUTABLE_AV(POPs);
    SV *sv;

#if PERL_VERSION > 6
    if (SvROK(elemsv) && !SvGAMAGIC(elemsv) && ckWARN(WARN_MISC))
        Perl_warner(aTHX_ packWARN(WARN_MISC),
                    "Use of reference \"%"SVf"\" as array index",
                    SVfARG(elemsv));
#endif
    if (SvTYPE(av) != SVt_PVAV)	RETPUSHUNDEF;
    svp = av_fetch(av, elem, 0);
    sv = (svp ? *svp : &PL_sv_undef);
    if (SvRMAGICAL(av) && SvGMAGICAL(sv)) mg_get(sv);
    PUSHs(sv);
    RETURN;
}
' if 0;

  foreach $ppdata (@pp_list) {
    my ( $name, $runtime, $declare ) = @$ppdata;
    print "\nstatic\nCCPP($name)\n{\n";
    my ( $type, $varlist, $line );
    while ( ( $type, $varlist ) = each %$declare ) {
      $varlist = $declare->{$type};
      print "\t$type ", join( ", ", @$varlist ), ";\n";
    }
    foreach $line (@$runtime) {
      print $line, "\n";
    }
    print "}\n";
  }
}

sub runtime {
  my $line;
  foreach $line (@_) {
    push_runtime("\t$line");
  }
}

sub init_pp {
  $ppname           = shift;
  $runtime_list_ref = [];
  $declare_ref      = {};
  runtime("dSP;");
  declare( "I32", "oldsave" );
  map { declare( "SV", "*$_" ) } qw(sv src dst left right);
  declare( "MAGIC", "*mg" );
  $decl->add( "#undef cxinc", "#define cxinc() Perl_cxinc(aTHX)")
    if $] < 5.011001 and $inline_ops;
  declare( "PERL_CONTEXT", "*cx" );
  declare( "I32", "gimme");
  $decl->add("static OP * $ppname (pTHX);");
  debug "init_pp: $ppname\n" if $debug{queue};
}

# Initialise runtime_callback function for Stackobj class
BEGIN { B::Stackobj::set_callback( \&runtime ) }

=head2 cc_queue

Creates a new ccpp optree.

Initialised by saveoptree_callback in L<B::C>, replaces B::C::walk_and_save_optree.
Called by every C<CV::save> if ROOT.
B<blocksort> also creates its block closure with cc_queue.

=cut

# coverage: test 18, 28 (fixed with B-C-1.30 r971)
sub cc_queue {
  my ( $name, $root, $start, @pl ) = @_;
  debug "cc_queue: name $name, root $root, start $start, padlist (@pl)\n"
    if $debug{queue};
  if ( $name eq "*ignore*" or $name =~ /^pp_sub_.*(FETCH|MODIFY)_SCALAR_ATTRIBUTES$/) {
    $name = '';
  } else {
    push( @cc_todo, [ $name, $root, $start, ( @pl ? @pl : @padlist ) ] );
  }
  my $fakeop_next = 0;
  if ($name =~ /^pp_sub_.*DESTROY$/) {
    # curse in sv_clean_objs() checks for ->op_next->op_type
    $fakeop_next = $start->next->save;
  }
  my $fakeop = B::FAKEOP->new( "next" => $fakeop_next, ppaddr => $name );
  $start = $fakeop->save;
  debug "cc_queue: name $name returns $start\n" if $debug{queue};
  return $start;
}
BEGIN { B::C::set_callback( \&cc_queue ) }

sub valid_int     { $_[0]->{flags} & VALID_INT }
sub valid_double  { $_[0]->{flags} & VALID_NUM }
sub valid_numeric { $_[0]->{flags} & ( VALID_INT | VALID_NUM ) }
sub valid_str     { $_[0]->{flags} & VALID_STR }
sub valid_sv      { $_[0]->{flags} & VALID_SV }

sub top_int     { @stack ? $stack[-1]->as_int     : "TOPi" }
sub top_double  { @stack ? $stack[-1]->as_double  : "TOPn" }
sub top_numeric { @stack ? $stack[-1]->as_numeric : "TOPn" }
sub top_sv      { @stack ? $stack[-1]->as_sv      : "TOPs" }
sub top_str     { @stack ? $stack[-1]->as_str     : "TOPs" }
sub top_bool    { @stack ? $stack[-1]->as_bool    : "SvTRUE(TOPs)" }

sub pop_int     { @stack ? ( pop @stack )->as_int     : "POPi" }
sub pop_double  { @stack ? ( pop @stack )->as_double  : "POPn" }
sub pop_numeric { @stack ? ( pop @stack )->as_numeric : "POPn" }
sub pop_str     { @stack ? ( pop @stack )->as_str      : "POPs" }
sub pop_sv      { @stack ? ( pop @stack )->as_sv      : "POPs" }

sub pop_bool {
  if (@stack) {
    return ( ( pop @stack )->as_bool );
  }
  else {
    # Careful: POPs has an auto-decrement and SvTRUE evaluates
    # its argument more than once.
    runtime("sv = POPs;");
    return "SvTRUE(sv)";
  }
}

sub write_back_lexicals {
  my $avoid = shift || 0;
  debug "write_back_lexicals($avoid) called from @{[(caller(1))[3]]}\n"
    if $debug{shadow};
  my $lex;
  foreach $lex (@pad) {
    next unless ref($lex);
    $lex->write_back unless $lex->{flags} & $avoid;
  }
}

=head1 save_or_restore_lexical_state

The compiler tracks state of lexical variables in @pad to generate optimised
code. But multiple execution paths lead to the entry point of a basic block.
The state of the first execution path is saved and all other execution
paths are restored to the state of the first one.

Missing flags are regenerated by loading values.

Added flags must are removed; otherwise the compiler would be too optimistic,
hence generating code which doesn't match state of the other execution paths.

=cut

sub save_or_restore_lexical_state {
  my $bblock = shift;
  unless ( exists $lexstate{$bblock} ) {
    foreach my $lex (@pad) {
      next unless ref($lex);
      ${ $lexstate{$bblock} }{ $lex->{iv} } = $lex->{flags};
    }
  }
  else {
    foreach my $lex (@pad) {
      next unless ref($lex);
      my $old_flags = ${ $lexstate{$bblock} }{ $lex->{iv} };
      next if ( $old_flags eq $lex->{flags} );
      my $changed = $old_flags ^ $lex->{flags};
      if ( $changed & VALID_SV ) {
        ( $old_flags & VALID_SV ) ? $lex->write_back : $lex->invalidate;
      }
      if ( $changed & VALID_NUM ) {
        ( $old_flags & VALID_NUM ) ? $lex->load_double : $lex->invalidate_double;
      }
      if ( $changed & VALID_INT ) {
        ( $old_flags & VALID_INT ) ? $lex->load_int : $lex->invalidate_int;
      }
      if ( $changed & VALID_STR ) {
        ( $old_flags & VALID_STR ) ? $lex->load_str : $lex->invalidate_str;
      }
    }
  }
}

sub write_back_stack {
  debug "write_back_stack() ".scalar(@stack)." called from @{[(caller(1))[3]]}\n"
    if $debug{shadow};
  return unless @stack;
  runtime( sprintf( "EXTEND(sp, %d);", scalar(@stack) ) );
  foreach my $obj (@stack) {
    runtime( sprintf( "PUSHs((SV*)%s);", $obj->as_sv ) );
  }
  @stack = ();
}

sub invalidate_lexicals {
  my $avoid = shift || 0;
  debug "invalidate_lexicals($avoid) called from @{[(caller(1))[3]]}\n"
    if $debug{shadow};
  my $lex;
  foreach $lex (@pad) {
    next unless ref($lex);
    $lex->invalidate unless $lex->{flags} & $avoid;
  }
}

sub reload_lexicals {
  my $lex;
  foreach $lex (@pad) {
    next unless ref($lex);
    my $type = $lex->{type};
    if ( $type == T_INT ) {
      $lex->as_int;
    }
    elsif ( $type == T_NUM ) {
      $lex->as_double;
    }
    elsif ( $type == T_STR ) {
      $lex->as_str;
    }
    else {
      $lex->as_sv;
    }
  }
}

{

  package B::Pseudoreg;

  #
  # This class allocates pseudo-registers (OK, so they're C variables).
  #
  my %alloc;   # Keyed by variable name. A value of 1 means the
               # variable has been declared. A value of 2 means
               # it's in use.

  sub new_scope { %alloc = () }

  sub new ($$$) {
    my ( $class, $type, $prefix ) = @_;
    my ( $ptr, $i, $varname, $status, $obj );
    $prefix =~ s/^(\**)//;
    $ptr = $1;
    $i   = 0;
    do {
      $varname = "$prefix$i";
      $status  = exists $alloc{$varname} ? $alloc{$varname} : 0;
    } while $status == 2;

    if ( $status != 1 ) {
      # Not declared yet
      B::CC::declare( $type, "$ptr$varname" );
      $alloc{$varname} = 2;    # declared and in use
    }
    $obj = bless \$varname, $class;
    return $obj;
  }

  sub DESTROY {
    my $obj = shift;
    $alloc{$$obj} = 1;         # no longer in use but still declared
  }
}
{

  package B::Shadow;

  #
  # This class gives a standard API for a perl object to shadow a
  # C variable and only generate reloads/write-backs when necessary.
  #
  # Use $obj->load($foo) instead of runtime("shadowed_c_var = foo").
  # Use $obj->write_back whenever shadowed_c_var needs to be up to date.
  # Use $obj->invalidate whenever an unknown function may have
  # set shadow itself.

  sub new {
    my ( $class, $write_back ) = @_;

    # Object fields are perl shadow variable, validity flag
    # (for *C* variable) and callback sub for write_back
    # (passed perl shadow variable as argument).
    bless [ undef, 1, $write_back ], $class;
  }

  sub load {
    my ( $obj, $newval ) = @_;
    $obj->[1] = 0;         # C variable no longer valid
    $obj->[0] = $newval;
  }

  sub value {
    return $_[0]->[0];
  }

  sub write_back {
    my $obj = shift;
    if ( !( $obj->[1] ) ) {
      $obj->[1] = 1;       # C variable will now be valid
      &{ $obj->[2] }( $obj->[0] );
    }
  }
  sub invalidate { $_[0]->[1] = 0 }    # force C variable to be invalid
}

my $curcop = B::Shadow->new(
  sub {
    my $op = shift;
    my $opsym = $op->save;
    runtime("PL_curcop = (COP*)$opsym;");
  }
);

#
# Context stack shadowing. Mimics stuff in pp_ctl.c, cop.h and so on.
#
sub dopoptoloop {
  my $cxix = $#cxstack;
  while ( $cxix >= 0 && CxTYPE_no_LOOP( $cxstack[$cxix] ) ) {
    $cxix--;
  }
  debug "dopoptoloop: returning $cxix" if $debug{cxstack};
  return $cxix;
}

sub dopoptolabel {
  my $label = shift;
  my $cxix  = $#cxstack;
  while (
    $cxix >= 0
    && ( CxTYPE_no_LOOP( $cxstack[$cxix] )
      || $cxstack[$cxix]->{label} ne $label )
    )
  {
    $cxix--;
  }
  debug "dopoptolabel: returning $cxix\n" if $debug{cxstack};
  if ($cxix < 0 and $debug{cxstack}) {
    for my $cx (0 .. $#cxstack) {
      debug "$cx: ",$cxstack[$cx]->{label},"\n";
    }
    for my $op (keys %{$labels->{label}}) {
      debug $labels->{label}->{$op},"\n";
    }
  }
  return $cxix;
}

sub push_label {
  my $op = shift;
  my $type = shift;
  push @{$labels->{$type}}, ( $op );
}

sub pop_label {
  my $type = shift;
  my $op = pop @{$labels->{$type}};
  write_label ($op); # avoids duplicate labels
}

sub error {
  my $format = shift;
  my $file   = $curcop->[0]->file;
  my $line   = $curcop->[0]->line;
  $errors++;
  if (@_) {
    warn sprintf( "ERROR at %s:%d: $format\n", $file, $line, @_ );
  }
  else {
    warn sprintf( "ERROR at %s:%d: %s\n", $file, $line, $format );
  }
}

# run-time eval is too late for attrs being checked by perlcore. BEGIN does not help.
# use types is the right approach. But until types is fixed we use this hack.
# Note that we also need a new CHECK_SCALAR_ATTRIBUTES hook, starting with v5.22.
sub init_type_attrs {
  eval q[

  our $valid_attr = '^(int|num|str|double|string|unsigned|register|temporary|ro|readonly|const)$';
  sub MODIFY_SCALAR_ATTRIBUTES {
    my $pkg = shift;
    my $v = shift;
    my $attr = $B::CC::valid_attr;
    $attr =~ s/\b$pkg\b//;
    if (my @bad = grep !/$attr/, @_) {
      return @bad;
    } else {
      no strict 'refs';
      push @{"$pkg\::$v\::attributes"}, @_; # create a magic glob
      return ();
    }
  }
  sub FETCH_SCALAR_ATTRIBUTES {
    my ($pkg, $v) = @_;
    no strict 'refs';
    return @{"$pkg\::$v\::attributes"};
  }

  # pollute our callers namespace for attributes to be accepted with -MB::CC
  *main::MODIFY_SCALAR_ATTRIBUTES = \&B::CC::MODIFY_SCALAR_ATTRIBUTES;
  *main::FETCH_SCALAR_ATTRIBUTES  = \&B::CC::FETCH_SCALAR_ATTRIBUTES;

  # my int $i : register : ro;
  *int::MODIFY_SCALAR_ATTRIBUTES = \&B::CC::MODIFY_SCALAR_ATTRIBUTES;
  *int::FETCH_SCALAR_ATTRIBUTES  = \&B::CC::FETCH_SCALAR_ATTRIBUTES;

  # my double $d : ro;
  *num::MODIFY_SCALAR_ATTRIBUTES = \&B::CC::MODIFY_SCALAR_ATTRIBUTES;
  *num::FETCH_SCALAR_ATTRIBUTES  = \&B::CC::FETCH_SCALAR_ATTRIBUTES;
  *str::MODIFY_SCALAR_ATTRIBUTES = \&B::CC::MODIFY_SCALAR_ATTRIBUTES;
  *str::FETCH_SCALAR_ATTRIBUTES  = \&B::CC::FETCH_SCALAR_ATTRIBUTES;

  # deprecated:
  *double::MODIFY_SCALAR_ATTRIBUTES = \&B::CC::MODIFY_SCALAR_ATTRIBUTES;
  *double::FETCH_SCALAR_ATTRIBUTES  = \&B::CC::FETCH_SCALAR_ATTRIBUTES;
  *string::MODIFY_SCALAR_ATTRIBUTES = \&B::CC::MODIFY_SCALAR_ATTRIBUTES;
  *string::FETCH_SCALAR_ATTRIBUTES  = \&B::CC::FETCH_SCALAR_ATTRIBUTES;
  ];

}

=head2 load_pad

Load pad takes (the elements of) a PADLIST as arguments and loads up @pad
with Stackobj-derived objects which represent those lexicals.

If/when perl itself can generate type information C<(my int $foo; my $foo : int)> then we'll
take advantage of that here. Until then, we'll use the L<-fname-magic/-fno-name-magic>
hack to tell the compiler when we want a lexical to be a particular type or to be a register.

=cut

sub load_pad {
  my ( $namelistav, $valuelistav ) = @_;
  @padlist = @_;
  my @namelist  = $namelistav->ARRAY;
  my @valuelist = $valuelistav->ARRAY;
  my $ix;
  @pad = ();
  debug "load_pad: $#namelist names, $#valuelist values\n" if $debug{pad};

  # Temporary lexicals don't get named so it's possible for @valuelist
  # to be strictly longer than @namelist. We count $ix up to the end of
  # @valuelist but index into @namelist for the name. Any temporaries which
  # run off the end of @namelist will make $namesv undefined and we treat
  # that the same as having an explicit SPECIAL sv_undef object in @namelist.
  # [XXX If/when @_ becomes a lexical, we must start at 0 here.]
  for ( $ix = 1 ; $ix < @valuelist ; $ix++ ) {
    my $namesv = $namelist[$ix];
    my $type   = T_UNKNOWN;
    my $flags  = 0;
    my $name   = "tmp";
    my $class  = B::class($namesv);
    if ( !defined($namesv) || $class eq "SPECIAL" ) {
      # temporaries have &PL_sv_undef instead of a PVNV for a name
      $flags = VALID_SV | TEMPORARY | REGISTER;
    }
    else {
      my ($nametry) = $namesv->PV =~ /^\$(.+)$/ if $namesv->PV;
      $name = $nametry if $nametry;

      # my int $i; my num $d; compiled code only, unless the source provides the int and num packages.
      # With Ctypes it is easier. my c_int $i; defines an external Ctypes int, which can be efficiently
      # compiled in Perl also.
      # XXX Better use attributes, like my $i:int; my $d:num; which works un-compiled also.
      if (ref($namesv) eq 'B::PVMG' and ref($namesv->SvSTASH) eq 'B::HV') { # my int
        $class = $namesv->SvSTASH->NAME;
        if ($class eq 'int') {
          $type  = T_INT;
          $flags = VALID_SV | VALID_INT;
        }
        elsif ($class eq 'num' or $class eq 'double') { # my num
          $type  = T_NUM;
          $flags = VALID_SV | VALID_NUM;
        }
        elsif ($class eq 'str' or $class eq 'string') { # my str
          $type  = T_STR;
          $flags = VALID_SV | VALID_STR;
        }
        #elsif ($class eq 'c_int') {  # use Ctypes;
        #  $type  = T_INT;
        #  $flags = VALID_SV | VALID_INT;
        #}
        #elsif ($class eq 'c_double') {
        #  $type  = T_NUM;
        #  $flags = VALID_SV | VALID_NUM;
        #}
        # TODO: MooseX::Types
      }

      # Valid scalar type attributes:
      #   int num str ro readonly const unsigned
      # Note: PVMG from above also.
      # Typed arrays and hashes later.
      if (0 and $class =~ /^(I|P|S|N)V/
	  and $opt_type_attr
	  and UNIVERSAL::can($class,"CHECK_SCALAR_ATTRIBUTES")) # with 5.18
      {
        require attributes;
        #my $svtype = uc reftype ($namesv);
        # test 105
        my @attr = attributes::get(\$namesv); # how to get em from B? see optimize
        warn "\$$name attrs: ".@attr if $verbose or $debug{pad};
        #my $valid_types = ${"$class\::valid_attr"}; # They ARE valid, parser checked already.
      }

      # XXX We should try Devel::TypeCheck for type inference also

      # magic names: my $i_ir, my $d_d. without -fno-name-magic cmdline option only
      if ( $type == T_UNKNOWN and $opt_name_magic and $name =~ /^(.*)_([dis])(r?)$/ ) {
        $name = $1;
        if ( $2 eq "i" ) {
          $type  = T_INT;
          $flags = VALID_SV | VALID_INT;
        }
        elsif ( $2 eq "d" ) {
          $type  = T_NUM;
          $flags = VALID_SV | VALID_NUM;
        }
        elsif ( $2 eq "s" ) {
          $type  = T_STR;
          $flags = VALID_SV | VALID_STR;
        }
        $flags |= REGISTER if $3;
      }
    }
    $name = "${ix}_$name";
    # comppadname bug with overlong strings
    if ($] < 5.008008 and length($name) > 100 and $name =~ /\0\0/) {
      my $i = index($name,"\0");
      $name = substr($name,0,$i) if $i > -1;
    }
    $pad[$ix] =
      B::Stackobj::Padsv->new( $type, $flags, $ix, "i$name", "d$name" );

    debug sprintf( "PL_curpad[$ix] = %s\n", $pad[$ix]->peek ) if $debug{pad};
  }
}

sub declare_pad {
  my $ix;
  for ( $ix = 1 ; $ix <= $#pad ; $ix++ ) {
    my $type = $pad[$ix]->{type};
    declare( "IV",
      $type == T_INT ? sprintf( "%s=0", $pad[$ix]->{iv} ) : $pad[$ix]->{iv} )
      if $pad[$ix]->save_int;
    declare( "NV",
      $type == T_NUM
        ? sprintf( "%s = 0", $pad[$ix]->{nv} )
        : $pad[$ix]->{nv} )
      if $pad[$ix]->save_double;
    declare( "PV",
      $type == T_STR
        ? sprintf( "%s = 0", $pad[$ix]->{sv} )
        : $pad[$ix]->{sv} )
      if $pad[$ix]->save_str;
  }
}

# for cc: unique ascii representation of an utf8 string, for labels
sub encode_utf8($) {
  my $l = shift;
  if ($] > 5.007 and utf8::is_utf8($l)) {
    #  utf8::encode($l);
    #  $l =~ s/([\x{0100}-\x{ffff}])/sprintf("u%x", $1)/ge;
    #$l = substr(B::cstring($l), 1, -1);
    #$l =~ s/\\/u/g;
    $l = join('', map { $_ < 127 ? $_ : sprintf("u_%x_", $_) } unpack("U*", $l));
  }
  return $l;
}

#
# Debugging stuff
#
sub peek_stack {
  sprintf "stack = %s\n", join( " ", map( $_->minipeek, @stack ) );
}

#
# OP stuff
#

=head2 label

We not only mark named labels in C as such - with prefix "label_".

We also have to mark each known (back jumps) and yet unknown branch targets
(forward jumps) for compile-time generated branch points, with the "lab_"
prefix.

=cut

sub label {
  my $op = shift;
  # Preserve original label name for "real" labels
  if ($op->can("label") and $op->label) {
    my $l = encode_utf8 $op->label;
    # cc should error on duplicate named labels
    return sprintf( "label_%s_%x", $l, $$op);
  } else {
    return sprintf( "lab_%x", $$op );
  }
}

sub write_label {
  my $op = shift;
  $op->save if $$op;
  # debug sprintf("lab_%x:?\n", $$op) if $debug{cxstack};
  unless ($labels->{label}->{$$op}) {
    my $l = label($op);
    # named label but op not yet known?
    if ( $op->can("label") and $op->label ) {
      $l = "label_" . encode_utf8 $op->label;
      # only print first such label. test 21
      push_runtime(sprintf( "  %s:", $l))
	unless $labels->{label}->{$l};
      $labels->{label}->{$l} = $$op;
    }
    if ($verbose) {
      push_runtime(sprintf( "  %s:\t/* %s */", label($op), $op->name ));
    } else {
      push_runtime(sprintf( "  %s:", label($op) ));
    }
    # avoid printing duplicate jump labels
    $labels->{label}->{$$op} = $l;
    if ($op->can("label") and $op->label ) {
      push(@cxstack, {
		      type   => 0,
		      op     => $op,
		      nextop => ((ref($op) eq 'B::LOOP') && $op->nextop) ? $op->nextop : $op,
		      redoop => ((ref($op) eq 'B::LOOP') && $op->redoop) ? $op->redoop : $op,
		      lastop => ((ref($op) eq 'B::LOOP') && $op->lastop) ? $op->lastop : $op,
		      'label' => $op->can("label") && $op->label ? $op->label : $l
		     });
    }
  }
}

sub loadop {
  my $op    = shift;
  my $opsym = $op->save;
  $op_count++; # for statistics
  runtime("PL_op = $opsym;") unless $know_op;
  return $opsym;
}

sub doop {
  my $op     = shift;
  my $ppaddr = $op->ppaddr;
  my $sym    = loadop($op);
  my $ppname = "pp_" . $op->name;
  if ($inline_ops) {
    # inlining direct calls is safe, just CALLRUNOPS for macros not
    $ppaddr = "Perl_".$ppname;
    $no_stack{$ppname}
      ? runtime("PL_op = $ppaddr(aTHX);")
      : runtime("PUTBACK; PL_op = $ppaddr(aTHX); SPAGAIN;");
  } else {
    $no_stack{$ppname}
      ? runtime("PL_op = $ppaddr(aTHX);")
      : runtime("DOOP($ppaddr);");
  }
  $know_op = 1;
  return $sym;
}

sub gimme {
  my $op    = shift;
  my $want = $op->flags & OPf_WANT;
  return ( $want == OPf_WANT_VOID ? G_VOID :
           $want == OPf_WANT_SCALAR ? G_SCALAR :
           $want == OPf_WANT_LIST ? G_ARRAY :
           undef );
}

#
# Code generation for PP code
#

# coverage: 18,19,25,...
sub pp_null {
  my $op = shift;
  $B::C::nullop_count++;
  return $op->next;
}

# coverage: 102
sub pp_stub {
  my $op    = shift;
  my $gimme = gimme($op);
  if ( not defined $gimme ) {
    write_back_stack();
    runtime("if (block_gimme() == G_SCALAR)",
            "\tXPUSHs(&PL_sv_undef);");
  } elsif ( $gimme == G_SCALAR ) {
    my $obj = B::Stackobj::Const->new(sv_undef);
    push( @stack, $obj );
  }
  return $op->next;
}

# coverage: 2,21,28,30
sub pp_unstack {
  my $op = shift;
  @stack = ();
  runtime("PP_UNSTACK;");
  return $op->next;
}

# coverage: 2,21,27,28,30
sub pp_and {
  my $op   = shift;
  my $next = $op->next;
  reload_lexicals();
  unshift( @bblock_todo, $next );
  if ( @stack >= 1 ) {
    my $obj  = pop @stack;
    my $bool = $obj->as_bool;
    write_back_stack();
    save_or_restore_lexical_state($$next);
    if ($bool =~ /POPs/) {
      runtime("sv = $bool;",
	      sprintf("if (!sv) { PUSHs(sv); goto %s;}", label($next)));
    } else {
      runtime(sprintf(
		"if (!$bool) { PUSHs((SV*)%s); goto %s;}", $obj->as_sv, label($next)
	      ));
    }
  }
  else {
    save_or_restore_lexical_state($$next);
    runtime( sprintf( "if (!%s) goto %s;", top_bool(), label($next) ),
      "sp--;" );
  }
  return $op->other;
}

# Nearly identical to pp_and, but leaves stack unchanged.
sub pp_andassign {
  my $op   = shift;
  my $next = $op->next;
  reload_lexicals();
  unshift( @bblock_todo, $next );
  if ( @stack >= 1 ) {
    my $obj  = pop @stack;
    my $bool = $obj->as_bool;
    write_back_stack();
    save_or_restore_lexical_state($$next);
    if ($bool =~ /POPs/) {
      runtime("sv = $bool;",
	      sprintf("PUSHs((SV*)%s); if (!$bool) { goto %s;}",
		      $obj->as_sv, label($next)));
    } else {
      runtime(
	sprintf("PUSHs((SV*)%s); if (!$bool) { goto %s;}",
		$obj->as_sv, label($next)));
    }
  }
  else {
    save_or_restore_lexical_state($$next);
    runtime( sprintf( "if (!%s) goto %s;", top_bool(), label($next) ) );
  }
  return $op->other;
}

# coverage: 28
sub pp_or {
  my $op   = shift;
  my $next = $op->next;
  reload_lexicals();
  unshift( @bblock_todo, $next );
  if ( @stack >= 1 ) {
    my $obj  = pop @stack;
    my $bool = $obj->as_bool;
    write_back_stack();
    save_or_restore_lexical_state($$next);
    if ($bool =~ /POPs/) {
      runtime("sv = $bool;",
	      sprintf("if (sv) { PUSHs(sv); goto %s;}", label($next)));
    } else {
      runtime(
	sprintf("if ($bool) { PUSHs((SV*)%s); goto %s; }", $obj->as_sv, label($next)));
    }
  }
  else {
    save_or_restore_lexical_state($$next);
    runtime( sprintf( "if (%s) goto %s;", top_bool(), label($next) ),
      "sp--;" );
  }
  return $op->other;
}

# Nearly identical to pp_or, but leaves stack unchanged.
sub pp_orassign {
  my $op   = shift;
  my $next = $op->next;
  reload_lexicals();
  unshift( @bblock_todo, $next );
  if ( @stack >= 1 ) {
    my $obj  = pop @stack;
    my $bool = $obj->as_bool;
    write_back_stack();
    save_or_restore_lexical_state($$next);
    runtime(
      sprintf(
        "PUSHs((SV*)%s); if ($bool) { goto %s; }", $obj->as_sv, label($next)
      )
    );
  }
  else {
    save_or_restore_lexical_state($$next);
    runtime( sprintf( "if (%s) goto %s;", top_bool(), label($next) ) );
  }
  return $op->other;
}

# coverage: issue 45 (1,2)
# in CORE aliased to pp_defined
# default dor is okay issue 45 (3,4)
sub pp_dorassign {
  my $op   = shift;
  my $next = $op->next;
  reload_lexicals();
  unshift( @bblock_todo, $next );
  my $sv  = pop @stack;
  write_back_stack();
  save_or_restore_lexical_state($$next);
  runtime( sprintf( "PUSHs(%s); if (%s && SvANY(%s)) goto %s;\t/* dorassign */",
                    $sv->as_sv, $sv->as_sv, $sv->as_sv, label($next)) ) if $sv;
  return $op->other;
}

# coverage: 102
sub pp_cond_expr {
  my $op    = shift;
  my $false = $op->next;
  unshift( @bblock_todo, $false );
  reload_lexicals();
  my $bool = pop_bool();
  write_back_stack();
  save_or_restore_lexical_state($$false);
  runtime( sprintf( "if (!$bool) goto %s;\t/* cond_expr */", label($false) ) );
  return $op->other;
}

# coverage: 9,10,12,17,18,22,28,32
sub pp_padsv {
  my $op = shift;
  my $ix = $op->targ;
  push( @stack, $pad[$ix] ) if $pad[$ix];
  if ( $op->flags & OPf_MOD ) {
    my $private = $op->private;
    if ( $private & OPpLVAL_INTRO ) {
      # coverage: 9,10,12,17,18,19,20,22,27,28,31,32
      runtime("SAVECLEARSV(PL_curpad[$ix]);");
    }
    elsif ( $private & OPpDEREF ) {
      # coverage: 18
      if ($] >= 5.015002) {
	runtime(sprintf( "PL_curpad[%d] = Perl_vivify_ref(aTHX_ PL_curpad[%d], %d);",
			 $ix, $ix, $private & OPpDEREF ));
      } else {
	runtime(sprintf( "Perl_vivify_ref(aTHX_ PL_curpad[%d], %d);",
			 $ix, $private & OPpDEREF ));
      }
      $vivify_ref_defined++;
      $pad[$ix]->invalidate if $pad[$ix];
    }
  }
  return $op->next;
}

# coverage: 1-5,7-14,18-23,25,27-32
sub pp_const {
  my $op = shift;
  my $sv = $op->sv;
  my $obj;

  # constant could be in the pad (under useithreads)
  if ($$sv) {
    $obj = $constobj{$$sv};
    if ( !defined($obj) ) {
      $obj = $constobj{$$sv} = B::Stackobj::Const->new($sv);
    }
  }
  else {
    $obj = $pad[ $op->targ ];
  }
  # XXX looks like method_named has only const as prev op
  if ($op->next
      and $op->next->can('name')
      and $op->next->name eq 'method_named'
     ) {
    $package_pv = svop_or_padop_pv($op);
    debug "save package_pv \"$package_pv\" for method_name\n" if $debug{op};
  }
  push( @stack, $obj );
  return $op->next;
}

# coverage: 1-39, fails in 33
sub pp_nextstate {
  my $op = shift;
  if ($labels->{'nextstate'}->[-1] and $labels->{'nextstate'}->[-1] == $op) {
    debug sprintf("pop_label nextstate: cxstack label %s\n", $curcop->[0]->label) if $debug{cxstack};
    pop_label 'nextstate';
  } else {
    write_label($op);
  }
  $curcop->load($op);
  loadop($op);
  #testcc 48: protect CopFILE_free and CopSTASH_free in END block (#296)
  if ($ppname =~ /^pp_sub_END(_\d+)?$/ and $ITHREADS) {
    runtime("#ifdef USE_ITHREADS",
            "CopFILE((COP*)PL_op) = NULL;");
    if ($] >= 5.018) {
      runtime("CopSTASH_set((COP*)PL_op, NULL);");
    } elsif ($] >= 5.016 and $] <= 5.017) {
      runtime("CopSTASHPV_set((COP*)PL_op, NULL, 0);");
    } else {
      runtime("CopSTASHPV_set((COP*)PL_op, NULL);");
    }
    runtime("#endif");
  }
  @stack = ();
  debug( sprintf( "%s:%d\n", $op->file, $op->line ) ) if $debug{lineno};
  debug( sprintf( "CopLABEL %s\n", $op->label ) ) if $op->label and $debug{cxstack};
  runtime("TAINT_NOT;") if $opt_taint; # TODO Not always needed (resets PL_taint = 0)
  runtime("sp = PL_stack_base + cxstack[cxstack_ix].blk_oldsp;"); # TODO reset sp not needed always
  if ( $freetmps_each_bblock || $freetmps_each_loop ) {
    $need_freetmps = 1;
  }
  else {
    runtime("FREETMPS;"); # TODO Not always needed
  }
  return $op->next;
}

# Like pp_nextstate, but used instead when the debugger is active.
sub pp_dbstate { pp_nextstate(@_) }

#default_pp will handle this:
#sub pp_bless { $curcop->write_back; default_pp(@_) }
#sub pp_repeat { $curcop->write_back; default_pp(@_) }
# The following subs need $curcop->write_back if we decide to support arybase:
# pp_pos, pp_substr, pp_index, pp_rindex, pp_aslice, pp_lslice, pp_splice
#sub pp_caller { $curcop->write_back; default_pp(@_) }

# coverage: ny
sub bad_pp_reset {
  if ($inline_ops) {
    my $op = shift;
    warn "inlining reset\n" if $debug{op};
    $curcop->write_back if $curcop;
    runtime '{ /* pp_reset */';
    runtime '  const char * const tmps = (MAXARG < 1) ? (const char *)"" : POPpconstx;';
    runtime '  sv_reset(tmps, CopSTASH(PL_curcop));}';
    runtime 'PUSHs(&PL_sv_yes);';
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 20
sub pp_regcreset {
  if ($inline_ops) {
    my $op = shift;
    warn "inlining regcreset\n" if $debug{op};
    $curcop->write_back if $curcop;
    runtime 'PL_reginterp_cnt = 0;	/* pp_regcreset */';
    runtime 'TAINT_NOT;' if $opt_taint;
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 103
sub pp_stringify {
  if ($inline_ops and $] >= 5.008) {
    my $op = shift;
    warn "inlining stringify\n" if $debug{op};
    my $sv = top_sv();
    my $ix = $op->targ;
    my $targ = $pad[$ix];
    runtime "sv_copypv(PL_curpad[$ix], $sv);\t/* pp_stringify */";
    $stack[-1] = $targ if @stack;
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 9,10,27
sub bad_pp_anoncode {
  if ($inline_ops) {
    my $op = shift;
    warn "inlining anoncode\n" if $debug{op};
    my $ix = $op->targ;
    my $ppname = "pp_" . $op->name;
    write_back_lexicals() unless $skip_lexicals{$ppname};
    write_back_stack()    unless $skip_stack{$ppname};
    # XXX finish me. this works only with >= 5.10
    runtime '{ /* pp_anoncode */',
	'  CV *cv = MUTABLE_CV(PAD_SV(PL_op->op_targ));',
	'  if (CvCLONE(cv))',
	'    cv = MUTABLE_CV(sv_2mortal(MUTABLE_SV(Perl_cv_clone(aTHX_ cv))));',
	'  EXTEND(SP,1);',
	'  PUSHs(MUTABLE_SV(cv));',
	'}';
    invalidate_lexicals() unless $skip_invalidate{$ppname};
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 35
# XXX TODO get prev op. For now saved in pp_const.
sub pp_method_named {
  my ( $op ) = @_;
  my $name = svop_or_padop_pv($op);
  # The pkg PV is at [PL_stack_base+TOPMARK+1], the previous op->sv->PV.
  my $stash = $package_pv ? $package_pv."::" : "main::";
  $name = $stash . $name;
  if (exists &$name) {
    debug "save method_name \"$name\"\n" if $debug{op};
    svref_2object( \&{$name} )->save;
  } else {
    debug "skip saving non-existing method_name \"$name\"\n" if $debug{op}; #CC 50
  }
  default_pp(@_);
}

# inconsequence: gvs are not passed around on the stack
# coverage: 26,103
sub bad_pp_srefgen {
  if ($inline_ops) {
    my $op = shift;
    warn "inlining srefgen\n" if $debug{op};
    #my $ppname = "pp_" . $op->name;
    #$curcop->write_back;
    #write_back_lexicals() unless $skip_lexicals{$ppname};
    #write_back_stack()    unless $skip_stack{$ppname};
    my $svobj = $stack[-1]->as_sv;
    my $sv = pop_sv();
    # XXX fix me
    runtime "{ /* pp_srefgen */
	SV* rv;
	SV* sv = $sv;";
    # sv = POPs
    #B::svref_2object(\$sv);
    if (($svobj->flags & 0xff) == $SVt_PVLV
	and B::PVLV::LvTYPE($svobj) eq ord('y'))
    {
      runtime 'if (LvTARGLEN(sv))
	    vivify_defelem(sv);
	if (!(sv = LvTARG(sv)))
	    sv = &PL_sv_undef;
	else
	    SvREFCNT_inc_void_NN(sv);';
    }
    elsif (($svobj->flags & 0xff) == $SVt_PVAV) {
      runtime 'if (!AvREAL((const AV *)sv) && AvREIFY((const AV *)sv))
	    av_reify(MUTABLE_AV(sv));
	SvTEMP_off(sv);
	SvREFCNT_inc_void_NN(sv);';
    }
    #elsif ($sv->SvPADTMP && !IS_PADGV(sv)) {
    #  runtime 'sv = newSVsv(sv);';
    #}
    else {
      runtime 'SvTEMP_off(sv);
	SvREFCNT_inc_void_NN(sv);';
    }
    runtime 'rv = sv_newmortal();
	sv_upgrade(rv, SVt_IV);
	SvRV_set(rv, sv);
	SvROK_on(rv);
        PUSHBACK;
	}';
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 9,10,27
#sub pp_refgen

# coverage: 28, 14
sub pp_rv2gv {
  my $op = shift;
  $curcop->write_back if $curcop;
  my $ppname = "pp_" . $op->name;
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  my $sym = doop($op);
  if ( $op->private & OPpDEREF ) {
    $init->add( sprintf("((UNOP *)$sym)->op_first = $sym;") );
    $init->add( sprintf( "((UNOP *)$sym)->op_type = %d;", $op->first->type ) );
  }
  return $op->next;
}

# coverage: 18,19,25
sub pp_sort {
  my $op     = shift;
  #my $ppname = $op->ppaddr;
  if ( $op->flags & OPf_SPECIAL && $op->flags & OPf_STACKED ) {
    # blocksort is awful. E.g. we need to the leading NULL op, invalidates -fcop
    # Ugly surgery required. sort expects as block: pushmark rv2gv leave => enter
    # pp_sort() OP *kid = cLISTOP->op_first->op_sibling;/* skip over pushmark 4 to null */
    #	    kid = cUNOPx(kid)->op_first;		/* pass rv2gv (null'ed) */
    #	    kid = cUNOPx(kid)->op_first;		/* pass leave */
    #
    #3        <0> pushmark s ->4
    #8        <@> sort lKS* ->9
    #4           <0> pushmark s ->5
    #-           <1> null sK/1 ->5
    #-              <1> ex-leave sKP ->-
    #-                 <0> enter s ->-
    #                      some code doing cmp or ncmp
    #            Example with 3 const args: print sort { bla; $b <=> $a } 1,4,3
    #5           <$> const[IV 1] s ->6
    #6           <$> const[IV 4] s ->7
    #7           <$> const[IV 3] s ->8 => sort
    #
    my $root  = $op->first->sibling->first; #leave or null
    my $start = $root->first;  #enter
    warn "blocksort: root=",$root->name,", start=",$start->name,"\n" if $debug{op};
    my $pushmark = $op->first->save; #pushmark sibling to null
    $op->first->sibling->save; #null->first to leave
    $root->save;               #ex-leave
    my $sym = $start->save;    #enter
    my $fakeop = cc_queue( "pp_sort" . sprintf("%x",abs($$op)), $root, $start );
    $init->add( sprintf( "(%s)->op_next = %s;", $sym, $fakeop ) );
  }
  $curcop->write_back;
  write_back_lexicals();
  write_back_stack();
  doop($op);
  return $op->next;
}

# coverage: 2-4,6,7,13,15,21,24,26,27,30,31
sub pp_gv {
  my $op = shift;
  my $gvsym;
  if ($ITHREADS) {
    $gvsym = $pad[ $op->padix ]->as_sv;
    #push @stack, ($pad[$op->padix]);
  }
  else {
    $gvsym = $op->gv->save;
    # XXX
    #my $obj = new B::Stackobj::Const($op->gv);
    #push( @stack, $obj );
  }
  write_back_stack();
  runtime("XPUSHs((SV*)$gvsym);");
  return $op->next;
}

# coverage: 2,3,4,9,11,14,20,21,23,28
sub pp_gvsv {
  my $op = shift;
  my $gvsym;
  if ($ITHREADS) {
    #debug(sprintf("OP name=%s, class=%s\n",$op->name,B::class($op))) if $debug{pad};
    debug( sprintf( "GVSV->padix = %d\n", $op->padix ) ) if $debug{pad};
    $gvsym = $pad[ $op->padix ]->as_sv;
    debug( sprintf( "GVSV->private = 0x%x\n", $op->private ) ) if $debug{pad};
  }
  else {
    $gvsym = $op->gv->save;
  }
  write_back_stack();
  # Expects GV*, not SV* PL_curpad
  $gvsym = "(GV*)$gvsym" if $gvsym =~ /PL_curpad/;
  if ($gvsym eq '(SV*)&PL_sv_undef') {
    runtime("XPUSHs($gvsym);");
  }
  elsif ( $op->private & OPpLVAL_INTRO ) {
    runtime("XPUSHs(save_scalar($gvsym));");
    #my $obj = new B::Stackobj::Const($op->gv);
    #push( @stack, $obj );
  }
  else {
    $PERL510
      ? runtime("XPUSHs(GvSVn($gvsym));")
      : runtime("XPUSHs(GvSV($gvsym));");
  }
  return $op->next;
}

# Check for faster fetch calls. Returns 0 if the fast 'no' is in effect.
sub autovivification {
  if (!$opt_autovivify) {
    return 0;
  } elsif ($INC{'autovivification.pm'}) {
    return _autovivification($curcop->[0]);
  } else {
    return 1;
  }
}

# coverage: 16, issue44
sub pp_aelemfast {
  my $op = shift;
  my ($av, $rmg);
  if ($op->flags & OPf_SPECIAL) {
    my $sv = $pad[ $op->targ ]->as_sv;
    my @c = comppadlist->ARRAY;
    my @p = $c[1]->ARRAY;
    my $lex = $p[ $op->targ ];
    $rmg  = ($lex and ref $lex eq 'B::AV' and ($lex->MAGICAL & SVs_RMG or !$lex->ARRAY)) ? 1 : 0;
    # MUTABLE_AV is only needed to catch compiler const loss
    # $av = $] > 5.01000 ? "MUTABLE_AV($sv)" : $sv;
    $av = "(AV*)$sv";
  } else {
    my $gvsym;
    if ($ITHREADS) { #padop XXX if it's only a OP, no PADOP? t/CORE/op/ref.t test 36
      if ($op->can('padix')) {
        #warn "padix\n";
        $gvsym = $pad[ $op->padix ]->as_sv;
	my @c = comppadlist->ARRAY; # XXX curpad, not comppad!!
	my @p = $c[1]->ARRAY;
	my $lex = $p[ $op->padix ];
	$rmg  = ($lex and ref $lex eq 'B::AV' and ($lex->MAGICAL & SVs_RMG or !$lex->ARRAY)) ? 1 : 0;
      } else {
        $gvsym = 'PL_incgv'; # XXX passes, but need to investigate why. cc test 43 5.10.1
        #write_back_stack();
        #runtime("PUSHs(&PL_sv_undef);");
        #return $op->next;
      }
    }
    else { #svop
      my $gv = $op->gv;
      $gvsym = $gv->save;
      my $gvav = $gv->AV; # test 16, tied gvav
      $rmg  = $] < 5.007 ? 0 : ($gvav and ($gvav->MAGICAL & SVs_RMG  or !$gvav->ARRAY)) ? 1 : 0;
    }
    $av = "GvAV($gvsym)";
  }
  my $ix   = $op->private;
  my $lval = $op->flags & OPf_MOD;
  my $vivify = !$rmg ? autovivification() : 1; # no need to call if $rmg
  debug "aelemfast: vivify=$vivify, rmg=$rmg, lval=$lval, -fautovivify=$opt_autovivify -faelem=$opt_aelem\n" if $debug{pad};
  return _aelem($op, $av, $ix, $lval, $rmg, $vivify);
}

sub _aelem {
  my ($op, $av, $ix, $lval, $rmg, $vivify) = @_;
  if ($opt_aelem and !$rmg and !$vivify and $ix >= 0) {
    push @stack, B::Stackobj::Aelem->new($av, $ix, $lval);
  } else {
    write_back_stack();
    runtime(
      "{ AV* av = (AV*)$av;",
      "  SV** const svp = av_fetch(av, $ix, $lval);",
      "  SV *sv = (svp ? *svp : &PL_sv_undef);",
      (!$lval and $rmg) ? "  if (SvRMAGICAL(av) && SvGMAGICAL(sv)) mg_get(sv);" : "",
      "  PUSHs(sv);",
      "}"
    );
  }
  return $op->next;
}

# coverage: ?
sub pp_aelem {
  my $op = shift;
  my ($ix, $av);
  my $lval = ($op->flags & OPf_MOD or $op->private & (OPpLVAL_DEFER || OPpLVAL_INTRO)) ? 1 : 0;
  my $vivify = autovivification();
  my $rmg = $opt_magic;  # use -fno-magic for the av (2nd stack arg)
  if (@stack >= 1) { # at least ix
    $ix = pop_int(); # TODO: substract CopARYBASE from ix
    if (@stack >= 1) {
      my $avobj = $stack[-1]->as_obj;
      $rmg  = ($avobj and $avobj->MAGICAL & SVs_RMG) ? 1 : 0;
    }
    $av = pop_sv();
    debug "aelem: vivify = $vivify, rmg = $rmg, lval = $lval\n" if $debug{pad};
    return _aelem($op, $av, $ix, $lval, $rmg, $vivify);
  } else {
    if ($lval or $rmg) { # always
      return default_pp($op);
    } else {
      $ix = pop_int(); # TODO: substract CopARYBASE from ix
      $av = pop_sv();
      debug "aelem: vivify = $vivify, rmg = $rmg, lval = $lval\n" if $debug{pad};
      return _aelem($op, $av, $ix, $lval, $rmg, $vivify);
    }
  }
}

# coverage: ?
sub int_binop {
  my ( $op, $operator, $unsigned ) = @_;
  if ( $op->flags & OPf_STACKED ) {
    my $right = pop_int();
    if ( @stack >= 1 ) {
      my $left = top_int();
      $stack[-1]->set_int( &$operator( $left, $right ), $unsigned );
    }
    else {
      my $sv_setxv = $unsigned ? 'sv_setuv' : 'sv_setiv';
      runtime( sprintf( "$sv_setxv(TOPs, %s);", &$operator( "TOPi", $right ) ) );
    }
  }
  else {
    my $targ  = $pad[ $op->targ ];
    my $right = B::Pseudoreg->new( "IV", "riv" );
    my $left  = B::Pseudoreg->new( "IV", "liv" );
    runtime( sprintf( "$$right = %s; $$left = %s;", pop_int(), pop_int ) );
    $targ->set_int( &$operator( $$left, $$right ), $unsigned );
    push( @stack, $targ );
  }
  return $op->next;
}

sub INTS_CLOSED ()    { 0x1 }
sub INT_RESULT ()     { 0x2 }
sub NUMERIC_RESULT () { 0x4 }

# coverage: 101
sub numeric_binop {
  my ( $op, $operator, $flags ) = @_;
  my $force_int = 0;
  $flags = 0 unless $flags;
  $force_int ||= ( $flags & INT_RESULT );
  $force_int ||=
    (    $flags & INTS_CLOSED
      && @stack >= 2
      && valid_int( $stack[-2] )
      && valid_int( $stack[-1] ) );
  if ( $op->flags & OPf_STACKED ) {
    runtime(sprintf("/* %s */", $op->name)) if $verbose;
    my $right = pop_numeric();
    if ( @stack >= 1 ) {
      my $left = top_numeric();
      if ($force_int) {
        $stack[-1]->set_int( &$operator( $left, $right ) );
      }
      else {
        $stack[-1]->set_numeric( &$operator( $left, $right ) );
      }
    }
    else {
      if ($force_int) {
        my $rightruntime = B::Pseudoreg->new( "IV", "riv" );
        runtime( sprintf( "$$rightruntime = %s;", $right ) );
        runtime(
          sprintf(
            "sv_setiv(TOPs, %s);", &$operator( "TOPi", $$rightruntime )
          )
        );
      }
      else {
        my $rightruntime = B::Pseudoreg->new( "NV", "rnv" );
        runtime( sprintf( "$$rightruntime = %s;\t/* %s */", $right, $op->name ) );
        runtime(
          sprintf(
            "sv_setnv(TOPs, %s);", &$operator( "TOPn", $$rightruntime )
          )
        );
      }
    }
  }
  else {
    my $targ = $pad[ $op->targ ];
    $force_int ||= ( $targ->{type} == T_INT );
    if ($force_int) {
      my $right = B::Pseudoreg->new( "IV", "riv" );
      my $left  = B::Pseudoreg->new( "IV", "liv" );
      runtime(
        sprintf( "$$right = %s;", pop_numeric()),
        sprintf( "$$left = %s;\t/* %s */", pop_numeric(), pop_numeric(), $op->name ) );
      $targ->set_int( &$operator( $$left, $$right ) );
    }
    else {
      my $right = B::Pseudoreg->new( "NV", "rnv" );
      my $left  = B::Pseudoreg->new( "NV", "lnv" );
      runtime(
        sprintf( "$$right = %s;", pop_numeric()),
        sprintf( "$$left = %s;\t/* %s */", pop_numeric(), $op->name ) );
      $targ->set_numeric( &$operator( $$left, $$right ) );
    }
    push( @stack, $targ );
  }
  return $op->next;
}

sub numeric_unop {
  my ( $op, $operator, $flags ) = @_;
  my $force_int = 0;
  $force_int ||= ( $flags & INT_RESULT );
  $force_int ||=
    (    $flags & INTS_CLOSED
      && @stack >= 1
      && valid_int( $stack[-1] ) );
  my $targ = $pad[ $op->targ ];
  $force_int ||= ( $targ->{type} == T_INT );
  if ($force_int) {
    my $arg  = B::Pseudoreg->new( "IV", "liv" );
    runtime(sprintf( "$$arg = %s;\t/* %s */",
                     pop_numeric, $op->name ) );
    # XXX set targ?
    $targ->set_int( &$operator( $$arg ) );
  }
  else {
    my $arg  = B::Pseudoreg->new( "NV", "lnv" );
    runtime(sprintf( "$$arg = %s;\t/* %s */",
                     pop_numeric, $op->name ) );
    # XXX set targ?
    $targ->set_numeric( &$operator( $$arg ) );
  }
  push( @stack, $targ );
  return $op->next;
}

# coverage: 18
sub pp_ncmp {
  my ($op) = @_;
  if ( $op->flags & OPf_STACKED ) {
    my $right = pop_numeric();
    if ( @stack >= 1 ) {
      my $left = top_numeric();
      runtime sprintf( "if (%s > %s){\t/* %s */", $left, $right, $op->name );
      $stack[-1]->set_int(1);
      $stack[-1]->write_back();
      runtime sprintf( "}else if (%s < %s ) {", $left, $right );
      $stack[-1]->set_int(-1);
      $stack[-1]->write_back();
      runtime sprintf( "}else if (%s == %s) {", $left, $right );
      $stack[-1]->set_int(0);
      $stack[-1]->write_back();
      runtime sprintf("}else {");
      $stack[-1]->set_sv("&PL_sv_undef");
      runtime "}";
    }
    else {
      my $rightruntime = B::Pseudoreg->new( "NV", "rnv" );
      runtime( sprintf( "$$rightruntime = %s;\t/* %s */", $right, $op->name ) );
      runtime sprintf( qq/if ("TOPn" > %s){/, $rightruntime );
      runtime sprintf("  sv_setiv(TOPs,1);");
      runtime sprintf( qq/}else if ( "TOPn" < %s ) {/, $$rightruntime );
      runtime sprintf("  sv_setiv(TOPs,-1);");
      runtime sprintf( qq/} else if ("TOPn" == %s) {/, $$rightruntime );
      runtime sprintf("  sv_setiv(TOPs,0);");
      runtime sprintf(qq/}else {/);
      runtime sprintf("  sv_setiv(TOPs,&PL_sv_undef;");
      runtime "}";
    }
  }
  else {
    my $targ  = $pad[ $op->targ ];
    my $right = B::Pseudoreg->new( "NV", "rnv" );
    my $left  = B::Pseudoreg->new( "NV", "lnv" );
    runtime(
      sprintf( "$$right = %s; $$left = %s;\t/* %s */",
               pop_numeric(), pop_numeric, $op->name ) );
    runtime sprintf( "if (%s > %s){ /*targ*/", $$left, $$right );
    $targ->set_int(1);
    $targ->write_back();
    runtime sprintf( "}else if (%s < %s ) {", $$left, $$right );
    $targ->set_int(-1);
    $targ->write_back();
    runtime sprintf( "}else if (%s == %s) {", $$left, $$right );
    $targ->set_int(0);
    $targ->write_back();
    runtime sprintf("}else {");
    $targ->set_sv("&PL_sv_undef");
    runtime "}";
    push( @stack, $targ );
  }
  #runtime "return NULL;";
  return $op->next;
}

# coverage: ?
sub sv_binop {
  my ( $op, $operator, $flags ) = @_;
  if ( $op->flags & OPf_STACKED ) {
    my $right = pop_sv();
    if ( @stack >= 1 ) {
      my $left = top_sv();
      if ( $flags & INT_RESULT ) {
        $stack[-1]->set_int( &$operator( $left, $right ) );
      }
      elsif ( $flags & NUMERIC_RESULT ) {
        $stack[-1]->set_numeric( &$operator( $left, $right ) );
      }
      else {
        # XXX Does this work?
        runtime(
          sprintf( "sv_setsv($left, %s);\t/* %s */",
                   &$operator( $left, $right ), $op->name ) );
        $stack[-1]->invalidate;
      }
    }
    else {
      my $f;
      if ( $flags & INT_RESULT ) {
        $f = "sv_setiv";
      }
      elsif ( $flags & NUMERIC_RESULT ) {
        $f = "sv_setnv";
      }
      else {
        $f = "sv_setsv";
      }
      runtime( sprintf( "%s(TOPs, %s);\t/* %s */",
                        $f, &$operator( "TOPs", $right ), $op->name ) );
    }
  }
  else {
    my $targ = $pad[ $op->targ ];
    runtime( sprintf( "right = %s; left = %s;\t/* %s */",
                      pop_sv(), pop_sv, $op->name ) );
    if ( $flags & INT_RESULT ) {
      $targ->set_int( &$operator( "left", "right" ) );
    }
    elsif ( $flags & NUMERIC_RESULT ) {
      $targ->set_numeric( &$operator( "left", "right" ) );
    }
    else {
      # XXX Does this work?
      runtime(sprintf("sv_setsv(%s, %s);",
                      $targ->as_sv, &$operator( "left", "right" ) ));
      $targ->invalidate;
    }
    push( @stack, $targ );
  }
  return $op->next;
}

# coverage: ?
sub bool_int_binop {
  my ( $op, $operator ) = @_;
  my $right = B::Pseudoreg->new( "IV", "riv" );
  my $left  = B::Pseudoreg->new( "IV", "liv" );
  runtime( sprintf( "$$right = %s; $$left = %s;\t/* %s */",
                    pop_int(), pop_int(), $op->name ) );
  my $bool = B::Stackobj::Bool->new( B::Pseudoreg->new( "int", "b" ) );
  $bool->set_int( &$operator( $$left, $$right ) );
  push( @stack, $bool );
  return $op->next;
}

# coverage: ?
sub bool_numeric_binop {
  my ( $op, $operator ) = @_;
  my $right = B::Pseudoreg->new( "NV", "rnv" );
  my $left  = B::Pseudoreg->new( "NV", "lnv" );
  runtime(
    sprintf( "$$right = %s; $$left = %s;\t/* %s */",
             pop_numeric(), pop_numeric(), $op->name ) );
  my $bool = B::Stackobj::Bool->new( B::Pseudoreg->new( "int", "b" ) );
  $bool->set_numeric( &$operator( $$left, $$right ) );
  push( @stack, $bool );
  return $op->next;
}

# coverage: ?
sub bool_sv_binop {
  my ( $op, $operator ) = @_;
  runtime( sprintf( "right = %s; left = %s;\t/* %s */",
                    pop_sv(), pop_sv(), $op->name ) );
  my $bool = B::Stackobj::Bool->new( B::Pseudoreg->new( "int", "b" ) );
  $bool->set_numeric( &$operator( "left", "right" ) );
  push( @stack, $bool );
  return $op->next;
}

# coverage: ?
sub infix_op {
  my $opname = shift;
  return sub { "$_[0] $opname $_[1]" }
}

# coverage: ?
sub prefix_op {
  my $opname = shift;
  return sub { sprintf( "%s(%s)", $opname, join( ", ", @_ ) ) }
}

BEGIN {
  my $plus_op     = infix_op("+");
  my $minus_op    = infix_op("-");
  my $multiply_op = infix_op("*");
  my $divide_op   = infix_op("/");
  my $modulo_op   = infix_op("%");
  my $lshift_op   = infix_op("<<");
  my $rshift_op   = infix_op(">>");
  my $scmp_op     = prefix_op("sv_cmp");
  my $seq_op      = prefix_op("sv_eq");
  my $sne_op      = prefix_op("!sv_eq");
  my $slt_op      = sub { "sv_cmp($_[0], $_[1]) < 0" };
  my $sgt_op      = sub { "sv_cmp($_[0], $_[1]) > 0" };
  my $sle_op      = sub { "sv_cmp($_[0], $_[1]) <= 0" };
  my $sge_op      = sub { "sv_cmp($_[0], $_[1]) >= 0" };
  my $eq_op       = infix_op("==");
  my $ne_op       = infix_op("!=");
  my $lt_op       = infix_op("<");
  my $gt_op       = infix_op(">");
  my $le_op       = infix_op("<=");
  my $ge_op       = infix_op(">=");

  #
  # XXX The standard perl PP code has extra handling for
  # some special case arguments of these operators.
  #
  sub pp_add      { numeric_binop( $_[0], $plus_op ) }
  sub pp_subtract { numeric_binop( $_[0], $minus_op ) }
  sub pp_multiply { numeric_binop( $_[0], $multiply_op ) }
  sub pp_divide   { numeric_binop( $_[0], $divide_op ) }

  sub pp_modulo      { int_binop( $_[0], $modulo_op ) }    # differs from perl's
  # http://perldoc.perl.org/perlop.html#Shift-Operators:
  # If use integer is in force then signed C integers are used,
  # else unsigned C integers are used.
  sub pp_left_shift  { int_binop( $_[0], $lshift_op, VALID_UNSIGNED ) }
  sub pp_right_shift { int_binop( $_[0], $rshift_op, VALID_UNSIGNED ) }
  sub pp_i_add       { int_binop( $_[0], $plus_op ) }
  sub pp_i_subtract  { int_binop( $_[0], $minus_op ) }
  sub pp_i_multiply  { int_binop( $_[0], $multiply_op ) }
  sub pp_i_divide    { int_binop( $_[0], $divide_op ) }
  sub pp_i_modulo    { int_binop( $_[0], $modulo_op ) }

  sub pp_eq { bool_numeric_binop( $_[0], $eq_op ) }
  sub pp_ne { bool_numeric_binop( $_[0], $ne_op ) }
  # coverage: 21
  sub pp_lt { bool_numeric_binop( $_[0], $lt_op ) }
  # coverage: 28
  sub pp_gt { bool_numeric_binop( $_[0], $gt_op ) }
  sub pp_le { bool_numeric_binop( $_[0], $le_op ) }
  sub pp_ge { bool_numeric_binop( $_[0], $ge_op ) }

  sub pp_i_eq { bool_int_binop( $_[0], $eq_op ) }
  sub pp_i_ne { bool_int_binop( $_[0], $ne_op ) }
  sub pp_i_lt { bool_int_binop( $_[0], $lt_op ) }
  sub pp_i_gt { bool_int_binop( $_[0], $gt_op ) }
  sub pp_i_le { bool_int_binop( $_[0], $le_op ) }
  sub pp_i_ge { bool_int_binop( $_[0], $ge_op ) }

  sub pp_scmp { sv_binop( $_[0], $scmp_op, INT_RESULT ) }
  sub pp_slt { bool_sv_binop( $_[0], $slt_op ) }
  sub pp_sgt { bool_sv_binop( $_[0], $sgt_op ) }
  sub pp_sle { bool_sv_binop( $_[0], $sle_op ) }
  sub pp_sge { bool_sv_binop( $_[0], $sge_op ) }
  sub pp_seq { bool_sv_binop( $_[0], $seq_op ) }
  sub pp_sne { bool_sv_binop( $_[0], $sne_op ) }

#  sub pp_sin  { numeric_unop( $_[0], prefix_op("Perl_sin"), NUMERIC_RESULT ) }
#  sub pp_cos  { numeric_unop( $_[0], prefix_op("Perl_cos"), NUMERIC_RESULT ) }
#  sub pp_exp  { numeric_unop( $_[0], prefix_op("Perl_exp"), NUMERIC_RESULT ) }
#  sub pp_abs  { numeric_unop( $_[0], prefix_op("abs") ) }
#  sub pp_negate { numeric_unop( $_[0], sub { "- $_[0]" }; ) }

# pow has special perl logic
##  sub pp_pow  { numeric_binop( $_[0], prefix_op("Perl_pow"), NUMERIC_RESULT ) }
#XXX log and sqrt need to check negative args
#  sub pp_sqrt { numeric_unop( $_[0], prefix_op("Perl_sqrt"), NUMERIC_RESULT ) }
#  sub pp_log  { numeric_unop( $_[0], prefix_op("Perl_log"), NUMERIC_RESULT ) }
#  sub pp_atan2 { numeric_binop( $_[0], prefix_op("Perl_atan2"), NUMERIC_RESULT ) }

}

# coverage: 3,4,9,10,11,12,17,18,20,21,23
sub pp_sassign {
  my $op        = shift;
  my $backwards = $op->private & OPpASSIGN_BACKWARDS;
  debug( sprintf( "sassign->private=0x%x\n", $op->private ) ) if $debug{op};
  my ( $dst, $src );
  runtime("/* pp_sassign */") if $verbose;
  if ( @stack >= 2 ) {
    $dst = pop @stack;
    $src = pop @stack;
    ( $src, $dst ) = ( $dst, $src ) if $backwards;
    my $type = $src->{type};
    if ( $type == T_INT ) {
      $dst->set_int( $src->as_int, $src->{flags} & VALID_UNSIGNED );
    }
    elsif ( $type == T_NUM ) {
      $dst->set_numeric( $src->as_numeric );
    }
    else {
      $dst->set_sv( $src->as_sv );
    }
    push( @stack, $dst );
  }
  elsif ( @stack == 1 ) {
    if ($backwards) {
      my $src  = pop @stack;
      my $type = $src->{type};
      runtime("if (PL_tainting && PL_tainted) TAINT_NOT;") if $opt_taint;
      if ( $type == T_INT ) {
        if ( $src->{flags} & VALID_UNSIGNED ) {
          runtime sprintf( "sv_setuv(TOPs, %s);", $src->as_int );
        }
        else {
          runtime sprintf( "sv_setiv(TOPs, %s);", $src->as_int );
        }
      }
      elsif ( $type == T_NUM ) {
        runtime sprintf( "sv_setnv(TOPs, %s);", $src->as_double );
      }
      else {
        runtime sprintf( "sv_setsv(TOPs, %s);", $src->as_sv );
      }
      runtime("SvSETMAGIC(TOPs);") if $opt_magic;
    }
    else {
      my $dst  = $stack[-1];
      my $type = $dst->{type};
      runtime("sv = POPs;");
      runtime("MAYBE_TAINT_SASSIGN_SRC(sv);") if $opt_taint;
      if ( $type == T_INT ) {
        $dst->set_int("SvIV(sv)");
      }
      elsif ( $type == T_NUM ) {
        $dst->set_double("SvNV(sv)");
      }
      else {
	$opt_magic
	  ? runtime("SvSetMagicSV($dst->{sv}, sv);")
	  : runtime("SvSetSV($dst->{sv}, sv);");
        $dst->invalidate;
      }
    }
  }
  else {
    # empty perl stack, both at run-time
    if ($backwards) {
      runtime("src = POPs; dst = TOPs;");
    }
    else {
      runtime("dst = POPs; src = TOPs;");
    }
    runtime(
      $opt_taint ? "MAYBE_TAINT_SASSIGN_SRC(src);" : "",
      "SvSetSV(dst, src);",
      $opt_magic ? "SvSETMAGIC(dst);" : "",
      "SETs(dst);"
    );
  }
  return $op->next;
}

# coverage: ny
sub pp_preinc {
  my $op = shift;
  if ( @stack >= 1 ) {
    my $obj  = $stack[-1];
    my $type = $obj->{type};
    if ( $type == T_INT || $type == T_NUM ) {
      $obj->set_int( $obj->as_int . " + 1" );
    }
    else {
      runtime sprintf( "PP_PREINC(%s);", $obj->as_sv );
      $obj->invalidate();
    }
  }
  else {
    runtime sprintf("PP_PREINC(TOPs);");
  }
  return $op->next;
}

# coverage: 1-32,35
sub pp_pushmark {
  my $op = shift;
  # runtime(sprintf("/* %s */", $op->name)) if $verbose;
  write_back_stack();
  runtime("PUSHMARK(sp);");
  return $op->next;
}

# coverage: 28
sub pp_list {
  my $op = shift;
  runtime(sprintf("/* %s */", $op->name)) if $verbose;
  write_back_stack();
  my $gimme = gimme($op);
  if ( not defined $gimme ) {
    runtime("PP_LIST(block_gimme());");
  } elsif ( $gimme == G_ARRAY ) {    # sic
    runtime("POPMARK;");        # need this even though not a "full" pp_list
  }
  else {
    runtime("PP_LIST($gimme);");
  }
  return $op->next;
}

# coverage: 6,8,9,10,24,26,27,31,35
sub pp_entersub {
  my $op = shift;
  runtime(sprintf("/* %s */", $op->name)) if $verbose;
  $curcop->write_back if $curcop;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym = doop($op);
  $op->next->save if ${$op->next};
  $op->first->save if ${$op->first} and $op->first->type;
  # sometimes needs an additional check
  my $ck_next = ${$op->next} ? "PL_op != ($sym)->op_next && " : "";
  runtime("while ($ck_next PL_op != (OP*)0 ){",
          "\tPL_op = (*PL_op->op_ppaddr)(aTHX);",
          "\tSPAGAIN;}");
  $know_op = 0;
  invalidate_lexicals( REGISTER | TEMPORARY );
  # B::C::check_entersub($op);
  return $op->next;
}

# coverage: 16,26,35,51,72,73
sub pp_bless {
  my $op = shift;
  $curcop->write_back if $curcop;
  # B::C::check_bless($op);
  default_pp($op);
}


# coverage: ny
sub pp_formline {
  my $op     = shift;
  my $ppname = "pp_" . $op->name;
  runtime(sprintf("/* %s */", $ppname)) if $verbose;
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  my $sym = doop($op);

  # See comment in pp_grepwhile to see why!
  $init->add("((LISTOP*)$sym)->op_first = $sym;");
  runtime("if (PL_op == ((LISTOP*)($sym))->op_first) {");
  save_or_restore_lexical_state( ${ $op->first } );
  runtime( sprintf( "goto %s;", label( $op->first ) ),
           "}");
  return $op->next;
}

# coverage: 2,17,21,28,30
sub pp_goto {
  my $op     = shift;
  my $ppname = "pp_" . $op->name;
  runtime(sprintf("/* %s */", $ppname)) if $verbose;
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  my $sym = doop($op);
  runtime("if (PL_op != ($sym)->op_next && PL_op != (OP*)0){return PL_op;}");
  invalidate_lexicals() unless $skip_invalidate{$ppname};
  return $op->next;
}

# coverage: 1-39, c_argv.t 2
sub pp_enter {
  # XXX fails with simple c_argv.t 2. no cxix. Disabled for now
  if (0 and $inline_ops) {
    my $op = shift;
    runtime(sprintf("/* %s */", $op->name)) if $verbose;
    warn "inlining enter\n" if $debug{op};
    $curcop->write_back if $curcop;
    if (!($op->flags & OPf_WANT)) {
      my $cxix = $#cxstack;
      if ( $cxix >= 0 ) {
        if ( $op->flags & OPf_SPECIAL ) {
          runtime "gimme = block_gimme();";
        } else {
          runtime "gimme = cxstack[cxstack_ix].blk_gimme;";
        }
      } else {
        runtime "gimme = G_SCALAR;";
      }
    } else {
      runtime "gimme = OP_GIMME(PL_op, -1);";
    }
    runtime($] >= 5.011001 and $] < 5.011004
	    ? 'ENTER_with_name("block");' : 'ENTER;',
      "SAVETMPS;",
      "PUSHBLOCK(cx, CXt_BLOCK, SP);");
    return $op->next;
  } else {
    return default_pp(@_);
  }
}

# coverage: ny
sub pp_enterwrite { pp_entersub(@_) }

# coverage: 6,8,9,10,24,26,27,31
sub pp_leavesub {
  my $op = shift;
  my $ppname = "pp_" . $op->name;
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  runtime("if (PL_curstackinfo->si_type == PERLSI_SORT){",
          "\tPUTBACK;return 0;",
          "}");
  doop($op);
  return $op->next;
}

# coverage: ny
sub pp_leavewrite {
  my $op = shift;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym = doop($op);

  # XXX Is this the right way to distinguish between it returning
  # CvSTART(cv) (via doform) and pop_return()?
  #runtime("if (PL_op) PL_op = (*PL_op->op_ppaddr)(aTHX);");
  runtime("SPAGAIN;");
  $know_op = 0;
  invalidate_lexicals( REGISTER | TEMPORARY );
  return $op->next;
}

# coverage: ny
sub pp_entergiven { pp_enterwrite(@_) }
# coverage: ny
sub pp_leavegiven { pp_leavewrite(@_) }

sub doeval {
  my $op = shift;
  $curcop->write_back;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym    = loadop($op);
  my $ppaddr = $op->ppaddr;
  runtime("PP_EVAL($ppaddr, ($sym)->op_next);");
  $know_op = 1;
  invalidate_lexicals( REGISTER | TEMPORARY );
  return $op->next;
}

# coverage: 12
sub pp_entereval { doeval(@_) }
# coverage: ny
sub pp_dofile    { doeval(@_) }

# coverage: 28
#pp_require is protected by pp_entertry, so no protection for it.
sub pp_require {
  my $op = shift;
  $curcop->write_back;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym = doop($op);
  # sometimes needs an additional check
  my $ck_next = ${$op->next} ? "PL_op != ($sym)->op_next && " : "";
  runtime("while ($ck_next PL_op != (OP*)0 ) {", #(test 28).
          "  PL_op = (*PL_op->op_ppaddr)(aTHX);",
          "  SPAGAIN;",
          "}");
  $know_op = 1;
  invalidate_lexicals( REGISTER | TEMPORARY );
  # B::C::check_require($op); # mark package
  return $op->next;
}

# coverage: 32
sub pp_entertry {
  my $op = shift;
  $curcop->write_back;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym = doop($op);
  $entertry_defined = 1;
  my $next = $op->next; # broken in 5.12, fixed in B::C by upgrading BASEOP
  # jump past leavetry
  $next = $op->other->next if $op->can("other"); # before 5.11.4 and after 5.13.8
  my $l = label( $next );
  debug "ENTERTRY label=$l (".ref($op).") ->".$next->name."(".ref($next).")\n";
  runtime(sprintf( "PP_ENTERTRY(%s);", $l));
  if ($next->isa('B::COP')) {
    push_label($next, 'nextstate');
  } else {
    push_label($op->other, 'leavetry') if $op->can("other");
  }
  invalidate_lexicals( REGISTER | TEMPORARY );
  return $op->next;
}

# coverage: 32
sub pp_leavetry {
  my $op = shift;
  pop_label 'leavetry' if $labels->{'leavetry'}->[-1] and $labels->{'leavetry'}->[-1] == $op;
  default_pp($op);
  runtime("PP_LEAVETRY;");
  write_label($op->next);
  return $op->next;
}

# coverage: ny
sub pp_grepstart {
  my $op = shift;
  if ( $need_freetmps && $freetmps_each_loop ) {
    runtime("FREETMPS;");    # otherwise the grepwhile loop messes things up
    $need_freetmps = 0;
  }
  write_back_stack();
  my $sym  = doop($op);
  my $next = $op->next;
  $next->save;
  my $nexttonext = $next->next;
  $nexttonext->save;
  save_or_restore_lexical_state($$nexttonext);
  runtime(
    sprintf( "if (PL_op == (($sym)->op_next)->op_next) goto %s;",
      label($nexttonext) )
  );
  return $op->next->other;
}

# coverage: ny
sub pp_mapstart {
  my $op = shift;
  if ( $need_freetmps && $freetmps_each_loop ) {
    runtime("FREETMPS;");    # otherwise the mapwhile loop messes things up
    $need_freetmps = 0;
  }
  write_back_stack();

  # pp_mapstart can return either op_next->op_next or op_next->op_other and
  # we need to be able to distinguish the two at runtime.
  my $sym  = doop($op);
  my $next = $op->next;
  $next->save;
  my $nexttonext = $next->next;
  $nexttonext->save;
  save_or_restore_lexical_state($$nexttonext);
  runtime(
    sprintf( "if (PL_op == (($sym)->op_next)->op_next) goto %s;",
      label($nexttonext) )
  );
  return $op->next->other;
}

# coverage: ny
sub pp_grepwhile {
  my $op   = shift;
  my $next = $op->next;
  unshift( @bblock_todo, $next );
  write_back_lexicals();
  write_back_stack();
  my $sym = doop($op);

  # pp_grepwhile can return either op_next or op_other and we need to
  # be able to distinguish the two at runtime. Since it's possible for
  # both ops to be "inlined", the fields could both be zero. To get
  # around that, we hack op_next to be our own op (purely because we
  # know it's a non-NULL pointer and can't be the same as op_other).
  $init->add("((LOGOP*)$sym)->op_next = $sym;");
  save_or_restore_lexical_state($$next);
  runtime( sprintf( "if (PL_op == ($sym)->op_next) goto %s;", label($next) ) );
  $know_op = 0;
  return $op->other;
}

# coverage: ny
sub pp_mapwhile { pp_grepwhile(@_) }

# coverage: 24
sub pp_return {
  my $op = shift;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  doop($op);
  runtime( "PUTBACK;", "return PL_op;" );
  $know_op = 0;
  return $op->next;
}

sub nyi {
  my $op = shift;
  warn sprintf( "Warning: %s not yet implemented properly\n", $op->ppaddr );
  return default_pp($op);
}

# coverage: 17
sub pp_range {
  my $op    = shift;
  my $flags = $op->flags;
  if ( !( $flags & OPf_WANT ) ) {
    if ($strict) {
      error("context of range unknown at compile-time\n");
    } else {
      warn("Warning: context of range unknown at compile-time\n");
      runtime('warn("context of range unknown at compile-time");');
    }
    return default_pp($op);
  }
  write_back_lexicals();
  write_back_stack();
  unless ( ( $flags & OPf_WANT ) == OPf_WANT_LIST ) {
    # We need to save our UNOP structure since pp_flop uses
    # it to find and adjust out targ. We don't need it ourselves.
    $op->save;
    save_or_restore_lexical_state( ${ $op->other } );
    runtime sprintf( "if (SvTRUE(PL_curpad[%d])) goto %s;",
      $op->targ, label( $op->other ) );
    unshift( @bblock_todo, $op->other );
  }
  return $op->next;
}

# coverage: 17, 30
sub pp_flip {
  my $op    = shift;
  my $flags = $op->flags;
  if ( !( $flags & OPf_WANT ) ) {
    if ($strict) {
      error("context of flip unknown at compile-time\n");
    } else {
      warn("Warning: context of flip unknown at compile-time\n");
      runtime('warn("context of flip unknown at compile-time");');
    }
    return default_pp($op);
  }
  if ( ( $flags & OPf_WANT ) == OPf_WANT_LIST ) {
    return $op->first->other;
  }
  write_back_lexicals();
  write_back_stack();
  # We need to save our UNOP structure since pp_flop uses
  # it to find and adjust out targ. We don't need it ourselves.
  $op->save;
  my $ix      = $op->targ;
  my $rangeix = $op->first->targ;
  runtime(
    ( $op->private & OPpFLIP_LINENUM )
    ? "if (PL_last_in_gv && SvIV(TOPs) == IoLINES(GvIOp(PL_last_in_gv))) {"
    : "if (SvTRUE(TOPs)) {"
  );
  runtime("\tsv_setiv(PL_curpad[$rangeix], 1);");
  if ( $op->flags & OPf_SPECIAL ) {
    runtime("sv_setiv(PL_curpad[$ix], 1);");
  }
  else {
    save_or_restore_lexical_state( ${ $op->first->other } );
    runtime( "\tsv_setiv(PL_curpad[$ix], 0);",
      "\tsp--;", sprintf( "\tgoto %s;", label( $op->first->other ) ) );
  }
  runtime( "}", qq{sv_setpv(PL_curpad[$ix], "");}, "SETs(PL_curpad[$ix]);" );
  $know_op = 0;
  return $op->next;
}

# coverage: 17
sub pp_flop {
  my $op = shift;
  default_pp($op);
  $know_op = 0;
  return $op->next;
}

sub enterloop {
  my $op     = shift;
  my $nextop = $op->nextop;
  my $lastop = $op->lastop;
  my $redoop = $op->redoop;
  $curcop->write_back if $curcop;
  debug "enterloop: pushing on cxstack\n" if $debug{cxstack};
  push(
    @cxstack,
    {
      type => $PERL512 ? CXt_LOOP_PLAIN : CXt_LOOP,
      op => $op,
      "label" => $curcop->[0]->label,
      nextop  => $nextop,
      lastop  => $lastop,
      redoop  => $redoop
    }
  );
  debug sprintf("enterloop: cxstack label %s\n", $curcop->[0]->label) if $debug{cxstack};
  $nextop->save;
  $lastop->save;
  $redoop->save;
  # We need to compile the corresponding pp_leaveloop even if it's
  # never executed. This is needed to get @cxstack right.
  # Use case:  while(1) { .. }
  unshift @bblock_todo, ($lastop);
  if (0 and $inline_ops and $op->name eq 'enterloop') {
    warn "inlining enterloop\n" if $debug{op};
    # XXX = GIMME_V fails on freebsd7 5.8.8 (28)
    # = block_gimme() fails on the rest, but passes on freebsd7
    runtime "gimme = GIMME_V;"; # XXX
    if ($PERL512) {
      runtime('ENTER_with_name("loop1");',
              'SAVETMPS;',
              'ENTER_with_name("loop2");',
              'PUSHBLOCK(cx, CXt_LOOP_PLAIN, SP);',
              'PUSHLOOP_PLAIN(cx, SP);');
    } else {
      runtime('ENTER;',
              'SAVETMPS;',
              'ENTER;',
              'PUSHBLOCK(cx, CXt_LOOP, SP);',
              'PUSHLOOP(cx, 0, SP);');
    }
    return $op->next;
  } else {
    return default_pp($op);
  }
}

# coverage: 6,21,28,30
sub pp_enterloop { enterloop(@_) }
# coverage: 2
sub pp_enteriter { enterloop(@_) }

# coverage: 6,21,28,30
sub pp_leaveloop {
  my $op = shift;
  if ( !@cxstack ) {
    die "panic: leaveloop, no cxstack";
  }
  debug "leaveloop: popping from cxstack\n" if $debug{cxstack};
  pop(@cxstack);
  return default_pp($op);
}

# coverage: ?
sub pp_next {
  my $op = shift;
  my $cxix;
  if ( $op->flags & OPf_SPECIAL ) {
    $cxix = dopoptoloop();
    if ( $cxix < 0 ) {
      warn "Warning: \"next\" used outside loop\n";
      return default_pp($op); # no optimization
    }
  }
  else {
    my $label = $op->pv;
    if ($label) {
      $cxix = dopoptolabel( $label );
      if ( $cxix < 0 ) {
	# coverage: t/testcc 21
	warn(sprintf("Warning: Label not found at compile time for \"next %s\"\n", $label ));
	$labels->{nlabel}->{$label} = $$op;
	return $op->next;
      }
    }
    # Add support to leave non-loop blocks.
    if ( CxTYPE_no_LOOP( $cxstack[$cxix] ) ) {
      if (!$cxstack[$cxix]->{'nextop'} or !$cxstack[$cxix]->{'label'}) {
	error("Use of \"next\" for non-loop and non-label blocks not yet implemented\n");
      }
    }
  }
  default_pp($op);
  my $nextop = $cxstack[$cxix]->{nextop};
  if ($nextop) {
    push( @bblock_todo, $nextop );
    save_or_restore_lexical_state($$nextop);
    runtime( sprintf( "goto %s;", label($nextop) ) );
  }
  return $op->next;
}

# coverage: ?
sub pp_redo {
  my $op = shift;
  my $cxix;
  if ( $op->flags & OPf_SPECIAL ) {
    $cxix = dopoptoloop();
    if ( $cxix < 0 ) {
      #warn("Warning: \"redo\" used outside loop\n");
      return default_pp($op); # no optimization
    }
  }
  else {
    my $label = $op->pv;
    if ($label) {
      $cxix = dopoptolabel( $label );
      if ( $cxix < 0 ) {
	warn(sprintf("Warning: Label not found at compile time for \"redo %s\"\n", $label ));
	$labels->{nlabel}->{$label} = $$op;
	return $op->next;
      }
    }
    # Add support to leave non-loop blocks.
    if ( CxTYPE_no_LOOP( $cxstack[$cxix] ) ) {
      if (!$cxstack[$cxix]->{'redoop'} or !$cxstack[$cxix]->{'label'}) {
	error("Use of \"redo\" for non-loop and non-label blocks not yet implemented\n");
      }
    }
  }
  default_pp($op);
  my $redoop = $cxstack[$cxix]->{redoop};
  if ($redoop) {
    push( @bblock_todo, $redoop );
    save_or_restore_lexical_state($$redoop);
    runtime( sprintf( "goto %s;", label($redoop) ) );
  }
  return $op->next;
}

# coverage: issue36, cc_last.t
sub pp_last {
  my $op = shift;
  my $cxix;
  if ( $op->flags & OPf_SPECIAL ) {
    $cxix = dopoptoloop();
    if ( $cxix < 0 ) {
      #warn("Warning: \"last\" used outside loop\n");
      return default_pp($op); # no optimization
    }
  }
  elsif (ref($op) eq 'B::PVOP') { # !OPf_STACKED
    my $label = $op->pv;
    if ($label) {
      $cxix = dopoptolabel( $label );
      if ( $cxix < 0 ) {
	# coverage: cc_last.t 2 (ok) 4 (ok)
	warn( sprintf("Warning: Label not found at compile time for \"last %s\"\n", $label ));
	# last does not jump into the future, by name without $$op
	# instead it should jump to the block afterwards
	$labels->{nlabel}->{$label} = $$op;
	return $op->next;
      }
    }
    # Add support to leave non-loop blocks. label fixed with 1.11
    if ( CxTYPE_no_LOOP( $cxstack[$cxix] ) ) {
      if (!$cxstack[$cxix]->{'lastop'} or !$cxstack[$cxix]->{'label'}) {
	error("Use of \"last\" for non-loop and non-label blocks not yet implemented\n");
      }
    }
  }
  default_pp($op);
  if ($cxstack[$cxix]->{lastop} and $cxstack[$cxix]->{lastop}->next) {
    my $lastop = $cxstack[$cxix]->{lastop}->next;
    push( @bblock_todo, $lastop );
    save_or_restore_lexical_state($$lastop);
    runtime( sprintf( "goto %s;", label($lastop) ) );
  }
  return $op->next;
}

# coverage: 3,4
sub pp_subst {
  my $op = shift;
  write_back_lexicals();
  write_back_stack();
  my $sym      = doop($op);
  my $replroot = $op->pmreplroot;
  if ($$replroot) {
    save_or_restore_lexical_state($$replroot);
    runtime sprintf(
      "if (PL_op == ((PMOP*)(%s))%s) goto %s;",
      $sym, $PERL510 ? "->op_pmreplrootu.op_pmreplroot" : "->op_pmreplroot",
      label($replroot)
    );
    $op->pmreplstart->save;
    push( @bblock_todo, $replroot );
  }
  invalidate_lexicals();
  return $op->next;
}

# coverage: 3
sub pp_substcont {
  my $op = shift;
  write_back_lexicals();
  write_back_stack();
  doop($op);
  my $pmop = $op->other;
  #warn sprintf( "substcont: op = %s, pmop = %s\n", peekop($op), peekop($pmop) ) if $verbose;

  #   my $pmopsym = objsym($pmop);
  my $pmopsym = $pmop->save;    # XXX can this recurse?
  # warn "pmopsym = $pmopsym\n" if $verbose;
  save_or_restore_lexical_state( ${ $pmop->pmreplstart } );
  runtime sprintf(
    "if (PL_op == ((PMOP*)(%s))%s) goto %s;",
    $pmopsym,
    $PERL510 ? "->op_pmstashstartu.op_pmreplstart" : "->op_pmreplstart",
    label( $pmop->pmreplstart )
  );
  push( @bblock_todo, $pmop->pmreplstart );
  invalidate_lexicals();
  return $pmop->next;
}

# coverage: issue24
# resolve the DBM library at compile-time, not at run-time
sub pp_dbmopen {
  my $op = shift;
  require AnyDBM_File;
  my $dbm = $AnyDBM_File::ISA[0];
  svref_2object( \&{"$dbm\::bootstrap"} )->save;
  return default_pp($op);
}

sub default_pp {
  my $op     = shift;
  my $ppname = "pp_" . $op->name;
  # runtime(sprintf("/* %s */", $ppname)) if $verbose;
  if ( $curcop and $need_curcop{$ppname} ) {
    $curcop->write_back;
  }
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  doop($op);

  # XXX If the only way that ops can write to a TEMPORARY lexical is
  # when it's named in $op->targ then we could call
  # invalidate_lexicals(TEMPORARY) and avoid having to write back all
  # the temporaries. For now, we'll play it safe and write back the lot.
  invalidate_lexicals() unless $skip_invalidate{$ppname};
  return $op->next;
}

sub compile_op {
  my $op     = shift;
  my $ppname = "pp_" . $op->name;
  if ( exists $ignore_op{$ppname} ) {
    return $op->next;
  }
  debug peek_stack() if $debug{stack};
  if ( $debug{op} ) {
    debug sprintf( "%s [%s]\n",
      peekop($op), $op->flags & OPf_STACKED ? "OPf_STACKED" : $op->targ );
  }
  no strict 'refs';
  if ( defined(&$ppname) ) {
    $know_op = 0;
    return &$ppname($op);
  }
  else {
    return default_pp($op);
  }
}

sub compile_bblock {
  my $op = shift;
  warn "compile_bblock: ", peekop($op), "\n" if $debug{bblock};
  save_or_restore_lexical_state($$op);
  write_label($op);
  $know_op = 0;
  do {
    $op = compile_op($op);
    if ($] < 5.013 and ($opt_slow_signals or ($$op and $async_signals{$op->name}))) {
      runtime("PERL_ASYNC_CHECK();");
    }
  } while ( defined($op) && $$op && !exists( $leaders->{$$op} ) );
  write_back_stack();    # boo hoo: big loss
  reload_lexicals();
  return $op;
}

sub cc {
  my ( $name, $root, $start, @padlist ) = @_;
  my $op;
  if ( $done{$$start} ) {
    warn "repeat=>" . ref($start) . " $name,\n" if $verbose;
    $decl->add( sprintf( "#define $name  %s", $done{$$start} ) );
    return;
  }
  return if ref($padlist[0]) !~ /^B::(AV|PADNAMELIST)$/ or ref($padlist[1]) ne 'B::AV';
  warn "cc $name\n" if $verbose;
  init_pp($name);
  load_pad(@padlist);
  %lexstate = ();
  B::Pseudoreg->new_scope;
  @cxstack = ();
  if ( $debug{timings} ) {
    warn sprintf( "Basic block analysis at %s\n", timing_info );
  }
  $leaders = find_leaders( $root, $start );
  my @leaders = keys %$leaders;
  if ( $#leaders > -1 ) {
    # Don't add basic blocks of dead code.
    # It would produce errors when processing $cxstack.
    # @bblock_todo = ( values %$leaders );
    # Instead, save $root (pp_leavesub) separately,
    # because it will not get compiled if located in dead code.
    $root->save;
    unshift @bblock_todo, ($start) if $$start;
  }
  else {
    runtime("return PL_op?PL_op->op_next:0;");
  }
  if ( $debug{timings} ) {
    warn sprintf( "Compilation at %s\n", timing_info );
  }
  while (@bblock_todo) {
    $op = shift @bblock_todo;
    warn sprintf( "Considering basic block %s\n", peekop($op) ) if $debug{bblock};
    next if !defined($op) || !$$op || $done{$$op};
    warn "...compiling it\n" if $debug{bblock};
    do {
      $done{$$op} = $name;
      $op = compile_bblock($op);
      if ( $need_freetmps && $freetmps_each_bblock ) {
        runtime("FREETMPS;");
        $need_freetmps = 0;
      }
    } while defined($op) && $$op && !$done{$$op};
    if ( $need_freetmps && $freetmps_each_loop ) {
      runtime("FREETMPS;");
      $need_freetmps = 0;
    }
    if ( !$$op ) {
      runtime( "PUTBACK;",
               "return NULL;" );
    }
    elsif ( $done{$$op} ) {
      save_or_restore_lexical_state($$op);
      runtime( sprintf( "goto %s;", label($op) ) );
    }
  }
  if ( $debug{timings} ) {
    warn sprintf( "Saving runtime at %s\n", timing_info );
  }
  declare_pad(@padlist);
  save_runtime();
}

sub cc_recurse {
  my ($ccinfo);
  my $start = cc_queue(@_) if @_;

  while ( $ccinfo = shift @cc_todo ) {
    if ($ccinfo->[0] eq 'pp_sub_warnings__register_categories') {
      # patch broken PADLIST
      #warn "cc $ccinfo->[0] patch broken PADLIST (inc-i340)\n" if $verbose;
      #debug "cc(ccinfo): @$ccinfo skipped (inc-i340)\n" if $debug{queue};
      #$ccinfo->[0] = 'NULL';
      my @empty = ();
      #$ccinfo->[3] = $ccinfo->[4] = svref_2object(\@empty);
    }
    if ($DB::deep and $ccinfo->[0] =~ /^pp_sub_(DB|Term__ReadLine)_/) {
      warn "cc $ccinfo->[0] skipped (debugging)\n" if $verbose;
      debug "cc(ccinfo): @$ccinfo skipped (debugging)\n" if $debug{queue};
    }
    elsif (exists $cc_pp_sub{$ccinfo->[0]}) { # skip duplicates
      warn "cc $ccinfo->[0] already defined\n" if $verbose;
      debug "cc(ccinfo): @$ccinfo already defined\n" if $debug{queue};
      while (exists $cc_pp_sub{$ccinfo->[0]}) {
        if ($ccinfo->[0] =~ /^(pp_(?:lex)?sub_.*_)(\d*)$/) {
          my $s = $2;
          $s++;
          $ccinfo->[0] = $1 . $s;
        } else {
          $ccinfo->[0] .= '_0';
        }
      }
      warn "cc renamed to $ccinfo->[0]\n" if $verbose;
      cc(@$ccinfo);
      $cc_pp_sub{$ccinfo->[0]}++;
    } else {
      debug "cc(ccinfo): @$ccinfo\n" if $debug{queue};
      cc(@$ccinfo);
      $cc_pp_sub{$ccinfo->[0]}++;
    }
  }
  return $start;
}

sub cc_obj {
  my ( $name, $cvref ) = @_;
  my $cv         = svref_2object($cvref);
  my @padlist    = $cv->PADLIST->ARRAY;
  my $curpad_sym = $padlist[1]->save;
  set_curcv $cv;
  cc_recurse( $name, $cv->ROOT, $cv->START, @padlist );
}

sub cc_main {
  my @comppadlist = comppadlist->ARRAY;
  my $curpad_nam  = $comppadlist[0]->save('curpad_name');
  my $curpad_sym  = $comppadlist[1]->save('curpad_syms');;
  my $init_av     = init_av->save('INIT');
  set_curcv B::main_cv;
  my $start = cc_recurse( "pp_main", main_root, main_start, @comppadlist );

  # Do save_unused_subs before saving inc_hv
  B::C::module($module) if $module;
  save_unused_subs();

  my $warner = $SIG{__WARN__};
  save_sig($warner);

  my($inc_hv, $inc_av, $end_av);
  if ( !defined($module) ) {
    # forbid run-time extends of curpad syms, names and INC
    warn "save context:\n" if $verbose;
    $init->add("/* save context */");
    $init->add('/* %INC */');
    inc_cleanup();
    my $inc_gv = svref_2object( \*main::INC );
    $inc_hv    = $inc_gv->HV->save('main::INC');
    $init->add( sprintf( "GvHV(%s) = s\\_%x;",
			 $inc_gv->save('main::INC'), $inc_gv->HV ) );
    local ($B::C::const_strings);
    $B::C::const_strings = 1 if $B::C::ro_inc;
    $inc_hv          = $inc_gv->HV->save('main::INC');
    $inc_av          = $inc_gv->AV->save('main::INC');
  }
  {
    # >=5.10 needs to defer nullifying of all vars in END, not only new ones.
    local ($B::C::const_strings);
    $B::C::in_endav = 1;
    $end_av  = end_av->save('END');
  }
  cc_recurse();
  return if $errors or $check;

  if ( !defined($module) ) {
    # XXX TODO push BEGIN/END blocks to modules code.
    $init->add(
      sprintf( "PL_main_root = s\\_%x;", ${ main_root() } ),
      "PL_main_start = $start;",
      "PL_curpad = AvARRAY($curpad_sym);",
      "PL_comppad = $curpad_sym;");
    if ($] < 5.017005) {
      $init->add(
	"av_store((AV*)CvPADLIST(PL_main_cv), 0, SvREFCNT_inc($curpad_nam)); /* namepad */",
	"av_store((AV*)CvPADLIST(PL_main_cv), 1, SvREFCNT_inc($curpad_sym)); /* curpad */");
    } else {
      $init->add(
	"PadlistARRAY(CvPADLIST(PL_main_cv))[0] = (PAD*)SvREFCNT_inc($curpad_nam); /* namepad */",
	"PadlistARRAY(CvPADLIST(PL_main_cv))[1] = (PAD*)SvREFCNT_inc($curpad_sym); /* curpad */");
    }
    $init->add(
      "GvHV(PL_incgv) = $inc_hv;",
      "GvAV(PL_incgv) = $inc_av;",
      "PL_initav = (AV*)$init_av;",
      "PL_endav = (AV*)$end_av;");
    if ($] < 5.017) {
      my $amagic_generate = B::amagic_generation;
      $init->add("PL_amagic_generation = $amagic_generate;");
    };
  }

  seek( STDOUT, 0, 0 );   #prevent print statements from BEGIN{} into the output
  fixup_ppaddr();
  print "/* using B::CC $B::CC::VERSION backend */\n";
  output_boilerplate();
  print "\n";
  output_all("perl_init");
  output_runtime();
  print "\n";
  output_main_rest();

  if ( defined($module) ) {
    my $cmodule = $module ||= 'main';
    $cmodule =~ s/::/__/g;
    print <<"EOT";

#include "XSUB.h"
XS(boot_$cmodule)
{
    dXSARGS;
    perl_init();
    ENTER;
    SAVETMPS;
    SAVEVPTR(PL_curpad);
    SAVEVPTR(PL_op);
    PL_curpad = AvARRAY($curpad_sym);
    PL_op = $start;
    pp_main(aTHX);
    FREETMPS;
    LEAVE;
    ST(0) = &PL_sv_yes;
    XSRETURN(1);
}
EOT
  } else {
    output_main();
  }
  if ( $debug{timings} ) {
    warn sprintf( "Done at %s\n", timing_info );
  }
}

sub compile_stats {
   my $s = "Total number of OPs processed: $op_count\n";
   $s .= "Total number of unresolved symbols: $B::C::unresolved_count\n"
     if $B::C::unresolved_count;
   return $s;
}

# Accessible via use B::CC '-ftype-attr'; in user code, or -MB::CC=-O2 on the cmdline
sub import {
  my @options = @_;
  # Allow debugging in CHECK blocks without Od
  $DB::single = 1 if defined &DB::DB;
  my ( $option, $opt, $arg );
  # init with -O0
  foreach my $ref ( values %optimise ) {
    $$ref = 0;
  }
  $B::C::fold     = 0 if $] >= 5.013009; # utf8::Cased tables
  $B::C::warnings = 0 if $] >= 5.013005; # Carp warnings categories and B
  $B::C::destruct = 0 unless $] < 5.008; # fast_destruct
  $opt_taint = 1;
  $opt_magic = 1;      # only makes sense with -fno-magic
  $opt_autovivify = 1; # only makes sense with -fno-autovivify
OPTION:
  while ( $option = shift @options ) {
    if ( $option =~ /^-(.)(.*)/ ) {
      $opt = $1;
      $arg = $2;
    }
    else {
      unshift @options, $option;
      last OPTION;
    }
    if ( $opt eq "-" && $arg eq "-" ) {
      shift @options;
      last OPTION;
    }
    elsif ( $opt eq "o" ) {
      $arg ||= shift @options;
      open( STDOUT, ">$arg" ) or return "open '>$arg': $!\n";
    }
    elsif ( $opt eq "c" ) {
      $check       = 1;
      $B::C::check = 1;
    }
    elsif ( $opt eq "v" ) {
      $verbose       = 1;
      B::C::verbose(1); # crashed in C _save_common_middle(B::FAKEOP)
    }
    elsif ( $opt eq "u" ) {
      $arg ||= shift @options;
      eval "require $arg;";
      mark_unused( $arg, 1 );
    }
    elsif ( $opt eq "U" ) {
      $arg ||= shift @options;
      mark_skip( $arg );
    }
    elsif ( $opt eq "strict" ) {
      $arg ||= shift @options;
      $strict++;
    }
    elsif ( $opt eq "f" ) {
      $arg ||= shift @options;
      my $value = $arg !~ s/^no-//;
      $arg =~ s/-/_/g;
      my $ref = $optimise{$arg};
      if ( defined($ref) ) {
        $$ref = $value;
      }
      else {
        # Pass down to B::C
        my $ref = $B::C::option_map{$arg};
        if ( defined($ref) ) {
          $$ref = $value;
	  $c_optimise{$ref}++;
        }
        else {
          warn qq(Warning: ignoring unknown optimisation "$arg"\n);
        }
      }
    }
    elsif ( $opt eq "O" ) {
      $arg = 1 if $arg eq "";
      foreach my $ref ( values %optimise ) {
        $$ref = 0;
      }
      if ($arg >= 2) {
        $freetmps_each_loop = 1;
        if (!$ITHREADS) {
          #warn qq(Warning: ignoring -faelem with threaded perl\n);
          $opt_aelem = 1; # unstable, test: 68 pp_padhv targ assert
        }
      }
      if ( $arg >= 1 ) {
        $opt_type_attr = 1;
        $freetmps_each_bblock = 1 unless $freetmps_each_loop;
      }
    }
    elsif ( $opt eq "n" ) {
      $arg ||= shift @options;
      $init_name = $arg;
    }
    elsif ( $opt eq "m" ) {
      $module = $arg;
      mark_unused( $arg, undef );
    }
    #elsif ( $opt eq "p" ) {
    #  $arg ||= shift @options;
    #  $patchlevel = $arg;
    #}
    elsif ( $opt eq "D" ) {
      $arg ||= shift @options;
      $verbose++;
      # note that we should not clash too much with the B::C debug map
      # because we set theirs also
      my %debug_map = (O => 'op',
                       T => 'stack',    # was S
                       c => 'cxstack',
                       a => 'pad',      # was p
                       r => 'runtime',
                       w => 'shadow',   # was s
                       q => 'queue',
                       l => 'lineno',
                       t => 'timings',
                       b => 'bblock');
      $arg = join('',keys %debug_map).'Fsp' if $arg eq 'full';
      foreach $arg ( split( //, $arg ) ) {
        if ( $arg eq "o" ) {
          B->debug(1);
        }
        elsif ( $debug_map{$arg} ) {
          $debug{ $debug_map{$arg} }++;
        }
        elsif ( $arg eq "F" and eval "require B::Flags;" ) {
          $debug{flags}++;
          $B::C::debug{flags}++;
        }
	elsif ( exists $B::C::debug_map{$arg} ) {
          $B::C::verbose++;
          $B::C::debug{ $B::C::debug_map{$arg} }++;
	}
	else {
	  warn qq(Warning: ignoring unknown -D option "$arg"\n);
	}
      }
    }
  }
  $strict++ if !$strict and $Config{ccflags} !~ m/-DDEBUGGING/;
  if ($opt_omit_taint) {
    $opt_taint = 0;
    warn "Warning: -fomit_taint is deprecated. Use -fno-taint instead.\n";
  }

  # rgs didn't want opcodes to be added to Opcode. So I had to add it to a
  # seperate Opcodes package.
  eval { require Opcodes; };
  if (!$@ and $Opcodes::VERSION) {
    my $MAXO = Opcodes::opcodes();
    for (0..$MAXO-1) {
      no strict 'refs';
      my $ppname = "pp_".Opcodes::opname($_);
      # opflags n: no args, no return values. don't need save/restore stack
      # But pp_enter, pp_leave use/change global stack.
      next if $ppname eq 'pp_enter' || $ppname eq 'pp_leave';
      $no_stack{$ppname} = 1
        if Opcodes::opflags($_) & 512;
      # XXX More Opcodes options to be added later
    }
  }
  #if ($debug{op}) {
  #  warn "no_stack: ",join(" ",sort keys %no_stack),"\n";
  #}

  mark_skip(qw(B::C B::C::Config B::CC B::Asmdata B::FAKEOP
               B::Pseudoreg B::Shadow B::C::InitSection
               O B::Stackobj B::Stackobj::Bool B::Stackobj::Padsv
               B::Stackobj::Const B::Stackobj::Aelem B::Bblock));
  $B::C::all_bc_deps{$_}++ for qw(Opcodes Opcode B::Concise attributes double int num str string subs);
  mark_skip(qw(DB Term::ReadLine)) if defined &DB::DB;

  # Set some B::C optimizations.
  # optimize_ppaddr is not needed with B::CC as CC does it even better.
  for (qw(optimize_warn_sv save_data_fh av_init save_sig destruct const_strings)) {
    no strict 'refs';
    ${"B::C::$_"} = 1 unless $c_optimise{$_};
  }
  $B::C::destruct = 0 unless $c_optimise{destruct} and $] > 5.008;
  $B::C::stash = 0 unless $c_optimise{stash};
  if (!$B::C::Config::have_independent_comalloc) {
    $B::C::av_init = 1 unless $c_optimise{av_init};
    $B::C::av_init2 = 0 unless $c_optimise{av_init2};
  } else {
    $B::C::av_init = 0 unless $c_optimise{av_init};
    $B::C::av_init2 = 1 unless $c_optimise{av_init2};
  }
  init_type_attrs() if $opt_type_attr; # but too late for -MB::CC=-O2 on import. attrs are checked before
  @options;
}

# -MO=CC entry point
sub compile {
  my @options = @_;
  @options = import(@options);

  init_sections();
  $init = B::C::Section->get("init");
  $decl = B::C::Section->get("decl");

  # just some subs or main?
  if (@options) {
    return sub {
      my ( $objname, $ppname );
      foreach $objname (@options) {
        $objname = "main::$objname" unless $objname =~ /::/;
        ( $ppname = $objname ) =~ s/^.*?:://;
        eval "cc_obj(qq(pp_sub_$ppname), \\&$objname)";
        die "cc_obj(qq(pp_sub_$ppname, \\&$objname) failed: $@" if $@;
        return if $errors;
      }
      my $warner = $SIG{__WARN__};
      save_sig($warner);
      fixup_ppaddr();
      return if $check;
      output_boilerplate();
      print "\n";
      output_all( $init_name || "init_module" );
      output_runtime();
      output_main_rest();
    }
  }
  else {
    return sub { cc_main() };
  }
}

1;

__END__

=head1 EXAMPLES

        perl -MO=CC,-O2,-ofoo.c foo.pl
        perl cc_harness -o foo foo.c

Note that C<cc_harness> lives in the C<B> subdirectory of your perl
library directory. The utility called C<perlcc> may also be used to
help make use of this compiler.

	# create a shared XS module
        perl -MO=CC,-mFoo,-oFoo.c Foo.pm
        perl cc_harness -shared -c -o Foo.so Foo.c

        # side-effects just for the types and attributes
        perl -MB::CC -e'my int $i:unsigned; ...'

=head1 TYPES

Implemented type classes are B<int> and B<num>.
Planned is B<str> also.
Implemented are only SCALAR types yet.
Typed arrays and hashes and perfect hashes need L<coretypes>, L<types> and
proper C<const> support first.

Deprecated are inferred types via the names of locals, with '_i', '_d' suffix
and an optional 'r' suffix for register allocation.

  C<my ($i_i, $j_ir, $num_d);>

Planned type attributes are B<int>, B<num>, B<str>, B<unsigned>, B<ro> / B<const>.

The attributes are perl attributes, and C<int|num|str> are either
compiler classes or hints for more allowed types.

  C<my int $i :num;>  declares a NV with SVf_IOK. Same as C<my $i:int:double;>
  C<my int $i;>          declares an IV. Same as C<my $i:int;>
  C<my int $i :str;>  declares a PVIV. Same as C<my $i:int:string;>

  C<my int @array :unsigned = (0..4);> will be used as c var in faster arithmetic and cmp.
                                       With :const or :ro even more.
  C<my str %hash :const
    = (foo => 'foo', bar => 'bar');> declare string values,
                                     generate as read-only perfect hash.

B<:unsigned> is valid for int only and declares an UV.

B<:register> denotes optionally a short and hot life-time.

B<:temporary> are usually generated internally, nameless lexicals.
They are more aggressivly destroyed and ignored.

B<:ro> or B<:const> throw a compile-time error on write access and may optimize
the internal structure of the variable. We don't need to write back the variable
to perl (lexical write_back).

STATUS

OK (classes only):

  my int $i;
  my num $d;

NOT YET OK (attributes):

  my int $i :register;
  my $i :int;
  my $const :int:const;
  my $uv :int:unsigned;

ISSUES

This does not work with pure perl, unless you C<use B::CC> or C<use types> or
implement the classes and attribute type stubs in your code,
C<sub Mypkg::MODIFY_SCALAR_ATTRIBUTES {}> and C<sub Mypkg::FETCH_SCALAR_ATTRIBUTES {}>.
(TODO: empty should be enough to be detected by the compiler.)

Compiled code pulls in the magic MODIFY_SCALAR_ATTRIBUTES and FETCH_SCALAR_ATTRIBUTES
functions, even if they are used at compile time only.

Using attributes adds an import block to your code.

Up until 5.20 only B<our> variable attributes are checked at compile-time,
B<my> variables attributes at run-time only, which is too late for the compiler.
Perl attributes need to be fixed for types hints by adding C<CHECK_SCALAR_ATTRIBUTES>.

FUTURE

We should be able to support types on ARRAY and HASH.
For arrays also sizes to omit bounds-checking.

  my int @array; # array of ints, faster magic-less access esp. in inlined arithmetic and cmp.
  my str @array : const = qw(foo bar);   # compile-time error on write. no lexical write_back

  my int $hash = {"1" => 1, "2" => 2};   # int values, type-checked on write my
  str %hash1 : const = (foo => 'bar');   # string keys only => maybe gperf
                                         # compile-time error on write

Typed hash keys are always strings, as array keys are always int. Only the values are typed.

We should be also able to add type attributes for functions and methods,
i.e. for argument and return types. See L<types> and
L<http://blogs.perl.org/users/rurban/2011/02/use-types.html>

=head1 BUGS

Plenty. Current status: experimental.

=head1 DIFFERENCES

These aren't really bugs but they are constructs which are heavily
tied to perl's compile-and-go implementation and with which this
compiler backend cannot cope.

=head2 Loops

Standard perl calculates the target of "next", "last", and "redo"
at run-time. The compiler calculates the targets at compile-time.
For example, the program

    sub skip_on_odd { next NUMBER if $_[0] % 2 }
    NUMBER: for ($i = 0; $i < 5; $i++) {
        skip_on_odd($i);
        print $i;
    }

produces the output

    024

with standard perl but calculates with the compiler the
goto label_NUMBER wrong, producing 01234.

=head2 Context of ".."

The context (scalar or array) of the ".." operator determines whether
it behaves as a range or a flip/flop. Standard perl delays until
runtime the decision of which context it is in but the compiler needs
to know the context at compile-time. For example,

    @a = (4,6,1,0,0,1);
    sub range { (shift @a)..(shift @a) }
    print range();
    while (@a) { print scalar(range()) }

generates the output

    456123E0

with standard Perl but gives a run-time warning with compiled Perl.

If the option B<-strict> is used it gives a compile-time error.

=head2 Arithmetic

Compiled Perl programs use native C arithmetic much more frequently
than standard perl. Operations on large numbers or on boundary
cases may produce different behaviour.
In doubt B::CC code behaves more like with C<use integer>.

=head2 Deprecated features

Features of standard perl such as C<$[> which have been deprecated
in standard perl since Perl5 was released have not been implemented
in the optimizing compiler.

=head1 AUTHORS

Malcolm Beattie C<MICB at cpan.org> I<(1996-1998, retired)>,
Vishal Bhatia <vishal at deja.com> I(1999),
Gurusamy Sarathy <gsar at cpan.org> I(1998-2001),
Reini Urban C<perl-compiler at googlegroups.com> I(2008-now),
Heinz Knutzen C<heinz.knutzen at gmx.de> I(2010)
Will Braswell C<wbraswell at hush.com> I(2012)

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 78
# End:
# vim: expandtab shiftwidth=2:
