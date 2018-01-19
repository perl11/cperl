#line 2 "op.c"
/*    op.c
 *
 *    Copyright (C) 1991, 1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000,
 *    2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008 by Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 */

/*
 * 'You see: Mr. Drogo, he married poor Miss Primula Brandybuck.  She was
 *  our Mr. Bilbo's first cousin on the mother's side (her mother being the
 *  youngest of the Old Took's daughters); and Mr. Drogo was his second
 *  cousin.  So Mr. Frodo is his first *and* second cousin, once removed
 *  either way, as the saying is, if you follow me.'       --the Gaffer
 *
 *     [p.23 of _The Lord of the Rings_, I/i: "A Long-Expected Party"]
 */

/* This file contains the functions that create, manipulate and optimize
 * the OP structures that hold a compiled perl program.
 *
 * Note that during the build of miniperl, a temporary copy of this file
 * is made, called opmini.c.
 *
 * A Perl program is compiled into a tree of OP nodes. Each op contains:
 *  * structural OP pointers to its children and siblings (op_sibling,
 *    op_first etc) that define the tree structure;
 *  * execution order OP pointers (op_next, plus sometimes op_other,
 *    op_lastop  etc) that define the execution sequence plus variants;
 *  * a pointer to the C "pp" function that would execute the op;
 *  * any data specific to that op.
 * For example, an OP_CONST op points to the pp_const() function and to an
 * SV containing the constant value. When pp_const() is executed, its job
 * is to push that SV onto the stack.
 *
 * OPs are mainly created by the newFOO() functions, which are mainly
 * called from the parser (in perly.y) as the code is parsed. For example
 * the Perl code $a + $b * $c would cause the equivalent of the following
 * to be called (oversimplifying a bit):
 *
 *  newBINOP(OP_ADD, flags,
 *	newSVREF($a),
 *	newBINOP(OP_MULTIPLY, flags, newSVREF($b), newSVREF($c))
 *  )
 *
 * As the parser reduces low-level rules, it creates little op subtrees;
 * as higher-level rules are resolved, these subtrees get joined together
 * as branches on a bigger subtree, until eventually a top-level rule like
 * a subroutine definition is reduced, at which point there is one large
 * parse tree left.
 *
 * The execution order pointers (op_next) are generated as the subtrees
 * are joined together. Consider this sub-expression: A*B + C/D: at the
 * point when it's just been parsed, the op tree looks like:
 *
 *   [+]
 *    |
 *   [*]------[/]
 *    |        |
 *    A---B    C---D
 *
 * with the intended execution order being:
 *
 *   [PREV] => A => B => [*] => C => D => [/] =>  [+] => [NEXT]
 *
 * At this point all the nodes' op_next pointers will have been set,
 * except that:
 *    * we don't know what the [NEXT] node will be yet;
 *    * we don't know what the [PREV] node will be yet, but when it gets
 *      created and needs its op_next set, it needs to be set to point to
 *      A, which is non-obvious.
 * To handle both those cases, we temporarily set the top node's
 * op_next to point to the first node to be executed in this subtree (A in
 * this case). This means that initially a subtree's op_next chain,
 * starting from the top node, will visit each node in execution sequence
 * then point back at the top node.
 * When we embed this subtree in a larger tree, its top op_next is used
 * to get the start node, then is set to point to its new neighbour.
 * For example the two separate [*],A,B and [/],C,D subtrees would
 * initially have had:
 *   [*] => A;  A => B;  B => [*]
 * and
 *   [/] => C;  C => D;  D => [/]
 * When these two subtrees were joined together to make the [+] subtree,
 * [+]'s op_next was set to [*]'s op_next, i.e. A; then [*]'s op_next was
 * set to point to [/]'s op_next, i.e. C.
 *
 * This op_next linking is done by the LINKLIST() macro and its underlying
 * op_linklist() function. Given a top-level op, if its op_next is
 * non-null, it's already been linked, so leave it. Otherwise link it with
 * its children as described above, possibly recursively if any of the
 * children have a null op_next.
 *
 * In summary: given a subtree, its top-level node's op_next will either
 * be:
 *   NULL: the subtree hasn't been LINKLIST()ed yet;
 *   fake: points to the start op for this subtree;
 *   real: once the subtree has been embedded into a larger tree
 */

/*

Here's an older description from Larry.

Perl's compiler is essentially a 3-pass compiler with interleaved phases:

    A bottom-up pass
    A top-down pass
    An execution-order pass

The bottom-up pass is represented by all the "newOP" routines and
the ck_ routines.  The bottom-upness is actually driven by yacc.
So at the point that a ck_ routine fires, we have no idea what the
context is, either upward in the syntax tree, or either forward or
backward in the execution order.  (The bottom-up parser builds that
part of the execution order it knows about, but if you follow the "next"
links around, you'll find it's actually a closed loop through the
top level node.)

Whenever the bottom-up parser gets to a node that supplies context to
its components, it invokes that portion of the top-down pass that applies
to that part of the subtree (and marks the top node as processed, so
if a node further up supplies context, it doesn't have to take the
plunge again).  As a particular subcase of this, as the new node is
built, it takes all the closed execution loops of its subcomponents
and links them into a new closed loop for the higher level node.  But
it's still not the real execution order.

The actual execution order is not known till we get a grammar reduction
to a top-level unit like a subroutine or file that will be called by
"name" rather than via a "next" pointer.  At that point, we can call
into peep() to do that code's portion of the 3rd pass.  It has to be
recursive, but it's recursive on basic blocks, not on tree nodes.
*/

/* To implement user lexical pragmas, there needs to be a way at run time to
   get the compile time state of %^H for that block.  Storing %^H in every
   block (or even COP) would be very expensive, so a different approach is
   taken.  The (running) state of %^H is serialised into a tree of HE-like
   structs.  Stores into %^H are chained onto the current leaf as a struct
   refcounted_he * with the key and the value.  Deletes from %^H are saved
   with a value of PL_sv_placeholder.  The state of %^H at any point can be
   turned back into a regular HV by walking back up the tree from that point's
   leaf, ignoring any key you've already seen (placeholder or not), storing
   the rest into the HV structure, then removing the placeholders. Hence
   memory is only used to store the %^H deltas from the enclosing COP, rather
   than the entire %^H on each COP.

   To cause actions on %^H to write out the serialisation records, it has
   magic type 'H'. This magic (itself) does nothing, but its presence causes
   the values to gain magic type 'h', which has entries for set and clear.
   C<Perl_magic_sethint> updates C<PL_compiling.cop_hints_hash> with a store
   record, with deletes written by C<Perl_magic_clearhint>. C<SAVEHINTS>
   saves the current C<PL_compiling.cop_hints_hash> on the save stack, so that
   it will be correctly restored when any inner compiling scope is exited.
*/

#include "EXTERN.h"
#define PERL_IN_OP_C
#include "perl.h"
#include "keywords.h"
#include "feature.h"
#include "regcomp.h"

/*#define SIG_DEBUG*/

#define CALL_PEEP(o) PL_peepp(aTHX_ o)
#define CALL_RPEEP(o) PL_rpeepp(aTHX_ o)
#define CALL_OPFREEHOOK(o) if (PL_opfreehook) PL_opfreehook(aTHX_ o)

static const char array_passed_to_stat[] =
    "Array passed to stat will be coerced to a scalar";

/* Some typestashes are corrupted upstream somehow. */

#if PTRSIZE == 8
#define VALIDTYPE(stash) ( \
    stash \
    /* && PTR2IV(stash) > 0x1000 && PTR2IV(stash) < 0x1000000000000 */ \
    && SvTYPE(stash) == SVt_PVHV)
#else
#define VALIDTYPE(stash) ( \
    stash \
    /* && PTR2IV(stash) > 0x1000 */ \
    && SvTYPE(stash) == SVt_PVHV)
#endif

#define IS_TYPE(o, type)   OP_TYPE_IS_NN((o), OP_##type)
#define ISNT_TYPE(o, type) OP_TYPE_ISNT_NN((o), OP_##type)
#define IS_NULL_OP(o)  ((o)->op_type == OP_NULL)
#define IS_AND_OP(o)   ((o)->op_type == OP_AND)
#define IS_OR_OP(o)    ((o)->op_type == OP_OR)
#define IS_CONST_OP(o) ((o)->op_type == OP_CONST)
#define IS_STATE_OP(o)  \
      (OP_TYPE_IS_NN((o), OP_NEXTSTATE) \
    || OP_TYPE_IS_NN((o), OP_DBSTATE))
#define IS_RV2ANY_OP(o)  \
      (OP_TYPE_IS_NN((o), OP_RV2SV) \
    || OP_TYPE_IS_NN((o), OP_RV2AV) \
    || OP_TYPE_IS_NN((o), OP_RV2HV))
#define IS_SUB_OP(o)  \
    (OP_TYPE_IS_NN((o), OP_ENTERSUB) \
  || OP_TYPE_IS_NN((o), OP_ENTERXSSUB))
#define IS_LEAVESUB_OP(o)  \
    (OP_TYPE_IS_NN((o), OP_LEAVESUB) \
  || OP_TYPE_IS_NN((o), OP_LEAVESUBLV))
#define IS_SUB_TYPE(type)  \
    ((type) == OP_ENTERSUB) || ((type) == OP_ENTERXSSUB)
#define OP_GIMME_VOID(o)    (OP_GIMME((o),0) == G_VOID)
#define OP_GIMME_SCALAR(o)  (OP_GIMME((o),0) == G_SCALAR)

#ifndef PERL_MAX_UNROLL_LOOP_COUNT
#  define PERL_MAX_UNROLL_LOOP_COUNT 5
#else
# if (PERL_MAX_UNROLL_LOOP_COUNT <= 0) || (PERL_MAX_UNROLL_LOOP_COUNT > 20)
#  error Invalid PERL_MAX_UNROLL_LOOP_COUNT: max 0..20
# endif
#endif

/*
=for apidoc s|const char*	|typename	|HV* stash

Returns the sanitized typename of the stash of the padname type,
without main:: prefix.

=cut
*/
/* Too big for gcc to inline. */
STATIC
const char * S_typename(pTHX_ const HV* stash)
{
    if (!(UNLIKELY(VALIDTYPE(stash))))
        return NULL;
    {
        const char *name = HvNAME(stash);
        int l = HvNAMELEN(stash);
        if (!name)
            return NULL;
        if (l > 6 && *name == 'm' && memEQc(name, "main::"))
            return name+6;
        else
            return name; /* custom blessed type or auto-created coretype */
    }
}

/*
  DEFER_OP

  Used to avoid recursion through the op tree in L<perlapi/scalarvoid>() and
  L<perlapi/op_free>().
*/

#define DEFERRED_OP_STEP 100
#define DEFER_OP(o) \
  STMT_START { \
    if (UNLIKELY(defer_ix == (defer_stack_alloc-1))) {    \
        defer_stack_alloc += DEFERRED_OP_STEP; \
        assert(defer_stack_alloc > 0); \
        Renew(defer_stack, defer_stack_alloc, OP *); \
    } \
    defer_stack[++defer_ix] = o; \
  } STMT_END

#define POP_DEFERRED_OP() (defer_ix >= 0 ? defer_stack[defer_ix--] : (OP *)NULL)

/*
=for apidoc in|OP*	|op_next_nn	|OP* o

Returns the next non-NULL op, skipping all NULL ops in the chain.

=cut
*/
PERL_STATIC_INLINE OP*
S_op_next_nn(OP* o) {
    PERL_ARGS_ASSERT_OP_NEXT_NN;
    while (OP_TYPE_IS(OpNEXT(o), OP_NULL))
        o = OpNEXT(o);
    return OpNEXT(o);
}

/*
=for apidoc in|OP*	|op_prev_nn	|OP* us

Returns the previous sibling or parent op, pointing via OpSIBLNG or
OpFIRST to us.  Walks the the siblings until the parent, and then
descent again to the kids until it finds us.

=cut
*/
PERL_STATIC_INLINE OP*
S_op_prev_nn(const OP* us) {
    OP* o = (OP*)us;
    PERL_ARGS_ASSERT_OP_PREV_NN;
#ifndef PERL_OP_PARENT
    Perl_croak_nocontext("panic: invalid op_prev_nn");
#endif
    for (; OpHAS_SIBLING(o); o = OpSIBLING(o)) ;
    if (!o->op_moresib) {
        if (!o->op_sibparent)
            return NULL;
        o = o->op_sibparent;
    }
    if (OpFIRST(o) == us)
        return o;
    for (o = OpFIRST(o); OpSIBLING(o) != us; o = OpSIBLING(o)) ;
    return o;
}

/*
=for apidoc in|OP*	|op_prevstart_nn	|const OP* start|OP* us

Returns the previous op, pointing via OpNEXT to us.
Walks down the CvSTART until it finds us.

=cut
*/
PERL_STATIC_INLINE OP*
S_op_prevstart_nn(const OP* start, const OP* us) {
    OP* o = (OP*)start;
    PERL_ARGS_ASSERT_OP_PREVSTART_NN;
    for (; o && OpNEXT(o) != us; o = OpNEXT(o)) ;
    return o;
}
/*
=for apidoc sn|void	|prune_chain_head |OP** op_p

remove any leading "empty" ops from the op_next chain whose first
node's address is stored in op_p. Store the updated address of the
first node in op_p.

=cut
*/
static void
S_prune_chain_head(OP** op_p)
{
    PERL_ARGS_ASSERT_PRUNE_CHAIN_HEAD;
    while (*op_p
        && (   IS_NULL_OP(*op_p)
            || IS_TYPE(*op_p, SCOPE)
            || IS_TYPE(*op_p, SCALAR)
            || IS_TYPE(*op_p, LINESEQ)))
        *op_p = OpNEXT(*op_p);
    if (*op_p && IS_STATE_OP(*op_p) && IS_TYPE(OpNEXT(*op_p), SIGNATURE))
        *op_p = OpNEXT(*op_p);
}


/* See the explanatory comments above struct opslab in F<op.h>. */

#ifdef PERL_DEBUG_READONLY_OPS
#  define PERL_SLAB_SIZE 128
#  define PERL_MAX_SLAB_SIZE 4096
#  include <sys/mman.h>
#endif

#ifndef PERL_SLAB_SIZE
#  define PERL_SLAB_SIZE 64
#endif
#ifndef PERL_MAX_SLAB_SIZE
#  define PERL_MAX_SLAB_SIZE 2048
#endif

/* rounds up to nearest pointer */
#define SIZE_TO_PSIZE(x)	(((x) + sizeof(I32 *) - 1)/sizeof(I32 *))
#define DIFF(o,p)		((size_t)((I32 **)(p) - (I32**)(o)))

/*
=for apidoc s|OPSLAB*	|new_slab	|size_t sz

Creates a new memory region, a slab, for ops, with room for sz
pointers. sz starts with PERL_SLAB_SIZE (=64) and is then extended by
factor two in Slab_Alloc().

=cut
*/
static OPSLAB *
S_new_slab(pTHX_ size_t sz)
{
#ifdef PERL_DEBUG_READONLY_OPS
    OPSLAB *slab = (OPSLAB *) mmap(0, sz * sizeof(I32 *),
				   PROT_READ|PROT_WRITE,
				   MAP_ANON|MAP_PRIVATE, -1, 0);
    DEBUG_m(PerlIO_printf(Perl_debug_log, "mapped %lu at %p\n",
			  (unsigned long) sz, slab));
    if (slab == MAP_FAILED) {
	perror("mmap failed");
	abort();
    }
    slab->opslab_size = (U16)sz;
#else
    OPSLAB *slab = (OPSLAB *)PerlMemShared_calloc(sz, sizeof(I32 *));
#endif
#ifndef WIN32
    /* The context is unused in non-Windows */
    PERL_UNUSED_CONTEXT;
#endif
    slab->opslab_first = (OPSLOT *)((I32 **)slab + sz - 1);
    return slab;
}

/* requires double parens and aTHX_ */
#define DEBUG_S_warn(args)					       \
    DEBUG_S( 								\
	PerlIO_printf(Perl_debug_log, "%s", SvPVx_nolen(Perl_mess args)) \
    )

/*
=for apidoc XpR|void *	|Slab_Alloc	|size_t sz

Creates a new memory region, a slab, for some ops, with room for sz
pointers. sz starts with PERL_SLAB_SIZE (=64) and is then extended by
factor two.

=cut
*/
void *
Perl_Slab_Alloc(pTHX_ size_t sz)
{
    OPSLAB *slab;
    OPSLAB *slab2;
    OPSLOT *slot;
    OP *o;
    size_t opsz, space;

    /* We only allocate ops from the slab during subroutine compilation.
       We find the slab via PL_compcv, hence that must be non-NULL. It could
       also be pointing to a subroutine which is now fully set up (CvROOT()
       pointing to the top of the optree for that sub), or a subroutine
       which isn't using the slab allocator. If our sanity checks aren't met,
       don't use a slab, but allocate the OP directly from the heap.  */
    if (!PL_compcv || CvROOT(PL_compcv)
     || (CvSTART(PL_compcv) && !CvSLABBED(PL_compcv)))
    {
	o = (OP*)PerlMemShared_calloc(1, sz);
        goto gotit;
    }

    /* While the subroutine is under construction, the slabs are accessed via
       CvSTART(), to avoid needing to expand PVCV by one pointer for something
       unneeded at runtime. Once a subroutine is constructed, the slabs are
       accessed via CvROOT(). So if CvSTART() is NULL, no slab has been
       allocated yet.  See the commit message for 8be227ab5eaa23f2 for more
       details.  */
    if (!CvSTART(PL_compcv)) {
	CvSTART(PL_compcv) =
	    (OP *)(slab = new_slab(PERL_SLAB_SIZE));
	CvSLABBED_on(PL_compcv);
	slab->opslab_refcnt = 2; /* one for the CV; one for the new OP */
    }
    else ++(slab = (OPSLAB *)CvSTART(PL_compcv))->opslab_refcnt;

    opsz = SIZE_TO_PSIZE(sz);
    sz = opsz + OPSLOT_HEADER_P;

    /* The slabs maintain a free list of OPs. In particular, constant folding
       will free up OPs, so it makes sense to re-use them where possible. A
       freed up slot is used in preference to a new allocation.  */
    if (slab->opslab_freed) {
	OP **too = &slab->opslab_freed;
	o = *too;
        space = o ? DIFF(OpSLOT(o), OpSLOT(o)->opslot_next) : 0;
	DEBUG_S_warn((aTHX_ "found free op at %p, slab %p, size %lu for %lu",
                      (void*)o, (void*)slab, (unsigned long)space, (unsigned long)sz));
        assert(space < INT_MAX);
	while (o && (space = DIFF(OpSLOT(o), OpSLOT(o)->opslot_next)) < sz) {
	    DEBUG_S_warn((aTHX_ "Alas! too small %lu < %lu",
                          (unsigned long)space, (unsigned long)sz));
	    o = *(too = &OpNEXT(o));
	    if (o) {
                DEBUG_S_warn((aTHX_ "found another free op at %p", (void*)o));
                if (!o->op_slabbed) {
                    /* this op was not added by core. the slot became corrupt */
                    DEBUG_S_warn((aTHX_ "but it is not slabbed %p (not added by core)",
                                  (void*)o));
                    OpSLOT(o)->opslot_next = NULL;
                    o = NULL;
                }
            }
	}
        assert(space < 1000); /* detect opslot corruption (Variable::Magic) */
	if (o) {
	    *too = OpNEXT(o);
	    Zero(o, opsz, I32 *);
	    o->op_slabbed = 1;
	    goto gotit;
	}
    }

#define INIT_OPSLOT \
	    slot->opslot_slab = slab;			\
	    slot->opslot_next = slab2->opslab_first;	\
	    slab2->opslab_first = slot;			\
	    o = &slot->opslot_op;			\
	    o->op_slabbed = 1

    /* The partially-filled slab is next in the chain. */
    slab2 = slab->opslab_next ? slab->opslab_next : slab;
    if ((space = DIFF(&slab2->opslab_slots, slab2->opslab_first)) < sz) {
        DEBUG_S_warn((aTHX_ "remaining slab space is too small %lu < %lu",
                      (unsigned long)space, (unsigned long)sz));
	/* If we can fit a BASEOP, add it to the free chain, so as not
	   to waste it. */
	if (space >= SIZE_TO_PSIZE(sizeof(OP)) + OPSLOT_HEADER_P) {
	    slot = &slab2->opslab_slots;
	    INIT_OPSLOT;
	    o->op_type = OP_FREED;
	    OpNEXT(o) = slab->opslab_freed;
	    slab->opslab_freed = o;
	}

	/* Create a new slab.  Make this one twice as big. */
	slot = slab2->opslab_first;
	while (slot->opslot_next) slot = slot->opslot_next;
	slab2 = new_slab((DIFF(slab2, slot)+1)*2 > PERL_MAX_SLAB_SIZE
                         ? PERL_MAX_SLAB_SIZE
                         : (DIFF(slab2, slot)+1)*2);
	slab2->opslab_next = slab->opslab_next;
	slab->opslab_next = slab2;
        DEBUG_S_warn((aTHX_ "created new slab space twice as large %lu",
                      (unsigned long)DIFF(&slab2->opslab_slots, slab2->opslab_first)));
    }
    assert((space = DIFF(&slab2->opslab_slots, slab2->opslab_first)) >= sz);

    /* Create a new op slot */
    slot = (OPSLOT *)((I32 **)slab2->opslab_first - sz);
    assert(slot >= &slab2->opslab_slots);
    if (DIFF(&slab2->opslab_slots, slot)
	 < SIZE_TO_PSIZE(sizeof(OP)) + OPSLOT_HEADER_P)
	slot = &slab2->opslab_slots;
    INIT_OPSLOT;
    DEBUG_S_warn((aTHX_ "allocating op at %p, slab %p, in space %lu >= %lu",
                  (void*)o, (void*)slab, (unsigned long)space, (unsigned long)sz));

  gotit:
    assert(!o->op_rettype);
#ifdef PERL_OP_PARENT
    /* moresib == 0, op_sibling == 0 implies a solitary unattached op */
    assert(!o->op_moresib);
    assert(!o->op_sibparent);
#endif

    return (void *)o;
}

#undef INIT_OPSLOT

#ifdef PERL_DEBUG_READONLY_OPS
void
Perl_Slab_to_ro(pTHX_ OPSLAB *slab)
{
    PERL_ARGS_ASSERT_SLAB_TO_RO;

    if (slab->opslab_readonly) return;
    slab->opslab_readonly = 1;
    for (; slab; slab = slab->opslab_next) {
	/*DEBUG_U(PerlIO_printf(Perl_debug_log,"mprotect ->ro %lu at %p\n",
			      (unsigned long) slab->opslab_size, slab));*/
	if (mprotect(slab, slab->opslab_size * sizeof(I32 *), PROT_READ))
	    Perl_warn(aTHX_ "mprotect for %p %lu failed with %d", slab,
			     (unsigned long)slab->opslab_size, errno);
    }
}

void
Perl_Slab_to_rw(pTHX_ OPSLAB *const slab)
{
    OPSLAB *slab2;

    PERL_ARGS_ASSERT_SLAB_TO_RW;

    if (!slab->opslab_readonly) return;
    slab2 = slab;
    for (; slab2; slab2 = slab2->opslab_next) {
	/*DEBUG_U(PerlIO_printf(Perl_debug_log,"mprotect ->rw %lu at %p\n",
			      (unsigned long) size, slab2));*/
	if (mprotect((void *)slab2, slab2->opslab_size * sizeof(I32 *),
		     PROT_READ|PROT_WRITE)) {
	    Perl_warn(aTHX_ "mprotect RW for %p %lu failed with %d", slab,
			     (unsigned long)slab2->opslab_size, errno);
	}
    }
    slab->opslab_readonly = 0;
}

#else
#  define Slab_to_rw(op)    NOOP
#endif

/* This cannot possibly be right, but it was copied from the old slab
   allocator, to which it was originally added, without explanation, in
   commit 083fcd5. */
#ifdef NETWARE
#    define PerlMemShared PerlMem
#endif

/* make freed ops die if they're inadvertently executed */
#ifdef DEBUGGING
static OP *
S_pp_freed(pTHX)
{
    if (PL_op->op_targ)
        DIE(aTHX_ "panic: freed op %s 0x%p called\n",
                  PL_op_name[PL_op->op_targ], PL_op);
    else
        DIE(aTHX_ "panic: freed op 0x%p called\n", PL_op);
}
#endif

/*
=for apidoc Xp|void	|Slab_Free	|NN void *op

Free memory for the slabbed op.

=cut
*/
void
Perl_Slab_Free(pTHX_ void *op)
{
    OP * const o = (OP *)op;
    OPSLAB *slab;
#ifdef DEBUGGING
    size_t space;
#endif

    PERL_ARGS_ASSERT_SLAB_FREE;

#ifdef DEBUGGING
    o->op_ppaddr = S_pp_freed;
    o->op_targ = (PADOFFSET)o->op_type;
#endif
    /* If this op is already freed, our refcount will get screwy. */
    assert(ISNT_TYPE(o, FREED));

    if (!o->op_slabbed) {
        if (!o->op_static)
	    PerlMemShared_free(op);
	return;
    }
    o->op_type = OP_FREED;
    slab = OpSLAB(o);
    OpNEXT(o) = slab->opslab_freed;
    slab->opslab_freed = o;
#ifdef DEBUGGING
    space = OpSLOT(o)->opslot_next ? DIFF(OpSLOT(o), OpSLOT(o)->opslot_next) : 0;
#endif
    DEBUG_S_warn((aTHX_ "free op at %p, recorded in slab %p, size %lu", (void*)o,
                  (void*)slab, (unsigned long)space));
    assert(space < 1000); /* maxop size, catch slab corruption by external modules (Variable::Magic) */
    OpslabREFCNT_dec_padok(slab);
}

/*
=for apidoc p|void	|opslab_free_nopad	|NN OPSLAB* slab

Frees the slab area, embedded into temporary disabling PL_comppad.

=cut
*/
void
Perl_opslab_free_nopad(pTHX_ OPSLAB *slab)
{
    const bool havepad = !!PL_comppad;
    PERL_ARGS_ASSERT_OPSLAB_FREE_NOPAD;
    if (havepad) {
	ENTER;
	PAD_SAVE_SETNULLPAD();
    }
    opslab_free(slab);
    if (havepad) LEAVE;
}

/*
=for apidoc p|void	|opslab_free	|NN OPSLAB* slab

Frees the slab area.

=cut
*/
void
Perl_opslab_free(pTHX_ OPSLAB *slab)
{
    OPSLAB *slab2;
    PERL_ARGS_ASSERT_OPSLAB_FREE;
    PERL_UNUSED_CONTEXT;
    DEBUG_S_warn((aTHX_ "freeing slab %p", (void*)slab));
    assert(slab->opslab_refcnt == 1);
    do {
	slab2 = slab->opslab_next;
#ifdef DEBUGGING
	slab->opslab_refcnt = ~(size_t)0;
#endif
#ifdef PERL_DEBUG_READONLY_OPS
	DEBUG_m(PerlIO_printf(Perl_debug_log, "Deallocate slab at %p\n",
					       (void*)slab));
	if (munmap(slab, slab->opslab_size * sizeof(I32 *))) {
	    perror("munmap failed");
	    abort();
	}
#else
	PerlMemShared_free(slab);
#endif
        slab = slab2;
    } while (slab);
}

/*
=for apidoc p|void	|opslab_force_free	|NN OPSLAB* slab

Forcefully frees the slab area, even if there are still live OPs in
it.  Frees all the containing OPs.

=cut
*/
void
Perl_opslab_force_free(pTHX_ OPSLAB *slab)
{
    OPSLAB *slab2;
#ifdef DEBUGGING
    size_t savestack_count = 0;
#endif
    PERL_ARGS_ASSERT_OPSLAB_FORCE_FREE;
    DEBUG_S_warn((aTHX_ "forced freeing slab %p", (void*)slab));
    slab2 = slab;
    do {
        OPSLOT *slot;
	for (slot = slab2->opslab_first;
	     slot->opslot_next;
	     slot = slot->opslot_next) {
	    if (slot->opslot_op.op_type != OP_FREED
	     && !(slot->opslot_op.op_savefree
#ifdef DEBUGGING
		  && ++savestack_count
#endif
		 )
	    ) {
		assert(slot->opslot_op.op_slabbed);
		op_free(&slot->opslot_op);
		if (slab->opslab_refcnt == 1) goto free;
	    }
	}
    } while ((slab2 = slab2->opslab_next));
    /* > 1 because the CV still holds a reference count. */
    if (slab->opslab_refcnt > 1) { /* still referenced by the savestack */
#ifdef DEBUGGING
	assert(savestack_count == slab->opslab_refcnt-1);
#endif
	/* Remove the CV’s reference count. */
	slab->opslab_refcnt--;
	return;
    }
   free:
    opslab_free(slab);
}

#ifdef PERL_DEBUG_READONLY_OPS
OP *
Perl_op_refcnt_inc(pTHX_ OP *o)
{
    if(o) {
        OPSLAB *const slab = o->op_slabbed ? OpSLAB(o) : NULL;
        if (slab && slab->opslab_readonly) {
            Slab_to_rw(slab);
            ++o->op_targ;
            Slab_to_ro(slab);
        } else {
            ++o->op_targ;
        }
    }
    return o;

}

PADOFFSET
Perl_op_refcnt_dec(pTHX_ OP *o)
{
    PADOFFSET result;
    OPSLAB *const slab = o->op_slabbed ? OpSLAB(o) : NULL;

    PERL_ARGS_ASSERT_OP_REFCNT_DEC;

    if (slab && slab->opslab_readonly) {
        Slab_to_rw(slab);
        result = --o->op_targ;
        Slab_to_ro(slab);
    } else {
        result = --o->op_targ;
    }
    return result;
}
#endif
/*
 * In the following definition, the ", (OP*)0" is just to make the compiler
 * think the expression is of the right type: croak actually does a Siglongjmp.
 */
#define CHECKOP(type,o) \
    ((PL_op_mask && PL_op_mask[type])				\
     ? ( op_free((OP*)o),					\
	 Perl_croak(aTHX_ "'%s' trapped by operation mask", PL_op_desc[type]),	\
	 (OP*)0 )						\
     : PL_check[type](aTHX_ (OP*)o))

#define RETURN_UNLIMITED_NUMBER (PERL_INT_MAX / 2)

/*
=for apidoc sR	|OP*	|no_fh_allowed	|NN OP *o

Throws a parser error: Missing comma after first argument to %s function
for an op which does not take an optional comma-less filehandle argument.
i.e. not C<print $fh arg>, rather C<call $fh, $arg>.

=cut
*/
static OP *
S_no_fh_allowed(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_NO_FH_ALLOWED;

    yyerror(Perl_form(aTHX_ "Missing comma after first argument to %s function",
		 OP_DESC(o)));
    return o;
}

static OP *
S_too_few_arguments_pv(pTHX_ OP *o, const char* name, U32 flags)
{
    PERL_ARGS_ASSERT_TOO_FEW_ARGUMENTS_PV;
    yyerror_pv(Perl_form(aTHX_ "Not enough arguments for %s", name), flags);
    return o;
}

static OP *
S_too_many_arguments_pv(pTHX_ OP *o, const char *name, U32 flags)
{
    PERL_ARGS_ASSERT_TOO_MANY_ARGUMENTS_PV;

    yyerror_pv(Perl_form(aTHX_ "Too many arguments for %s", name), flags);
    return o;
}

static void
S_bad_type_pv(pTHX_ I32 n, const char *t, const OP *o, const OP *kid)
{
    PERL_ARGS_ASSERT_BAD_TYPE_PV;

    yyerror_pv(Perl_form(aTHX_ "Type of arg %d to %s must be %s (not %s)",
		 (int)n, PL_op_desc[(o)->op_type], t, OP_DESC(kid)), 0);
}

/* remove flags var, its unused in all callers, move to to right end since gv
  and kid are always the same */
static void
S_bad_type_gv(pTHX_ I32 n, GV *gv, const OP *kid, const char *t)
{
    SV * const namesv = cv_name((CV *)gv, NULL, CV_NAME_NOMAIN);
    PERL_ARGS_ASSERT_BAD_TYPE_GV;
 
    yyerror_pv(Perl_form(aTHX_ "Type of arg %d to %" SVf " must be %s (not %s)",
		 (int)n, SVfARG(namesv), t, OP_DESC(kid)), SvUTF8(namesv));
}

/* so far for scalars only */
PERL_STATIC_INLINE const char *
S_core_type_name(pTHX_ core_types_t t)
{
    if (t == type_Void)
        return "Void";
    else if (t > type_Any)
        Perl_die(aTHX_ "Invalid coretype index %d\n", t);
    return core_types_n[t];
}

static void
S_bad_type_core(pTHX_ const char *argname, GV *gv,
                core_types_t got, const char* gotname, bool gotu8,
                const char *wanted, bool wu8)
{
    SV * const namesv = cv_name((CV *)gv, NULL, CV_NAME_NOMAIN);
    const char *name = got == type_Object ? gotname : core_type_name(got);
    PERL_ARGS_ASSERT_BAD_TYPE_CORE;
    PERL_UNUSED_ARG(gotu8);
    PERL_UNUSED_ARG(wu8);
    assert(namesv);

    /* TODO utf8 for got and wanted */
    /* diag_listed_as: Type of arg %d to %s must be %s (not %s) */
    yyerror_pv(Perl_form(aTHX_ "Type of arg %s to %" SVf " must be %s (not %s)",
                         argname, SVfARG(namesv), wanted, name),
               SvUTF8(namesv));
}

static void
S_warn_type_core(pTHX_ const char *argname, const char *to,
                 core_types_t got, const char* gotname,
                 const char *wanted)
{
    const char *name = got == type_Object ? gotname : core_type_name(got);
    Perl_ck_warner(aTHX_ packWARN(WARN_TYPES),
                   "Type of %s to %s must be %s (not %s)",
                   to, argname, wanted, name);
}

static void
S_no_bareword_allowed(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_NO_BAREWORD_ALLOWED;

    qerror(Perl_mess(aTHX_
		     "Bareword \"%" SVf "\" not allowed while \"strict subs\" in use",
		     SVfARG(cSVOPo_sv)));
    o->op_private &= ~OPpCONST_STRICT; /* prevent warning twice about the same OP */
}

/*
=for p	|PADOFFSET|allocmy	|NN const char *const name|const STRLEN len\
				|const U32 flags

"register" allocation.

Does some sanity checking, adds a new pad variable via pad_add_name_pvn()
and returns the targ offset for it.

=cut
*/
PADOFFSET
Perl_allocmy(pTHX_ const char *const name, const STRLEN len, const U32 flags)
{
    PADOFFSET off;
    const bool is_our = (PL_parser->in_my == KEY_our);

    PERL_ARGS_ASSERT_ALLOCMY;

    if (flags & ~SVf_UTF8)
	Perl_croak(aTHX_ "panic: allocmy illegal flag bits 0x%" UVxf,
		   (UV)flags);

    /* complain about "my $<special_var>" etc etc */
    if (   len
        && !(  is_our
            || isALPHA(name[1])
            || (   (flags & SVf_UTF8)
                && isIDFIRST_utf8_safe((U8 *)name+1, name + len))
            || (name[1] == '_' && (*name == '$' || len > 2))))
    {
	if (!(flags & SVf_UTF8 && UTF8_IS_START(name[1]))
	 && isASCII(name[1])
	 && (!isPRINT(name[1]) || strchr("\t\n\r\f", name[1]))) {
	    /* diag_listed_as: Can't use global %s in "%s" */
	    yyerror(Perl_form(aTHX_ "Can't use global %c^%c%.*s in \"%s\"",
			      name[0], toCTRL(name[1]), (int)(len - 2), name + 2,
			      PL_parser->in_my == KEY_state ? "state" : "my"));
	} else {
	    yyerror_pv(Perl_form(aTHX_ "Can't use global %.*s in \"%s\"", (int) len, name,
			      PL_parser->in_my == KEY_state ? "state" : "my"), flags & SVf_UTF8);
	}
    }
#ifndef USE_CPERL
    else if (len == 2 && name[1] == '_' && !is_our)
	Perl_croak(aTHX_ "Can't use global %s in \"%s\"",
                   "$_", PL_parser->in_my == KEY_state
                         ? "state"
                         : "my");
#endif

    /* allocate a spare slot and store the name in that slot */

    off = pad_add_name_pvn(name, len,
		       (is_our ? padadd_OUR :
		        PL_parser->in_my == KEY_state ? padadd_STATE : 0)
                           | (flags & SVf_UTF8 ? padadd_UTF8 : 0),
		    PL_parser->in_my_stash,
		    (is_our
		        /* $_ is always in main::, even with our */
			? (PL_curstash && !memEQs(name,len,"$_")
			    ? PL_curstash
			    : PL_defstash)
			: NULL
		    )
    );
    /* anon sub prototypes contains state vars should always be cloned,
     * otherwise the state var would be shared between anon subs */

    if (PL_parser->in_my == KEY_state && CvANON(PL_compcv))
	CvCLONE_on(PL_compcv);

    return off;
}

/*
=head1 Optree Manipulation Functions

=for apidoc alloccopstash

Available only under threaded builds, this function allocates an entry in
C<PL_stashpad> for the stash passed to it.

=cut
*/

#ifdef USE_ITHREADS
PADOFFSET
Perl_alloccopstash(pTHX_ HV *hv)
{
    PADOFFSET off = 0, o = 1;
    bool found_slot = FALSE;

    PERL_ARGS_ASSERT_ALLOCCOPSTASH;

    if (PL_stashpad[PL_stashpadix] == hv) return PL_stashpadix;

    for (; o < PL_stashpadmax; ++o) {
	if (PL_stashpad[o] == hv) return PL_stashpadix = o;
	if (!PL_stashpad[o] || SvTYPE(PL_stashpad[o]) != SVt_PVHV)
	    found_slot = TRUE, off = o;
    }
    if (!found_slot) {
	Renew(PL_stashpad, PL_stashpadmax + 10, HV *);
	Zero(PL_stashpad + PL_stashpadmax, 10, HV *);
	off = PL_stashpadmax;
	PL_stashpadmax += 10;
    }

    PL_stashpad[PL_stashpadix = off] = hv;
    return off;
}
#endif


/*
=for s|void	|op_destroy	|NN OP* o

Free the body of an op without examining its contents.
Always use this rather than FreeOp directly.

=cut
*/
PERL_STATIC_INLINE void
S_op_destroy(pTHX_ OP *o)
{
    FreeOp(o);
}

/* Destructor */

/*
=for apidoc Am|void	|op_free	|OP *o

Free an op.  Only use this when an op is no longer linked to from any
optree.

=cut
*/
void
Perl_op_free(pTHX_ OP *o)
{
#ifdef DEBUGGING
    dVAR;
#endif
    OPCODE type;
    SSize_t defer_ix = -1;
    SSize_t defer_stack_alloc = 0;
    OP **defer_stack = NULL;

    do {

        /* Though ops may be freed twice, freeing the op after its slab is a
           big no-no. */
        assert(!o || !o->op_slabbed || OpSLAB(o)->opslab_refcnt != ~(size_t)0);
        /* During the forced freeing of ops after compilation failure, kidops
           may be freed before their parents. */
        if (!o || IS_TYPE(o, FREED))
            continue;

        type = o->op_type;

        /* an op should only ever acquire op_private flags that we know about.
         * If this fails, you may need to fix something in regen/op_private.
         * Don't bother testing if:
         *   * the op_ppaddr doesn't match the op; someone may have
         *     overridden the op and be doing strange things with it;
         *   * we've errored, as op flags are often left in an
         *     inconsistent state then. Note that an error when
         *     compiling the main program leaves PL_parser NULL, so
         *     we can't spot faults in the main code, only
         *     evaled/required code */
#ifdef DEBUGGING
        if (   o->op_ppaddr == PL_ppaddr[o->op_type]
            && PL_parser
            && !PL_parser->error_count)
        {
            assert(!(o->op_private & ~PL_op_private_valid[type]));
        }
#endif

        if (UNLIKELY(o->op_private & OPpREFCOUNTED)) {
            switch (type) {
            case OP_LEAVESUB:
            case OP_LEAVESUBLV:
            case OP_LEAVEEVAL:
            case OP_LEAVE:
            case OP_SCOPE:
            case OP_LEAVEWRITE:
                {
                PADOFFSET refcnt;
                OP_REFCNT_LOCK;
                refcnt = OpREFCNT_dec(o);
                OP_REFCNT_UNLOCK;
                if (refcnt) {
                    /* Need to find and remove any pattern match ops from the list
                       we maintain for reset().  */
                    find_and_forget_pmops(o);
                    continue;
                }
                }
                break;
            default:
                break;
            }
        }

        /* Call the op_free hook if it has been set. Do it now so that it's called
         * at the right time for refcounted ops, but still before all of the kids
         * are freed. */
        CALL_OPFREEHOOK(o);

        if (OpKIDS(o)) {
            OP *kid, *nextkid;
            for (kid = OpFIRST(o); kid; kid = nextkid) {
                nextkid = OpSIBLING(kid); /* Get before next freeing kid */
                if (!kid || IS_TYPE(kid, FREED))
                    /* During the forced freeing of ops after
                       compilation failure, kidops may be freed before
                       their parents. */
                    continue;
                if (!OpKIDS(kid))
                    /* If it has no kids, just free it now */
                    op_free(kid);
                else
                    DEFER_OP(kid);
            }
        }
        if (UNLIKELY(type == OP_NULL))
            type = (OPCODE)o->op_targ;

#ifdef PERL_DEBUG_READONLY_OPS
        /* otherwise a NOOP */
        if (o->op_slabbed)
            Slab_to_rw(OpSLAB(o));
#endif

        /* COP* is not cleared by op_clear() so that we may track line
         * numbers etc even after null() */
        if (type == OP_NEXTSTATE || type == OP_DBSTATE) {
            cop_free((COP*)o);
        }

        op_clear(o);
        if (LIKELY(!o->op_static))
            FreeOp(o); /* Which is Slab_Free() */
        if (PL_op == o)
            PL_op = NULL;
    } while ( (o = POP_DEFERRED_OP()) );

    Safefree(defer_stack);
}

/*
=for apidoc op_clear_gv

Free a GV attached to an OP

=cut
*/
static void
#ifdef USE_ITHREADS
S_op_clear_gv(pTHX_ OP *o, PADOFFSET *ixp)
#else
S_op_clear_gv(pTHX_ OP *o, SV**svp)
#endif
{

    GV *gv = (o &&
              (   IS_TYPE(o, GV)
               || IS_TYPE(o, GVSV)
               || IS_TYPE(o, MULTIDEREF)
               || IS_TYPE(o, SIGNATURE)))
#ifdef USE_ITHREADS
                && PL_curpad
                ? ((GV*)PAD_SVl(*ixp)) : NULL;
#else
                ? (GV*)(*svp) : NULL;
#endif
    /* It's possible during global destruction that the GV is freed
       before the optree. Whilst the SvREFCNT_inc is happy to bump from
       0 to 1 on a freed SV, the corresponding SvREFCNT_dec from 1 to 0
       will trigger an assertion failure, because the entry to sv_clear
       checks that the scalar is not already freed.  A check of for
       !SvIS_FREED(gv) turns out to be invalid, because during global
       destruction the reference count can be forced down to zero
       (with SVf_BREAK set).  In which case raising to 1 and then
       dropping to 0 triggers cleanup before it should happen.  I
       *think* that this might actually be a general, systematic,
       weakness of the whole idea of SVf_BREAK, in that code *is*
       allowed to raise and lower references during global destruction,
       so any *valid* code that happens to do this during global
       destruction might well trigger premature cleanup.  */
    bool still_valid = gv && SvREFCNT(gv);
    PERL_ARGS_ASSERT_OP_CLEAR_GV;

    if (still_valid)
        SvREFCNT_inc_simple_void(gv);
#ifdef USE_ITHREADS
    if (*ixp > 0) {
        pad_swipe(*ixp, TRUE);
        *ixp = 0;
    }
#else
    SvREFCNT_dec(*svp);
    *svp = NULL;
#endif
    if (still_valid) {
        int try_downgrade = SvREFCNT(gv) == 2;
        SvREFCNT_dec_NN(gv);
        if (try_downgrade)
            gv_try_downgrade(gv);
    }
}


/*
=for apidoc EXp	|void	|op_clear	|NN OP* o

free all the SVs (gv, pad, ...) attached to the op.

=cut
*/
void
Perl_op_clear(pTHX_ OP *o)
{

    dVAR;

    PERL_ARGS_ASSERT_OP_CLEAR;

    switch (o->op_type) {
    case OP_NULL:	/* Was holding old type, if any. */
        /* FALLTHROUGH */
    case OP_ENTERTRY:
    case OP_ENTEREVAL:	/* Was holding hints. */
	o->op_targ = 0;
	break;
    default:
	if (!(o->op_flags & OPf_REF)
	    || (PL_check[o->op_type] != Perl_ck_ftst))
	    break;
	/* FALLTHROUGH */
    case OP_GVSV:
    case OP_GV:
    case OP_AELEMFAST:
#ifdef USE_ITHREADS
            op_clear_gv(o, &(cPADOPx(o)->op_padix));
#else
            op_clear_gv(o, &(cSVOPx(o)->op_sv));
#endif
	break;
    case OP_METHOD_REDIR:
    case OP_METHOD_REDIR_SUPER:
#ifdef USE_ITHREADS
	if (cMETHOPx(o)->op_rclass_targ) {
	    pad_swipe(cMETHOPx(o)->op_rclass_targ, 1);
	    cMETHOPx(o)->op_rclass_targ = 0;
	}
#else
	SvREFCNT_dec(cMETHOPx(o)->op_rclass_sv);
	cMETHOPx(o)->op_rclass_sv = NULL;
#endif
        /* FALLTHROUGH */
    case OP_METHOD_NAMED:
    case OP_METHOD_SUPER:
        SvREFCNT_dec(cMETHOPx(o)->op_u.op_meth_sv);
        cMETHOPx(o)->op_u.op_meth_sv = NULL;
#ifdef USE_ITHREADS
        if (o->op_targ) {
            pad_swipe(o->op_targ, 1);
            o->op_targ = 0;
        }
#endif
        break;
    case OP_CONST:
    case OP_HINTSEVAL:
	SvREFCNT_dec(cSVOPo->op_sv);
	cSVOPo->op_sv = NULL;
#ifdef USE_ITHREADS
	/** Bug #15654
	  Even if op_clear does a pad_free for the target of the op,
	  pad_free doesn't actually remove the sv that exists in the pad;
	  instead it lives on. This results in that it could be reused as 
	  a target later on when the pad was reallocated.
	**/
        if(o->op_targ) {
          pad_swipe(o->op_targ,1);
          o->op_targ = 0;
        }
#endif
	break;
    case OP_DUMP:
    case OP_GOTO:
    case OP_NEXT:
    case OP_LAST:
    case OP_REDO:
	if (o->op_flags & (OPf_SPECIAL|OPf_STACKED|OPf_KIDS))
	    break;
	/* FALLTHROUGH */
    case OP_TRANS:
    case OP_TRANSR:
        if (   (IS_TYPE(o, TRANS) || IS_TYPE(o, TRANSR))
            && (o->op_private & (OPpTRANS_FROM_UTF|OPpTRANS_TO_UTF)))
        {
#ifdef USE_ITHREADS
	    if (cPADOPo->op_padix > 0) {
		pad_swipe(cPADOPo->op_padix, TRUE);
		cPADOPo->op_padix = 0;
	    }
#else
	    SvREFCNT_dec(cSVOPo->op_sv);
	    cSVOPo->op_sv = NULL;
#endif
	}
	else {
	    PerlMemShared_free(cPVOPo->op_pv);
	    cPVOPo->op_pv = NULL;
	}
	break;
    case OP_SUBST:
	op_free(cPMOPo->op_pmreplrootu.op_pmreplroot);
	goto clear_pmop;

    case OP_SPLIT:
        if ( (o->op_private & OPpSPLIT_ASSIGN) /* @array  = split */
         && !OpSTACKED(o))                     /* @{expr} = split */
        {
            if (o->op_private & OPpSPLIT_LEX)
                pad_free(cPMOPo->op_pmreplrootu.op_pmtargetoff);
            else
#ifdef USE_ITHREADS
                pad_swipe(cPMOPo->op_pmreplrootu.op_pmtargetoff, TRUE);
#else
                SvREFCNT_dec(MUTABLE_SV(cPMOPo->op_pmreplrootu.op_pmtargetgv));
#endif
        }
	/* FALLTHROUGH */
    case OP_MATCH:
    case OP_QR:
    clear_pmop:
	if (!(cPMOPo->op_pmflags & PMf_CODELIST_PRIVATE))
	    op_free(cPMOPo->op_code_list);
	cPMOPo->op_code_list = NULL;
	forget_pmop(cPMOPo);
	cPMOPo->op_pmreplrootu.op_pmreplroot = NULL;
        /* we use the same protection as the "SAFE" version of the PM_ macros
         * here since sv_clean_all might release some PMOPs
         * after PL_regex_padav has been cleared
         * and the clearing of PL_regex_padav needs to
         * happen before sv_clean_all
         */
#ifdef USE_ITHREADS
	if(PL_regex_pad) {        /* We could be in destruction */
	    const IV offset = (cPMOPo)->op_pmoffset;
	    ReREFCNT_dec(PM_GETRE(cPMOPo));
	    PL_regex_pad[offset] = UNDEF;
            sv_catpvn_nomg(PL_regex_pad[0], (const char *)&offset,
			   sizeof(offset));
        }
#else
	ReREFCNT_dec(PM_GETRE(cPMOPo));
	PM_SETRE(cPMOPo, NULL);
#endif

	break;

#ifndef USE_CPERL
    case OP_ARGCHECK:
        PerlMemShared_free(cUNOP_AUXo->op_aux);
        break;
#endif
  
    case OP_MULTICONCAT:
        {
            UNOP_AUX_item *aux = cUNOP_AUXo->op_aux;
            /* aux[PERL_MULTICONCAT_IX_PLAIN_PV] and/or
             * aux[PERL_MULTICONCAT_IX_UTF8_PV] point to plain and/or
             * utf8 shared strings */
            char *p1 = aux[PERL_MULTICONCAT_IX_PLAIN_PV].pv;
            char *p2 = aux[PERL_MULTICONCAT_IX_UTF8_PV].pv;
            if (p1)
                PerlMemShared_free(p1);
            if (p2 && p1 != p2)
                PerlMemShared_free(p2);
            PerlMemShared_free(aux);
        }
        break;

    case OP_MULTIDEREF:
        {
            UNOP_AUX_item *items = cUNOP_AUXo->op_aux;
            UV actions = items->uv;
            bool last = 0;
            bool is_hash = FALSE;

            while (!last) {
                switch (actions & MDEREF_ACTION_MASK) {

                case MDEREF_reload:
                    actions = (++items)->uv;
                    continue;

                case MDEREF_HV_padhv_helem:
                    is_hash = TRUE;
                    /* FALLTHROUGH */
                case MDEREF_AV_padav_aelem:
                    pad_free((++items)->pad_offset);
                    goto do_elem;

                case MDEREF_HV_gvhv_helem:
                    is_hash = TRUE;
                    /* FALLTHROUGH */
                case MDEREF_AV_gvav_aelem:
#ifdef USE_ITHREADS
                    op_clear_gv(o, &((++items)->pad_offset));
#else
                    op_clear_gv(o, &((++items)->sv));
#endif
                    goto do_elem;

                case MDEREF_HV_gvsv_vivify_rv2hv_helem:
                    is_hash = TRUE;
                    /* FALLTHROUGH */
                case MDEREF_AV_gvsv_vivify_rv2av_aelem:
#ifdef USE_ITHREADS
                    op_clear_gv(o, &((++items)->pad_offset));
#else
                    op_clear_gv(o, &((++items)->sv));
#endif
                    goto do_vivify_rv2xv_elem;

                case MDEREF_HV_padsv_vivify_rv2hv_helem:
                    is_hash = TRUE;
                    /* FALLTHROUGH */
                case MDEREF_AV_padsv_vivify_rv2av_aelem:
                    pad_free((++items)->pad_offset);
                    goto do_vivify_rv2xv_elem;

                case MDEREF_HV_pop_rv2hv_helem:
                case MDEREF_HV_vivify_rv2hv_helem:
                    is_hash = TRUE;
                    /* FALLTHROUGH */
                do_vivify_rv2xv_elem:
                case MDEREF_AV_pop_rv2av_aelem:
                case MDEREF_AV_vivify_rv2av_aelem:
                do_elem:
                    switch (actions & MDEREF_INDEX_MASK) {
                    case MDEREF_INDEX_none:
                        last = 1;
                        break;
                    case MDEREF_INDEX_const:
                        if (is_hash) {
#ifdef USE_ITHREADS
                            /* see RT #15654 */
                            pad_swipe((++items)->pad_offset, 1);
#else
                            SvREFCNT_dec((++items)->sv);
#endif
                        }
                        else
                            items++;
                        break;
                    case MDEREF_INDEX_padsv:
                        pad_free((++items)->pad_offset);
                        break;
                    case MDEREF_INDEX_gvsv:
#ifdef USE_ITHREADS
                        op_clear_gv(o, &((++items)->pad_offset));
#else
                        op_clear_gv(o, &((++items)->sv));
#endif
                        break;
                    }

                    if (actions & MDEREF_FLAG_last)
                        last = 1;
                    is_hash = FALSE;

                    break;

                default:
                    assert(0);
                    last = 1;
                    break;

                } /* switch */

                actions >>= MDEREF_SHIFT;
            } /* while */

            /* start of malloc is at op_aux[-1], where the length is
             * stored */
            PerlMemShared_free(cUNOP_AUXo->op_aux - 1);
        }
        break;

    case OP_SIGNATURE:
        {
            UNOP_AUX_item *items = cUNOP_AUXo->op_aux;
            UV actions = (++items)->uv;
            int go = 1;

            while (go) {
                switch (actions & SIGNATURE_ACTION_MASK) {
                case SIGNATURE_reload:
                    actions = (++items)->uv;
                    continue;
                case SIGNATURE_end:
                    go = 0;
                    break;
                case SIGNATURE_padintro:
                case SIGNATURE_arg_default_iv:
                    items++;
                    break;
                case SIGNATURE_arg_default_padsv:
                    pad_free((++items)->pad_offset);
                    break;

                case SIGNATURE_arg_default_gvsv:
#ifdef USE_ITHREADS
                    op_clear_gv(o, &((++items)->pad_offset));
#else
                    op_clear_gv(o, &((++items)->sv));
#endif
                    break;

                case SIGNATURE_arg_default_const:
#ifdef USE_ITHREADS
                    /* see RT #15654 */
                    pad_swipe((++items)->pad_offset, 1);
#else
                    SvREFCNT_dec((++items)->sv);
#endif
                    break;

                } /* switch */
                actions >>= SIGNATURE_SHIFT;
            } /* while */

            PerlMemShared_free(cUNOP_AUXo->op_aux - 1);
            break;
        } /* OP_SIGNATURE */

    } /* switch */

    if (o->op_targ > 0) {
	pad_free(o->op_targ);
	o->op_targ = 0;
    }
}

static void
S_cop_free(pTHX_ COP* cop)
{
    PERL_ARGS_ASSERT_COP_FREE;

    if (cop->op_static)
        goto curcop;
    CopFILE_free(cop);
    if (! specialWARN(cop->cop_warnings))
	PerlMemShared_free(cop->cop_warnings);
    cophh_free(CopHINTHASH_get(cop));
 curcop:
    if (PL_curcop == cop)
       PL_curcop = NULL;
}

static void
S_forget_pmop(pTHX_ PMOP *const o
	      )
{
    HV * const pmstash = PmopSTASH(o);

    PERL_ARGS_ASSERT_FORGET_PMOP;

    if (pmstash && !SvIS_FREED(pmstash) && SvMAGICAL(pmstash)) {
	MAGIC * const mg = mg_find((const SV *)pmstash, PERL_MAGIC_symtab);
	if (mg) {
	    PMOP **const array = (PMOP**) mg->mg_ptr;
	    U32 count = mg->mg_len / sizeof(PMOP**);
	    U32 i = count;

	    while (i--) {
		if (array[i] == o) {
		    /* Found it. Move the entry at the end to overwrite it.  */
		    array[i] = array[--count];
		    mg->mg_len = count * sizeof(PMOP**);
		    /* Could realloc smaller at this point always, but probably
		       not worth it. Probably worth free()ing if we're the
		       last.  */
		    if(!count) {
			Safefree(mg->mg_ptr);
			mg->mg_ptr = NULL;
		    }
		    break;
		}
	    }
	}
    }
    if (PL_curpm == o) 
	PL_curpm = NULL;
}

static void
S_find_and_forget_pmops(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_FIND_AND_FORGET_PMOPS;

    if (OpKIDS(o)) {
        OP *kid = OpFIRST(o);
	while (kid) {
	    switch (kid->op_type) {
	    case OP_SUBST:
	    case OP_SPLIT:
	    case OP_MATCH:
	    case OP_QR:
		forget_pmop((PMOP*)kid);
	    }
	    find_and_forget_pmops(kid);
	    kid = OpSIBLING(kid);
	}
    }
}

/*
=for apidoc Am|void	|op_null	|OP *o

Neutralizes an op when it is no longer needed, but is still linked to from
other ops.

=cut
*/

void
Perl_op_null(pTHX_ OP *o)
{
    dVAR;

    PERL_ARGS_ASSERT_OP_NULL;

    if (IS_NULL_OP(o))
	return;
    op_clear(o);
    o->op_targ = o->op_type;
    OpTYPE_set(o, OP_NULL);
}

void
Perl_op_refcnt_lock(pTHX)
  PERL_TSA_ACQUIRE(PL_op_mutex)
{
#ifdef USE_ITHREADS
    dVAR;
#endif
    PERL_UNUSED_CONTEXT;
    OP_REFCNT_LOCK;
}

void
Perl_op_refcnt_unlock(pTHX)
  PERL_TSA_RELEASE(PL_op_mutex)
{
#ifdef USE_ITHREADS
    dVAR;
#endif
    PERL_UNUSED_CONTEXT;
    OP_REFCNT_UNLOCK;
}


/*
=for apidoc Apdn|OP*	|op_sibling_splice	|\
	NULLOK OP *parent |NULLOK OP *start |int del_count |NULLOK OP* insert

A general function for editing the structure of an existing chain of
op_sibling nodes.  By analogy with the perl-level C<splice()> function, allows
you to delete zero or more sequential nodes, replacing them with zero or
more different nodes.  Performs the necessary op_first/op_last
housekeeping on the parent node and op_sibling manipulation on the
children.  The last deleted node will be marked as as the last node by
updating the op_sibling/op_sibparent or op_moresib field as appropriate.

Note that op_next is not manipulated, and nodes are not freed; that is the
responsibility of the caller.  It also won't create a new list op for an
empty list etc; use higher-level functions like op_append_elem() for that.

C<parent> is the parent node of the sibling chain. It may passed as C<NULL> if
the splicing doesn't affect the first or last op in the chain.

C<start> is the node preceding the first node to be spliced.  Sibling node(s)
following it will be deleted, and ops will be inserted after it.  If it is
C<NULL>, the first node onwards is deleted, and nodes are inserted at the
beginning.

C<del_count> is the number of sibling nodes to delete.  If zero, no
nodes are deleted.  If -1 or greater than or equal to the number of
remaining kids, all remaining kids are deleted.

C<insert> is the first of a chain of nodes to be inserted in place of the nodes.
If C<NULL>, no nodes are inserted.

The head of the chain of deleted ops is returned, or C<NULL> if no ops were
deleted.

For example:

    action                    before      after         returns
    ------                    -----       -----         -------

                              P           P
    splice(P, A, 2, X-Y-Z)    |           |             B-C
                              A-B-C-D     A-X-Y-Z-D

                              P           P
    splice(P, NULL, 1, X-Y)   |           |             A
                              A-B-C-D     X-Y-B-C-D

                              P           P
    splice(P, NULL, 3, NULL)  |           |             A-B-C
                              A-B-C-D     D

                              P           P
    splice(P, B, 0, X-Y)      |           |             NULL
                              A-B-C-D     A-B-X-Y-C-D


For lower-level direct manipulation of C<op_sibparent> and C<op_moresib>,
see C<L</OpMORESIB_set>>, C<L</OpLASTSIB_set>>, C<L</OpMAYBESIB_set>>.

=cut
*/

OP *
Perl_op_sibling_splice(OP *parent, OP *start, int del_count, OP* insert)
{
    OP *first;
    OP *rest;
    OP *last_del = NULL;
    OP *last_ins = NULL;

    if (start)
        first = OpSIBLING(start);
    else
        first = OpFIRST(parent);

    assert(del_count >= -1);

    if (del_count && first) {
        last_del = first;
        while (--del_count && OpHAS_SIBLING(last_del))
            last_del = OpSIBLING(last_del);
        rest = OpSIBLING(last_del);
        OpLASTSIB_set(last_del, NULL);
    }
    else
        rest = first;

    if (insert) {
        last_ins = insert;
        while (OpHAS_SIBLING(last_ins))
            last_ins = OpSIBLING(last_ins);
        OpMAYBESIB_set(last_ins, rest, NULL);
    }
    else
        insert = rest;

    if (start) {
        OpMAYBESIB_set(start, insert, NULL);
    }
    else {
        if (!parent)
            goto no_parent;        
        OpFIRST(parent) = insert;
        if (insert)
            parent->op_flags |= OPf_KIDS;
        else
            parent->op_flags &= ~OPf_KIDS;
    }

    if (!rest) {
        /* update op_last etc */
        U32 type;
        OP *lastop;

        if (!parent)
            goto no_parent;        

        /* ought to use OP_CLASS(parent) here, but that can't handle
         * ex-foo OP_NULL ops. Also note that XopENTRYCUSTOM() can't
         * either */
        type = parent->op_type;
        if (type == OP_CUSTOM) {
            dTHX;
            type = XopENTRYCUSTOM(parent, xop_class);
        }
        else {
            if (type == OP_NULL)
                type = parent->op_targ;
            type = PL_opargs[type] & OA_CLASS_MASK;
        }

        lastop = last_ins ? last_ins : start ? start : NULL;
        if (   type == OA_BINOP
            || type == OA_LISTOP
            || type == OA_PMOP
            || type == OA_LOOP
        )
            OpLAST(parent) = lastop;

        if (lastop)
            OpLASTSIB_set(lastop, parent);
    }
    return last_del ? first : NULL;

  no_parent:
    Perl_croak_nocontext("panic: op_sibling_splice(): NULL parent");
}


/*
=for apidoc Apd|OP*	|op_linklist	|NN OP *o

This function is the implementation of the L</LINKLIST> macro.

It is responsible to establish postfix order of the subtree, the kids,
linking recursively the next pointers together, depending on the
siblings and kids. The head is the exit node, the first kid the start
node, the siblings following each other.

The compiler arranges the optree first with empty op_next pointers.
If LINKLIST is called on an unempty op it does nothing.
LINKLIST sets all the op_next pointers.

The head node must have no op_next pointer, this is the exit condition
for the recursion.

=cut
*/

OP *
Perl_op_linklist(pTHX_ OP *o)
{
    OP *first;
    PERL_ARGS_ASSERT_OP_LINKLIST;

    if (OpNEXT(o))
	return OpNEXT(o);

    /* establish postfix order */
    first = OpFIRST(o);
    if (first) {
        OP *kid;
	OpNEXT(o) = LINKLIST(first);
	kid = first;
	for (;;) {
            OP *sibl = OpSIBLING(kid);
            if (sibl) {
                OpNEXT(kid) = LINKLIST(sibl);
                kid = sibl;
	    } else {
		OpNEXT(kid) = o;
		break;
	    }
	}
    }
    else
	OpNEXT(o) = o;

    return OpNEXT(o);
}

#ifdef PERL_OP_PARENT

/*
=for apidoc op_parent

Returns the parent OP of C<o>, if it has a parent. Returns C<NULL> otherwise.
This function is only available on perls built with C<-DPERL_OP_PARENT>,
which is the default since v5.25.1/v5.25.3c

=cut
*/

OP *
Perl_op_parent(OP *o)
{
    PERL_ARGS_ASSERT_OP_PARENT;
    while (OpHAS_SIBLING(o))
        o = OpSIBLING(o);
    return o->op_sibparent;
}

#endif


/*
=for apidoc s|OP*  |op_sibling_newUNOP	|NULLOK OP *parent|NULLOK OP *start|I32 type|I32 flags

replace the sibling following start with a new UNOP, which becomes
the parent of the original sibling; e.g.

   op_sibling_newUNOP(P, A, unop-args...)
  
   P              P
   |      becomes |
   A-B-C          A-U-C
                    |
                    B

where U is the new UNOP.

parent and start args are the same as for op_sibling_splice();
type and flags args are as newUNOP().

Returns the new UNOP.

=cut
*/

static OP *
S_op_sibling_newUNOP(pTHX_ OP *parent, OP *start, I32 type, I32 flags)
{
    OP *kid = op_sibling_splice(parent, start, 1, NULL);
    OP* newop = newUNOP(type, flags, kid);
    op_sibling_splice(parent, start, 0, newop);
    return newop;
}


/*
=for apidoc pM	|LOGOP*	|alloc_LOGOP	|I32 type|NULLOK OP *first|NULLOK OP *other

lowest-level newLOGOP-style function - just allocates and populates
the struct. Higher-level stuff should be done by S_new_logop() /
newLOGOP(). This function exists mainly to avoid op_first assignment
being spread throughout this file.

=cut
*/

static LOGOP *
S_alloc_LOGOP(pTHX_ I32 type, OP *first, OP* other)
{
    dVAR;
    LOGOP *logop;
    OP *kid = first;
    NewOp(1101, logop, 1, LOGOP);
    OpTYPE_set(logop, type);
    OpFIRST(logop) = first;
    OpOTHER(logop) = other;
    if (kid) {
        logop->op_flags = OPf_KIDS;
        while (kid && OpHAS_SIBLING(kid))
            kid = OpSIBLING(kid);
        OpLASTSIB_set(kid, (OP*)logop);
    }
    return logop;
}


/* Contextualizers */

/*
=for apidoc Am|OP *	|op_contextualize	|NN OP *o|I32 context

Applies a syntactic context to an op tree representing an expression.
C<o> is the op tree, and C<context> must be C<G_SCALAR>, C<G_ARRAY>,
or C<G_VOID> to specify the context to apply, i.e. what the lhs side will expect.
The modified op tree is returned.

=cut
*/

OP *
Perl_op_contextualize(pTHX_ OP *o, I32 context)
{
    PERL_ARGS_ASSERT_OP_CONTEXTUALIZE;
    switch (context) {
	case G_SCALAR: return scalar(o);
	case G_ARRAY:  return list(o);
	case G_VOID:   return scalarvoid(o);
	default:
	    Perl_croak(aTHX_ "panic: op_contextualize bad context %ld",
		       (long) context);
    }
}

/*
=for apidoc s|OP*	|scalarkids	|NN OP* o

Sets scalar context for all kids.

=cut
*/
static OP *
S_scalarkids(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_SCALARKIDS;
    if (OpKIDS(o)) {
        OP *kid;
        for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
	    scalar(kid);
    }
    return o;
}

/*
=for apidoc set_boolean

Force the op to be in boolean context, similar to L</scalar>
and L</scalarboolean>
This just abstracts away the various private TRUEBOOL flag values.

=cut
*/
PERL_STATIC_INLINE OP*
S_set_boolean(pTHX_ OP* o)
{
    PERL_ARGS_ASSERT_SET_BOOLEAN;
    if ( IS_TYPE(o, RV2HV)  ||
         IS_TYPE(o, RV2AV)  ||
         IS_TYPE(o, PADHV)  ||
         IS_TYPE(o, PADAV)  ||
         IS_TYPE(o, LENGTH) ||
         IS_TYPE(o, GREPWHILE) ||
         IS_TYPE(o, SUBST)  ||
         IS_TYPE(o, POS)    ||
         IS_TYPE(o, REF) )
        o->op_private |= OPpTRUEBOOL;
    else if (IS_TYPE(o, AASSIGN))
        o->op_private |= OPpASSIGN_TRUEBOOL;
    return o;
}

/*
=for apidoc s|OP*	|scalarboolean	|NN OP* o

Checks boolean context for the op, merely for syntax warnings.

Note: We cannot L</set_boolean> context here, as some ops
still require the non-boolified stackvalue.
See L</check_for_bool_cxt>.

=cut
*/
static OP *
S_scalarboolean(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_SCALARBOOLEAN;

    if ((IS_TYPE(o, SASSIGN) && IS_CONST_OP(OpFIRST(o)) &&
         !OpSPECIAL(OpFIRST(o))) ||
        (IS_TYPE(o, NOT) && IS_TYPE(OpFIRST(o), SASSIGN) &&
         IS_CONST_OP(OpFIRST(OpFIRST(o))) &&
         !OpSPECIAL(OpFIRST(OpFIRST(o))))) {
	if (ckWARN(WARN_SYNTAX)) {
	    const line_t oldline = CopLINE(PL_curcop);

	    if (PL_parser && PL_parser->copline != NOLINE) {
		/* This ensures that warnings are reported at the first line
                   of the conditional, not the last.  */
		CopLINE_set(PL_curcop, PL_parser->copline);
            }
	    Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
                        "Found = in conditional, should be ==");
	    CopLINE_set(PL_curcop, oldline);
	}
    }
    return scalar(o);
}

static SV *
S_op_varname_subscript(pTHX_ const OP *o, int subscript_type)
{
    const OPCODE type = o->op_type;
    assert(o);
    assert(   type == OP_PADAV || type == OP_RV2AV
           || type == OP_PADHV || type == OP_RV2HV);
    {
	const char funny  = type == OP_PADAV
			 || type == OP_RV2AV ? '@' : '%';
	if (type == OP_RV2AV || type == OP_RV2HV) {
	    GV *gv;
	    if (ISNT_TYPE(OpFIRST(o), GV)
	     || !(gv = cGVOPx_gv(OpFIRST(o))))
		return NULL;
	    return varname(gv, funny, 0, NULL, 0, subscript_type);
	}
	return
	    varname(MUTABLE_GV(PL_compcv), funny, o->op_targ, NULL, 0, subscript_type);
    }
}

static SV *
S_op_varname(pTHX_ const OP *o)
{
    return S_op_varname_subscript(aTHX_ o, 1);
}

static void
S_op_pretty(pTHX_ const OP *o, SV **retsv, const char **retpv)
{ /* or not so pretty :-) */
    if (IS_CONST_OP(o)) {
	*retsv = cSVOPo_sv;
	if (SvPOK(*retsv)) {
	    SV *sv = *retsv;
	    *retsv = sv_newmortal();
	    pv_pretty(*retsv, SvPVX_const(sv), SvCUR(sv), 32, NULL, NULL,
		      PERL_PV_PRETTY_DUMP |PERL_PV_ESCAPE_UNI_DETECT);
	}
	else if (!SvOK(*retsv))
	    *retpv = "undef";
    }
    else *retpv = "...";
}

static void
S_scalar_slice_warning(pTHX_ const OP *o)
{
    OP *kid;
    const bool h = OP_TYPE_IS_OR_WAS_NN(o, OP_HSLICE);
    const char lbrack = h ? '{' : '[';
    const char rbrack = h ? '}' : ']';
    SV *name;
    SV *keysv = NULL; /* just to silence compiler warnings */
    const char *key = NULL;

    if (!(o->op_private & OPpSLICEWARNING))
	return;
    if (PL_parser && PL_parser->error_count)
	/* This warning can be nonsensical when there is a syntax error. */
	return;

    kid = OpFIRST(o);
    kid = OpSIBLING(kid); /* get past pushmark */
    /* weed out false positives: any ops that can return lists */
    switch (kid->op_type) {
    case OP_BACKTICK:
    case OP_GLOB:
    case OP_READLINE:
    case OP_MATCH:
    case OP_RV2AV:
    case OP_EACH:
    case OP_VALUES:
    case OP_KEYS:
    case OP_SPLIT:
    case OP_LIST:
    case OP_SORT:
    case OP_REVERSE:
    case OP_ENTERSUB:
    case OP_ENTERXSSUB:
    case OP_CALLER:
    case OP_LSTAT:
    case OP_STAT:
    case OP_READDIR:
    case OP_SYSTEM:
    case OP_TMS:
    case OP_LOCALTIME:
    case OP_GMTIME:
    case OP_ENTEREVAL:
	return;
    }

    /* Don't warn if we have a nulled list either. */
    if (OP_TYPE_WAS_NN(kid, OP_LIST))
        return;

    assert(OpSIBLING(kid));
    name = S_op_varname(aTHX_ OpSIBLING(kid));
    if (!name) /* XS module fiddling with the op tree */
	return;
    S_op_pretty(aTHX_ kid, &keysv, &key);
    assert(SvPOK(name));
    sv_chop(name,SvPVX(name)+1);
    if (key)
       /* diag_listed_as: Scalar value @%s[%s] better written as $%s[%s] */
	Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
		   "Scalar value @%" SVf "%c%s%c better written as $%" SVf
		   "%c%s%c",
		    SVfARG(name), lbrack, key, rbrack, SVfARG(name),
		    lbrack, key, rbrack);
    else
       /* diag_listed_as: Scalar value @%s[%s] better written as $%s[%s] */
	Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
		   "Scalar value @%" SVf "%c%" SVf "%c better written as $%"
		    SVf "%c%" SVf "%c",
		    SVfARG(name), lbrack, SVfARG(keysv), rbrack,
		    SVfARG(name), lbrack, SVfARG(keysv), rbrack);
}

OP *
Perl_scalar(pTHX_ OP *o)
{
    OP *kid;

    /* assumes no premature commitment */
    if (!o || (PL_parser && PL_parser->error_count)
        || (o->op_flags & OPf_WANT)
        || IS_TYPE(o, RETURN))
    {
	return o;
    }

    o->op_flags = (o->op_flags & ~OPf_WANT) | OPf_WANT_SCALAR;

    switch (o->op_type) {
    case OP_REPEAT:
	scalar(OpFIRST(o));
	if (o->op_private & OPpREPEAT_DOLIST) {
	    kid = OpFIRST(OpFIRST(o));
	    assert(IS_TYPE(kid, PUSHMARK));
	    if (OpHAS_SIBLING(kid) && !OpHAS_SIBLING(OpSIBLING(kid))) {
		op_null(OpFIRST(OpFIRST(o)));
		o->op_private &=~ OPpREPEAT_DOLIST;
	    }
	}
	break;
    case OP_OR:
    case OP_AND:
    case OP_COND_EXPR:
	for (kid = OpSIBLING(OpFIRST(o)); kid; kid = OpSIBLING(kid))
	    scalar(kid);
	break;
	/* FALLTHROUGH */
    case OP_SPLIT:
    case OP_MATCH:
    case OP_QR:
    case OP_SUBST:
    case OP_NULL:
    default:
	if (OpKIDS(o)) {
	    for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
		scalar(kid);
	}
	break;
    case OP_LEAVE:
    case OP_LEAVETRY:
	kid = OpFIRST(o);
	scalar(kid);
	kid = OpSIBLING(kid);
    do_kids:
	while (kid) {
	    OP *sib = OpSIBLING(kid);
	    if (sib && ISNT_TYPE(kid, LEAVEWHEN)
                && (  OpHAS_SIBLING(sib) || ISNT_TYPE(sib, NULL)
		|| (  sib->op_targ != OP_NEXTSTATE
		   && sib->op_targ != OP_DBSTATE  )))
		scalarvoid(kid);
	    else
		scalar(kid);
	    kid = sib;
	}
	PL_curcop = &PL_compiling;
	break;
    case OP_SCOPE:
    case OP_LINESEQ:
    case OP_LIST:
	kid = OpFIRST(o);
	goto do_kids;
    case OP_SORT:
	Perl_ck_warner(aTHX_ packWARN(WARN_VOID), "Useless use of sort in scalar context");
	break;
    case OP_KVHSLICE:
    case OP_KVASLICE: {
	/* Warn about scalar context */
	const char lbrack = IS_TYPE(o, KVHSLICE) ? '{' : '[';
	const char rbrack = IS_TYPE(o, KVHSLICE) ? '}' : ']';
	SV *name;
	SV *keysv = NULL;
	const char *key = NULL;

	/* This warning can be nonsensical when there is a syntax error. */
	if (PL_parser && PL_parser->error_count)
	    break;

	if (!ckWARN(WARN_SYNTAX)) break;

	kid = OpSIBLING(OpFIRST(o)); /* get past pushmark */
	assert(OpSIBLING(kid));
	name = S_op_varname(aTHX_ OpSIBLING(kid));
	if (!name) /* XS module fiddling with the op tree */
	    break;
	S_op_pretty(aTHX_ kid, &keysv, &key);
	assert(SvPOK(name));
	sv_chop(name,SvPVX(name)+1);
	if (key)
  /* diag_listed_as: %%s[%s] in scalar context better written as $%s[%s] */
	    Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
		       "%%%" SVf "%c%s%c in scalar context better written "
		       "as $%" SVf "%c%s%c",
			SVfARG(name), lbrack, key, rbrack, SVfARG(name),
			lbrack, key, rbrack);
	else {
            assert(keysv);
  /* diag_listed_as: %%s[%s] in scalar context better written as $%s[%s] */
	    Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
		       "%%%" SVf "%c%" SVf "%c in scalar context better "
		       "written as $%" SVf "%c%" SVf "%c",
			SVfARG(name), lbrack, SVfARG(keysv), rbrack,
			SVfARG(name), lbrack, SVfARG(keysv), rbrack);
        }
      }
    }
    return o;
}

/*
=for apidoc A|OP*	|scalarvoid	|NN OP* arg

Assigns scalar void context to the optree, i.e. it takes only a scalar
argument, no list and returns nothing.

=cut
*/
OP *
Perl_scalarvoid(pTHX_ OP *arg)
{
    dVAR;
    OP *kid;
    SV* sv;
    SSize_t defer_stack_alloc = 0;
    SSize_t defer_ix = -1;
    OP **defer_stack = NULL;
    OP *o = arg;
    PERL_ARGS_ASSERT_SCALARVOID;

    do {
        U8 want;
        SV *useless_sv = NULL;
        const char* useless = NULL;

        if (IS_STATE_OP(o)
            || (IS_NULL_OP(o) && (o->op_targ == OP_NEXTSTATE
                               || o->op_targ == OP_DBSTATE)))
            PL_curcop = (COP*)o;                /* for warning below */

        /* assumes no premature commitment */
        want = o->op_flags & OPf_WANT;
        if ((want && want != OPf_WANT_SCALAR)
            || (PL_parser && PL_parser->error_count)
            || OP_TYPE_IS_NN(o, OP_RETURN) || OP_TYPE_IS_NN(o, OP_REQUIRE)
            || OP_TYPE_IS_NN(o, OP_LEAVEWHEN))
        {
            continue;
        }

        if ((o->op_private & OPpTARGET_MY)
            && OP_HAS_TARGLEX(o->op_type)) /* OPp share the meaning */
        {
            /* newASSIGNOP has already applied scalar context, which we
               leave, as if this op is inside SASSIGN.  */
            continue;
        }

        o->op_flags = (o->op_flags & ~OPf_WANT) | OPf_WANT_VOID;

        switch (o->op_type) {
        default:
            if (!(PL_opargs[o->op_type] & OA_FOLDCONST))
                break;
            /* FALLTHROUGH */
        case OP_REPEAT:
            if (OpSTACKED(o))
                break;
            if (IS_TYPE(o, REPEAT))
                scalar(OpFIRST(o));
            goto func_ops;
	case OP_CONCAT:
            if ((o->op_flags & OPf_STACKED) &&
		    !(o->op_private & OPpCONCAT_NESTED))
                break;
	    goto func_ops;
        case OP_SUBSTR:
            if (o->op_private == 4)
                break;
            /* FALLTHROUGH */
        case OP_WANTARRAY:
        case OP_GV:
        case OP_SMARTMATCH:
        case OP_AV2ARYLEN:
        case OP_REF:
        case OP_REFGEN:
        case OP_SREFGEN:
        case OP_DEFINED:
        case OP_HEX:
        case OP_OCT:
        case OP_LENGTH:
        case OP_VEC:
        case OP_INDEX:
        case OP_RINDEX:
        case OP_SPRINTF:
        case OP_KVASLICE:
        case OP_KVHSLICE:
        case OP_UNPACK:
        case OP_PACK:
        case OP_JOIN:
        case OP_LSLICE:
        case OP_ANONLIST:
        case OP_ANONHASH:
        case OP_SORT:
        case OP_REVERSE:
        case OP_RANGE:
        case OP_FLIP:
        case OP_FLOP:
        case OP_CALLER:
        case OP_FILENO:
        case OP_EOF:
        case OP_TELL:
        case OP_GETSOCKNAME:
        case OP_GETPEERNAME:
        case OP_READLINK:
        case OP_TELLDIR:
        case OP_GETPPID:
        case OP_GETPGRP:
        case OP_GETPRIORITY:
        case OP_TIME:
        case OP_TMS:
        case OP_LOCALTIME:
        case OP_GMTIME:
        case OP_GHBYNAME:
        case OP_GHBYADDR:
        case OP_GHOSTENT:
        case OP_GNBYNAME:
        case OP_GNBYADDR:
        case OP_GNETENT:
        case OP_GPBYNAME:
        case OP_GPBYNUMBER:
        case OP_GPROTOENT:
        case OP_GSBYNAME:
        case OP_GSBYPORT:
        case OP_GSERVENT:
        case OP_GPWNAM:
        case OP_GPWUID:
        case OP_GGRNAM:
        case OP_GGRGID:
        case OP_GETLOGIN:
        case OP_PROTOTYPE:
        case OP_RUNCV:
        func_ops:
            useless = OP_DESC(o);
            break;

        case OP_GVSV:
        case OP_PADSV:
        case OP_PADAV:
        case OP_PADHV:
        case OP_PADANY:
        case OP_AELEM:
        case OP_AELEMFAST:
        case OP_AELEMFAST_LEX:
        case OP_AELEMFAST_LEX_U:
        case OP_OELEM:
        case OP_OELEMFAST:
        case OP_ASLICE:
        case OP_HELEM:
        case OP_HSLICE:
            if (!(o->op_private & (OPpLVAL_INTRO|OPpOUR_INTRO)))
                /* Otherwise it's "Useless use of grep iterator" */
                useless = OP_DESC(o);
            break;

        case OP_SPLIT:
            if (!(o->op_private & OPpSPLIT_ASSIGN))
                useless = OP_DESC(o);
            break;

        case OP_NOT:
            kid = OpFIRST(o);
            if (ISNT_TYPE(kid, MATCH) &&
                ISNT_TYPE(kid, SUBST) &&
                ISNT_TYPE(kid, TRANS) &&
                ISNT_TYPE(kid, TRANSR)) {
                goto func_ops;
            }
            useless = "negative pattern binding (!~)";
            break;

        case OP_SUBST:
            if (cPMOPo->op_pmflags & PMf_NONDESTRUCT)
                useless = "non-destructive substitution (s///r)";
            break;

        case OP_TRANSR:
            useless = "non-destructive transliteration (tr///r)";
            break;

        case OP_RV2GV:
        case OP_RV2SV:
        case OP_RV2AV:
        case OP_RV2HV:
            if (!(o->op_private & (OPpLVAL_INTRO|OPpOUR_INTRO)) &&
                (!OpHAS_SIBLING(o) || ISNT_TYPE(OpSIBLING(o), READLINE)))
                useless = "a variable";
            break;

        case OP_CONST:
            sv = cSVOPo_sv;
            if (cSVOPo->op_private & OPpCONST_STRICT)
                no_bareword_allowed(o);
            else {
                if (ckWARN(WARN_VOID)) {
                    NV nv;
                    /* don't warn on optimised away booleans, eg
                     * use constant Foo, 5; Foo || print; */
                    if (cSVOPo->op_private & OPpCONST_SHORTCIRCUIT)
                        useless = NULL;
                    /* the constants 0 and 1 are permitted as they are
                       conventionally used as dummies in constructs like
                       1 while some_condition_with_side_effects;  */
                    else if (SvNIOK(sv) && ((nv = SvNV(sv)) == 0.0 || nv == 1.0))
                        useless = NULL;
                    else if (SvPOK(sv)) {
                        SV * const dsv = newSVpvs("");
                        useless_sv
                            = Perl_newSVpvf(aTHX_
                                            "a constant (%s)",
                                            pv_pretty(dsv, SvPVX_const(sv),
                                                      SvCUR(sv), 32, NULL, NULL,
                                                      PERL_PV_PRETTY_DUMP
                                                      | PERL_PV_ESCAPE_NOCLEAR
                                                      | PERL_PV_ESCAPE_UNI_DETECT));
                        SvREFCNT_dec_NN(dsv);
                    }
                    else if (SvOK(sv)) {
                        useless_sv = Perl_newSVpvf(aTHX_ "a constant (%" SVf ")", SVfARG(sv));
                    }
                    else
                        useless = "a constant (undef)";
                }
            }
            op_null(o);         /* don't execute or even remember it */
            break;

        case OP_POSTINC:
            OpTYPE_set(o, OP_PREINC);  /* pre-increment is faster */
            break;

        case OP_POSTDEC:
            OpTYPE_set(o, OP_PREDEC);  /* pre-decrement is faster */
            break;

        case OP_I_POSTINC:
            OpTYPE_set(o, OP_I_PREINC);        /* pre-increment is faster */
            break;

        case OP_I_POSTDEC:
            OpTYPE_set(o, OP_I_PREDEC);        /* pre-decrement is faster */
            break;

        case OP_SASSIGN: {
            OP *rv2gv;
            UNOP *refgen, *rv2cv;
            LISTOP *exlist;

            if ((o->op_private & ~OPpASSIGN_BACKWARDS) != 2)
                break;

            rv2gv = OpLAST(o);
            if (!rv2gv || ISNT_TYPE(rv2gv, RV2GV))
                break;

            refgen = (UNOP *)OpFIRST(o);
            if (!refgen || (ISNT_TYPE(refgen, REFGEN)
                         && ISNT_TYPE(refgen, SREFGEN)))
                break;

            exlist = (LISTOP *)OpFIRST(refgen);
            if (NO_OP_TYPE_OR_WASNT(exlist, OP_LIST))
                break;

            if (ISNT_TYPE(OpFIRST(exlist), PUSHMARK)
                && OpFIRST(exlist) != OpLAST(exlist))
                break;

            rv2cv = (UNOP*)OpLAST(exlist);
            if (ISNT_TYPE(rv2cv, RV2CV))
                break;

            assert ((rv2gv->op_private & OPpDONT_INIT_GV) == 0);
            assert ((o->op_private & OPpASSIGN_CV_TO_GV) == 0);
            assert ((rv2cv->op_private & OPpMAY_RETURN_CONSTANT) == 0);

            o->op_private |= OPpASSIGN_CV_TO_GV;
            rv2gv->op_private |= OPpDONT_INIT_GV;
            rv2cv->op_private |= OPpMAY_RETURN_CONSTANT;

            break;
        }

        case OP_AASSIGN: {
            inplace_aassign(o);
            break;
        }

        case OP_OR:
        case OP_AND:
            kid = OpFIRST(o);
            if (IS_TYPE(kid, NOT) && OpKIDS(kid)) {
                if (IS_TYPE(o, AND)) {
                    OpTYPE_set(o, OP_OR);
                } else {
                    OpTYPE_set(o, OP_AND);
                }
                op_null(kid);
            }
            /* FALLTHROUGH */

        case OP_DOR:
        case OP_COND_EXPR:
        case OP_ENTERGIVEN:
        case OP_ENTERWHEN:
            for (kid = OpSIBLING(OpFIRST(o)); kid; kid = OpSIBLING(kid))
                if (!OpKIDS(kid))
                    scalarvoid(kid);
                else
                    DEFER_OP(kid);
        break;

        case OP_NULL:
            if (OpSTACKED(o))
                break;
            /* FALLTHROUGH */
        case OP_NEXTSTATE:
        case OP_DBSTATE:
        case OP_ENTERTRY:
        case OP_ENTER:
            if (!OpKIDS(o))
                break;
            /* FALLTHROUGH */
        case OP_SCOPE:
        case OP_LEAVE:
        case OP_LEAVETRY:
        case OP_LEAVELOOP:
        case OP_LINESEQ:
        case OP_LEAVEGIVEN:
        case OP_LEAVEWHEN:
        kids:
            for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
                if (!OpKIDS(kid))
                    scalarvoid(kid);
                else
                    DEFER_OP(kid);
            break;
        case OP_LIST:
            /* If the first kid after pushmark is something that the padrange
               optimisation would reject, then null the list and the pushmark.
            */
            if (IS_TYPE((kid = OpFIRST(o)), PUSHMARK)
                && (  !(kid = OpSIBLING(kid))
                      || (  ISNT_TYPE(kid, PADSV)
                         && ISNT_TYPE(kid, PADAV)
                         && ISNT_TYPE(kid, PADHV))
                      || kid->op_private & ~OPpLVAL_INTRO
                      || !(kid = OpSIBLING(kid))
                      || (  ISNT_TYPE(kid, PADSV)
                         && ISNT_TYPE(kid, PADAV)
                         && ISNT_TYPE(kid, PADHV))
                      || kid->op_private & ~OPpLVAL_INTRO)
            ) {
                op_null(OpFIRST(o)); /* NULL the pushmark */
                op_null(o); /* NULL the list */
            }
            goto kids;
        case OP_ENTEREVAL:
            scalarkids(o);
            break;
        case OP_SCALAR:
            scalar(o);
            break;
        }

        if (useless_sv) {
            /* mortalise it, in case warnings are fatal.  */
            Perl_ck_warner(aTHX_ packWARN(WARN_VOID),
                           "Useless use of %" SVf " in void context",
                           SVfARG(sv_2mortal(useless_sv)));
        }
        else if (useless) {
            Perl_ck_warner(aTHX_ packWARN(WARN_VOID),
                           "Useless use of %s in void context",
                           useless);
        }
    } while ( (o = POP_DEFERRED_OP()) );

    Safefree(defer_stack);

    return arg;
}

/*
=for apidoc listkids

Sets list context for all kids.

=cut
*/
static OP *
S_listkids(pTHX_ OP *o)
{
    if (o && OpKIDS(o)) {
        OP *kid;
	for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
	    list(kid);
    }
    return o;
}

/*
=for apidoc list

Sets list context for the op.

=cut
*/
OP *
Perl_list(pTHX_ OP *o)
{
    OP *kid;

    /* assumes no premature commitment */
    if (!o || (o->op_flags & OPf_WANT)
	 || (PL_parser && PL_parser->error_count)
	 || IS_TYPE(o, RETURN))
    {
	return o;
    }

    if ((o->op_private & OPpTARGET_MY)
        && OP_HAS_TARGLEX(o->op_type)) /* OPp share the meaning */
    {
	return o;				/* As if inside SASSIGN */
    }

    o->op_flags = (o->op_flags & ~OPf_WANT) | OPf_WANT_LIST;

    switch (o->op_type) {
    case OP_FLOP:
	list(OpFIRST(o));
	break;
    case OP_REPEAT:
	if (o->op_private & OPpREPEAT_DOLIST && !OpSTACKED(o)) {
	    list(OpFIRST(o));
	    kid = OpLAST(o);
	    if (IS_CONST_OP(kid) && SvIOK(kSVOP_sv) && SvIVX(kSVOP_sv) == 1)
	    {
		op_null(o); /* repeat */
		op_null(OpFIRST(OpFIRST(o)));/* pushmark */
		/* const (rhs): */
		op_free(op_sibling_splice(o, OpFIRST(o), 1, NULL));
	    }
	}
	break;
    case OP_OR:
    case OP_AND:
    case OP_COND_EXPR:
	for (kid = OpSIBLING(OpFIRST(o)); kid; kid = OpSIBLING(kid))
	    list(kid);
	break;
    default:
    case OP_MATCH:
    case OP_QR:
    case OP_SUBST:
    case OP_NULL:
	if (!OpKIDS(o))
	    break;
	if (!OpNEXT(o) && IS_TYPE(OpFIRST(o), FLOP)) {
	    list(OpFIRST(o));
	    return gen_constant_list(o);
	}
	listkids(o);
	break;
    case OP_LIST:
	listkids(o);
	if (IS_TYPE(OpFIRST(o), PUSHMARK)) {
	    op_null(OpFIRST(o)); /* NULL the pushmark */
	    op_null(o); /* NULL the list */
	}
	break;
    case OP_LEAVE:
    case OP_LEAVETRY:
	kid = OpFIRST(o);
	list(kid);
	kid = OpSIBLING(kid);
    do_kids:
	while (kid) {
	    OP *sib = OpSIBLING(kid);
	    if (sib && ISNT_TYPE(kid, LEAVEWHEN))
		scalarvoid(kid);
	    else
		list(kid);
	    kid = sib;
	}
	PL_curcop = &PL_compiling;
	break;
    case OP_SCOPE:
    case OP_LINESEQ:
	kid = OpFIRST(o);
	goto do_kids;
    }
    return o;
}

/*
=for apidoc scalarseq

Sets scalar void context for scalar sequences: lineseq, scope, leave
and leavetry.

=cut
*/
static OP *
S_scalarseq(pTHX_ OP *o)
{
    if (o) {
	const OPCODE type = o->op_type;

	if (type == OP_LINESEQ || type == OP_SCOPE ||
	    type == OP_LEAVE   || type == OP_LEAVETRY)
	{
     	    OP *kid, *sib;
	    for (kid = OpFIRST(o); kid; kid = sib) {
		if ((sib = OpSIBLING(kid))
                    && (OpHAS_SIBLING(sib) || ISNT_TYPE(sib, NULL)
		    || (  sib->op_targ != OP_NEXTSTATE
		       && sib->op_targ != OP_DBSTATE  )))
		{
		    scalarvoid(kid);
		}
	    }
	    PL_curcop = &PL_compiling;
	}
	o->op_flags &= ~OPf_PARENS;
	if (PL_hints & HINT_BLOCK_SCOPE)
	    o->op_flags |= OPf_PARENS;
    }
    else
	o = newOP(OP_STUB, 0);
    return o;
}

/*
=for apidoc modkids

Sets lvalue context for all kids.

=cut
*/
static OP *
S_modkids(pTHX_ OP *o, I32 type)
{
    if (o && OpKIDS(o)) {
        OP *kid;
        for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
	    op_lvalue(kid, type);
    }
    return o;
}


/*
=for apidoc s|void	|check_hash_fields_and_hekify	|NULLOK UNOP *rop|NN SVOP *key_op

for a helem/hslice/kvslice, if its a fixed hash, croak on invalid
const fields. Also, convert CONST keys to HEK-in-SVs.
rop is the op that retrieves the hash;
key_op is the first key

=cut
*/

static void
S_check_hash_fields_and_hekify(pTHX_ UNOP *rop, SVOP *key_op)
{
    PADNAME *lexname;
    GV **fields;
    bool check_fields;
    PERL_ARGS_ASSERT_CHECK_HASH_FIELDS_AND_HEKIFY;

    /* find the padsv corresponding to $lex->{} or @{$lex}{} */
    if (rop) {
        if (IS_TYPE(OpFIRST(rop), PADSV))
            /* @$hash{qw(keys here)} */
            rop = (UNOP*)OpFIRST(rop);
        else {
            /* @{$hash}{qw(keys here)} */
            if (IS_TYPE(OpFIRST(rop), SCOPE)
             && IS_TYPE(OpLAST(OpFIRST(rop)), PADSV))
            {
                rop = (UNOP*)OpLAST(OpFIRST(rop));
            }
            else
                rop = NULL;
        }
    }

    lexname = NULL; /* just to silence compiler warnings */
    fields  = NULL; /* just to silence compiler warnings */

    check_fields =
            rop
         && (lexname = padnamelist_fetch(PL_comppad_name, rop->op_targ),
             SvPAD_TYPED(lexname))
         && (fields = (GV**)hv_fetchs(PadnameTYPE(lexname), "FIELDS", FALSE))
         && isGV(*fields) && GvHV(*fields);

    /* key_op is not-NULL the first time.
       so yes, clang could optimize in the first loop to ignore the conditional.
       as in do {} while */
    CLANG35_DIAG_IGNORE(-Wpointer-bool-conversion);
    for (; key_op; key_op = (SVOP*)OpSIBLING(key_op)) {
        SV **svp, *sv;
        CLANG35_DIAG_RESTORE;
        if (ISNT_TYPE(key_op, CONST))
            continue;
        svp = cSVOPx_svp(key_op);

        /* make sure it's not a bareword under strict subs */
        if (key_op->op_private & OPpCONST_BARE &&
            key_op->op_private & OPpCONST_STRICT)
        {
            no_bareword_allowed((OP*)key_op);
        }

        /* Make the CONST have a shared SV */
        if (   !SvIsCOW_shared_hash(sv = *svp)
            && SvTYPE(sv) < SVt_PVMG
            && SvOK(sv)
            && !SvROK(sv))
        {
            SSize_t keylen;
            const char * const key = SvPV_const(sv, *(STRLEN*)&keylen);
            if (UNLIKELY(keylen > I32_MAX)) {
                Perl_croak(aTHX_ "panic: hash key too long (%" UVuf ")", (UV) keylen);
            } else {
                SV *nsv = newSVpvn_share(key, SvUTF8(sv) ? -keylen : keylen, 0);
                SvREFCNT_dec_NN(sv);
                *svp = nsv;
            }
        }

        if (   check_fields
            && !hv_fetch_ent(GvHV(*fields), *svp, FALSE, 0))
        {
            Perl_croak(aTHX_ "No such class field \"%" SVf "\" "
                        "in variable %" PNf " of type %" HEKf,
                        SVfARG(*svp), PNfARG(lexname),
                        HEKfARG(HvNAME_HEK(PadnameTYPE(lexname))));
        }
    }
}

/* info returned by S_sprintf_is_multiconcatable() */

struct sprintf_ismc_info {
    SSize_t nargs;    /* num of args to sprintf (not including the format) */
    char  *start;     /* start of raw format string */
    char  *end;       /* bytes after end of raw format string */
    STRLEN total_len; /* total length (in bytes) of format string, not
                         including '%s' and  half of '%%' */
    STRLEN variant;   /* number of bytes by which total_len_p would grow
                         if upgraded to utf8 */
    bool   utf8;      /* whether the format is utf8 */
};


/* is the OP_SPRINTF o suitable for converting into a multiconcat op?
 * i.e. its format argument is a const string with only '%s' and '%%'
 * formats, and the number of args is known, e.g.
 *    sprintf "a=%s f=%s", $a[0], scalar(f());
 * but not
 *    sprintf "i=%d a=%s f=%s", $i, @a, f();
 *
 * If successful, the sprintf_ismc_info struct pointed to by info will be
 * populated.
 */

STATIC bool
S_sprintf_is_multiconcatable(pTHX_ OP *o,struct sprintf_ismc_info *info)
{
    OP    *pm, *constop, *kid;
    SV    *sv;
    char  *s, *e, *p;
    SSize_t nargs, nformats;
    STRLEN cur, total_len, variant;
    bool   utf8;

    /* if sprintf's behaviour changes, die here so that someone
     * can decide whether to enhance this function or skip optimising
     * under those new circumstances */
    assert(!OpSTACKED(o));
    /*assert(!(PL_opargs[OP_SPRINTF] & OA_TARGLEX));*/
    assert(!(o->op_private & ~OPpARG4_MASK));

    pm = OpFIRST(o);
    if (ISNT_TYPE(pm, PUSHMARK)) /* weird coreargs stuff */
        return FALSE;
    constop = OpSIBLING(pm);
    if (!constop || !(IS_CONST_OP(constop)))
        return FALSE;
    sv = cSVOPx_sv(constop);
    if (SvMAGICAL(sv) || !SvPOK(sv))
        return FALSE;

    s = SvPV(sv, cur);
    e = s + cur;

    /* Scan format for %% and %s and work out how many %s there are.
     * Abandon if other format types are found.
     */

    nformats  = 0;
    total_len = 0;
    variant   = 0;

    for (p = s; p < e; p++) {
        if (*p != '%') {
            total_len++;
            if (!UTF8_IS_INVARIANT(*p))
                variant++;
            continue;
        }
        p++;
        if (p >= e)
            return FALSE; /* lone % at end gives "Invalid conversion" */
        if (*p == '%')
            total_len++;
        else if (*p == 's')
            nformats++;
        else
            return FALSE;
    }

    if (!nformats || nformats > PERL_MULTICONCAT_MAXARG)
        return FALSE;

    utf8 = cBOOL(SvUTF8(sv));
    if (utf8)
        variant = 0;

    /* scan args; they must all be in scalar cxt */

    nargs = 0;
    kid = OpSIBLING(constop);

    while (kid) {
        if (!(OpWANT_SCALAR(kid)))
            return FALSE;
        nargs++;
        kid = OpSIBLING(kid);
    }

    if (nargs != nformats)
        return FALSE; /* e.g. sprintf("%s%s", $a); */

    info->nargs      = nargs;
    info->start      = s;
    info->end        = e;
    info->total_len  = total_len;
    info->variant    = variant;
    info->utf8       = utf8;

    return TRUE;
}



/*
=for apidoc maybe_multiconcat

Given an OP_STRINGIFY, OP_SASSIGN, OP_CONCAT or OP_SPRINTF op, possibly
convert it (and its children) into an OP_MULTICONCAT. See the code
comments just before pp_multiconcat() for the full details of what
OP_MULTICONCAT supports.

Basically we're looking for an optree with a chain of OP_CONCATS down
the LHS (or an OP_SPRINTF), with possibly an OP_SASSIGN, and/or
OP_STRINGIFY, and/or OP_CONCAT acting as '.=' at its head, e.g.

     $x = "$a$b-$c"

 looks like

     SASSIGN
        |
     STRINGIFY   -- PADSV[$x]
        |
        |
     ex-PUSHMARK -- CONCAT/S
                       |
                    CONCAT/S  -- PADSV[$d]
                       |
                    CONCAT    -- CONST["-"]
                       |
                    PADSV[$a] -- PADSV[$b]

Note that at this stage the OP_SASSIGN may have already been optimised
away with OPpTARGET_MY set on the OP_STRINGIFY or OP_CONCAT.

=cut
*/

STATIC void
S_maybe_multiconcat(pTHX_ OP *o)
{
    OP *lastkidop;   /* the right-most of any kids unshifted onto o */
    OP *topop;       /* the top-most op in the concat tree (often equals o,
                        unless there are assign/stringify ops above it */
    OP *parentop;    /* the parent op of topop (or itself if no parent) */
    OP *targmyop;    /* the op (if any) with the OPpTARGET_MY flag */
    OP *targetop;    /* the op corresponding to target=... or target.=... */
    OP *stringop;    /* the OP_STRINGIFY op, if any */
    OP *nextop;      /* used for recreating the op_next chain without consts */
    OP *kid;         /* general-purpose op pointer */
    UNOP_AUX_item *aux;
    UNOP_AUX_item *lenp;
    char *const_str, *p;
    struct sprintf_ismc_info sprintf_info;

                     /* store info about each arg in args[];
                      * toparg is the highest used slot; argp is a general
                      * pointer to args[] slots */
    struct {
        void *p;      /* initially points to const sv (or null for op);
                         later, set to SvPV(constsv), with ... */
        STRLEN len;   /* ... len set to SvPV(..., len) */
    } *argp, *toparg, args[PERL_MULTICONCAT_MAXARG*2 + 1];

    SSize_t nargs  = 0;
    SSize_t nconst = 0;
    SSize_t nadjconst  = 0; /* adjacent consts - may be demoted to args */
    STRLEN variant;
    bool utf8 = FALSE;
    bool kid_is_last = FALSE; /* most args will be the RHS kid of a concat op;
                                 the last-processed arg will the LHS of one,
                                 as args are processed in reverse order */
    U8   stacked_last = 0;   /* whether the last seen concat op was STACKED */
    STRLEN total_len  = 0;   /* sum of the lengths of the const segments */
    U8 flags          = 0;   /* what will become the op_flags and ... */
    U8 private_flags  = 0;   /* ... op_private of the multiconcat op */
    bool is_sprintf = FALSE; /* we're optimising an sprintf */
    bool is_targable  = FALSE; /* targetop is an OPpTARGET_MY candidate */
    bool prev_was_const = FALSE; /* previous arg was a const */
    PERL_ARGS_ASSERT_MAYBE_MULTICONCAT;

    /* -----------------------------------------------------------------
     * Phase 1:
     *
     * Examine the optree non-destructively to determine whether it's
     * suitable to be converted into an OP_MULTICONCAT. Accumulate
     * information about the optree in args[].
     */

    argp     = args;
    targmyop = NULL;
    targetop = NULL;
    stringop = NULL;
    topop    = o;
    parentop = o;

    assert(   o->op_type == OP_SASSIGN
           || o->op_type == OP_CONCAT
           || o->op_type == OP_SPRINTF
           || o->op_type == OP_STRINGIFY);

    Zero(&sprintf_info, 1, struct sprintf_ismc_info);

    /* first see if, at the top of the tree, there is an assign,
     * append and/or stringify */

    if (IN_ENCODING)
        return;
    if (IS_TYPE(topop, SASSIGN)) {
        /* expr = ..... */
        if (o->op_ppaddr != PL_ppaddr[OP_SASSIGN])
            return;
        if (o->op_private & (OPpASSIGN_BACKWARDS|OPpASSIGN_CV_TO_GV))
            return;
        assert(!(o->op_private & ~OPpARG2_MASK)); /* barf on unknown flags */

        parentop = topop;
        topop = OpFIRST(o);
        targetop = OpSIBLING(topop);
        if (!targetop) /* probably some sort of syntax error */
            return;
    }
    else if (IS_TYPE(topop, CONCAT) &&
             OpSTACKED(topop) &&
             (OpFLAGS(OpFIRST(o)) & OPf_MOD) &&
             !(OpPRIVATE(topop) & OPpCONCAT_NESTED)
            )
    {
        /* expr .= ..... */

        /* OPpTARGET_MY shouldn't be able to be set here. If it is,
         * decide what to do about it */
        assert(!(o->op_private & OPpTARGET_MY));

        /* barf on unknown flags */
        assert(!(o->op_private & ~(OPpARG2_MASK|OPpTARGET_MY)));
        private_flags |= OPpMULTICONCAT_APPEND;
        targetop = OpFIRST(o);
        parentop = topop;
        topop    = OpSIBLING(targetop);

        /* $x .= <FOO> gets optimised to rcatline instead */
        if (topop->op_type == OP_READLINE)
            return;
    }

    if (targetop) {
        /* Can targetop (the LHS) if it's a padsv, be be optimised
         * away and use OPpTARGET_MY instead?
         */
        if (    IS_TYPE(targetop, PADSV)
            && !(targetop->op_private & OPpDEREF)
            && !(targetop->op_private & OPpPAD_STATE)
               /* we don't support 'my $x .= ...' */
                && (   IS_TYPE(o, SASSIGN)
                || !(targetop->op_private & OPpLVAL_INTRO))
        )
            is_targable = TRUE;
    }

    if (IS_TYPE(topop, STRINGIFY)) {
        if (topop->op_ppaddr != PL_ppaddr[OP_STRINGIFY])
            return;
        stringop = topop;

        /* barf on unknown flags */
        assert(!(o->op_private & ~(OPpARG4_MASK|OPpTARGET_MY)));

        if (OpPRIVATE(topop) & OPpTARGET_MY) {
            if (IS_TYPE(o, SASSIGN))
                return; /* can't have two assigns */
            targmyop = topop;
        }

        private_flags |= OPpMULTICONCAT_STRINGIFY;
        parentop = topop;
        topop = OpFIRST(topop);
        assert(OP_TYPE_IS_OR_WAS_NN(topop, OP_PUSHMARK));
        topop = OpSIBLING(topop);
    }

    if (IS_TYPE(topop, SPRINTF)) {
        if (topop->op_ppaddr != PL_ppaddr[OP_SPRINTF])
            return;
        if (OpPRIVATE(topop) & OPpTARGET_MY) {
            if (IS_TYPE(o, SASSIGN))
                return; /* can't have two assigns */
            targmyop = topop;
        }
        if ( LIKELY(!OpSTACKED(topop)) &&
             S_sprintf_is_multiconcatable(aTHX_ topop, &sprintf_info) ) {
            nargs     = sprintf_info.nargs;
            total_len = sprintf_info.total_len;
            variant   = sprintf_info.variant;
            utf8      = sprintf_info.utf8;
            is_sprintf = TRUE;
            private_flags |= OPpMULTICONCAT_FAKE;
            toparg = argp;
            /* we have an sprintf op rather than a concat optree.
             * Skip most of the code below which is associated with
             * processing that optree. We also skip phase 2, determining
             * whether its cost effective to optimise, since for sprintf,
             * multiconcat is *always* faster */
            goto create_aux;
        }
        /* note that even if the sprintf itself isn't multiconcatable,
         * the expression as a whole may be, e.g. in
         *    $x .= sprintf("%d",...)
         * the sprintf op will be left as-is, but the concat/S op may
         * be upgraded to multiconcat
         */
    }
    else if (IS_TYPE(topop, CONCAT)) {
        if (topop->op_ppaddr != PL_ppaddr[OP_CONCAT])
            return;

        if (OpPRIVATE(topop) & OPpTARGET_MY) {
            if (IS_TYPE(o, SASSIGN) || targmyop)
                return; /* can't have two assigns */
            targmyop = topop;
        }
    }

    /* Is it safe to convert a sassign/stringify/concat op into
     * a multiconcat? */
    assert((PL_opargs[OP_SASSIGN]   & OA_CLASS_MASK) == OA_BINOP);
    assert((PL_opargs[OP_CONCAT]    & OA_CLASS_MASK) == OA_BINOP);
    assert((PL_opargs[OP_STRINGIFY] & OA_CLASS_MASK) == OA_LISTOP);
    assert((PL_opargs[OP_SPRINTF]   & OA_CLASS_MASK) == OA_LISTOP);
    STATIC_ASSERT_STMT(   STRUCT_OFFSET(BINOP,    op_last)
                       == STRUCT_OFFSET(UNOP_AUX, op_aux));
    STATIC_ASSERT_STMT(   STRUCT_OFFSET(LISTOP,   op_last)
                       == STRUCT_OFFSET(UNOP_AUX, op_aux));

    /* Now scan the down the tree looking for a series of
     * CONCAT/OPf_STACKED ops on the LHS (with the last one not
     * stacked). For example this tree:
     *
     *     |
     *   CONCAT/STACKED
     *     |
     *   CONCAT/STACKED -- EXPR5
     *     |
     *   CONCAT/STACKED -- EXPR4
     *     |
     *   CONCAT -- EXPR3
     *     |
     *   EXPR1  -- EXPR2
     *
     * corresponds to an expression like
     *
     *   (EXPR1 . EXPR2 . EXPR3 . EXPR4 . EXPR5)
     *
     * Record info about each EXPR in args[]: in particular, whether it is
     * a stringifiable OP_CONST and if so what the const sv is.
     *
     * The reason why the last concat can't be STACKED is the difference
     * between
     *
     *    ((($a .= $a) .= $a) .= $a) .= $a
     *
     * and
     *    $a . $a . $a . $a . $a
     *
     * The main difference between the optrees for those two constructs
     * is the presence of the last STACKED. As well as modifying $a,
     * the former sees the changed $a between each concat, so if $s is
     * initially 'a', the first returns 'a' x 16, while the latter returns
     * 'a' x 5. And pp_multiconcat can't handle that kind of thing.
     */

    kid = topop;

    for (;;) {
        OP *argop;
        SV *sv;
        bool last = FALSE;

        if (    IS_TYPE(kid, CONCAT)
            && !kid_is_last
        ) {
            OP *k1, *k2;
            k1 = OpFIRST(kid);
            k2 = OpSIBLING(k1);
            /* shouldn't happen except maybe after compile err? */
            if (!k2)
                return;

            /* avoid turning (A . B . ($lex = C) ...)  into  (A . B . C ...) */
            if (kid->op_private & OPpTARGET_MY)
                kid_is_last = TRUE;

            stacked_last = OpSTACKED(kid);
            if (!stacked_last)
                kid_is_last = TRUE;

            kid   = k1;
            argop = k2;
        }
        else {
            argop = kid;
            last = TRUE;
        }

        if (   nargs + nadjconst  >  PERL_MULTICONCAT_MAXARG        - 2
            || (argp - args + 1)  > (PERL_MULTICONCAT_MAXARG*2 + 1) - 2)
        {
            /* At least two spare slots are needed to decompose both
             * concat args. If there are no slots left, continue to
             * examine the rest of the optree, but don't push new values
             * on args[]. If the optree as a whole is legal for conversion
             * (in particular that the last concat isn't STACKED), then
             * the first PERL_MULTICONCAT_MAXARG elements of the optree
             * can be converted into an OP_MULTICONCAT now, with the first
             * child of that op being the remainder of the optree -
             * which may itself later be converted to a multiconcat op
             * too.
             */
            if (last) {
                /* the last arg is the rest of the optree */
                argp++->p = NULL;
                nargs++;
            }
        }
        else if (   IS_CONST_OP(argop)
            && ((sv = cSVOPx_sv(argop)))
            /* defer stringification until runtime of 'constant'
             * things that might stringify variantly, e.g. the radix
             * point of NVs, or overloaded RVs */
            && (SvPOK(sv) || SvIOK(sv))
            && (!SvGMAGICAL(sv))
        ) {
            argp++->p = sv;
            utf8   |= cBOOL(SvUTF8(sv));
            nconst++;
            if (prev_was_const)
                /* this const may be demoted back to a plain arg later;
                 * make sure we have enough arg slots left */
                nadjconst++;
            prev_was_const = !prev_was_const;
        }
        else {
            argp++->p = NULL;
            nargs++;
            prev_was_const = FALSE;
        }

        if (last)
            break;
    }

    toparg = argp - 1;

    if (stacked_last)
        return; /* we don't support ((A.=B).=C)...) */

    /* look for two adjacent consts and don't fold them together:
     *     $o . "a" . "b"
     * should do
     *     $o->concat("a")->concat("b")
     * rather than
     *     $o->concat("ab")
     * (but $o .=  "a" . "b" should still fold)
     */
    {
        bool seen_nonconst = FALSE;
        for (argp = toparg; argp >= args; argp--) {
            if (argp->p == NULL) {
                seen_nonconst = TRUE;
                continue;
            }
            if (!seen_nonconst)
                continue;
            if (argp[1].p) {
                /* both previous and current arg were constants;
                 * leave the current OP_CONST as-is */
                argp->p = NULL;
                nconst--;
                nargs++;
            }
        }
    }

    /* -----------------------------------------------------------------
     * Phase 2:
     *
     * At this point we have determined that the optree *can* be converted
     * into a multiconcat. Having gathered all the evidence, we now decide
     * whether it *should*.
     */


    /* we need at least one concat action, e.g.:
     *
     *  Y . Z
     *  X = Y . Z
     *  X .= Y
     *
     * otherwise we could be doing something like $x = "foo", which
     * if treated as as a concat, would fail to COW.
     */
    if (nargs + nconst + cBOOL(private_flags & OPpMULTICONCAT_APPEND) < 2)
        return;

    /* Benchmarking seems to indicate that we gain if:
     * * we optimise at least two actions into a single multiconcat
     *    (e.g concat+concat, sassign+concat);
     * * or if we can eliminate at least 1 OP_CONST;
     * * or if we can eliminate a padsv via OPpTARGET_MY
     */

    if (
           /* eliminated at least one OP_CONST */
           nconst >= 1
           /* eliminated an OP_SASSIGN */
        || o->op_type == OP_SASSIGN
           /* eliminated an OP_PADSV */
        || (!targmyop && is_targable)
    )
        /* definitely a net gain to optimise */
        goto optimise;

    /* ... if not, what else? */

    /* special-case '$lex1 = expr . $lex1' (where expr isn't lex1):
     * multiconcat is faster (due to not creating a temporary copy of
     * $lex1), whereas for a general $lex1 = $lex2 . $lex3, concat is
     * faster.
     */
    if (   nconst == 0
         && nargs == 2
         && targmyop
         && IS_TYPE(topop, CONCAT)
    ) {
        PADOFFSET t = targmyop->op_targ;
        OP *k1 = OpFIRST(topop);
        OP *k2 = OpLAST(topop);
        if (   IS_TYPE(k2, PADSV)
            && k2->op_targ == t
               && (ISNT_TYPE(k1, PADSV)
                || k1->op_targ != t)
        )
            goto optimise;
    }

    /* need at least two concats */
    if (nargs + nconst + cBOOL(private_flags & OPpMULTICONCAT_APPEND) < 3)
        return;



    /* -----------------------------------------------------------------
     * Phase 3:
     *
     * At this point the optree has been verified as ok to be optimised
     * into an OP_MULTICONCAT. Now start changing things.
     */

   optimise:

    /* stringify all const args and determine utf8ness */

    variant = 0;
    for (argp = args; argp <= toparg; argp++) {
        SV *sv = (SV*)argp->p;
        if (!sv)
            continue; /* not a const op */
        if (utf8 && !SvUTF8(sv))
            sv_utf8_upgrade_nomg(sv);
        argp->p = SvPV_nomg(sv, argp->len);
        total_len += argp->len;
        
        /* see if any strings would grow if converted to utf8 */
        if (!utf8) {
            char *p    = (char*)argp->p;
            STRLEN len = argp->len;
            while (len--) {
                U8 c = *p++;
                if (!UTF8_IS_INVARIANT(c))
                    variant++;
            }
        }
    }

    /* create and populate aux struct */

  create_aux:

    aux = (UNOP_AUX_item*)PerlMemShared_malloc(
                    sizeof(UNOP_AUX_item)
                    *  (
                           PERL_MULTICONCAT_HEADER_SIZE
                         + ((nargs + 1) * (variant ? 2 : 1))
                        )
                    );
    const_str = (char *)PerlMemShared_malloc(total_len ? total_len : 1);

    /* Extract all the non-const expressions from the concat tree then
     * dispose of the old tree, e.g. convert the tree from this:
     *
     *  o => SASSIGN
     *         |
     *       STRINGIFY   -- TARGET
     *         |
     *       ex-PUSHMARK -- CONCAT
     *                        |
     *                      CONCAT -- EXPR5
     *                        |
     *                      CONCAT -- EXPR4
     *                        |
     *                      CONCAT -- EXPR3
     *                        |
     *                      EXPR1  -- EXPR2
     *
     *
     * to:
     *
     *  o => MULTICONCAT
     *         |
     *       ex-PUSHMARK -- EXPR1 -- EXPR2 -- EXPR3 -- EXPR4 -- EXPR5 -- TARGET
     *
     * except that if EXPRi is an OP_CONST, it's discarded.
     *
     * During the conversion process, EXPR ops are stripped from the tree
     * and unshifted onto o. Finally, any of o's remaining original
     * childen are discarded and o is converted into an OP_MULTICONCAT.
     *
     * In this middle of this, o may contain both: unshifted args on the
     * left, and some remaining original args on the right. lastkidop
     * is set to point to the right-most unshifted arg to delineate
     * between the two sets.
     */


    if (is_sprintf) {
        /* create a copy of the format with the %'s removed, and record
         * the sizes of the const string segments in the aux struct */
        char *q, *oldq;
        lenp = aux + PERL_MULTICONCAT_IX_LENGTHS;

        p    = sprintf_info.start;
        q    = const_str;
        oldq = q;
        for (; p < sprintf_info.end; p++) {
            if (*p == '%') {
                p++;
                if (*p != '%') {
                    (lenp++)->ssize = q - oldq;
                    oldq = q;
                    continue;
                }
            }
            *q++ = *p;
        }
        lenp->ssize = q - oldq;
        assert((STRLEN)(q - const_str) == total_len);

        /* Attach all the args (i.e. the kids of the sprintf) to o (which
         * may or may not be topop) The pushmark and const ops need to be
         * kept in case they're an op_next entry point.
         */
        lastkidop = OpLAST(topop);
        kid = OpFIRST(topop); /* pushmark */
        op_null(kid);
        assert(OpSIBLING(kid));
        op_null(kid->_OP_SIBPARENT_FIELDNAME); /* const, NN */
        if (o != topop) {
            kid = op_sibling_splice(topop, NULL, -1, NULL); /* cut all args */
            op_sibling_splice(o, NULL, 0, kid); /* and attach to o */
            lastkidop->op_next = o;
        }
    }
    else {
        p = const_str;
        lenp = aux + PERL_MULTICONCAT_IX_LENGTHS;

        lenp->ssize = -1;

        /* Concatenate all const strings into const_str.
         * Note that args[] contains the RHS args in reverse order, so
         * we scan args[] from top to bottom to get constant strings
         * in L-R order
         */
        for (argp = toparg; argp >= args; argp--) {
            if (!argp->p)
                /* not a const op */
                (++lenp)->ssize = -1;
            else {
                STRLEN l = argp->len;
                Copy(argp->p, p, l, char);
                p += l;
                if (lenp->ssize == -1)
                    lenp->ssize = l;
                else
                    lenp->ssize += l;
            }
        }

        kid = topop;
        nextop = o;
        lastkidop = NULL;

        for (argp = args; argp <= toparg; argp++) {
            /* only keep non-const args, except keep the first-in-next-chain
             * arg no matter what it is (but nulled if OP_CONST), because it
             * may be the entry point to this subtree from the previous
             * op_next.
             */
            bool last = (argp == toparg);
            OP *prev;

            /* set prev to the sibling *before* the arg to be cut out,
             * e.g.:
             *
             *         |
             * kid=  CONST
             *         |
             * prev= CONST -- EXPR
             *         |
             */
            if (argp == args && ISNT_TYPE(kid, CONCAT)) {
                /* in e.g. '$x . = f(1)' there's no RHS concat tree
                 * so the expression to be cut isn't kid->op_last but
                 * kid itself */
                OP *o1, *o2;
                /* find the op before kid */
                o1 = NULL;
                o2 = OpFIRST(parentop);
                while (o2 && o2 != kid) {
                    o1 = o2;
                    o2 = OpSIBLING(o2);
                }
                assert(o2 == kid);
                prev = o1;
                kid  = parentop;
            }
            else if (kid == o && lastkidop)
                prev = last ? lastkidop : OpSIBLING(lastkidop);
            else
                prev = last ? NULL : OpFIRST(kid);

            if (!argp->p || last) {
                /* cut RH op */
                OP *aop = op_sibling_splice(kid, prev, 1, NULL);
                /* and unshift to front of o */
                op_sibling_splice(o, NULL, 0, aop);
                /* record the right-most op added to o: later we will
                 * free anything to the right of it */
                if (!lastkidop)
                    lastkidop = aop;
                aop->op_next = nextop;
                if (last) {
                    if (argp->p)
                        /* null the const at start of op_next chain */
                        op_null(aop);
                }
                else if (prev)
                    nextop = prev->op_next;
            }

            /* the last two arguments are both attached to the same concat op */
            if (argp < toparg - 1)
                kid = prev;
        }
    }

    /* Populate the aux struct */

    aux[PERL_MULTICONCAT_IX_NARGS].ssize     = nargs;
    aux[PERL_MULTICONCAT_IX_PLAIN_PV].pv     = utf8 ? NULL : const_str;
    aux[PERL_MULTICONCAT_IX_PLAIN_LEN].ssize = utf8 ?    0 : total_len;
    aux[PERL_MULTICONCAT_IX_UTF8_PV].pv      = const_str;
    aux[PERL_MULTICONCAT_IX_UTF8_LEN].ssize  = total_len;

    /* if variant > 0, calculate a variant const string and lengths where
     * the utf8 version of the string will take 'variant' more bytes than
     * the plain one. */

    if (variant) {
        char              *p = const_str;
        STRLEN          ulen = total_len + variant;
        UNOP_AUX_item  *lens = aux + PERL_MULTICONCAT_IX_LENGTHS;
        UNOP_AUX_item *ulens = lens + (nargs + 1);
        char             *up = (char*)PerlMemShared_malloc(ulen);
        SSize_t            n;

        aux[PERL_MULTICONCAT_IX_UTF8_PV].pv    = up;
        aux[PERL_MULTICONCAT_IX_UTF8_LEN].ssize = ulen;

        for (n = 0; n < (nargs + 1); n++) {
            SSize_t i;
            char * orig_up = up;
            for (i = (lens++)->ssize; i > 0; i--) {
                U8 c = *p++;
                append_utf8_from_native_byte(c, (U8**)&up);
            }
            (ulens++)->ssize = (i < 0) ? i : up - orig_up;
        }
    }

    if (stringop) {
        /* if there was a top(ish)-level OP_STRINGIFY, we need to keep
         * that op's first child - an ex-PUSHMARK - because the op_next of
         * the previous op may point to it (i.e. it's the entry point for
         * the o optree)
         */
        OP *pmop =
            (stringop == o)
                ? op_sibling_splice(o, lastkidop, 1, NULL)
                : op_sibling_splice(stringop, NULL, 1, NULL);
        assert(OP_TYPE_IS_OR_WAS_NN(pmop, OP_PUSHMARK));
        op_sibling_splice(o, NULL, 0, pmop);
        if (!lastkidop)
            lastkidop = pmop;
    }

    /* Optimise 
     *    target  = A.B.C...
     *    target .= A.B.C...
     */

    if (targetop) {
        assert(!targmyop);

        if (IS_TYPE(o, SASSIGN)) {
            /* Move the target subtree from being the last of o's children
             * to being the last of o's preserved children.
             * Note the difference between 'target = ...' and 'target .= ...':
             * for the former, target is executed last; for the latter,
             * first.
             */
            kid = OpSIBLING(lastkidop);
            op_sibling_splice(o, kid, 1, NULL); /* cut target op */
            op_sibling_splice(o, lastkidop, 0, targetop); /* and paste */
            lastkidop->op_next = kid->op_next;
            lastkidop = targetop;
        }
        else {
            /* Move the target subtree from being the first of o's
             * original children to being the first of *all* o's children.
             */
            if (lastkidop) {
                op_sibling_splice(o, lastkidop, 1, NULL); /* cut target op */
                op_sibling_splice(o, NULL, 0, targetop);  /* and paste*/
            }
            else {
                /* if the RHS of .= doesn't contain a concat (e.g.
                 * $x .= "foo"), it gets missed by the "strip ops from the
                 * tree and add to o" loop earlier */
                assert(topop->op_type != OP_CONCAT);
                if (stringop) {
                    /* in e.g. $x .= "$y", move the $y expression
                     * from being a child of OP_STRINGIFY to being the
                     * second child of the OP_CONCAT
                     */
                    assert(OpFIRST(stringop) == topop);
                    op_sibling_splice(stringop, NULL, 1, NULL);
                    op_sibling_splice(o, OpFIRST(o), 0, topop);
                }
                assert(topop == OpSIBLING(OpFIRST(o)));
                if (toparg->p)
                    op_null(topop);
                lastkidop = topop;
            }
        }

        if (is_targable) {
            /* optimise
             *  my $lex  = A.B.C...
             *     $lex  = A.B.C...
             *     $lex .= A.B.C...
             * The original padsv op is kept but nulled in case it's the
             * entry point for the optree (which it will be for
             * '$lex .=  ... '
             */
            private_flags |= OPpTARGET_MY;
            private_flags |= (targetop->op_private & OPpLVAL_INTRO);
            o->op_targ = targetop->op_targ;
            targetop->op_targ = 0;
            op_null(targetop);
        }
        else
            flags |= OPf_STACKED;
    }
    else if (targmyop) {
        private_flags |= OPpTARGET_MY;
        if (o != targmyop) {
            o->op_targ = targmyop->op_targ;
            targmyop->op_targ = 0;
        }
    }

    /* detach the emaciated husk of the sprintf/concat optree and free it */
    for (;;) {
        kid = op_sibling_splice(o, lastkidop, 1, NULL);
        if (!kid)
            break;
        op_free(kid);
    }

    /* and convert o into a multiconcat */

    o->op_flags        = (flags|OPf_KIDS|stacked_last
                         |(o->op_flags & (OPf_WANT|OPf_PARENS)));
    o->op_private      = private_flags;
    o->op_type         = OP_MULTICONCAT;
    o->op_ppaddr       = PL_ppaddr[OP_MULTICONCAT];
    cUNOP_AUXo->op_aux = aux;
}

/*
=for apidoc cv_check_inline

examine an optree to determine whether it's in-lineable.
In contrast to op_const_sv allow short op sequences which are not
constant folded.
max 15 ops, no new pad, no intermediate return, no recursion, ...
cv_inline needs to translate the args, change return to jumps.

$lhs = call(...); => $lhs = do {...inlined...};

=cut
*/

#ifndef PERL_MAX_INLINE_OPS
#define PERL_MAX_INLINE_OPS 15
#endif

#ifdef PERL_INLINE_SUBS
static bool
S_cv_check_inline(pTHX_ const OP *o, CV *compcv)
{
    const OP *firstop = o;
    unsigned short i = 0;

    PERL_UNUSED_ARG(compcv);
    PERL_ARGS_ASSERT_CV_CHECK_INLINE;

    for (; o; o = o->op_next) {
	const OPCODE type = o->op_type;
        i++;

        if (i > PERL_MAX_INLINE_OPS) return FALSE;
	if (type == OP_NEXTSTATE || type == OP_DBSTATE
            || type == OP_NULL   || type == OP_LINESEQ
            || type == OP_PUSHMARK)
            continue;
	if (   type == OP_RETURN || type == OP_GOTO
            || type == OP_CALLER || type == OP_WARN
            || type == OP_DIE    || type == OP_RESET
            || type == OP_RUNCV  || type == OP_PADRANGE)
	    return FALSE;
	else if (type == OP_LEAVESUB)
	    break;
	else if (type == OP_ENTERSUB && OpFIRST(o) == firstop) {
	    return FALSE;
	}
    }
    return TRUE;
}
#endif

/*
=for apidoc s|void |process_optree	|NULLOK CV *cv|NN OP *root|NN OP *start

Do the post-compilation processing of an op_tree with specified
root and start

  * attach it to cv (if non-null)
  * set refcnt
  * run pre-peep optimizer, peep, finalize, prune an empty head, etc
  * tidy pad

=cut
*/

static void
S_process_optree(pTHX_ CV *cv, OP *root, OP *start)
{
    OP **startp;
    PERL_ARGS_ASSERT_PROCESS_OPTREE;

    if (cv) {
        CvROOT(cv) = root;
        /* The cv no longer needs to hold a refcount on the slab, as CvROOT
           itself has a refcount. */
        CvSLABBED_off(cv);
        startp = &CvSTART(cv);
        OpslabREFCNT_dec_padok((OPSLAB *)*startp);
    }
    else
        /* XXX for some reason, evals, require and main optrees are
         * never attached to their CV; instead they just hang off
         * PL_main_root + PL_main_start or PL_eval_root + PL_eval_start
         * and get manually freed when appropriate */
        startp = PL_in_eval? &PL_eval_start : &PL_main_start;
    *startp = start;

    root->op_private |= OPpREFCOUNTED;
    OpREFCNT_set(root, 1);
#ifdef PERL_FAKE_SIGNATURE
    /* does the sub look like it might start with 'my (...) = @_' ? */
    if (cv && IS_LEAVESUB_OP(root)) {
        OP *kid = OpFIRST(root);
        if (   kid
            && IS_TYPE(kid, LINESEQ)
            && (kid = OpFIRST(kid))
            && IS_STATE_OP(kid)
            && (!CopLABEL((COP*)kid))
            && (kid = OpSIBLING(kid))
            && IS_TYPE(kid, AASSIGN)
            && OpWANT_VOID(kid)
        )
        {
            S_maybe_op_signature(aTHX_ cv, root);
            root   = CvROOT(cv);
        }
    }
#endif
    optimize_optree(root);
    CALL_PEEP(*startp);
    finalize_optree(root);
    S_prune_chain_head(startp);

    if (cv) {
#ifdef PERL_INLINE_SUBS
        if (start && cv_check_inline(start, cv))
            CvINLINABLE_on(cv);
#endif
        /* now that optimizer has done its work, adjust pad values */
        pad_tidy(IS_TYPE(root, LEAVEWRITE)
                    ? padtidy_FORMAT
                    : CvCLONE(cv) ? padtidy_SUBCLONE : padtidy_SUB);
    }
}



/*
=for apidoc s||maybe_op_signature|NN CV *cv|NN OP *o

Does fake_signatures.
If the sub starts with 'my (...) = @_',
replace those ops with an OP_SIGNATURE.
Here we don't have to add the default $self invocant.

Cannot handle shift as this leaves leftover args.

=cut
*/
#ifdef PERL_FAKE_SIGNATURE
static void
S_maybe_op_signature(pTHX_ CV *cv, OP *o)
{
    OP *lineseq, *nextstate, *aassign, *kid, *first_padop, *sigop;
    UNOP_AUX_item *items;
    int items_ix;
    int actions_ix;
    UV action_acc;    /* accumulated actions for the current
                                        items[action_ix] slot */
    int action_count; /* how many actions have been stored in the
                            current items[action_ix] */
    int size;
    bool slurp_av      = FALSE;
    bool slurp_hv      = FALSE;
    int args           = 0;
    int pad_vars       = 0;
    PADOFFSET pad_base = NOT_IN_PAD;

    PERL_ARGS_ASSERT_MAYBE_OP_SIGNATURE;
    PERL_UNUSED_ARG(cv);

    if (PERLDB_LINE) /* no fake sigs with -d */
        return;
    lineseq   = OpFIRST(o);
    nextstate = OpFIRST(lineseq);
    aassign   = OpSIBLING(nextstate);

    /* ops up to this point already verified by caller */

    /* look for '= @_':
        aassign
          null (ex-list)
              pushmark
              rv2av
                gv[*_]
    */
    kid = OpFIRST(aassign);
    if (!kid || ISNT_TYPE(kid, NULL))
        return;
    kid = OpFIRST(kid);
    if (!kid || ISNT_TYPE(kid, PUSHMARK))
        return;
    kid = OpSIBLING(kid);
    if (!kid || ISNT_TYPE(kid, RV2AV))
        return;
    if (kid->op_private
            & (OPpSLICEWARNING|OPpMAYBE_LVSUB|OPpOUR_INTRO|OPpLVAL_INTRO))
        return;
    kid = OpFIRST(kid);
    if (!kid || ISNT_TYPE(kid, GV))
        return;
    if (cGVOPx_gv(kid) != PL_defgv || !OP_TYPE_IS(OpNEXT(kid), OP_RV2AV))
        return;
    /* we should ignore extra rhs args after = (@_, ...);
       but for sanity skip with extra rhs args here already [cperl #157]
       and do not count the lhs vars.
         my($self,$extra)=(@_,0);
    */
    if (!OP_TYPE_IS_OR_WAS(OpNEXT(OpNEXT(kid)), OP_LIST)) /* no extra values */
        return;

    if (cophh_fetch_pvs(CopHINTHASH_get(PL_curcop), "no_fake_signatures",
                        REFCOUNTED_HE_EXISTS))
        return;

    /* at this point the RHS of the aassign is definitely @_ */

    /* LHS of aassign looks like
     * null (ex-list)
     *   pushmark
     *   padsv and/or undef x N
     *   with optional trailing padav/padhv
     *
     * skip the null and pushmark, then process all the
     * pad ops. Return on anything unexpected/
     */

    kid = OpLAST(aassign);
    if (!kid || OP_TYPE_ISNT(kid, OP_NULL))
        return;
    kid = OpFIRST(kid);
    if (!kid || OP_TYPE_ISNT(kid, OP_PUSHMARK))
        return;
    kid = first_padop = OpSIBLING(kid);

    for(; kid; kid = OpSIBLING(kid)) {
        if (slurp_av || slurp_hv) /* @foo or %foo must be last */
            return;

        if (OpKIDS(kid)) /* something weird */
            return;

        args++;
        if (args > 32767)
            return;

        if (IS_TYPE(kid, UNDEF))
            continue;

        if (IS_TYPE(kid, PADAV)) {
            if (kid->op_private &
                    (OPpSLICEWARNING|OPpMAYBE_LVSUB|OPpPAD_STATE))
                return;
            slurp_av = TRUE;
        }
        else if (IS_TYPE(kid, PADHV)) {
            if (kid->op_private &
                    ( OPpSLICEWARNING|OPpMAYBE_LVSUB|OPpMAYBE_TRUEBOOL
                     |OPpTRUEBOOL|OPpPAD_STATE))
                return;
            slurp_hv = TRUE;
        }
        else if (IS_TYPE(kid, PADSV)) {
            if (kid->op_private & (OPpDEREF|OPpPAD_STATE))
                return;
        }
        else 
            return;

        if ((kid->op_flags & (OPf_REF|OPf_MOD)) != (OPf_REF|OPf_MOD))
            return;

        if (!(kid->op_private & OPpLVAL_INTRO))
            return;

        pad_vars++;
        if (pad_vars >= OPpPADRANGE_COUNTMASK)
            return;

        if (pad_base == NOT_IN_PAD)
            pad_base = kid->op_targ;
        else if (pad_base + pad_vars -1 != kid->op_targ)
            return;

    }

    /* We have a match. Create an OP_SIGNATURE op */
    /* Calculate size of items array */
    size =  1    /* size field */
          + 1    /* numbers of args field */
                 /* the actions index */
          + 1    /* padintro item field */

          /* number of action item fields */
          + (args /* number of arg actions */
              + 1 /* padintro action */
              + 1 /* end action */
              - 1 /* 1..N fits in 1 slot rather than 0..N-1 */
            ) / (UVSIZE * 8 / SIGNATURE_SHIFT) + 1;

    DEBUG_k(Perl_deb(aTHX_ "fake_signature: %" SVf "\n",
                     SVfARG(cv_name(cv, NULL, CV_NAME_NOMAIN))));
    items = (UNOP_AUX_item*)PerlMemShared_malloc(sizeof(UNOP_AUX_item) * size);

    items[0].uv = size - 1;
    items[1].uv = args | (1  << 15); /* fake slurpy bit */
    actions_ix = 2;
    items[actions_ix].uv = 0;
    items[3].uv = ((pad_base << OPpPADRANGE_COUNTSHIFT) | pad_vars);
    items_ix = 4;

    action_acc = SIGNATURE_padintro;
    action_count = 1;

    for (kid = first_padop; ; kid = OpSIBLING(kid)) {
        UV action =
            !kid                     ? SIGNATURE_end
          : IS_TYPE(kid, UNDEF) ? (SIGNATURE_arg|SIGNATURE_FLAG_skip)
          : IS_TYPE(kid, PADSV) ? SIGNATURE_arg
          : IS_TYPE(kid, PADAV) ? SIGNATURE_array
          :                            SIGNATURE_hash;

        action_acc |= action << (action_count * SIGNATURE_SHIFT);
        assert(actions_ix < size);
        items[actions_ix].uv = action_acc;
        action_count = (action_count + 1) % (UVSIZE * 8 / SIGNATURE_SHIFT);

        if (!action_count) {
            actions_ix = items_ix++;
            action_acc = 0;
        }

        if (!kid)
            break;
    }

    sigop = newUNOP_AUX(OP_SIGNATURE, 0, NULL, items + 1);
    sigop->op_private |= OPpSIGNATURE_FAKE; /* not a real signature */
    CvSIGOP(cv) = (UNOP_AUX*)sigop;

    /* excise the aassign from the lineseq and
     * replace them with the OP_SIGNATURE */
    op_sibling_splice(lineseq, nextstate, 1, sigop);
    OpNEXT(nextstate) = sigop;
    OpNEXT(sigop) = OpNEXT(aassign);
    op_free(aassign);
}
#endif


/*
=for apidoc optimize_optree

This function applies some optimisations to the optree in top-down order.
It is called before the peephole optimizer, which processes ops in
execution order. Note that finalize_optree() also does a top-down scan,
but is called *after* the peephole optimizer.

=cut
*/
void
Perl_optimize_optree(pTHX_ OP* o)
{
    PERL_ARGS_ASSERT_OPTIMIZE_OPTREE;

    ENTER;
    SAVEVPTR(PL_curcop);

    optimize_op(o);

    LEAVE;
}


/* 
=for apidoc optimize_op

Helper for optimize_optree() which optimises a single op then recurses
to optimise any children.

=cut
*/
STATIC void
S_optimize_op(pTHX_ OP* o)
{
    OP *kid;

    PERL_ARGS_ASSERT_OPTIMIZE_OP;
    assert(o->op_type != OP_FREED);

    switch (o->op_type) {
    case OP_NEXTSTATE:
    case OP_DBSTATE:
	PL_curcop = ((COP*)o);		/* for warnings */
	break;


    case OP_CONCAT:
    case OP_SASSIGN:
    case OP_STRINGIFY:
    case OP_SPRINTF:
        maybe_multiconcat(o);
        break;

    case OP_SUBST:
	if (cPMOPo->op_pmreplrootu.op_pmreplroot)
	    optimize_op(cPMOPo->op_pmreplrootu.op_pmreplroot);
	break;

    default:
	break;
    }

    if (!(o->op_flags & OPf_KIDS))
        return;

    for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
        optimize_op(kid);
}


/*
=for apidoc finalize_optree

This function finalizes the optree.  Should be called directly after
the complete optree is built.  It does some additional
checking which can't be done in the normal C<ck_>xxx functions and makes
the tree thread-safe.

=cut
*/
void
Perl_finalize_optree(pTHX_ OP* o)
{
    PERL_ARGS_ASSERT_FINALIZE_OPTREE;

    ENTER;
    SAVEVPTR(PL_curcop);

    finalize_op(o);

    LEAVE;
}

#ifdef USE_ITHREADS
/*
=for apidoc op_relocate_sv

Relocate sv to the pad for thread safety.
Despite being a "constant", the SV is written to,
for reference counts, sv_upgrade() etc.

=cut
*/
void
Perl_op_relocate_sv(pTHX_ SV** svp, PADOFFSET* targp)
{
    PADOFFSET ix;
    PERL_ARGS_ASSERT_OP_RELOCATE_SV;
    if (!*svp) return;
    ix = pad_alloc(OP_CONST, SVf_READONLY);
    SvREFCNT_dec(PAD_SVl(ix));
    PAD_SETSV(ix, *svp);
    /* XXX I don't know how this isn't readonly already. */
    if (!SvIsCOW(PAD_SVl(ix))) SvREADONLY_on(PAD_SVl(ix));
    *svp = NULL;
    *targp = ix;
}
#endif

/*
=for apidoc op_gv_set

Set the gv as the op_sv.
With threads also relocate a gv to the pad for thread safety.
cperl-only

=cut
*/
PERL_STATIC_INLINE void
S_op_gv_set(pTHX_ OP* o, GV* gv)
{
#ifdef USE_ITHREADS
    PADOFFSET po = AvFILLp(PL_comppad);
    PERL_ARGS_ASSERT_OP_GV_SET;
    STATIC_ASSERT_STMT(sizeof(PADOP) <= sizeof(SVOP));
    ASSERT_CURPAD_ACTIVE("op_gv_set");
    assert(PL_curpad == AvARRAY(PL_comppad));
    assert(OP_IS_PADOP(o->op_type)); /* only with cperl. with perl5 you need to check SVOP */

    SvREFCNT_inc_simple_void_NN(gv);

#ifdef USE_PAD_REUSE
    if (!SvPADTMP(gv) && PL_comppad == PadlistARRAY(CvPADLIST(PL_main_cv))[1]) {
# ifndef PAD_REUSE_MRU
#  define PAD_REUSE_MRU 8
# endif
        /* Search the last 8 global pads for reuse. All those should be readonly if GV.
         * XXX pad_swipe may delete our reused pad when going out of scope, which breaks our reuse.
         * We need to find out our scope padrange.
         */
        PADOFFSET i;
        CACHE_PREFETCH(PL_curpad[po-PAD_REUSE_MRU], 0, 0);
        for (i = po; i >= PAD_REUSE_MRU; i--) {
            if (PL_curpad[i] == (SV*)gv) {
                DEBUG_kv(Perl_deb(aTHX_ "op_gv_set %s reuse [%lu] %s 0x%x\n",
                                  SvPVX_const(gv_display(gv)), (unsigned long)i,
                                  SvPEEK((SV*)gv), SvFLAGS(gv)));
                cPADOPx(o)->op_padix = i;
                return;
            }
        }
    }
#endif
    po = pad_alloc(o->op_type, SVf_READONLY);
    cPADOPx(o)->op_padix = po;
    if (PAD_SVl(po) && !SvIS_FREED(PAD_SVl(po)))
        sv_free(PAD_SVl(po));
    PAD_SETSV(po, (SV*)gv);
    DEBUG_kv(Perl_deb(aTHX_ "op_gv_set %s [%lu] %s 0x%x\n",
                      SvPVX_const(gv_display(gv)), (unsigned long)po,
                      SvPEEK((SV*)gv), SvFLAGS(gv)));
#else
    PERL_ARGS_ASSERT_OP_GV_SET;
    assert(OP_IS_SVOP(o->op_type));
    cSVOPo->op_sv = SvREFCNT_inc_simple_NN((SV*)gv);
#endif
}


/*
=for apidoc finalize_op

Calls several op-specific finalizers, warnings and fixups.

=cut
*/
static void
S_finalize_op(pTHX_ OP* o)
{
    PERL_ARGS_ASSERT_FINALIZE_OP;

    assert(o->op_type != OP_FREED);

    switch (o->op_type) {
    case OP_NEXTSTATE:
    case OP_DBSTATE:
	PL_curcop = ((COP*)o);		/* for warnings */
	break;
    case OP_EXEC:
        if (OpHAS_SIBLING(o)) {
            OP *sib = OpSIBLING(o);
            if (   IS_STATE_OP(sib)
                && ckWARN(WARN_EXEC)
                && OpHAS_SIBLING(sib))
            {
                const OPCODE type = OpSIBLING(sib)->op_type;
                if (type != OP_EXIT && type != OP_WARN && type != OP_DIE) {
                    const line_t oldline = CopLINE(PL_curcop);
                    CopLINE_set(PL_curcop, CopLINE((COP*)sib));
                    Perl_warner(aTHX_ packWARN(WARN_EXEC),
                                "Statement unlikely to be reached");
                    Perl_warner(aTHX_ packWARN(WARN_EXEC),
                                "\t(Maybe you meant system() when you said exec()?)\n");
                    CopLINE_set(PL_curcop, oldline);
                }
	    }
        }
	break;

    case OP_GV:
	if ((o->op_private & OPpEARLY_CV) && ckWARN(WARN_PROTOTYPE)) {
	    GV * const gv = cGVOPo_gv;
	    if (SvTYPE(gv) == SVt_PVGV && GvCV(gv) && SvPVX_const(GvCV(gv))) {
		/* XXX could check prototype here instead of just carping */
		SV * const sv = sv_newmortal();
		gv_efullname3(sv, gv, NULL);
		Perl_warner(aTHX_ packWARN(WARN_PROTOTYPE),
		    "%" SVf "() called too early to check prototype",
		    SVfARG(sv));
	    }
	}
	break;

    case OP_CONST:
	if (cSVOPo->op_private & OPpCONST_STRICT)
	    no_bareword_allowed(o);
#ifdef USE_ITHREADS
        /* FALLTHROUGH */
    case OP_HINTSEVAL:
        op_relocate_sv(&cSVOPo->op_sv, &o->op_targ);
#endif
        break;

#ifdef USE_ITHREADS
    /* Relocate all the METHOP's SVs to the pad for thread safety. */
    case OP_METHOD_NAMED:
    case OP_METHOD_SUPER:
    case OP_METHOD_REDIR:
    case OP_METHOD_REDIR_SUPER:
        op_relocate_sv(&cMETHOPx(o)->op_u.op_meth_sv, &o->op_targ);
        break;
#endif

    case OP_HELEM: {
	UNOP *rop;
	SVOP *key_op;
	OP *kid;

	if (ISNT_TYPE((key_op = cSVOPx(OpLAST(o))), CONST))
	    break;

	rop = (UNOP*)OpFIRST(o);
	goto check_keys;

    case OP_HSLICE:
	S_scalar_slice_warning(aTHX_ o);
        /* FALLTHROUGH */

    case OP_KVHSLICE:
        kid = OpSIBLING(OpFIRST(o));
	if (/* I bet there's always a pushmark... */
	    OP_TYPE_ISNT_AND_WASNT_NN(kid, OP_LIST)
	    && ISNT_TYPE(kid, CONST))
	    break;

	key_op = (SVOP*)(IS_CONST_OP(kid)
				? kid
				: OpSIBLING(OpFIRST(kid)));
	rop = (UNOP*)OpLAST(o);

      check_keys:	
        if (o->op_private & OPpLVAL_INTRO || ISNT_TYPE(rop, RV2HV))
            rop = NULL;
        S_check_hash_fields_and_hekify(aTHX_ rop, key_op);
	break;
    }
    case OP_NULL:
	if (o->op_targ != OP_HSLICE && o->op_targ != OP_ASLICE)
	    break;
	/* FALLTHROUGH */
    case OP_ASLICE:
	S_scalar_slice_warning(aTHX_ o);
	break;

    case OP_SUBST: {
	if (cPMOPo->op_pmreplrootu.op_pmreplroot)
	    finalize_op(cPMOPo->op_pmreplrootu.op_pmreplroot);
	break;
    }
    default:
	break;
    }

    if (OpKIDS(o)) {
	OP *kid;

#ifdef DEBUGGING
        /* check that op_last points to the last sibling, and that
         * the last op_sibling/op_sibparent field points back to the
         * parent, and that the only ops with KIDS are those which are
         * entitled to them */
        U32 type = o->op_type;
        U32 family;
        bool has_last;

        if (type == OP_NULL) {
            type = o->op_targ;
            /* ck_glob creates a null UNOP with ex-type GLOB
             * (which is a list op. So pretend it wasn't a listop */
            if (type == OP_GLOB)
                type = OP_NULL;
        }
        family = PL_opargs[type] & OA_CLASS_MASK;

        has_last = (   family == OA_BINOP
                    || family == OA_LISTOP
                    || family == OA_PMOP
                    || family == OA_LOOP
                   );
        assert(  has_last /* has op_first and op_last, or ...
              ... has (or may have) op_first: */
              || family == OA_UNOP
              || family == OA_UNOP_AUX
              || family == OA_LOGOP
              || family == OA_BASEOP_OR_UNOP
              || family == OA_FILESTATOP
              || family == OA_LOOPEXOP
              || family == OA_METHOP
              || type == OP_CUSTOM
              || type == OP_NULL /* new_logop does this */
              );

        for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid)) {
#  ifdef PERL_OP_PARENT
            if (!OpHAS_SIBLING(kid)) {
                if (has_last)
                    assert(kid == OpLAST(o));
                assert(kid->op_sibparent == o);
            }
#  else
            if (has_last && !OpHAS_SIBLING(kid))
                assert(kid == OpLAST(o));
#  endif
        }
#endif

	for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
	    finalize_op(kid);
    }
}

/*
=for apidoc Amx|OP *	|op_lvalue	|OP *o|I32 type

Propagate lvalue ("modifiable") context to an op and its children.
C<type> represents the context type, roughly based on the type of op that
would do the modifying, although C<local()> is represented by C<OP_NULL>,
because it has no op type of its own (it is signalled by a flag on
the lvalue op).

This function detects things that can't be modified, such as C<$x+1>, and
generates errors for them.  For example, C<$x+1 = 2> would cause it to be
called with an op of type C<OP_ADD> and a C<type> argument of C<OP_SASSIGN>.

It also flags things that need to behave specially in an lvalue context,
such as C<$$x = 5> which might have to vivify a reference in C<$x>.

=cut
*/

static void
S_mark_padname_lvalue(pTHX_ PADNAME *pn)
{
    CV *cv = PL_compcv;
    PadnameLVALUE_on(pn);
    while (PadnameOUTER(pn) && PARENT_PAD_INDEX(pn)) {
	cv = CvOUTSIDE(cv);
        /* RT #127786: cv can be NULL due to an eval within the DB package
         * called from an anon sub - anon subs don't have CvOUTSIDE() set
         * unless they contain an eval, but calling eval within DB
         * pretends the eval was done in the caller's scope.
         */
	if (!cv)
            break;
	assert(CvPADLIST(cv));
	pn = PadlistNAMESARRAY(CvPADLIST(cv))[PARENT_PAD_INDEX(pn)];
	assert(PadnameLEN(pn));
	PadnameLVALUE_on(pn);
    }
}

static bool
S_vivifies(const OPCODE type)
{
    switch(type) {
    case OP_RV2AV:     case   OP_ASLICE:
    case OP_RV2HV:     case OP_KVASLICE:
    case OP_RV2SV:     case   OP_HSLICE:
    case OP_AELEMFAST: case OP_KVHSLICE:
    case OP_HELEM:
    case OP_AELEM:
	return 1;
    }
    return 0;
}

static void
S_lvref(pTHX_ OP *o, I32 type)
{
    dVAR;
    OP *kid;
    switch (o->op_type) {
    case OP_COND_EXPR:
	for (kid = OpSIBLING(OpFIRST(o)); kid;
	     kid = OpSIBLING(kid))
	    S_lvref(aTHX_ kid, type);
	/* FALLTHROUGH */
    case OP_PUSHMARK:
	return;
    case OP_RV2AV:
	if (ISNT_TYPE(OpFIRST(o), GV)) goto badref;
	o->op_flags |= OPf_STACKED;
	if (OpPARENS(o)) {
	    if (o->op_private & OPpLVAL_INTRO) {
                yyerror(Perl_form(aTHX_ "Can't modify reference to "
		      "localized parenthesized array in list assignment"));
		return;
	    }
	  slurpy:
            OpTYPE_set(o, OP_LVAVREF);
	    o->op_private &= OPpLVAL_INTRO|OPpPAD_STATE;
	    o->op_flags |= OPf_MOD|OPf_REF;
	    return;
	}
	o->op_private |= OPpLVREF_AV;
	goto checkgv;
    case OP_RV2CV:
	kid = OpFIRST(o);
	if (IS_NULL_OP(kid))
	    kid = OpFIRST(OpSIBLING(OpFIRST(kid)));
	o->op_private = OPpLVREF_CV;
	if (IS_TYPE(kid, GV))
	    o->op_flags |= OPf_STACKED;
	else if (IS_TYPE(kid, PADCV)) {
	    o->op_targ = kid->op_targ;
	    kid->op_targ = 0;
	    op_free(OpFIRST(o));
	    OpFIRST(o) = NULL;
	    o->op_flags &=~ OPf_KIDS;
	}
	else goto badref;
	break;
    case OP_RV2HV:
	if (OpPARENS(o)) {
	  parenhash:
	    yyerror(Perl_form(aTHX_ "Can't modify reference to "
				 "parenthesized hash in list assignment"));
            return;
	}
	o->op_private |= OPpLVREF_HV;
	/* FALLTHROUGH */
    case OP_RV2SV:
      checkgv:
	if (ISNT_TYPE(OpFIRST(o), GV)) goto badref;
	o->op_flags |= OPf_STACKED;
	break;
    case OP_PADHV:
	if (OpPARENS(o)) goto parenhash;
	o->op_private |= OPpLVREF_HV;
	/* FALLTHROUGH */
    case OP_PADSV:
	PAD_COMPNAME_GEN_set(o->op_targ, PERL_INT_MAX);
	break;
    case OP_PADAV:
	PAD_COMPNAME_GEN_set(o->op_targ, PERL_INT_MAX);
	if (OpPARENS(o)) goto slurpy;
	o->op_private |= OPpLVREF_AV;
	break;
    case OP_AELEM:
    case OP_HELEM:
	o->op_private |= OPpLVREF_ELEM;
	o->op_flags   |= OPf_STACKED;
	break;
    case OP_ASLICE:
    case OP_HSLICE:
        OpTYPE_set(o, OP_LVREFSLICE);
	o->op_private &= OPpLVAL_INTRO;
	return;
    case OP_NULL:
	if (OpSPECIAL(o))		/* do BLOCK */
	    goto badref;
	else if (!OpKIDS(o))
	    return;
	if (o->op_targ != OP_LIST) {
	    S_lvref(aTHX_ OpFIRST(o), type);
	    return;
	}
	/* FALLTHROUGH */
    case OP_LIST:
	for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid)) {
	    assert((kid->op_flags & OPf_WANT) != OPf_WANT_VOID);
	    S_lvref(aTHX_ kid, type);
	}
	return;
    case OP_STUB:
	if (OpPARENS(o))
	    return;
	/* FALLTHROUGH */
    default:
      badref:
	/* diag_listed_as: Can't modify reference to %s in %s assignment */
	yyerror(Perl_form(aTHX_ "Can't modify reference to %s in %s",
		     IS_NULL_OP(o) && OpSPECIAL(o)
		      ? "do block"
		      : OP_DESC(o),
		     PL_op_desc[type]));
	return;
    }
    OpTYPE_set(o, OP_LVREF);
    o->op_private &=
	OPpLVAL_INTRO|OPpLVREF_ELEM|OPpLVREF_TYPE|OPpPAD_STATE;
    if (type == OP_ENTERLOOP)
	o->op_private |= OPpLVREF_ITER;
}

PERL_STATIC_INLINE bool
S_potential_mod_type(I32 type)
{
    /* Types that only potentially result in modification.  */
    return type == OP_GREPSTART || type == OP_ENTERSUB || type == OP_ENTERXSSUB
	|| type == OP_REFGEN    || type == OP_LEAVESUBLV;
}

OP *
Perl_op_lvalue_flags(pTHX_ OP *o, I32 type, U32 flags)
{
    dVAR;
    OP *kid;
    /* -1 = error on localize, 0 = ignore localize, 1 = ok to localize */
    int localize = -1;

    if (!o || (PL_parser && PL_parser->error_count))
	return o;

    if ((o->op_private & OPpTARGET_MY)
        && OP_HAS_TARGLEX(o->op_type)) /* OPp share the meaning */
    {
	return o;
    }

    assert( (o->op_flags & OPf_WANT) != OPf_WANT_VOID );

    if (type == OP_PRTF || type == OP_SPRINTF) type = OP_ENTERSUB;

    switch (o->op_type) {
    case OP_UNDEF:
	PL_modcount++;
	return o;
    case OP_STUB:
	if (OpPARENS(o))
	    break;
	goto nomod;
    case OP_ENTERSUB:
    case OP_ENTERXSSUB:
	if ((type == OP_UNDEF || type == OP_REFGEN || type == OP_LOCK)
            && !OpSTACKED(o)) {
            OpTYPE_set(o, OP_RV2CV);		/* entersub => rv2cv */
	    assert(IS_NULL_OP(OpFIRST(o)));
	    op_null(OpFIRST(OpFIRST(o)));       /* disable pushmark */
	    break;
	}
	else {				/* lvalue subroutine call */
	    o->op_private |= OPpLVAL_INTRO;
	    PL_modcount = RETURN_UNLIMITED_NUMBER;
	    if (S_potential_mod_type(type)) {
		o->op_private |= OPpENTERSUB_INARGS;
		break;
	    }
	    else {                      /* Compile-time error message: */
		OP *kid = OpFIRST(o);
		CV *cv;
		GV *gv;
                SV *namesv;

		if (ISNT_TYPE(kid, PUSHMARK)) {
		    if (!OP_TYPE_WAS_NN(kid, OP_LIST))
			Perl_croak(aTHX_
				"panic: unexpected lvalue entersub "
				"args: type/targ %ld:%" UVuf,
				(long)kid->op_type, (UV)kid->op_targ);
		    kid = OpFIRST(kid);
		}
		while (OpHAS_SIBLING(kid))
		    kid = OpSIBLING(kid);
		if (!OP_TYPE_WAS_NN(kid, OP_RV2CV)) {
		    break;	/* Postpone until runtime */
		}

		kid = OpFIRST(kid);
		if (OP_TYPE_WAS_NN(kid, OP_RV2SV))
		    kid = OpFIRST(kid);
		if (IS_NULL_OP(kid))
		    Perl_croak(aTHX_
			       "Unexpected constant lvalue entersub "
			       "entry via type/targ %ld:%" UVuf,
			       (long)kid->op_type, (UV)kid->op_targ);
		if (ISNT_TYPE(kid, GV)) {
		    break;
		}

		gv = kGVOP_gv;
		cv = isGV(gv)
		    ? GvCV(gv)
		    : SvROK(gv) && SvTYPE(SvRV(gv)) == SVt_PVCV
			? MUTABLE_CV(SvRV(gv))
			: NULL;
		if (!cv)
		    break;
		if (CvLVALUE(cv))
		    break;
                if (flags & OP_LVALUE_NO_CROAK)
                    return NULL;

                namesv = cv_name(cv, NULL, 0);
                yyerror_pv(Perl_form(aTHX_ "Can't modify non-lvalue "
                                     "subroutine call of &%" SVf " in %s",
                                     SVfARG(namesv), PL_op_desc[type]),
                           SvUTF8(namesv));
                return o;
	    }
	}
	/* FALLTHROUGH */
    default:
      nomod:
	if (flags & OP_LVALUE_NO_CROAK)
            return NULL;
	/* grep, foreach, subcalls, refgen */
	if (S_potential_mod_type(type))
	    break;
	yyerror(Perl_form(aTHX_ "Can't modify %s in %s",
		     (IS_NULL_OP(o) && OpSPECIAL(o)
		      ? "do block"
		      : (IS_SUB_OP(o)
			? "non-lvalue subroutine call"
			: OP_DESC(o))),
		     type ? PL_op_desc[type] : "local"));
	return o;

    case OP_PREINC:
    case OP_PREDEC:
    case OP_POW:
    case OP_MULTIPLY:
    case OP_DIVIDE:
    case OP_MODULO:
    case OP_ADD:
    case OP_SUBTRACT:
    case OP_CONCAT:
    case OP_LEFT_SHIFT:
    case OP_RIGHT_SHIFT:
    case OP_BIT_AND:
    case OP_BIT_XOR:
    case OP_BIT_OR:
    case OP_I_MULTIPLY:
    case OP_I_DIVIDE:
    case OP_I_MODULO:
    case OP_I_ADD:
    case OP_I_SUBTRACT:
    case OP_I_POW:
#ifdef PERL_NATIVE_TYPES
    case OP_UINT_LEFT_SHIFT:
    case OP_UINT_RIGHT_SHIFT:
    case OP_UINT_POW:
    case OP_UINT_COMPLEMENT:
    case OP_INT_ADD:
    case OP_INT_SUBTRACT:
    case OP_INT_MULTIPLY:
    case OP_INT_DIVIDE:
    case OP_INT_MODULO:
    case OP_INT_NEGATE:
    case OP_INT_NOT:
    case OP_INT_ABS:
    case OP_NUM_ADD:
    case OP_NUM_SUBTRACT:
    case OP_NUM_MULTIPLY:
    case OP_NUM_DIVIDE:
    case OP_NUM_ATAN2:
    case OP_NUM_SIN:
    case OP_NUM_COS:
    case OP_NUM_EXP:
    case OP_NUM_LOG:
    case OP_NUM_SQRT:
    case OP_NUM_POW:
#endif
	if (!OpSTACKED(o))
	    goto nomod;
	PL_modcount++;
	break;

    case OP_REPEAT:
	if (OpSTACKED(o)) {
	    PL_modcount++;
	    break;
	}
	if (!(o->op_private & OPpREPEAT_DOLIST))
	    goto nomod;
	else {
	    const I32 mods = PL_modcount;
	    modkids(OpFIRST(o), type);
	    if (type != OP_AASSIGN)
		goto nomod;
	    kid = OpLAST(o);
	    if (IS_CONST_OP(kid) && SvIOK(kSVOP_sv)) {
		const IV iv = SvIV(kSVOP_sv);
		if (PL_modcount != RETURN_UNLIMITED_NUMBER)
		    PL_modcount =
			mods + (PL_modcount - mods) * (iv < 0 ? 0 : iv);
	    }
	    else
		PL_modcount = RETURN_UNLIMITED_NUMBER;
	}
	break;

    case OP_COND_EXPR:
	localize = 1;
	for (kid = OpSIBLING(OpFIRST(o)); kid; kid = OpSIBLING(kid))
	    op_lvalue(kid, type);
	break;

    case OP_RV2AV:
    case OP_RV2HV:
	if (type == OP_REFGEN && OpPARENS(o)) {
            PL_modcount = RETURN_UNLIMITED_NUMBER;
	    return o;		/* Treat \(@foo) like ordinary list. */
	}
	/* FALLTHROUGH */
    case OP_RV2GV:
	if (scalar_mod_type(o, type))
	    goto nomod;
	ref(OpFIRST(o), o->op_type);
	/* FALLTHROUGH */
    case OP_ASLICE:
    case OP_HSLICE:
	localize = 1;
	/* FALLTHROUGH */
    case OP_AASSIGN:
	/* Do not apply the lvsub flag for rv2[ah]v in scalar context.  */
	if (type == OP_LEAVESUBLV && (
                (ISNT_TYPE(o, RV2AV) && ISNT_TYPE(o, RV2HV))
	     || (o->op_flags & OPf_WANT) != OPf_WANT_SCALAR
	   ))
	    o->op_private |= OPpMAYBE_LVSUB;
	/* FALLTHROUGH */
    case OP_NEXTSTATE:
    case OP_DBSTATE:
        PL_modcount = RETURN_UNLIMITED_NUMBER;
	break;
    case OP_KVHSLICE:
    case OP_KVASLICE:
    case OP_AKEYS:
	if (type == OP_LEAVESUBLV)
	    o->op_private |= OPpMAYBE_LVSUB;
        goto nomod;
    case OP_AVHVSWITCH:
	if (type == OP_LEAVESUBLV
	 && (o->op_private & OPpAVHVSWITCH_MASK) + OP_EACH == OP_KEYS)
	    o->op_private |= OPpMAYBE_LVSUB;
        goto nomod;
    case OP_AV2ARYLEN:
	PL_hints |= HINT_BLOCK_SCOPE;
	if (type == OP_LEAVESUBLV)
	    o->op_private |= OPpMAYBE_LVSUB;
	PL_modcount++;
	break;
    case OP_RV2SV:
	ref(OpFIRST(o), o->op_type);
	localize = 1;
	/* FALLTHROUGH */
    case OP_GV:
	PL_hints |= HINT_BLOCK_SCOPE;
        /* FALLTHROUGH */
    case OP_SASSIGN:
    case OP_ANDASSIGN:
    case OP_ORASSIGN:
    case OP_DORASSIGN:
	PL_modcount++;
	break;

    case OP_AELEMFAST:
    case OP_AELEMFAST_LEX:
    case OP_AELEMFAST_LEX_U:
	localize = -1;
	PL_modcount++;
	break;

    case OP_PADAV:
    case OP_PADHV:
       PL_modcount = RETURN_UNLIMITED_NUMBER;
	if (type == OP_REFGEN && OpPARENS(o))
	    return o;		/* Treat \(@foo) like ordinary list. */
	if (scalar_mod_type(o, type))
	    goto nomod;
	if ((o->op_flags & OPf_WANT) != OPf_WANT_SCALAR
            && type == OP_LEAVESUBLV)
	    o->op_private |= OPpMAYBE_LVSUB;
	/* FALLTHROUGH */
    case OP_PADSV:
	PL_modcount++;
	if (!type) /* local() */
	    Perl_croak(aTHX_ "Can't localize lexical variable %" PNf,
			      PNfARG(PAD_COMPNAME(o->op_targ)));
	if (!(o->op_private & OPpLVAL_INTRO)
	 || (  type != OP_SASSIGN && type != OP_AASSIGN
	    && PadnameIsSTATE(PAD_COMPNAME_SV(o->op_targ))  ))
	    S_mark_padname_lvalue(aTHX_ PAD_COMPNAME_SV(o->op_targ));
	break;

    case OP_PUSHMARK:
	localize = 0;
	break;

    case OP_KEYS:
	if (type != OP_LEAVESUBLV && !scalar_mod_type(NULL, type))
	    goto nomod;
	goto lvalue_func;
    case OP_SUBSTR:
	if (o->op_private == 4) /* don't allow 4 arg substr as lvalue */
	    goto nomod;
	/* FALLTHROUGH */
    case OP_POS:
    case OP_VEC:
      lvalue_func:
	if (type == OP_LEAVESUBLV)
	    o->op_private |= OPpMAYBE_LVSUB;
	if (OpKIDS(o) && OpHAS_SIBLING(OpFIRST(o))) {
	    /* substr and vec */
	    /* If this op is in merely potential (non-fatal) modifiable
	       context, then apply OP_ENTERSUB context to
	       the kid op (to avoid croaking).  Other-
	       wise pass this op’s own type so the correct op is mentioned
	       in error messages.  */
	    op_lvalue(OpSIBLING(OpFIRST(o)),
		      S_potential_mod_type(type) ? (I32)OP_ENTERSUB : o->op_type);
	}
	break;

    case OP_AELEM:
    case OP_HELEM:
	ref(OpFIRST(o), o->op_type);
	if ((IS_SUB_TYPE(type)) &&
	     !(o->op_private & (OPpLVAL_INTRO | OPpDEREF)))
	    o->op_private |= OPpLVAL_DEFER;
	if (type == OP_LEAVESUBLV)
	    o->op_private |= OPpMAYBE_LVSUB;
	localize = 1;
	PL_modcount++;
	break;

    case OP_LEAVE:
    case OP_LEAVELOOP:
	o->op_private |= OPpLVALUE;
        /* FALLTHROUGH */
    case OP_SCOPE:
    case OP_ENTER:
    case OP_LINESEQ:
	localize = 0;
	if (OpKIDS(o))
	    op_lvalue(OpLAST(o), type);
	break;

    case OP_NULL:
	localize = 0;
	if (OpSPECIAL(o))		/* do BLOCK */
	    goto nomod;
	else if (!OpKIDS(o))
	    break;

	if (o->op_targ != OP_LIST) {
            OP *sib = OpSIBLING(OpFIRST(o));
            /* OP_TRANS and OP_TRANSR with argument have a weird optree
             * that looks like
             *
             *   null
             *      arg
             *      trans
             *
             * compared with things like OP_MATCH which have the argument
             * as a child:
             *
             *   match
             *      arg
             *
             * so handle specially to correctly get "Can't modify" croaks etc
             */

            if (sib && (IS_TYPE(sib, TRANS) || IS_TYPE(sib, TRANSR)))
            {
                /* this should trigger a "Can't modify transliteration" err */
                op_lvalue(sib, type);
            }
            op_lvalue(OpFIRST(o), type);
            break;
	}
	/* FALLTHROUGH */
    case OP_LIST:
	localize = 0;
	for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
	    /* elements might be in void context because the list is
	       in scalar context or because they are attribute sub calls */
	    if ( !OpWANT_VOID(kid) )
		op_lvalue(kid, type);
	break;

    case OP_COREARGS:
	return o;

    case OP_AND:
    case OP_OR:
	if (type == OP_LEAVESUBLV
            || !S_vivifies(OpFIRST(o)->op_type))
	    op_lvalue(OpFIRST(o), type);
	if (type == OP_LEAVESUBLV
	 || !S_vivifies(OpSIBLING(OpFIRST(o))->op_type))
	    op_lvalue(OpSIBLING(OpFIRST(o)), type);
	goto nomod;

    case OP_SREFGEN:
	if (type == OP_NULL) { /* local */
	  local_refgen:
	    if (!FEATURE_MYREF_IS_ENABLED)
		Perl_croak(aTHX_ "The experimental declared_refs "
				 "feature is not enabled");
	    Perl_ck_warner_d(aTHX_
		     packWARN(WARN_EXPERIMENTAL__DECLARED_REFS),
		    "Declaring references is experimental");
	    op_lvalue(OpFIRST(o), OP_NULL);
	    return o;
	}
	if (type != OP_AASSIGN && type != OP_SASSIGN
	 && type != OP_ENTERLOOP)
	    goto nomod;
	/* Don’t bother applying lvalue context to the ex-list.  */
	kid = OpFIRST(OpFIRST(o));
	assert (!OpHAS_SIBLING(kid));
	goto kid_2lvref;
    case OP_REFGEN:
	if (type == OP_NULL) /* local */
	    goto local_refgen;
	if (type != OP_AASSIGN) goto nomod;
	kid = OpFIRST(o);
      kid_2lvref:
	{
	    const U8 ec = PL_parser ? PL_parser->error_count : 0;
	    S_lvref(aTHX_ kid, type);
	    if (!PL_parser || PL_parser->error_count == ec) {
		if (!FEATURE_REFALIASING_IS_ENABLED)
		    Perl_croak(aTHX_
		       "Experimental aliasing via reference not enabled");
		Perl_ck_warner_d(aTHX_
				 packWARN(WARN_EXPERIMENTAL__REFALIASING),
				"Aliasing via reference is experimental");
	    }
	}
	if (IS_TYPE(o, REFGEN))
	    op_null(OpFIRST(OpFIRST(o))); /* pushmark */
	op_null(o);
	return o;

    case OP_SPLIT:
        if ((o->op_private & OPpSPLIT_ASSIGN)) {
	    /* This is actually @array = split.  */
	    PL_modcount = RETURN_UNLIMITED_NUMBER;
	    break;
	}
	goto nomod;

    case OP_SCALAR:
	op_lvalue(OpFIRST(o), OP_ENTERSUB);
	goto nomod;
    }

    /* [20011101.069 (#7861)] File test operators interpret OPf_REF to mean that
       their argument is a filehandle; thus \stat(".") should not set
       it. AMS 20011102 */
    if (type == OP_REFGEN &&
        PL_check[o->op_type] == Perl_ck_ftst)
        return o;

    if (type != OP_LEAVESUBLV)
        o->op_flags |= OPf_MOD;

    if (type == OP_AASSIGN || type == OP_SASSIGN)
	o->op_flags |= OPf_SPECIAL | (IS_SUB_OP(o) ? 0 : OPf_REF);
    else if (!type) { /* local() */
	switch (localize) {
	case 1:
	    o->op_private |= OPpLVAL_INTRO;
	    o->op_flags &= ~OPf_SPECIAL;
	    PL_hints |= HINT_BLOCK_SCOPE;
	    break;
	case 0:
	    break;
	case -1:
	    Perl_ck_warner(aTHX_ packWARN(WARN_SYNTAX),
			   "Useless localization of %s", OP_DESC(o));
	}
    }
    else if (type != OP_GREPSTART && type != OP_ENTERSUB && type != OP_ENTERXSSUB
             && type != OP_LEAVESUBLV && !IS_SUB_OP(o))
	o->op_flags |= OPf_REF;
    return o;
}

static bool
S_scalar_mod_type(const OP *o, I32 type)
{
    switch (type) {
    case OP_POS:
    case OP_SASSIGN:
	if (OP_TYPE_IS(o, OP_RV2GV))
	    return FALSE;
	/* FALLTHROUGH */
    case OP_PREINC:
    case OP_PREDEC:
    case OP_POSTINC:
    case OP_POSTDEC:
    case OP_I_PREINC:
    case OP_I_PREDEC:
    case OP_I_POSTINC:
    case OP_I_POSTDEC:
    case OP_POW:
    case OP_MULTIPLY:
    case OP_DIVIDE:
    case OP_MODULO:
    case OP_REPEAT:
    case OP_ADD:
    case OP_SUBTRACT:
    case OP_I_MULTIPLY:
    case OP_I_DIVIDE:
    case OP_I_MODULO:
    case OP_I_ADD:
    case OP_I_SUBTRACT:
    case OP_I_POW:
    case OP_LEFT_SHIFT:
    case OP_RIGHT_SHIFT:
    case OP_BIT_AND:
    case OP_BIT_XOR:
    case OP_BIT_OR:
    case OP_I_BIT_AND:
    case OP_I_BIT_XOR:
    case OP_I_BIT_OR:
    case OP_S_BIT_AND:
    case OP_S_BIT_XOR:
    case OP_S_BIT_OR:
    case OP_CONCAT:
    case OP_SUBST:
    case OP_TRANS:
    case OP_TRANSR:
    case OP_READ:
    case OP_SYSREAD:
    case OP_RECV:
    case OP_ANDASSIGN:
    case OP_ORASSIGN:
    case OP_DORASSIGN:
    case OP_VEC:
    case OP_SUBSTR:
	return TRUE;
    default:
	return FALSE;
    }
}

static bool
S_is_handle_constructor(const OP *o, I32 numargs)
{
    PERL_ARGS_ASSERT_IS_HANDLE_CONSTRUCTOR;

    switch (o->op_type) {
    case OP_PIPE_OP:
    case OP_SOCKPAIR:
	if (numargs == 2)
	    return TRUE;
	/* FALLTHROUGH */
    case OP_SYSOPEN:
    case OP_OPEN:
    case OP_SELECT:		/* XXX c.f. SelectSaver.pm */
    case OP_SOCKET:
    case OP_OPEN_DIR:
    case OP_ACCEPT:
	if (numargs == 1)
	    return TRUE;
	/* FALLTHROUGH */
    default:
	return FALSE;
    }
}

/*
=for apidoc refkids

Sets ref context for all kids.

=cut
*/
static OP *
S_refkids(pTHX_ OP *o, I32 type)
{
    if (o && OpKIDS(o)) {
        OP *kid;
        for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
	    ref(kid, type);
    }
    return o;
}

/*
=for apidoc ref

Sets ref context for the op, i.e. marks the op as modifying via OPf_MOD,
or OPf_REF for references.

=cut
*/
OP *
Perl_doref(pTHX_ OP *o, I32 type, bool set_op_ref)
{
    dVAR;
    OP *kid;

    PERL_ARGS_ASSERT_DOREF;

    if (PL_parser && PL_parser->error_count)
	return o;

    switch (o->op_type) {
    case OP_ENTERSUB:
    case OP_ENTERXSSUB:
	if ((type == OP_EXISTS || type == OP_DEFINED) && !OpSTACKED(o)) {
            OpTYPE_set(o, OP_RV2CV);             /* entersub => rv2cv */
	    assert(IS_NULL_OP(OpFIRST(o)));
	    op_null(OpFIRST(OpFIRST(o)));	/* disable pushmark */
	    o->op_flags |= OPf_SPECIAL;
	}
	else if (type == OP_RV2SV || type == OP_RV2AV || type == OP_RV2HV){
	    o->op_private |= (type == OP_RV2AV ? OPpDEREF_AV
			      : type == OP_RV2HV ? OPpDEREF_HV
			      : OPpDEREF_SV);
	    o->op_flags |= OPf_MOD;
	}

	break;

    case OP_COND_EXPR:
	for (kid = OpSIBLING(OpFIRST(o)); kid; kid = OpSIBLING(kid))
	    doref(kid, type, set_op_ref);
	break;
    case OP_RV2SV:
	if (type == OP_DEFINED)
	    o->op_flags |= OPf_SPECIAL;		/* don't create GV */
	doref(OpFIRST(o), o->op_type, set_op_ref);
	/* FALLTHROUGH */
    case OP_PADSV:
	if (type == OP_RV2SV || type == OP_RV2AV || type == OP_RV2HV) {
	    o->op_private |= (type == OP_RV2AV ? OPpDEREF_AV
			      : type == OP_RV2HV ? OPpDEREF_HV
			      : OPpDEREF_SV);
	    o->op_flags |= OPf_MOD;
	}
	break;

    case OP_RV2AV:
    case OP_RV2HV:
	if (set_op_ref)
	    o->op_flags |= OPf_REF;
	/* FALLTHROUGH */
    case OP_RV2GV:
	if (type == OP_DEFINED)
	    o->op_flags |= OPf_SPECIAL;		/* don't create GV */
	doref(OpFIRST(o), o->op_type, set_op_ref);
	break;

    case OP_PADAV:
    case OP_PADHV:
	if (set_op_ref)
	    o->op_flags |= OPf_REF;
	break;

    case OP_SCALAR:
    case OP_NULL:
	if (!OpKIDS(o) || type == OP_DEFINED)
	    break;
	doref(OpFIRST(o), type, set_op_ref);
	break;
    case OP_AELEM:
    case OP_HELEM:
	doref(OpFIRST(o), o->op_type, set_op_ref);
	if (type == OP_RV2SV || type == OP_RV2AV || type == OP_RV2HV) {
	    o->op_private |= (type == OP_RV2AV ? OPpDEREF_AV
			      : type == OP_RV2HV ? OPpDEREF_HV
			      : OPpDEREF_SV);
	    o->op_flags |= OPf_MOD;
	}
	break;

    case OP_SCOPE:
    case OP_LEAVE:
	set_op_ref = FALSE;
	/* FALLTHROUGH */
    case OP_ENTER:
    case OP_LIST:
	if (!OpKIDS(o))
	    break;
	doref(OpLAST(o), type, set_op_ref);
	break;
    default:
	break;
    }
    return scalar(o);

}

/*
=for apidoc dup_attrlist

Return a copy of an attribute list, i.e. a CONST or LIST with a
list of CONST values.

=cut
*/
static OP *
S_dup_attrlist(pTHX_ OP *o)
{
    OP *rop;

    PERL_ARGS_ASSERT_DUP_ATTRLIST;

    /* An attrlist is either a simple OP_CONST or an OP_LIST with kids,
     * where the first kid is OP_PUSHMARK and the remaining ones
     * are OP_CONST.  We need to push the OP_CONST values.
     */
    if (IS_CONST_OP(o))
	rop = newSVOP(OP_CONST, o->op_flags, SvREFCNT_inc_NN(cSVOPo->op_sv));
    else {
	assert((IS_TYPE(o, LIST)) && OpKIDS(o));
	rop = NULL;
	for (o = OpFIRST(o); o; o = OpSIBLING(o)) {
	    if (IS_CONST_OP(o))
		rop = op_append_elem(OP_LIST, rop,
				  newSVOP(OP_CONST, o->op_flags,
					  SvREFCNT_inc_NN(cSVOPo->op_sv)));
	}
    }
    return rop;
}

/*
=for apidoc attrs_has_const

Checks the attrs list if ":const" is in it.
But not C<("const", my $x)>.

Returns the number of found attribs with const, which is only relevant
for 1 for const being the single attr, 0 if no const was found, and >1
if there are also other attribs besides const.

If from_assign is TRUE, the attrs are already expanded to a full
ENTERSUB import call. If not it's a list, not attrs.
If from_assign is FALSE, it is from an unexpanded attrlist
C<our VAR :ATTR> declaration, without ENTERSUB.

  TRUE:  my $s :const = 1;  LIST-PUSHMARK-ENTERSUB
  TRUE:  my @a :const = 1;  LIST-PUSHMARK-PADAV-ENTERSUB
  TRUE:  our $s :const = 1; LIST-PUSHMARK-RV2SV(gv)-ENTERSUB
  FALSE: our $s :const = 1; CONST
  TRUE:  ("const",my $s) = 1; LIST-PUSHMARK-CONST

=cut
*/
int
Perl_attrs_has_const(pTHX_ OP *o, bool from_assign)
{
    if (!o)
        return 0;

    /* An attrlist is either a simple OP_CONST or an OP_LIST with kids,
     * where the first kid is OP_PUSHMARK and the remaining ones
     * are OP_CONST. Later also OP_GVSV, OP_PADSV.
     * Now we check the attrs after my_attrs, i.e. the list is the entersub
     * import call already. This would be fragile with a package called "const",
     * but this is forbidden.
     */
    if (IS_CONST_OP(o)) {
        if ( SvPOK(cSVOPx_sv(o)) &&
             strEQc(SvPVX_const(cSVOPx_sv(o)), "const") )
            return OpHAS_SIBLING(o) && IS_CONST_OP(OpSIBLING(o)) ? 2 : 1;
    } else {
        int num = 0;
        int found = 0;
	assert(IS_TYPE(o, LIST) && OpKIDS(o));
        o = OpFIRST(o);
        /* entersub is the either 1st or 2nd sibling */
        if (from_assign) {
            o = OpSIBLING(o);
            if (o && (IS_RV2ANY_OP(o) || IS_PADxV_OP(o))) /* our SCALAR :ATTR */
                o = OpSIBLING(o);
            if (!o)
                return 0;
            if (!IS_TYPE(o, ENTERSUB))
                return 0;
            else {
                o = OpFIRST(o);   /* pushmark */
                if (!OpHAS_SIBLING(o)) return 0; /* lval sub */
                o = OpSIBLING(o); /* "attributes" */
                if (!OpHAS_SIBLING(o)) return 0;
                o = OpSIBLING(o); /* package */
                if (!OpHAS_SIBLING(o)) return 0;
                o = OpSIBLING(o); /* scalarref */
                if (!OpHAS_SIBLING(o)) return 0;
                o = OpSIBLING(o); /* 1st REF arg */
            }
        }
	for (; o; o = OpSIBLING(o)) {
            const SV *sv = cSVOPx_sv(o);
	    if (IS_CONST_OP(o) && SvPOK(sv)) {
                num++;
                if (strEQc(SvPVX_const(sv), "const"))
                    found++;
            }
	}
        return found ? num : 0;
    }
    return 0;
}

/*
=for apidoc apply_attrs

Calls the attribute importer with the target and a list of attributes.
As manually done via C<use attributes $pkg, $rv, @attrs>.

=cut
*/
static void
S_apply_attrs(pTHX_ HV *stash, SV *target, OP *attrs)
{
    PERL_ARGS_ASSERT_APPLY_ATTRS;
    {
        SV * const stashsv = newSVhek(HvNAME_HEK(stash));

        /* fake up C<use attributes $pkg,$rv,@attrs> */

#define ATTRSMODULE "attributes"
#define ATTRSMODULE_PM "attributes.pm"

        Perl_load_module(
          aTHX_ PERL_LOADMOD_IMPORT_OPS,
          newSVpvs(ATTRSMODULE),
          NULL,
          op_prepend_elem(OP_LIST,
                          newSVOP(OP_CONST, 0, stashsv),
                          op_prepend_elem(OP_LIST,
                                          newSVOP(OP_CONST, 0,
                                                  newRV(target)),
                                          dup_attrlist(attrs))));
    }
}

/*
=for apidoc apply_attrs_my

Similar to L</apply_attrs> calls the attribute importer with the
target, which must be a lexical and a list of attributes.  As manually
done via C<use attributes $pkg, $rv, @attrs>.
This variant defers the import call to run-time.

Returns the list of attributes in the **imopsp argument.

=cut
*/
static void
S_apply_attrs_my(pTHX_ HV *stash, OP *target, OP *attrs, OP **imopsp)
{
    OP *pack, *imop, *arg;
    SV *meth, *stashsv, **svp;

    PERL_ARGS_ASSERT_APPLY_ATTRS_MY;

    if (!attrs)
	return;

    /* Ensure that attributes.pm is loaded. */
    /* Don't force the C<use> if we don't need it. */
    svp = hv_fetchs(GvHVn(PL_incgv), ATTRSMODULE_PM, FALSE);
    if (svp && *svp != UNDEF)
	NOOP;	/* already in %INC */
    else
	Perl_load_module(aTHX_ PERL_LOADMOD_NOIMPORT,
			       newSVpvs(ATTRSMODULE), NULL);

    /* Need package name for method call. */
    pack = newSVOP(OP_CONST, 0, newSVpvs(ATTRSMODULE));

    /* Build up the real arg-list. */
    stashsv = newSVhek(HvNAME_HEK(stash));

    if (IS_PADxV_OP(target)) {		  /* my LEX :ATTR */
        arg = newOP(OP_PADSV, 0);
        arg->op_targ = target->op_targ;
        arg = newUNOP(OP_REFGEN, 0, arg);
    } else if (IS_RV2ANY_OP(target) && /* our LEX :const */
               IS_TYPE(OpFIRST(target), GV) ) {
        arg = newSVREF(newGVOP(OP_GV,0,cGVOPx_gv(OpFIRST(target))));
        arg->op_targ = target->op_targ;
        if (ISNT_TYPE(target, RV2SV))
            OpTYPE_set(arg, target->op_type);
        arg = newUNOP(OP_REFGEN,0,arg);
    } else {
        /* This will be extended later for the ffi and its deferred sub attrs */
        arg = NULL;
	Perl_croak(aTHX_ "panic: invalid target %s in apply_attrs_my",
                   OP_NAME(target));
    }
    arg = op_prepend_elem(OP_LIST,
              newSVOP(OP_CONST, 0, stashsv),
                  op_prepend_elem(OP_LIST, arg,
                      dup_attrlist(attrs)));

    /* Fake up a method call to import */
    meth = newSVpvs_share("import");
    imop = op_convert_list(OP_ENTERSUB, OPf_STACKED|OPf_SPECIAL|OPf_WANT_VOID,
               op_append_elem(OP_LIST,
                   op_prepend_elem(OP_LIST, pack, arg),
                       newMETHOP_named(OP_METHOD_NAMED, 0, meth)));

    /* Combine the ops. */
    *imopsp = op_append_elem(OP_LIST, *imopsp, imop);
}

/*
=for apidoc apply_attrs_string

Attempts to apply a list of attributes specified by the C<attrstr> and
C<len> arguments to the subroutine identified by the C<cv> argument which
is expected to be associated with the package identified by the C<stashpv>
argument (see L<attributes>).  It gets this wrong, though, in that it
does not correctly identify the boundaries of the individual attribute
specifications within C<attrstr>.  This is not really intended for the
public API, but has to be listed here for systems such as AIX which
need an explicit export list for symbols.  (It's called from XS code
in support of the C<ATTRS:> keyword from F<xsubpp>.)  Patches to fix it
to respect attribute syntax properly would be welcome.

=cut
*/

void
Perl_apply_attrs_string(pTHX_ const char *stashpv, CV *cv,
                        const char *attrstr, STRLEN len)
{
    OP *attrs = NULL;

    PERL_ARGS_ASSERT_APPLY_ATTRS_STRING;

    if (!len) {
        len = strlen(attrstr);
    }

    while (len) {
        for (; isSPACE(*attrstr) && len; --len, ++attrstr) ;
        if (len) {
            const char * const sstr = attrstr;
            for (; !isSPACE(*attrstr) && len; --len, ++attrstr) ;
            attrs = op_append_elem(OP_LIST, attrs,
                                newSVOP(OP_CONST, 0,
                                        newSVpvn(sstr, attrstr-sstr)));
        }
    }

    Perl_load_module(aTHX_ PERL_LOADMOD_IMPORT_OPS,
		     newSVpvs(ATTRSMODULE),
                     NULL, op_prepend_elem(OP_LIST,
				  newSVOP(OP_CONST, 0, newSVpv(stashpv,0)),
				  op_prepend_elem(OP_LIST,
					       newSVOP(OP_CONST, 0,
						       newRV(MUTABLE_SV(cv))),
                                               attrs)));
}

/*
=for apidoc move_proto_attr
Move a run-time attribute to a compile-time prototype handling,
as with :prototype(...)
=cut
*/
static void
S_move_proto_attr(pTHX_ OP **proto, OP **attrs, const GV * name,
                        bool curstash)
{
    OP *new_proto = NULL;
    STRLEN pvlen;
    char *pv;
    OP *o;

    PERL_ARGS_ASSERT_MOVE_PROTO_ATTR;

    if (!*attrs)
        return;

    o = *attrs;
    if (IS_CONST_OP(o)) {
        pv = SvPV(cSVOPo_sv, pvlen);
        if (memBEGINs(pv, pvlen, "prototype(")) {
            SV * const tmpsv = newSVpvn_flags(pv + 10, pvlen - 11, SvUTF8(cSVOPo_sv));
            SV ** const tmpo = cSVOPx_svp(o);
            SvREFCNT_dec(cSVOPo_sv);
            *tmpo = tmpsv;
            new_proto = o;
            *attrs = NULL;
        }
    } else if (IS_TYPE(o, LIST)) {
        OP * lasto;
        assert(OpKIDS(o));
        lasto = OpFIRST(o);
        assert(IS_TYPE(lasto, PUSHMARK));
        for (o = OpSIBLING(lasto); o; o = OpSIBLING(o)) {
            if (IS_CONST_OP(o)) {
                pv = SvPV(cSVOPo_sv, pvlen);
                if (memBEGINs(pv, pvlen, "prototype(")) {
                    SV * const tmpsv = newSVpvn_flags(pv + 10, pvlen - 11, SvUTF8(cSVOPo_sv));
                    SV ** const tmpo = cSVOPx_svp(o);
                    SvREFCNT_dec(cSVOPo_sv);
                    *tmpo = tmpsv;
                    if (new_proto && ckWARN(WARN_MISC)) {
                        STRLEN new_len;
                        const char * newp = SvPV(cSVOPo_sv, new_len);
                        Perl_warner(aTHX_ packWARN(WARN_MISC),
                            "Attribute prototype(%" UTF8f ") discards earlier prototype attribute in same sub",
                            UTF8fARG(SvUTF8(cSVOPo_sv), new_len, newp));
                        op_free(new_proto);
                    }
                    else if (new_proto)
                        op_free(new_proto);
                    new_proto = o;
                    /* excise new_proto from the list */
                    op_sibling_splice(*attrs, lasto, 1, NULL);
                    o = lasto;
                    continue;
                }
            }
            lasto = o;
        }
        /* If the list is now just the PUSHMARK, scrap the whole thing; otherwise attributes.xs
           would get pulled in with no real need */
        if (!OpHAS_SIBLING(OpFIRST(*attrs))) {
            op_free(*attrs);
            *attrs = NULL;
        }
    }

    if (new_proto) {
        SV *svname;
        if (isGV(name)) {
            svname = sv_newmortal();
            gv_efullname3(svname, name, NULL);
        }
        else if (SvPOK(name) && *SvPVX((SV *)name) == '&')
            svname = newSVpvn_flags(SvPVX((SV *)name)+1, SvCUR(name)-1, SvUTF8(name)|SVs_TEMP);
        else
            svname = (SV *)name;
        if (ckWARN(WARN_ILLEGALPROTO)) {
            if (!validate_proto(svname, cSVOPx_sv(new_proto), TRUE, curstash, FALSE))
                return;
        }
        if (*proto && ckWARN(WARN_PROTOTYPE)) {
            STRLEN old_len, new_len;
            const char * oldp = SvPV(cSVOPx_sv(*proto), old_len);
            const char * newp = SvPV(cSVOPx_sv(new_proto), new_len);

            Perl_warner(aTHX_ packWARN(WARN_PROTOTYPE),
                "Prototype '%" UTF8f "' overridden by attribute 'prototype(%" UTF8f ")'"
                " in %" SVf,
                UTF8fARG(SvUTF8(cSVOPx_sv(*proto)), old_len, oldp),
                UTF8fARG(SvUTF8(cSVOPx_sv(new_proto)), new_len, newp),
                SVfARG(svname));
        }
        if (*proto)
            op_free(*proto);
        *proto = new_proto;
    }
}

/*
=for apidoc cant_declare
=cut
*/
static void
S_cant_declare(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CANT_DECLARE;
    if (IS_NULL_OP(o)
     && (o->op_flags & (OPf_SPECIAL|OPf_KIDS)) == OPf_KIDS)
        o = OpFIRST(o);
    yyerror(Perl_form(aTHX_ "Can't declare %s in \"%s\"",
                             IS_NULL_OP(o)
                               && OpSPECIAL(o)
                                 ? "do block"
                                 : OP_DESC(o),
                             PL_parser->in_my == KEY_our   ? "our"   :
                             PL_parser->in_my == KEY_state ? "state" :
                                                             "my"));
}

/*
=for apidoc newASSIGNOP_maybe_const

Checks the attrs of the left if it has const.
If so check dissect my_attrs() and check if there's another attr.
If so defer attribute->import to run-time.
If not just const the left side.

OpSPECIAL on the assign op denotes :const. Undo temp. READONLY-ness via
a private OPpASSIGN_CONSTINIT bit during assignment at run-time.

Do various compile-time assignments on const rhs values, to enable
constant folding.
my @a[] = (...) comes also here, setting the computed lhs AvSHAPED size.

Return the newASSIGNOP, or the folded assigned value.

=cut
*/
OP *
Perl_newASSIGNOP_maybe_const(pTHX_ OP *left, I32 optype, OP *right)
{
    int num;
    if (UNLIKELY( OP_TYPE_IS(left, OP_LIST) &&
                  ((num = attrs_has_const(left, TRUE)) != 0) ))
    {   /* my $x :const = $y; dissect my_attrs() */
        OP *attr = OpSIBLING(OpFIRST(left));
        OP *assign = NULL;
        /* defer :const after = */
        if (OP_TYPE_ISNT(attr, OP_ENTERSUB)) {
            left = attr;
            attr = OpSIBLING(attr);
            if (OpKIDS(left)) /* our: rv2Xv -> gv */
                OpMORESIB_set(OpFIRST(left), NULL);
        } else
            left = OpSIBLING(attr);
        OpMORESIB_set(left, NULL);
        OpMORESIB_set(attr, NULL);
        /* Should constant folding be deferred to ck_[sa]assign? */
        if (IS_PADxV_OP(left) && left->op_targ && left->op_private == OPpLVAL_INTRO) {
            if (IS_CONST_OP(right)) {
                SV* lsv = PAD_SV(left->op_targ);
                SV *rsv = cSVOPx_sv(right);
                if (SvTYPE(lsv) == SVt_NULL || SvTYPE(lsv) == SvTYPE(rsv)) {
                    DEBUG_k(Perl_deb(aTHX_ "my %s :const = %s\n",
                                     PAD_COMPNAME_PV(left->op_targ), SvPEEK(rsv)));
                    SvSetMagicSV(lsv, SvREFCNT_inc_NN(rsv));
                    left->op_private = 0; /* rm LVINTRO */
                    SvREADONLY_on(lsv);
                    op_free(right);
                    assign = ck_pad(left);
                } else if (SvTYPE(lsv) == SVt_PVAV) {
                    DEBUG_k(Perl_deb(aTHX_ "my %s[1] :const = (%s)\n",
                                     PAD_COMPNAME_PV(left->op_targ), SvPEEK(rsv)));
                    AvSHAPED_on((AV*)lsv); /* XXX we can even type it */
                    av_store((AV*)lsv,0,SvREFCNT_inc_NN(rsv));
                    SvREADONLY_on(lsv);
                    op_free(right);
                    assign = ck_pad(left);
                }
            }
            /* hashes not yet.
               they don't fold and are not checked, so we can defer to run-time init */
            else if (IS_TYPE(left, PADAV) &&
                     SvFLAGS(PAD_SV(left->op_targ)) == (SVpav_REAL|SVt_PVAV) &&
                     (IS_TYPE(right, LIST) ||
                      ( IS_TYPE(right, NULL) && OpKIDS(right) &&
                        IS_TYPE(OpFIRST(right), FLOP)))) {
                SSize_t i;
                AV* lsv = (AV*)PAD_SV(left->op_targ);
                /* check if all rhs elements are const */
                OP *o;
                if (IS_TYPE(right, LIST)) {
                    for (o = OpSIBLING(OpFIRST(right));
                         o && IS_CONST_OP(o);
                         o = OpSIBLING(o)) ;
                    if (!o) { /* is const */
                        DEBUG_k(Perl_deb(aTHX_ "my %s[1] :const = (...)\n",
                                         PAD_COMPNAME_PV(left->op_targ)));
                        for (i=0,o=OpSIBLING(OpFIRST(right)); o; o=OpSIBLING(o), i++) {
                            SV* rsv = cSVOPx_sv(o); /* XXX check for unique types */
                            av_store(lsv, i, SvREFCNT_inc_NN(rsv));
                        }
                        AvSHAPED_on(lsv); /* check if to set type */
                        SvREADONLY_on(lsv);
                        op_free(right);
                        assign = ck_pad(left);
                    }
                } else { /* range */
                    o = OpFIRST(OpFIRST(right));
                    if (OpKIDS(o) && IS_TYPE(OpFIRST(o), RANGE)) {
                        o = OpFIRST(o); /* range */
                        if (IS_CONST_OP(OpNEXT(o)) && IS_CONST_OP(OpOTHER(o))) {
                            SV* from = cSVOPx_sv(OpNEXT(o));
                            SV* to   = cSVOPx_sv(OpOTHER(o));
                            if (SvIOK(from) && SvIOK(to) && SvIVX(to) >= SvIVX(from)) {
                                SSize_t j = 0;
                                SSize_t fill = SvIVX(to) - SvIVX(from);
                                av_extend(lsv, fill);
                                DEBUG_k(Perl_deb(aTHX_
                                    "my %s[%d] :const = (%" IVdf "..%" IVdf ")\n",
                                    PAD_COMPNAME_PV(left->op_targ), (int)(fill+1),
                                    SvIVX(from), SvIVX(to)));
                                /* XXX native int types */
                                for (i=SvIVX(from); j <= fill; j++) {
                                    AvARRAY(lsv)[j] = newSViv(i++);
                                }
                                AvFILLp(lsv) = fill;
                                AvSHAPED_on(lsv);
                                SvREADONLY_on(lsv);
                                op_free(right);
                                assign = ck_pad(left);
                            }
                        }
                    }
                }
            }
        }
        /* our, but still mostly a NULL sv */
        else if (IS_TYPE(left, RV2SV) && IS_CONST_OP(right)) {
            GV* gv = cGVOPx_gv(OpFIRST(left));
            SV *rsv = cSVOPx_sv(right);
            SV *lsv = GvSV(gv);
            assert(IS_TYPE(OpFIRST(left), GV));
            if (SvTYPE(lsv) == SVt_NULL || SvTYPE(lsv) == SvTYPE(rsv)) {
                DEBUG_k(Perl_deb(aTHX_ "our $%s :const = %s\n",
                                 SvPEEK(lsv), SvPEEK(rsv)));
                SvSetMagicSV(lsv, SvREFCNT_inc_NN(rsv));
                SvREADONLY_on(lsv);
                assign = ck_rvconst(left);
            }
        } else if (IS_TYPE(left, RV2AV)) {
            GV* gv = cGVOPx_gv(OpFIRST(left));
            AV *lsv = GvAV(gv);
            /* check if all rhs elements are const */
            if (IS_CONST_OP(right)) {
                SV *rsv = cSVOPx_sv(right);
                DEBUG_k(Perl_deb(aTHX_ "our @%s[1] :const = %s\n",
                                 SvPEEK((SV*)lsv), SvPEEK(rsv)));
                AvSHAPED_on(lsv); /* we can even type it */
                av_store(lsv, 0, SvREFCNT_inc_NN(rsv));
                SvREADONLY_on(lsv);
                op_free(right);
                assign = ck_rvconst(left);
            } else if (IS_TYPE(right, LIST)) {
                SSize_t i;
                OP *o = OpSIBLING(OpFIRST(right));
                for (;o && IS_CONST_OP(o); o=OpSIBLING(o)) ;
                if (!o) {
                    DEBUG_k(Perl_deb(aTHX_ "our @%s[1] :const = (...)\n",
                                     SvPEEK((SV*)lsv)));
                    for (i=0,o=OpSIBLING(OpFIRST(right)); o; o=OpSIBLING(o), i++) {
                        SV* rsv = cSVOPx_sv(o); /* XXX check for unique types */
                        av_store(lsv, i, SvREFCNT_inc_NN(rsv));
                    }
                    AvSHAPED_on(lsv); /* we can even type it */
                    SvREADONLY_on(lsv);
                    op_free(right);
                    assign = ck_rvconst(left);
                }
            }
        }
        /* else not constant foldable. like a lhs ref, hash or list. */
        /* if :const is the only attr skip attributes->import */
        if (num > 1) {
            return op_append_list(OP_LINESEQ,
                       assign
                         ? assign
                         : newASSIGNOP(OPf_STACKED|OPf_SPECIAL,
                               left, optype, right),
                       scalar(attr));
        } else {
            op_free(attr);
            return assign
                     ? assign
                     : newASSIGNOP(OPf_STACKED|OPf_SPECIAL,
                           left, optype, right);
        }
    }
    /* no else as gcc-6 is not clever enough and emits a wrong warning */
    return newASSIGNOP(OPf_STACKED, left, optype, right);
}

/*
=for apidoc my_kid
=cut
*/
static OP *
S_my_kid(pTHX_ OP *o, OP *attrs, OP **imopsp)
{
    I32 type;
    const bool stately = PL_parser && PL_parser->in_my == KEY_state;

    PERL_ARGS_ASSERT_MY_KID;

    if (!o || (PL_parser && PL_parser->error_count))
	return o;

    type = o->op_type;

    if (OP_TYPE_IS_OR_WAS(o, OP_LIST)) {
        OP *kid;
        for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
	    my_kid(kid, attrs, imopsp);
	return o;
    } else if (type == OP_UNDEF || type == OP_STUB) {
	return o;
    } else if (type == OP_RV2SV ||	/* "our" declaration */
	       type == OP_RV2AV ||
	       type == OP_RV2HV) {
	if (ISNT_TYPE(OpFIRST(o), GV)) { /* MJD 20011224 */
	    S_cant_declare(aTHX_ o);
	} else if (attrs) {
	    GV * const gv = cGVOPx_gv(OpFIRST(o));
            HV *stash = GvSTASH(gv);
            if (!stash) stash = (HV*)SV_NO;
	    assert(PL_parser);
	    PL_parser->in_my = FALSE;
	    PL_parser->in_my_stash = NULL;
            /* We cannot get away without loading attributes.pm
               because our $a :const = $i still needs run-time init.
               It also simplifies newASSIGNOP_maybe_const().
            */
            if (attrs_has_const(attrs, FALSE))
                apply_attrs_my(stash, o, attrs, imopsp);
            else
                apply_attrs(stash,
			(type == OP_RV2SV ? GvSVn(gv) :
			 type == OP_RV2AV ? MUTABLE_SV(GvAVn(gv)) :
			 type == OP_RV2HV ? MUTABLE_SV(GvHVn(gv)) : MUTABLE_SV(gv)),
			attrs);
	}
	o->op_private |= OPpOUR_INTRO;
	return o;
    }
    else if (type == OP_REFGEN || type == OP_SREFGEN) {
	if (!FEATURE_MYREF_IS_ENABLED)
	    Perl_croak(aTHX_ "The experimental declared_refs "
			     "feature is not enabled");
	Perl_ck_warner_d(aTHX_
	     packWARN(WARN_EXPERIMENTAL__DECLARED_REFS),
	    "Declaring references is experimental");
	/* Kid is a nulled OP_LIST, handled above.  */
	my_kid(OpFIRST(o), attrs, imopsp);
	return o;
    }
    else if (type != OP_PADSV &&
	     type != OP_PADAV &&
	     type != OP_PADHV &&
	     type != OP_PUSHMARK)
    {
	S_cant_declare(aTHX_ o);
	return o;
    }
    else if (attrs && type != OP_PUSHMARK) {
	HV *stash;

        assert(PL_parser);
	PL_parser->in_my = FALSE;
	PL_parser->in_my_stash = NULL;

	/* check for C<my Dog $spot> when deciding package */
	stash = PAD_COMPNAME_TYPE(o->op_targ);
	if (!stash)
	    stash = PL_curstash;
        apply_attrs_my(stash, o, attrs, imopsp);
    }
    o->op_flags |= OPf_MOD;
    o->op_private |= OPpLVAL_INTRO;
    if (stately)
	o->op_private |= OPpPAD_STATE;
    return o;
}

/*
=for apidoc my_attrs

Prepend the lexical variable with the attribute->import call.

=cut
*/
OP *
Perl_my_attrs(pTHX_ OP *o, OP *attrs)
{
    OP *rops;
    int maybe_scalar = 0;

    PERL_ARGS_ASSERT_MY_ATTRS;

/* [perl #17376]: this appears to be premature, and results in code such as
   C< our(%x); > executing in list mode rather than void mode */
#if 0
    if (OpPARENS(o))
	list(o);
    else
	maybe_scalar = 1;
#else
    maybe_scalar = 1;
#endif
    if (attrs)
	SAVEFREEOP(attrs);
    rops = NULL;
    o = my_kid(o, attrs, &rops);
    if (rops) {
	if (maybe_scalar && IS_TYPE(o, PADSV)) {
	    o = scalar(op_append_list(OP_LIST, rops, o));
	    o->op_private |= OPpLVAL_INTRO;
	}
	else {
	    /* The listop in rops might have a pushmark at the beginning,
	       which will mess up list assignment. */
	    LISTOP * const lrops = (LISTOP *)rops; /* for brevity */
	    if (IS_TYPE(rops, LIST) &&
	        OpFIRST(lrops) && IS_TYPE(OpFIRST(lrops), PUSHMARK))
	    {
		OP * const pushmark = OpFIRST(lrops);
                /* excise pushmark */
                op_sibling_splice(rops, NULL, 1, NULL);
		op_free(pushmark);
	    }
	    o = op_append_list(OP_LIST, o, rops);
	}
    }
    PL_parser->in_my = FALSE;
    PL_parser->in_my_stash = NULL;
    return o;
}

/*
=for apidoc sawparens
=cut
*/
OP *
Perl_sawparens(pTHX_ OP *o)
{
    PERL_UNUSED_CONTEXT;
    if (o)
	o->op_flags |= OPf_PARENS;
    return o;
}

/*
=for apidoc bind_match
=cut
*/
OP *
Perl_bind_match(pTHX_ I32 type, OP *left, OP *right)
{
    OP *o;
    const OPCODE ltype = left->op_type;
    const OPCODE rtype = right->op_type;
    bool ismatchop = 0;

    PERL_ARGS_ASSERT_BIND_MATCH;

    if ( (ltype == OP_RV2AV || ltype == OP_RV2HV || ltype == OP_PADAV
	  || ltype == OP_PADHV) && ckWARN(WARN_MISC))
    {
      const char * const desc
	  = PL_op_desc[(
		          rtype == OP_SUBST || rtype == OP_TRANS
		       || rtype == OP_TRANSR
		       )
		       ? (int)rtype : OP_MATCH];
      const bool isary = ltype == OP_RV2AV || ltype == OP_PADAV;
      SV * const name = S_op_varname(aTHX_ left);
      if (name)
	Perl_warner(aTHX_ packWARN(WARN_MISC),
             "Applying %s to %" SVf " will act on scalar(%" SVf ")",
             desc, SVfARG(name), SVfARG(name));
      else {
	const char * const sample = (isary
	     ? "@array" : "%hash");
	Perl_warner(aTHX_ packWARN(WARN_MISC),
             "Applying %s to %s will act on scalar(%s)",
             desc, sample, sample);
      }
    }

    if (rtype == OP_CONST &&
	cSVOPx(right)->op_private & OPpCONST_BARE &&
	cSVOPx(right)->op_private & OPpCONST_STRICT)
    {
	no_bareword_allowed(right);
    }

    /* !~ doesn't make sense with /r, so error on it for now */
    if (rtype == OP_SUBST && (cPMOPx(right)->op_pmflags & PMf_NONDESTRUCT) &&
	type == OP_NOT)
	/* diag_listed_as: Using !~ with %s doesn't make sense */
	yyerror("Using !~ with s///r doesn't make sense");
    if (rtype == OP_TRANSR && type == OP_NOT)
	/* diag_listed_as: Using !~ with %s doesn't make sense */
	yyerror("Using !~ with tr///r doesn't make sense");

    ismatchop = (rtype == OP_MATCH ||
		 rtype == OP_SUBST ||
		 rtype == OP_TRANS || rtype == OP_TRANSR)
	     && !(right->op_flags & OPf_SPECIAL);
    if (ismatchop && right->op_private & OPpTARGET_MY) {
	right->op_targ = 0;
	right->op_private &= ~OPpTARGET_MY;
        DEBUG_kv(Perl_deb(aTHX_ "clear TARGET_MY on %s\n", OP_NAME(right)));
    }
    if (!OpSTACKED(right) && !right->op_targ && ismatchop) {
        if (IS_TYPE(left, PADSV) && !(left->op_private & OPpLVAL_INTRO)) {
            right->op_targ = left->op_targ;
            op_free(left);
            o = right;
        }
        else {
            right->op_flags |= OPf_STACKED;
            if (rtype != OP_MATCH && rtype != OP_TRANSR &&
            ! (rtype == OP_TRANS &&
               right->op_private & OPpTRANS_IDENTICAL) &&
	    ! (rtype == OP_SUBST &&
	       (cPMOPx(right)->op_pmflags & PMf_NONDESTRUCT)))
		left = op_lvalue(left, rtype);
	    if (OP_TYPE_IS_NN(right, OP_TRANS) || OP_TYPE_IS_NN(right, OP_TRANSR))
		o = newBINOP(OP_NULL, OPf_STACKED, scalar(left), right);
	    else
		o = op_prepend_elem(rtype, scalar(left), right);
	}
	if (type == OP_NOT)
	    return newUNOP(OP_NOT, 0, scalar(o));
	return o;
    }
    else
	return bind_match(type, left,
		pmruntime(newPMOP(OP_MATCH, 0), right, NULL, 0, 0));
}

/*
=for apidoc invert

Add a unary NOT op in front, inverting the op.

=cut
*/
OP *
Perl_invert(pTHX_ OP *o)
{
    if (!o)
	return NULL;
    return newUNOP(OP_NOT, OPf_SPECIAL, scalar(o));
}

/*
=for apidoc Amx|OP *	|op_scope	|OP *o

Wraps up an op tree with some additional ops so that at runtime a dynamic
scope will be created.  The original ops run in the new dynamic scope,
and then, provided that they exit normally, the scope will be unwound.
The additional ops used to create and unwind the dynamic scope will
normally be an C<enter>/C<leave> pair, but a C<scope> op may be used
instead if the ops are simple enough to not need the full dynamic scope
structure.

=cut
*/

OP *
Perl_op_scope(pTHX_ OP *o)
{
    dVAR;
    if (o) {
	if (OpPARENS(o) || PERLDB_NOOPT || TAINTING_get) {
	    o = op_prepend_elem(OP_LINESEQ, newOP(OP_ENTER, 0), o);
            OpTYPE_set(o, OP_LEAVE);
	}
	else if (IS_TYPE(o, LINESEQ)) {
	    OP *kid;
            OpTYPE_set(o, OP_SCOPE);
	    kid = OpFIRST(o);
	    if (IS_STATE_OP(kid)) {
		op_null(kid);

		/* The following deals with things like 'do {1 for 1}' */
		kid = OpSIBLING(kid);
		if (kid && IS_STATE_OP(kid))
		    op_null(kid);
	    }
	}
	else
	    o = newLISTOP(OP_SCOPE, 0, o, NULL);
    }
    return o;
}

/*
=for apidoc op_unscope

Nullify all state ops in the kids of a lineseq.

=cut
*/
OP *
Perl_op_unscope(pTHX_ OP *o)
{
    if (o && IS_TYPE(o, LINESEQ)) {
	OP *kid = OpFIRST(o);
	for(; kid; kid = OpSIBLING(kid))
	    if (IS_STATE_OP(kid))
		op_null(kid);
    }
    return o;
}

/*
=for apidoc Am|int	|block_start	|int full

Handles compile-time scope entry.
Arranges for hints to be restored on block
exit and also handles pad sequence numbers to make lexical variables scope
right.  Returns a savestack index for use with C<block_end>.

=cut
*/

int
Perl_block_start(pTHX_ int full)
{
    const int retval = PL_savestack_ix;

    PL_compiling.cop_seq = PL_cop_seqmax;
    COP_SEQMAX_INC;
    pad_block_start(full);
    SAVEHINTS();
    PL_hints &= ~HINT_BLOCK_SCOPE;
    SAVECOMPILEWARNINGS();
    PL_compiling.cop_warnings = DUP_WARNINGS(PL_compiling.cop_warnings);
    SAVEI32(PL_compiling.cop_seq);
    PL_compiling.cop_seq = 0;

    CALL_BLOCK_HOOKS(bhk_start, full);

    return retval;
}

/*
=for apidoc Am|OP *	|block_end	|I32 floor|OP *seq

Handles compile-time scope exit.

C<floor> is the savestack index returned by C<block_start>, and C<seq>
is the body of the block.

Returns the block, possibly modified.

=cut
*/

OP*
Perl_block_end(pTHX_ I32 floor, OP *seq)
{
    const int needblockscope = PL_hints & HINT_BLOCK_SCOPE;
    OP* retval = scalarseq(seq);
    OP *o;

    /* XXX Is the null PL_parser check necessary here? */
    assert(PL_parser); /* Let’s find out under debugging builds.  */
    if (PL_parser && PL_parser->parsed_sub) {
	o = newSTATEOP(0, NULL, NULL);
	op_null(o);
	retval = op_append_elem(OP_LINESEQ, retval, o);
    }

    CALL_BLOCK_HOOKS(bhk_pre_end, &retval);

    LEAVE_SCOPE(floor);
    if (needblockscope)
	PL_hints |= HINT_BLOCK_SCOPE; /* propagate out */
    o = pad_leavemy();

    if (o) {
	/* pad_leavemy has created a sequence of introcv ops for all my
	   subs declared in the block.  We have to replicate that list with
	   clonecv ops, to deal with this situation:

	       sub {
		   my sub s1;
		   my sub s2;
		   sub s1 { state sub foo { \&s2 } }
	       }->()

	   Originally, I was going to have introcv clone the CV and turn
	   off the stale flag.  Since &s1 is declared before &s2, the
	   introcv op for &s1 is executed (on sub entry) before the one for
	   &s2.  But the &foo sub inside &s1 (which is cloned when &s1 is
	   cloned, since it is a state sub) closes over &s2 and expects
	   to see it in its outer CV’s pad.  If the introcv op clones &s1,
	   then &s2 is still marked stale.  Since &s1 is not active, and
	   &foo closes over &s1’s implicit entry for &s2, we get a ‘Varia-
	   ble will not stay shared’ warning.  Because it is the same stub
	   that will be used when the introcv op for &s2 is executed, clos-
	   ing over it is safe.  Hence, we have to turn off the stale flag
	   on all lexical subs in the block before we clone any of them.
	   Hence, having introcv clone the sub cannot work.  So we create a
	   list of ops like this:

	       lineseq
		  |
		  +-- introcv
		  |
		  +-- introcv
		  |
		  +-- introcv
		  |
		  .
		  .
		  .
		  |
		  +-- clonecv
		  |
		  +-- clonecv
		  |
		  +-- clonecv
		  |
		  .
		  .
		  .
	 */
	OP *kid = OpKIDS(o) ? OpFIRST(o) : o;
	OP * const last = OpKIDS(o) ? OpLAST(o) : o;
	for (;; kid = OpSIBLING(kid)) {
	    OP *newkid = newOP(OP_CLONECV, 0);
	    newkid->op_targ = kid->op_targ;
	    o = op_append_elem(OP_LINESEQ, o, newkid);
	    if (kid == last) break;
	}
	retval = op_prepend_elem(OP_LINESEQ, o, retval);
    }

    CALL_BLOCK_HOOKS(bhk_post_end, &retval);

    return retval;
}

/*
=head1 Compile-time scope hooks

=for apidoc Aox|	|blockhook_register	|BHK* hk

Register a set of hooks to be called when the Perl lexical scope changes
at compile time.  See L<perlguts/"Compile-time scope hooks">.

=cut
*/

void
Perl_blockhook_register(pTHX_ BHK *hk)
{
    PERL_ARGS_ASSERT_BLOCKHOOK_REGISTER;

    Perl_av_create_and_push(aTHX_ &PL_blockhooks, newSViv(PTR2IV(hk)));
}

/*
=for apidoc newPROG
=cut
*/
void
Perl_newPROG(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_NEWPROG;

    if (PL_in_eval) {
	PERL_CONTEXT *cx;
	I32 i;
	if (PL_eval_root)
            return;
	PL_eval_root = newUNOP(OP_LEAVEEVAL,
			       ((PL_in_eval & EVAL_KEEPERR)
				? OPf_SPECIAL : 0), o);

	cx = CX_CUR();
	assert(CxTYPE(cx) == CXt_EVAL);

	if ((cx->blk_gimme & G_WANT) == G_VOID)
	    scalarvoid(PL_eval_root);
	else if ((cx->blk_gimme & G_WANT) == G_ARRAY)
	    list(PL_eval_root);
	else
	    scalar(PL_eval_root);

	PL_eval_start = op_linklist(PL_eval_root);
	OpNEXT(PL_eval_root) = NULL;
	i = PL_savestack_ix;
	SAVEFREEOP(o);
	ENTER;
        process_optree(NULL, PL_eval_root, PL_eval_start);
	LEAVE;
	PL_savestack_ix = i;
    }
    else {
	if (OP_TYPE_IS_NN(o, OP_LINESEQ) && OP_TYPE_IS(OpFIRST(o), OP_STUB))
        {
            /* This block is entered if nothing is compiled for the main
               program. This will be the case for an genuinely empty main
               program, or one which only has BEGIN blocks etc, so already
               run and freed.

               Historically (5.000) the guard above was !o. However, commit
               f8a08f7b8bd67b28 (Jun 2001), integrated to blead as
               c71fccf11fde0068, changed perly.y so that newPROG() is now
               called with the output of block_end(), which returns a new
               LINESEQ - STUB for the case of an empty optree. ByteLoader (and
               maybe other things) also take this path, because they set up
               PL_main_start and PL_main_root directly which should not be
               overwritten by this empty PL_compcv.

               If the parsing the main program aborts (due to parse errors,
               or due to BEGIN or similar calling exit), then newPROG()
               isn't even called, and hence this code path and its cleanups
               are skipped. This shouldn't make a make a difference:
               * a non-zero return from perl_parse is a failure, and
                 perl_destruct() should be called immediately.
               * however, if exit(0) is called during the parse, then
                 perl_parse() returns 0, and perl_run() is called. As
                 PL_main_start will be NULL, perl_run() will return
                 promptly, and the exit code will remain 0.
            */

	    PL_comppad_name = 0;
	    PL_compcv = 0;
	    S_op_destroy(aTHX_ o);
	    return;
	}
	PL_main_root = op_scope(sawparens(scalarvoid(o)));
	PL_curcop = &PL_compiling;
	PL_main_start = LINKLIST(PL_main_root);
	OpNEXT(PL_main_root) = NULL;
        process_optree(NULL, PL_main_root, PL_main_start);
	cv_forget_slab(PL_compcv);
	PL_compcv = 0;

	/* Register with debugger */
	if (PERLDB_INTER) {
	    CV * const cv = get_cvs("DB::postponed", 0);
	    if (cv) {
		dSP;
		PUSHMARK(SP);
		XPUSHs(MUTABLE_SV(CopFILEGV(&PL_compiling)));
		PUTBACK;
		call_sv(MUTABLE_SV(cv), G_DISCARD);
	    }
	}
    }
}

/*
=for apidoc localize

lex: 0 local
     1 my|our|state
     2 has
=cut
*/
OP *
Perl_localize(pTHX_ OP *o, I32 lex)
{
    PERL_ARGS_ASSERT_LOCALIZE;

    if (OpPARENS(o))
/* [perl #17376]: this appears to be premature, and results in code such as
   C< our(%x); > executing in list mode rather than void mode */
#if 0
	list(o);
#else
	NOOP;
#endif
    else {
	if ( PL_parser->bufptr > PL_parser->oldbufptr
	    && PL_parser->bufptr[-1] == ','
	    && ckWARN(WARN_PARENTHESIS))
	{
	    char *s = PL_parser->bufptr;
	    bool sigil = FALSE;

	    /* some heuristics to detect a potential error */
	    while (*s && (strchr(", \t\n", *s)))
		s++;

	    while (1) {
		if (*s && (strchr("@$%", *s) || (!lex && *s == '*'))
		       && *++s
		       && (isWORDCHAR(*s) || UTF8_IS_CONTINUED(*s))) {
		    s++;
		    sigil = TRUE;
		    while (*s && (isWORDCHAR(*s) || UTF8_IS_CONTINUED(*s)))
			s++;
		    while (*s && (strchr(", \t\n", *s)))
			s++;
		}
		else
		    break;
	    }
	    if (sigil && (*s == ';' || *s == '=')) {
		Perl_warner(aTHX_ packWARN(WARN_PARENTHESIS),
				"Parentheses missing around \"%s\" list",
				lex
				    ? (PL_parser->in_my == KEY_our
					? "our"
					: PL_parser->in_my == KEY_state
					    ? "state"
					    : "my")
				    : "local");
	    }
	}
    }
    if (lex)
	o = my(o);
    else
	o = op_lvalue(o, OP_NULL);		/* a bit kludgey */
    PL_parser->in_my = FALSE;
    PL_parser->in_my_stash = NULL;
    return o;
}

/*
=for apidoc hasterm

Adds the field name, padoffset and the field index to the current class.

=cut
*/
OP *
Perl_hasterm(pTHX_ OP *o)
{
    PADNAME *pn;
    char *key;
    I32 klen;
    PERL_ARGS_ASSERT_HASTERM;
    assert(PL_curstname);

    if (!PL_parser->in_class)
        return o;
    pn = PAD_COMPNAME(o->op_targ);
    key = PadnamePV(pn);
    klen = PadnameLEN(pn) - 1;
    if (UNLIKELY(PadnameUTF8(pn)))
        klen = -klen;
    field_pad_add(PL_curstash, key+1, klen, o->op_targ);
    OpPRIVATE(o) |= OPpPAD_STATE; /* keep it, protect from clearsv */
    return o;
}

/*
=for apidoc fields_size

Length of the L</HvFIELDS> buffer in L</HvAUX>.

=cut
*/
int
Perl_fields_size(char *fields)
{
    STRLEN len = 0;
    STRLEN l;
    if (!fields)
        return 0;
    else {
#ifdef FIELDS_DYNAMIC_PADSIZE
        const char padsize = *fields;
        fields++;
#else
        const char padsize = sizeof(PADOFFSET);
#endif
        for (; *fields; l=strlen(fields)+padsize+1, fields+=l, len+=l )
            ;
        return len + 1;
    }
}

/*
We want to use a dynamic padsize in the fields buffer.
*/
PADOFFSET
Perl_fields_padoffset(const char *fields, const int offset,
                      const char padsize)
{
    /* fight the optimizer, which insists to get the whole word.
       really, this cries for inline assembly. */
#if defined(FIELDS_DYNAMIC_PADSIZE)
    union {
        unsigned char p1;
        U16  p2;
        U32  p4;
# if PTRSIZE == 8 /* signed long */
        U64TYPE po;
# else
        PADOFFSET po;
# endif
    } pad;
    PERL_ARGS_ASSERT_FIELDS_PADOFFSET;
    if (LIKELY(padsize == 1)) {
        pad.p1 = (unsigned char)(fields[offset]);
        /*DEBUG_v(PerlIO_printf(Perl_debug_log, "po %s %d\n", fields, pad.p1));*/
        return (PADOFFSET)pad.p1;
    }
    else if (padsize == 2) {
        memcpy(&pad, &fields[offset], padsize);
        /*pad.p2 = (U16)(fields[offset]);*/
        return (PADOFFSET)pad.p2;
    }
    else
        pad.po = (PADOFFSET)fields[offset];
    /*DEBUG_v(PerlIO_printf(Perl_debug_log, "po %s %d %d => %lu '%d'\n", fields,
      offset, (int)padsize, pad.po, (int)(unsigned char)(fields[offset])));*/
    return (PADOFFSET)pad.po;
#else
    PADOFFSET pad;
    PERL_ARGS_ASSERT_FIELDS_PADOFFSET;
    memcpy(&pad, &fields[offset], padsize);
    /*DEBUG_v(PerlIO_printf(Perl_debug_log, "po %s %d %d => %lu\n", fields,
      offset, (int)padsize, pad));*/
    return pad;
#endif
}

/*
=for apidoc field_pad_add

Adds the fieldname (without the '$') with its compile-time padoffset to
the %klass.

If klen is negative, the hash key is UTF8.
Even if the klen argument is provided, the fieldname may not contain a
NULL character.

The old API is to add the pad to the @class::FIELDS array,
and the name with the index of the field to the %class::FIELDS hash.

The new API is via methods only, with a single buffer of name\0pad
entries, the search is be linear in a string buffer.  The typical
numbers are 1-3 - 20 fields per class.
The padsize will be dynamic eventually, currently sizeof(long).

The list of name/pad pairs always needs to end with a \0 char.

=cut
*/
void
Perl_field_pad_add(pTHX_ HV* klass, const char* key, I32 klen, PADOFFSET targ)
{
#ifdef OLD_FIELDS_GV
    SV* name = newSVpvn_flags(HvNAME(klass), HvNAMELEN(klass), HvNAMEUTF8(klass)|SVs_TEMP);
    GV *fields;
    const PADNAME *pn = PAD_COMPNAME(targ);
    PERL_ARGS_ASSERT_FIELD_PAD_ADD;

    sv_catpvs(name, "::FIELDS");
    fields = gv_fetchsv(name, GV_ADD, SVt_PVAV);

    av_push(GvAVn(fields), newSViv(targ));
    if (AvFILLp(GvAVn(fields)) >= MAX_NUMFIELDS)
        Perl_croak(aTHX_ "Too many fields");
    (void)hv_store(GvHVn(fields), key, klen, newSViv(AvFILLp(GvAVn(fields))), 0);

    if (SvPAD_TYPED(pn)) { /* see check_hash_fields_and_hekify() */
        HV *type = PadnameTYPE(pn);
        bool is_const = SvREADONLY(type);
        SvCUR_set(name, HvNAMELEN(klass)+2); /* with the :: */
        /* store in the type the GvHV to curstash */
        if (is_const) SvREADONLY_off(type);
        (void)hv_store(type, "FIELDS", 6,
                       SvREFCNT_inc_NN(gv_fetchsv(name, GV_ADD, SVt_PVHV)), 0);
        if (is_const) SvREADONLY_on(type);
    }
#else
    char *fields = HvFIELDS_get(klass);
    U32 len = abs(klen);
#ifdef FIELDS_DYNAMIC_PADSIZE
    const char padsize = targ < 250
        ? 1
        : targ < 65000
          ? 2
          : sizeof(PADOFFSET);
#else
    const char padsize = sizeof(PADOFFSET);
#endif
    if (!fields) {
        if (!SvOOK(klass)) {
            hv_iterinit(klass);
            SvOOK_on(klass);
        }
#ifdef FIELDS_DYNAMIC_PADSIZE
        fields = (char*)PerlMemShared_malloc(len+padsize+3);
        Copy(&padsize, fields, 1, char); /* one byte */
        fields++;
#else
        fields = (char*)PerlMemShared_malloc(len+padsize+2);
#endif
        Copy(key, fields, len+1, char);
        Copy(&targ, fields+len+1, padsize, char);
        fields[len+padsize+1] = '\0'; /* ending sentinel */
        /*DEBUG_v(PerlIO_printf(Perl_debug_log, "add %s %d %d => %lu\n", fields, len+1, (int)padsize, targ));*/
#ifdef FIELDS_DYNAMIC_PADSIZE
        HvFIELDS(klass) = fields-1;
#else
        HvFIELDS(klass) = fields;
#endif
    } else {
        int olen = 0, i, l, newlen;
#ifdef FIELDS_DYNAMIC_PADSIZE
        char *ofields = fields;
        if (padsize != *ofields) {
            /* realloc fields with new padsize %d <> old %d */
            char osize = *ofields;
            int num = numfields(klass);
            char *nfields;
            olen = fields_size(fields);
            newlen = olen + ((padsize-osize) * num) + len + padsize+1;
            DEBUG_k(Perl_deb(aTHX_ "realloc fields from padsize %d->%d: %d\n",
                             osize, padsize, newlen));
            nfields = (char*)PerlMemShared_malloc(newlen+1);
            Copy(&padsize, nfields, 1, char);
            fields++;
            ofields = nfields;
            nfields++;
            l = strlen(fields);
            for (i=0; *fields; i++) {
                PADOFFSET po = fields_padoffset(fields, l+1, osize);
                Copy(fields, nfields, l+1, char);
                Copy(&po, nfields+l+1, padsize, char);
                fields += l+osize+1;
                nfields += l+padsize+1;
                l = strlen(fields);
                if (i >= MAX_NUMFIELDS)
                    Perl_croak(aTHX_ "Too many fields");
            }
            Copy(key, nfields, len+1, char);
            Copy(&targ, nfields+len+1, padsize, char);
            ofields[newlen] = '\0'; /* ending sentinel */
            HvFIELDS(klass) = ofields;
            return;
        }
        fields++;
#else
        char *ofields = fields;
#endif
        /* olen and newlen excluding final \0 */
        for (i=0; *fields; l=strlen(fields)+padsize+1, fields += l, i++ )
            ;
        if (i >= MAX_NUMFIELDS)
            Perl_croak(aTHX_ "Too many fields");
        olen = fields - ofields;
        newlen = olen+len+padsize+1;
        ofields = (char*)PerlMemShared_realloc(ofields, newlen+1);
        if (ofields != HvFIELDS(klass)) {
            fields = ofields + olen;
        }
        Copy(key, fields, len+1, char);
        Copy(&targ, fields+len+1, padsize, char);
        /*DEBUG_v(PerlIO_printf(Perl_debug_log, "add %s %d %d => %lu\n", fields, len+1, (int)padsize, targ));*/
        ofields[newlen] = '\0'; /* ending sentinel */
        HvFIELDS(klass) = ofields;
    }
#endif
}

/*
=for apidoc field_search

Searches for the fieldname without the '$' in C<%class::>

If klen is negative, the hash key is UTF8.

Returns C<-1> if not found.
Returns the field index in the object/class fields list
and with C<*po> set, sets there the padoffset into comppad.
=cut
*/
int
Perl_field_search(pTHX_ const HV* klass, const char* key, I32 klen, PADOFFSET* pop)
{
#ifdef OLD_FIELDS_GV
    SV* gv;
    GV* fields;
    SV** svp;
    PERL_ARGS_ASSERT_FIELD_SEARCH;
    if (!HvNAME(klass)) return NOT_IN_PAD;
    gv = newSVpvn_flags(HvNAME(klass), HvNAMELEN(klass), HvNAMEUTF8(klass)|SVs_TEMP);
    sv_catpvs(gv, "::FIELDS");
    fields = gv_fetchsv(gv, 0, SVt_PVHV);
    if (!fields) return NOT_IN_PAD;
    svp = hv_fetch(GvHV(fields), key, klen, FALSE);

    if (svp && SvIOK(*svp)) {
        IV ix = SvIVX(*svp);
        if (pop) {
            SV *po = AvARRAY(GvAV(fields))[ix];
            if (po && SvIOK(po))
                *pop = (PADOFFSET)SvIVX(po);
        }
        return (int)ix;
    }
    else
        return NOT_IN_PAD;
#else
    PERL_ARGS_ASSERT_FIELD_SEARCH;
    PERL_UNUSED_ARG(klen);
    if (!HvNAME(klass)) return NOT_IN_PAD;
    {
        char *fields = HvFIELDS_get(klass);
        if (!fields)
            return NOT_IN_PAD;
        else {
#ifdef FIELDS_DYNAMIC_PADSIZE
            const char padsize = *fields;
#else
            const char padsize = sizeof(PADOFFSET);
#endif
            int i, l;
#ifdef FIELDS_DYNAMIC_PADSIZE
            fields++;
#endif
            l = strlen(fields);
            for (i=0; *fields && strNE(fields, key);
                  l = strlen(fields), fields += l+padsize+1, i++ )
                ;
            if (*fields) { /* found */
                if (pop)
                    *pop = fields_padoffset(fields, l+1, padsize);
                return i;
            } else
                return -1;
        }
    }
#endif
}

/*
=for apidoc field_pad
Returns the pad offset in C<comppad_name> for the field in the klass,
or C<NOT_IN_PAD> if not found.

If klen is negative, the key is UTF8.
=cut
*/
PADOFFSET
Perl_field_pad(pTHX_ const HV* klass, const char* key, I32 klen)
{
    PADOFFSET po;
    PERL_ARGS_ASSERT_FIELD_PAD;
    if (field_search(klass, key, klen, &po) >= 0)
        return po;
    else
        return NOT_IN_PAD;
}

/*
=for apidoc numfields

Number of fields in the klass.
=cut
*/
U16
Perl_numfields(pTHX_ const HV* klass)
{
#ifdef OLD_FIELDS_GV
    SV* name;
    GV* fields;
#endif
    PERL_ARGS_ASSERT_NUMFIELDS;
    if (!HvNAME(klass)) return 0;
#ifdef OLD_FIELDS_GV
    name = newSVpvn_flags(HvNAME(klass), HvNAMELEN(klass), HvNAMEUTF8(klass)|SVs_TEMP);
    sv_catpvs(name, "::FIELDS");
    fields = gv_fetchsv(name, 0, SVt_PVAV);
    if (!fields) return 0;
    return 1+AvFILLp(GvAV(fields));
#else
    {
        char *fields = HvFIELDS_get(klass);
        if (!fields)
            return 0;
        else {
#ifdef FIELDS_DYNAMIC_PADSIZE
            const char padsize = *fields;
#else
            const char padsize = sizeof(PADOFFSET);
#endif
            int i, l;
#ifdef FIELDS_DYNAMIC_PADSIZE
            fields++;
#endif
            for (i=0; *fields; l=strlen(fields), fields += l+padsize+1, i++ )
                ;
            return (U16)i;
        }
    }
#endif
}

/*
=for apidoc field_index

Return i'th field padoffset or C<NOT_IN_PAD>.
=cut
*/
PADOFFSET
Perl_field_index(pTHX_ const HV* klass, U16 i)
{
#ifdef OLD_FIELDS_GV
    SV* name;
    GV* fields;
    SV* po;
#endif
    PERL_ARGS_ASSERT_FIELD_INDEX;
    if (!HvNAME(klass)) return NOT_IN_PAD;
#ifdef OLD_FIELDS_GV
    /*name = newSVhek(HvNAME_HEK_NN(klass));*/
    name = newSVpvn_flags(HvNAME(klass), HvNAMELEN(klass), HvNAMEUTF8(klass)|SVs_TEMP);
    sv_catpvs(name, "::FIELDS");
    fields = gv_fetchsv(name, 0, SVt_PVAV);
    if (!fields || !GvAV(fields)) return NOT_IN_PAD;
    if (i > AvFILLp(GvAV(fields)))
        Perl_croak(aTHX_ "Invalid field index %d of %s %s", i, HvPKGTYPE_NN(klass),
                   HvNAME(klass));
    po = AvARRAY(GvAV(fields))[i];
    return po && SvIOK(po)
        ? (PADOFFSET)SvIVX(po)
        : NOT_IN_PAD;
#else
    {
        char *fields = HvFIELDS_get(klass);
        if (!fields)
            return NOT_IN_PAD;
        else {
            int j, l;
#ifdef FIELDS_DYNAMIC_PADSIZE
            const char padsize = *fields;
            fields++;
#else
            const char padsize = sizeof(PADOFFSET);
#endif
            l = strlen(fields);
            for (j=0; *fields && j < i; l=strlen(fields), fields += l+padsize+1, j++ )
                ;
            if (i == j)
                return fields_padoffset(fields, l+1, padsize);
            else
                return NOT_IN_PAD;
        }
    }
#endif
}

/*
=for apidoc jmaybe

Join list by C<$;>, \034.
Adds C<$;>, the $SUBSCRIPT_SEPARATOR before the op list, if there is a list.

If you refer to a hash element as
C<$foo{$x,$y,$z}> it really means
C<$foo{join($;, $x, $y, $z)}>

=cut
*/
OP *
Perl_jmaybe(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_JMAYBE;

    if (IS_TYPE(o, LIST)) {
	OP * const o2 = newSVREF(newGVOP(OP_GV, 0,
                            gv_fetchpvs(";", GV_ADD|GV_NOTQUAL, SVt_PV)));
	o = op_convert_list(OP_JOIN, 0, op_prepend_elem(OP_LIST, o2, o));
    }
    return o;
}

/*
=for apidoc op_std_init

Fixup all temp. pads: apply scalar context, and allocate missing targs.

=cut
*/
PERL_STATIC_INLINE OP *
S_op_std_init(pTHX_ OP *o)
{
    I32 type = o->op_type;

    PERL_ARGS_ASSERT_OP_STD_INIT;

    if (PL_opargs[type] & OA_RETSCALAR)
	scalar(o);
    if (PL_opargs[type] & OA_TARGET && !o->op_targ)
	o->op_targ = pad_alloc(type, SVs_PADTMP);

    return o;
}

/*
=for apidoc op_integerize

Change the optype to the integer variant, when use integer is in scope.

=cut
*/
PERL_STATIC_INLINE OP *
S_op_integerize(pTHX_ OP *o)
{
    I32 type = o->op_type;
    PERL_ARGS_ASSERT_OP_INTEGERIZE;

    if ((PL_opargs[type] & OA_OTHERINT) && (PL_hints & HINT_INTEGER))
    {
	dVAR;
	o->op_ppaddr = PL_ppaddr[++(o->op_type)];
    }
    return o;
}

/*
=for apidoc fold_constants

Apply constant folding to a scalar at compile-time, via a fake eval.
Returns a new op_folded op which replaces the old constant expression,
or the old unfolded op.

=cut
*/
static OP *
S_fold_constants(pTHX_ OP *const o)
{
    dVAR;
    OP * volatile curop;
    SV * volatile sv = NULL;
    COP not_compiling;
    OP *newop;
    OP *old_next;
    SV * const oldwarnhook = PL_warnhook;
    SV * const olddiehook  = PL_diehook;
    int ret = 0;
    volatile I32 type = o->op_type;
    I32 old_cxix;
    U8 oldwarn = PL_dowarn;
    bool is_stringify;
    dJMPENV;

    PERL_ARGS_ASSERT_FOLD_CONSTANTS;

    if (!(PL_opargs[type] & OA_FOLDCONST)) /* 82 ops */
      goto nope;

    DEBUG_kv(Perl_deb(aTHX_ "fold_constant(%s)?\n", OP_NAME(o)));
    switch (type) {
    case OP_UCFIRST:
    case OP_LCFIRST:
    case OP_UC:
    case OP_LC:
    case OP_FC:
#ifdef USE_LOCALE_CTYPE
	if (IN_LC_COMPILETIME(LC_CTYPE))
	    goto nope;
#endif
        break;
    case OP_S_LT:
    case OP_S_GT:
    case OP_S_LE:
    case OP_S_GE:
    case OP_S_CMP:
#ifdef USE_LOCALE_COLLATE
	if (IN_LC_COMPILETIME(LC_COLLATE))
	    goto nope;
#endif
        break;
    case OP_SPRINTF:
	/* XXX what about the numeric ops? */
#ifdef USE_LOCALE_NUMERIC
	if (IN_LC_COMPILETIME(LC_NUMERIC))
	    goto nope;
#endif
	break;
    case OP_UNPACK:
        if (OpWANT_LIST(o)) /* cannot represent a list as const SV */
            goto nope;
        /* fall through */
    case OP_PACK:
	if (!OpHAS_SIBLING(OpFIRST(o))
            || ISNT_TYPE(OpSIBLING(OpFIRST(o)), CONST))
	    goto nope;
	{
	    SV * const templ = cSVOPx_sv(OpSIBLING(OpFIRST(o)));
            const char *s = SvPVX_const(templ);
	    if (!SvPOK(templ) || SvGMAGICAL(templ))
                goto nope;
            /* unpack returning a list */
            if (type == OP_UNPACK && SvCUR(templ) > 1)
                goto nope;
            while (s < SvEND(templ)) {
                if (isALPHA_FOLD_EQ(*s, 'p'))
                    goto nope;
                s++;
	    }
	}
	break;
    case OP_REPEAT:
	if (o->op_private & OPpREPEAT_DOLIST) goto nope;
	break;
    case OP_SREFGEN:
	if (ISNT_TYPE(OpFIRST(OpFIRST(o)), CONST)
	 || SvPADTMP(cSVOPx_sv(OpFIRST(OpFIRST(o)))))
	    goto nope;
    }

    if (PL_parser && PL_parser->error_count)
	goto nope;		/* Don't try to run w/ errors */

    for (curop = LINKLIST(o); curop != o; curop = LINKLIST(curop)) {
        switch (curop->op_type) {
        case OP_CONST:
            if (   (curop->op_private & OPpCONST_BARE)
                && (curop->op_private & OPpCONST_STRICT)) {
                no_bareword_allowed(curop);
                goto nope;
            }
            /* FALLTHROUGH */
        case OP_LIST:
        case OP_SCALAR:
        case OP_NULL:
        case OP_PUSHMARK: /* Foldable; move to next op in list */
            break;

        default:
            /* No other op types are considered foldable */
	    goto nope;
	}
    }

    /*DEBUG_k(Perl_deb(aTHX_ "fold_constant(%s)", OP_NAME(o)));*/
    curop = LINKLIST(o);
    old_next = OpNEXT(o);
    OpNEXT(o) = 0;
    PL_op = curop;

    old_cxix = cxstack_ix;
    create_eval_scope(NULL, G_FAKINGEVAL);

    /* Verify that we don't need to save it:  */
    assert(PL_curcop == &PL_compiling);
    StructCopy(&PL_compiling, &not_compiling, COP);
    PL_curcop = &not_compiling;
    /* The above ensures that we run with all the correct hints of the
       currently compiling COP, but that IN_PERL_RUNTIME is true. */
    assert(IN_PERL_RUNTIME);
    PL_warnhook = PERL_WARNHOOK_FATAL;
    PL_diehook  = NULL;
    JMPENV_PUSH(ret);

    /* Effective $^W=1.  */
    if ( ! (PL_dowarn & G_WARN_ALL_MASK))
	PL_dowarn |= G_WARN_ON;

    switch (ret) {
    case 0:
	CALLRUNOPS(aTHX);
	sv = *(PL_stack_sp--);
	if (o->op_targ && sv == PAD_SV(o->op_targ)) {	/* grab pad temp? */
	    pad_swipe(o->op_targ,  FALSE);
	}
	else if (SvTEMP(sv)) {			/* grab mortal temp? */
	    SvREFCNT_inc_simple_void(sv);
	    SvTEMP_off(sv);
	}
	else { assert(SvIMMORTAL(sv)); }
	break;
    case 3:
	/* Something tried to die.  Abandon constant folding.  */
	/* Pretend the error never happened.  */
	CLEAR_ERRSV();
	OpNEXT(o) = old_next;
	break;
    default:
	JMPENV_POP;
	/* Don't expect 1 (setjmp failed) or 2 (something called my_exit)  */
	PL_warnhook = oldwarnhook;
	PL_diehook  = olddiehook;
	/* XXX note that this croak may fail as we've already blown away
	 * the stack - eg any nested evals */
	Perl_croak(aTHX_ "panic: fold_constants JMPENV_PUSH returned %d", ret);
    }
    JMPENV_POP;
    PL_dowarn   = oldwarn;
    PL_warnhook = oldwarnhook;
    PL_diehook  = olddiehook;
    PL_curcop = &PL_compiling;

    /* if we croaked, depending on how we croaked the eval scope
     * may or may not have already been popped */
    if (cxstack_ix > old_cxix) {
        assert(cxstack_ix == old_cxix + 1);
        assert(CxTYPE(CX_CUR()) == CXt_EVAL);
        delete_eval_scope();
    }
    if (ret)
	goto nope;

    /* OP_STRINGIFY and constant folding are used to implement qq.
       Here the constant folding is an implementation detail that we
       want to hide.  If the stringify op is itself already marked
       folded, however, then it is actually a folded join.  */
    is_stringify = type == OP_STRINGIFY && !o->op_folded;
    DEBUG_k(Perl_deb(aTHX_ "fold_constant(%s) => const\n", OP_NAME(o)));
    op_free(o);
    assert(sv);
    if (is_stringify)
	SvPADTMP_off(sv);
    else if (!SvIMMORTAL(sv)) {
	SvPADTMP_on(sv);
	SvREADONLY_on(sv);
    }
    newop = newSVOP(OP_CONST, 0, MUTABLE_SV(sv));
    DEBUG_kv(debop(newop));
    if (!is_stringify) newop->op_folded = 1;
    return newop;

 nope:
    return o;
}

/*
=for apidoc gen_constant_list

Compile-time expansion of a range list.

  e.g. 0..4 => 0,1,2,3,4

=cut
*/
static OP *
S_gen_constant_list(pTHX_ OP *o)
{
    dVAR;
    OP *curop, *old_next;
    SV * const oldwarnhook = PL_warnhook;
    SV * const olddiehook  = PL_diehook;
    COP *old_curcop;
    U8 oldwarn = PL_dowarn;
    SV **svp;
    AV *av;
    I32 old_cxix;
    COP not_compiling;
    int ret = 0;
    dJMPENV;
    bool op_was_null;

    list(o);
    if (PL_parser && PL_parser->error_count)
	return o;		/* Don't attempt to run with errors */

    curop = LINKLIST(o);
    old_next = OpNEXT(o);
    OpNEXT(o) = 0;
    op_was_null = o->op_type == OP_NULL;
    if (op_was_null) /* b3698342565fb462291fba4b432cfcd05b6eb4e1 */
	o->op_type = OP_CUSTOM;
    CALL_PEEP(curop);
    if (op_was_null)
	o->op_type = OP_NULL;
    S_prune_chain_head(&curop);
    PL_op = curop;

    old_cxix = cxstack_ix;
    create_eval_scope(NULL, G_FAKINGEVAL);

    old_curcop = PL_curcop;
    StructCopy(old_curcop, &not_compiling, COP);
    PL_curcop = &not_compiling;
    /* The above ensures that we run with all the correct hints of the
       current COP, but that IN_PERL_RUNTIME is true. */
    assert(IN_PERL_RUNTIME);
    PL_warnhook = PERL_WARNHOOK_FATAL;
    PL_diehook  = NULL;
    JMPENV_PUSH(ret);

    /* Effective $^W=1.  */
    if ( ! (PL_dowarn & G_WARN_ALL_MASK))
	PL_dowarn |= G_WARN_ON;

    switch (ret) {
    case 0:
#if defined DEBUGGING && !defined DEBUGGING_RE_ONLY
        PL_curstackinfo->si_stack_hwm = 0; /* stop valgrind complaining */
#endif
	Perl_pp_pushmark(aTHX);
	CALLRUNOPS(aTHX);
	PL_op = curop;
        assert(!OpSPECIAL(curop));
        assert(IS_TYPE(curop, RANGE));
	Perl_pp_anonlist(aTHX);
	break;
    case 3:
	CLEAR_ERRSV();
	OpNEXT(o) = old_next;
	break;
    default:
	JMPENV_POP;
	PL_warnhook = oldwarnhook;
	PL_diehook = olddiehook;
	Perl_croak(aTHX_ "panic: gen_constant_list JMPENV_PUSH returned %d",
	    ret);
    }

    JMPENV_POP;
    PL_dowarn = oldwarn;
    PL_warnhook = oldwarnhook;
    PL_diehook = olddiehook;
    PL_curcop = old_curcop;

    if (cxstack_ix > old_cxix) {
        assert(cxstack_ix == old_cxix + 1);
        assert(CxTYPE(CX_CUR()) == CXt_EVAL);
        delete_eval_scope();
    }
    if (ret)
	return o;

    OpTYPE_set(o, OP_RV2AV);
    o->op_flags &= ~OPf_REF;	/* treat \(1..2) like an ordinary list */
    o->op_flags |= OPf_PARENS;	/* and flatten \(1..2,3) */
    o->op_opt = 0;		/* needs to be revisited in rpeep() */
    av = (AV *)SvREFCNT_inc_NN(*PL_stack_sp--);

    /* replace subtree with an OP_CONST */
    curop = OpFIRST(o);
    op_sibling_splice(o, NULL, -1, newSVOP(OP_CONST, 0, (SV *)av));
    op_free(curop);

    if (AvFILLp(av) != -1) {
	for (svp = AvARRAY(av) + AvFILLp(av); svp >= AvARRAY(av); --svp) {
	    SvPADTMP_on(*svp);
	    SvREADONLY_on(*svp);
	}
    }
    LINKLIST(o);
    return list(o);
}

/*
=head1 Optree Manipulation Functions
*/

/* List constructors */

/*
=for apidoc Am|OP *	|op_append_elem	  |I32 optype|OP *first|OP *last

Append an item to the list of ops contained directly within a list-type
op, returning the lengthened list.  C<first> is the list-type op,
and C<last> is the op to append to the list.  C<optype> specifies the
intended opcode for the list.  If C<first> is not already a list of the
right type, it will be upgraded into one.  If either C<first> or C<last>
is null, the other is returned unchanged.

=cut
*/

OP *
Perl_op_append_elem(pTHX_ I32 type, OP *first, OP *last)
{
    if (!first)
	return last;

    if (!last)
	return first;

    if (first->op_type != (unsigned)type
	|| (type == OP_LIST && (first->op_flags & OPf_PARENS)))
    {
	return newLISTOP(type, 0, first, last);
    }

    op_sibling_splice(first, OpLAST(first), 0, last);
    first->op_flags |= OPf_KIDS;
    return first;
}

/*
=for apidoc Am|OP *	|op_append_list	  |I32 optype|OP *first|OP *last

Concatenate the lists of ops contained directly within two list-type ops,
returning the combined list.  C<first> and C<last> are the list-type ops
to concatenate.  C<optype> specifies the intended opcode for the list.
If either C<first> or C<last> is not already a list of the right type,
it will be upgraded into one.  If either C<first> or C<last> is null,
the other is returned unchanged.

=cut
*/

OP *
Perl_op_append_list(pTHX_ I32 type, OP *first, OP *last)
{
    if (!first)
	return last;

    if (!last)
	return first;

    if (first->op_type != (unsigned)type)
	return op_prepend_elem(type, first, last);

    if (last->op_type != (unsigned)type)
	return op_append_elem(type, first, last);

    OpMORESIB_set(OpLAST(first), OpFIRST(last));
    OpLAST(first) = OpLAST(last);
    OpLASTSIB_set(OpLAST(first), first);
    first->op_flags |= OpKIDS(last);

    S_op_destroy(aTHX_ last);

    return first;
}

/*
=for apidoc Am|OP *	|op_prepend_elem	|I32 optype|OP *first|OP *last

Prepend an item to the list of ops contained directly within a list-type
op, returning the lengthened list.  C<first> is the op to prepend to the
list, and C<last> is the list-type op.  C<optype> specifies the intended
opcode for the list.  If C<last> is not already a list of the right type,
it will be upgraded into one.  If either C<first> or C<last> is null,
the other is returned unchanged.

=cut
*/

OP *
Perl_op_prepend_elem(pTHX_ I32 type, OP *first, OP *last)
{
    if (!first)
	return last;

    if (!last)
	return first;

    if (last->op_type == (unsigned)type) {
	if (type == OP_LIST) {	/* already a PUSHMARK there */
            /* insert 'first' after pushmark */
            op_sibling_splice(last, OpFIRST(last), 0, first);
            if (!OpPARENS(first))
                last->op_flags &= ~OPf_PARENS;
	}
	else
            op_sibling_splice(last, NULL, 0, first);
	last->op_flags |= OPf_KIDS;
	return last;
    }

    return newLISTOP(type, 0, first, last);
}

/*
=for apidoc Am|OP *	|op_convert_list	|I32 type|I32 flags|OP *o

Converts C<o> into a list op if it is not one already, and then converts it
into the specified C<type>, calling its check function, allocating a target if
it needs one, and folding constants.

A list-type op is usually constructed one kid at a time via C<newLISTOP>,
C<op_prepend_elem> and C<op_append_elem>.  Then finally it is passed to
C<op_convert_list> to make it the right type.

=cut
*/

OP *
Perl_op_convert_list(pTHX_ I32 type, I32 flags, OP *o)
{
    dVAR;
    if (type < 0) type = -type, flags |= OPf_SPECIAL;
    if (!o || ISNT_TYPE(o, LIST))
        o = force_list(o, 0);
    else
    {
	o->op_flags &= ~OPf_WANT;
	o->op_private &= ~OPpLVAL_INTRO;
    }

    if (!(PL_opargs[type] & OA_MARK))
	op_null(OpFIRST(o));
    else {
	OP * const kid2 = OpSIBLING(OpFIRST(o));
	if (kid2 && IS_TYPE(kid2, COREARGS)) {
	    op_null(OpFIRST(o));
	    kid2->op_private |= OPpCOREARGS_PUSHMARK;
	}
    }

    if (type != OP_SPLIT)
        /* At this point o is a LISTOP, but OP_SPLIT is a PMOP; let
         * ck_split() create a real PMOP and leave the op's type as listop
         * for now. Otherwise op_free() etc will crash.
         */
        OpTYPE_set(o, type);

    o->op_flags |= flags;
    if (flags & OPf_FOLDED)
	o->op_folded = 1;

    o = CHECKOP(type, o);
    if (!OpRETTYPE(o))
        OpRETTYPE_set(o, OpTYPE_RET(type));
    if (o->op_type != (unsigned)type)
	return o;

    return fold_constants(op_integerize(op_std_init(o)));
}

/* Constructors */


/*
=head1 Optree construction

=for apidoc Am|OP *	|newNULLLIST

Constructs, checks, and returns a new C<stub> op, which represents an
empty list expression.

=cut
*/

OP *
Perl_newNULLLIST(pTHX)
{
    return newOP(OP_STUB, 0);
}

/*
=for apidoc force_list

promote o and any siblings to be a list if its not already; i.e.

 o - A - B

becomes

 list
   |
 pushmark - o - A - B

If nullit it true, the list op is nulled.
=cut
*/

static OP *
S_force_list(pTHX_ OP *o, bool nullit)
{
    if (!o || ISNT_TYPE(o, LIST)) {
        OP *rest = NULL;
        if (o) {
            /* manually detach any siblings then add them back later */
            rest = OpSIBLING(o);
            OpLASTSIB_set(o, NULL);
        }
	o = newLISTOP(OP_LIST, 0, o, NULL);
        if (rest)
            op_sibling_splice(o, OpLAST(o), 0, rest);
    }
    if (nullit)
        op_null(o);
    return o;
}

/*
=for apidoc Am|OP *|newLISTOP|I32 type|I32 flags|OP *first|OP *last

Constructs, checks, and returns an op of any list type.  C<type> is
the opcode.  C<flags> gives the eight bits of C<op_flags>, except that
C<OPf_KIDS> will be set automatically if required.  C<first> and C<last>
supply up to two ops to be direct children of the list op; they are
consumed by this function and become part of the constructed op tree.

For most list operators, the check function expects all the kid ops to be
present already, so calling C<newLISTOP(OP_JOIN, ...)> (e.g.) is not
appropriate.  What you want to do in that case is create an op of type
C<OP_LIST>, append more children to it, and then call L</op_convert_list>.
See L</op_convert_list> for more information.


=cut
*/

OP *
Perl_newLISTOP(pTHX_ I32 type, I32 flags, OP *first, OP *last)
{
    dVAR;
    LISTOP *listop;

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_LISTOP
	|| type == OP_CUSTOM);

    NewOp(1101, listop, 1, LISTOP);

    OpTYPE_set(listop, type);
    if (first || last)
	flags |= OPf_KIDS;
    listop->op_flags = (U8)flags;

    if (!last && first)
	last = first;
    else if (!first && last)
	first = last;
    else if (first)
	OpMORESIB_set(first, last);
    OpFIRST(listop) = first;
    OpLAST(listop) = last;
    if (type == OP_LIST) {
	OP* const pushop = newOP(OP_PUSHMARK, 0);
	OpMORESIB_set(pushop, first);
	OpFIRST(listop) = pushop;
	listop->op_flags |= OPf_KIDS;
	if (!last)
	    OpLAST(listop) = pushop;
    }
    if (OpLAST(listop))
        OpLASTSIB_set(OpLAST(listop), (OP*)listop);

    listop = (LISTOP *)CHECKOP(type, listop);
    if (!OpRETTYPE((OP*)listop))
        OpRETTYPE_set((OP*)listop, OpTYPE_RET(type));
    return (OP*)listop;
}

/*
=for apidoc Am|OP *|newOP|I32 type|I32 flags

Constructs, checks, and returns an op of any base type (any type that
has no extra fields).  C<type> is the opcode.  C<flags> gives the
eight bits of C<op_flags>, and, shifted up eight bits, the eight bits
of C<op_private>.

=cut
*/

OP *
Perl_newOP(pTHX_ I32 type, I32 flags)
{
    dVAR;
    OP *o;

    if (type == -OP_ENTEREVAL) {
	type = OP_ENTEREVAL;
	flags |= OPpEVAL_BYTES<<8;
    }

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_BASEOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_BASEOP_OR_UNOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_FILESTATOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_LOOPEXOP
        || OP_IS_ITER(type));

    /* A const PADSV maybe upgraded to a CONST in ck_pad: reserve a sv slot */
    if (type == OP_PADSV || type == OP_PADANY)
        NewOpSz(1101, o, sizeof(SVOP));
    else if (OP_IS_ITER(type))
        NewOpSz(1101, o, sizeof(LOGOP));
    else
        NewOp(1101, o, 1, OP);
    OpTYPE_set(o, type);
    o->op_flags = (U8)flags;

    OpNEXT(o) = o;
    o->op_private = (U8)(0 | (flags >> 8));
    if (PL_opargs[type] & OA_RETSCALAR)
	scalar(o);
    if (PL_opargs[type] & OA_TARGET)
	o->op_targ = pad_alloc(type, SVs_PADTMP);
    o = CHECKOP(type, o);
    if (!OpRETTYPE(o) && (flags = OpTYPE_RET(type)))
        OpRETTYPE_set(o, (U8)flags);
    return o;
}

/*
=for apidoc Am|OP *|newUNOP|I32 type|I32 flags|OP *first

Constructs, checks, and returns an op of any unary type.  C<type> is
the opcode.  C<flags> gives the eight bits of C<op_flags>, except that
C<OPf_KIDS> will be set automatically if required, and, shifted up eight
bits, the eight bits of C<op_private>, except that the bit with value 1
is automatically set.  C<first> supplies an optional op to be the direct
child of the unary op; it is consumed by this function and become part
of the constructed op tree.

=cut
*/

OP *
Perl_newUNOP(pTHX_ I32 type, I32 flags, OP *first)
{
    dVAR;
    UNOP *unop;

    if (type == -OP_ENTEREVAL) {
	type = OP_ENTEREVAL;
	flags |= OPpEVAL_BYTES<<8;
    }

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_UNOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_BASEOP_OR_UNOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_FILESTATOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_LOOPEXOP
	|| type == OP_SASSIGN
	|| type == OP_ENTERTRY
	|| type == OP_CUSTOM
	|| type == OP_NULL );

    if (!first)
	first = newOP(OP_STUB, 0);
    if (PL_opargs[type] & OA_MARK)
	first = force_list(first, 1);

    NewOp(1101, unop, 1, UNOP);
    OpTYPE_set(unop, type);
    OpFIRST(unop) = first;
    unop->op_flags = (U8)(flags | OPf_KIDS);
    unop->op_private = (U8)(1 | (flags >> 8));

    if (!OpHAS_SIBLING(first)) /* true unless weird syntax error */
        OpLASTSIB_set(first, (OP*)unop);

    unop = (UNOP*) CHECKOP(type, unop);
    if (!OpRETTYPE(unop))
        OpRETTYPE_set(unop, OpTYPE_RET(type));
    if (OpNEXT(unop))
	return (OP*)unop;

    return fold_constants(op_integerize(op_std_init((OP *) unop)));
}

/*
=for apidoc newUNOP_AUX

Similar to C<newUNOP>, but creates an C<UNOP_AUX> struct instead, with C<op_aux>
initialised to C<aux>

=cut
*/

OP *
Perl_newUNOP_AUX(pTHX_ I32 type, I32 flags, OP *first, UNOP_AUX_item *aux)
{
    dVAR;
    UNOP_AUX *unop;

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_UNOP_AUX
        || type == OP_CUSTOM);

    NewOp(1101, unop, 1, UNOP_AUX);
    unop->op_type = (OPCODE)type;
    unop->op_ppaddr = PL_ppaddr[type];
    OpFIRST(unop) = first;
    unop->op_flags = (U8)(flags | (first ? OPf_KIDS : 0));
    unop->op_private = (U8)((first ? 1 : 0) | (flags >> 8));
    unop->op_aux = aux;

    if (first && !OpHAS_SIBLING(first)) /* true unless weird syntax error */
        OpLASTSIB_set(first, (OP*)unop);

    unop = (UNOP_AUX*) CHECKOP(type, unop);
    if (!OpRETTYPE(unop))
        OpRETTYPE_set(unop, OpTYPE_RET(type));

    return op_std_init((OP *) unop);
}

/*
=for apidoc Am|OP *|newMETHOP|I32 type|I32 flags|OP *first

Constructs, checks, and returns an op of method type with a method name
evaluated at runtime.  C<type> is the opcode.  C<flags> gives the eight
bits of C<op_flags>, except that C<OPf_KIDS> will be set automatically,
and, shifted up eight bits, the eight bits of C<op_private>, except that
the bit with value 1 is automatically set.  C<dynamic_meth> supplies an
op which evaluates method name; it is consumed by this function and
become part of the constructed op tree.

Supported optypes: METHOD, METHOD_NAMED, METHOD_SUPER, METHOD_REDIR,
METHOD_REDIR_SUPER, CUSTOM.

=cut
*/

static OP*
S_newMETHOP_internal(pTHX_ I32 type, I32 flags, OP* dynamic_meth, SV* const_meth) {
    dVAR;
    METHOP *methop;

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_METHOP
        || type == OP_CUSTOM);

    NewOp(1101, methop, 1, METHOP);
    if (dynamic_meth) {
        if (PL_opargs[type] & OA_MARK) dynamic_meth = force_list(dynamic_meth, 1);
        methop->op_flags = (U8)(flags | OPf_KIDS);
        methop->op_u.op_first = dynamic_meth;
        methop->op_private = (U8)(1 | (flags >> 8));

        if (!OpHAS_SIBLING(dynamic_meth))
            OpLASTSIB_set(dynamic_meth, (OP*)methop);
    }
    else {
        assert(const_meth);
        methop->op_flags = (U8)(flags & ~OPf_KIDS);
        methop->op_u.op_meth_sv = const_meth;
        methop->op_private = (U8)(0 | (flags >> 8));
        methop->op_next = (OP*)methop;
    }

#ifdef USE_ITHREADS
    methop->op_rclass_targ = 0;
#else
    methop->op_rclass_sv = NULL;
#endif

    OpTYPE_set(methop, type);
    return CHECKOP(type, methop);
}

OP *
Perl_newMETHOP (pTHX_ I32 type, I32 flags, OP* dynamic_meth) {
    PERL_ARGS_ASSERT_NEWMETHOP;
    return newMETHOP_internal(type, flags, dynamic_meth, NULL);
}

/*
=for apidoc Am|OP *|newMETHOP_named|I32 type|I32 flags|SV *const_meth

Constructs, checks, and returns an op of method type with a constant
method name.  C<type> is the opcode.  C<flags> gives the eight bits of
C<op_flags>, and, shifted up eight bits, the eight bits of
C<op_private>.  C<const_meth> supplies a constant method name;
it must be a shared COW string.
Supported optypes: C<OP_METHOD_NAMED>.

=cut
*/

OP *
Perl_newMETHOP_named (pTHX_ I32 type, I32 flags, SV* const_meth) {
    PERL_ARGS_ASSERT_NEWMETHOP_NAMED;
    return newMETHOP_internal(type, flags, NULL, const_meth);
}

/*
=for apidoc Am|OP *|newBINOP|I32 type|I32 flags|OP *first|OP *last

Constructs, checks, and returns an op of any binary type.  C<type>
is the opcode.  C<flags> gives the eight bits of C<op_flags>, except
that C<OPf_KIDS> will be set automatically, and, shifted up eight bits,
the eight bits of C<op_private>, except that the bit with value 1 or
2 is automatically set as required.  C<first> and C<last> supply up to
two ops to be the direct children of the binary op; they are consumed
by this function and become part of the constructed op tree.

=cut
*/

OP *
Perl_newBINOP(pTHX_ I32 type, I32 flags, OP *first, OP *last)
{
    dVAR;
    BINOP *binop;

    ASSUME((PL_opargs[type] & OA_CLASS_MASK) == OA_BINOP
	|| type == OP_NULL || type == OP_CUSTOM);

    NewOp(1101, binop, 1, BINOP);

    if (!first)
	first = newOP(OP_NULL, 0);

    OpTYPE_set(binop, type);
    OpFIRST(binop) = first;
    binop->op_flags = (U8)(flags | OPf_KIDS);
    if (!last) {
	last = first;
	binop->op_private = (U8)(1 | (flags >> 8));
    }
    else {
	binop->op_private = (U8)(2 | (flags >> 8));
        OpMORESIB_set(first, last);
    }

    if (!OpHAS_SIBLING(last)) /* true unless weird syntax error */
        OpLASTSIB_set(last, (OP*)binop);

    OpLAST(binop) = OpSIBLING(OpFIRST(binop));
    if (OpLAST(binop))
        OpLASTSIB_set(OpLAST(binop), (OP*)binop);

    binop = (BINOP*)CHECKOP(type, binop);
    if (!OpRETTYPE(binop))
        OpRETTYPE_set(binop, OpTYPE_RET(type));
    if (OpNEXT(binop) || binop->op_type != (OPCODE)type)
	return (OP*)binop;

    return fold_constants(op_integerize(op_std_init((OP *)binop)));
}

/* Helper function for S_pmtrans(): comparison function to sort an array
 * of codepoint range pairs. Sorts by start point, or if equal, by end
 * point */

static int uvcompare(const void *a, const void *b)
    __attribute__nonnull__(1)
    __attribute__nonnull__(2)
    __attribute__pure__;
static int uvcompare(const void *a, const void *b)
{
    if (*((const UV *)a) < (*(const UV *)b))
	return -1;
    if (*((const UV *)a) > (*(const UV *)b))
	return 1;
    if (*((const UV *)a+1) < (*(const UV *)b+1))
	return -1;
    if (*((const UV *)a+1) > (*(const UV *)b+1))
	return 1;
    return 0;
}

/* Given an OP_TRANS / OP_TRANSR op o, plus OP_CONST ops expr and repl
 * containing the search and replacement strings, assemble into
 * a translation table attached as o->op_pv.
 * Free expr and repl.
 * It expects the toker to have already set the
 *   OPpTRANS_COMPLEMENT
 *   OPpTRANS_SQUASH
 *   OPpTRANS_DELETE
 * flags as appropriate; this function may add
 *   OPpTRANS_FROM_UTF
 *   OPpTRANS_TO_UTF
 *   OPpTRANS_IDENTICAL
 *   OPpTRANS_GROWS
 * flags
 */

static OP *
S_pmtrans(pTHX_ OP *o, OP *expr, OP *repl)
{
    SV * const tstr = ((SVOP*)expr)->op_sv;
    SV * const rstr = ((SVOP*)repl)->op_sv;
    STRLEN tlen;
    STRLEN rlen;
    const U8 *t = (U8*)SvPV_const(tstr, tlen);
    const U8 *r = (U8*)SvPV_const(rstr, rlen);
    I32 i;
    I32 j;
    I32 grows = 0;
    OPtrans_map *tbl;
    SSize_t struct_size; /* malloced size of table struct */

    const bool complement = cBOOL(o->op_private & OPpTRANS_COMPLEMENT);
    const I32 squash     = o->op_private & OPpTRANS_SQUASH;
    I32 del              = o->op_private & OPpTRANS_DELETE;
    SV* swash;

    PERL_ARGS_ASSERT_PMTRANS;

    PL_hints |= HINT_BLOCK_SCOPE;

    if (SvUTF8(tstr))
        o->op_private |= OPpTRANS_FROM_UTF;

    if (SvUTF8(rstr))
        o->op_private |= OPpTRANS_TO_UTF;

    if (o->op_private & (OPpTRANS_FROM_UTF|OPpTRANS_TO_UTF)) {

        /* for utf8 translations, op_sv will be set to point to a swash
         * containing codepoint ranges. This is done by first assembling
         * a textual representation of the ranges in listsv then compiling
         * it using swash_init(). For more details of the textual format,
         * see L<perlunicode.pod/"User-Defined Character Properties"> .
         */

	SV* const listsv = newSVpvs("# comment\n");
	SV* transv = NULL;
	const U8* tend = t + tlen;
	const U8* rend = r + rlen;
	STRLEN ulen;
	UV tfirst = 1;
	UV tlast = 0;
	IV tdiff;
	STRLEN tcount = 0;
	UV rfirst = 1;
	UV rlast = 0;
	IV rdiff;
	STRLEN rcount = 0;
	IV diff;
	I32 none = 0;
	U32 max = 0;
	I32 bits;
	I32 havefinal = 0;
	U32 final = 0;
	const I32 from_utf  = o->op_private & OPpTRANS_FROM_UTF;
	const I32 to_utf    = o->op_private & OPpTRANS_TO_UTF;
	U8* tsave = NULL;
	U8* rsave = NULL;
	const U32 flags = UTF8_ALLOW_DEFAULT;

	if (!from_utf) {
	    STRLEN len = tlen;
	    t = tsave = bytes_to_utf8(t, &len);
	    tend = t + len;
	}
	if (!to_utf && rlen) {
	    STRLEN len = rlen;
	    r = rsave = bytes_to_utf8(r, &len);
	    rend = r + len;
	}

/* There is a snag with this code on EBCDIC: scan_const() in toke.c has
 * encoded chars in native encoding which makes ranges in the EBCDIC 0..255
 * odd.  */

	if (complement) {
            /* utf8 and /c:
             * replace t/tlen/tend with a version that has the ranges
             * complemented
             */
	    U8 tmpbuf[UTF8_MAXBYTES+1];
	    UV *cp;
	    UV nextmin = 0;
	    Newx(cp, 2*tlen, UV);
	    i = 0;
	    transv = newSVpvs("");

            /* convert search string into array of (start,end) range
             * codepoint pairs stored in cp[]. Most "ranges" will start
             * and end at the same char */
	    while (t < tend) {
		cp[2*i] = utf8n_to_uvchr(t, tend-t, &ulen, flags);
		t += ulen;
                /* the toker converts X-Y into (X, ILLEGAL_UTF8_BYTE, Y) */
		if (t < tend && *t == ILLEGAL_UTF8_BYTE) {
		    t++;
		    cp[2*i+1] = utf8n_to_uvchr(t, tend-t, &ulen, flags);
		    t += ulen;
		}
		else {
		 cp[2*i+1] = cp[2*i];
		}
		i++;
	    }

            /* sort the ranges */
	    qsort(cp, i, 2*sizeof(UV), uvcompare);

            /* Create a utf8 string containing the complement of the
             * codepoint ranges. For example if cp[] contains [A,B], [C,D],
             * then transv will contain the equivalent of:
             * join '', map chr, 0,     ILLEGAL_UTF8_BYTE, A - 1,
             *                   B + 1, ILLEGAL_UTF8_BYTE, C - 1,
             *                   D + 1, ILLEGAL_UTF8_BYTE, 0x7fffffff;
             * A range of a single char skips the ILLEGAL_UTF8_BYTE and
             * end cp.
             */
	    for (j = 0; j < i; j++) {
		UV  val = cp[2*j];
		diff = val - nextmin;
		if (diff > 0) {
		    t = uvchr_to_utf8(tmpbuf,nextmin);
		    sv_catpvn(transv, (char*)tmpbuf, t - tmpbuf);
		    if (diff > 1) {
			U8  range_mark = ILLEGAL_UTF8_BYTE;
			t = uvchr_to_utf8(tmpbuf, val - 1);
			sv_catpvn(transv, (char *)&range_mark, 1);
			sv_catpvn(transv, (char*)tmpbuf, t - tmpbuf);
		    }
	        }
		val = cp[2*j+1];
		if (val >= nextmin)
		    nextmin = val + 1;
	    }

	    t = uvchr_to_utf8(tmpbuf,nextmin);
	    sv_catpvn(transv, (char*)tmpbuf, t - tmpbuf);
	    {
		U8 range_mark = ILLEGAL_UTF8_BYTE;
		sv_catpvn(transv, (char *)&range_mark, 1);
	    }
	    t = uvchr_to_utf8(tmpbuf, 0x7fffffff);
	    sv_catpvn(transv, (char*)tmpbuf, t - tmpbuf);
	    t = (const U8*)SvPVX_const(transv);
	    tlen = SvCUR(transv);
	    tend = t + tlen;
	    Safefree(cp);
	}
	else if (!rlen && !del) {
	    r = t; rlen = tlen; rend = tend;
	}

	if (!squash) {
		if ((!rlen && !del) || t == r ||
		    (tlen == rlen && memEQ((char *)t, (char *)r, tlen)))
		{
		    o->op_private |= OPpTRANS_IDENTICAL;
		}
	}

        /* extract char ranges from t and r and append them to listsv */

	while (t < tend || tfirst <= tlast) {
	    /* see if we need more "t" chars */
	    if (tfirst > tlast) {
		tfirst = (I32)utf8n_to_uvchr(t, tend - t, &ulen, flags);
		t += ulen;
		if (t < tend && *t == ILLEGAL_UTF8_BYTE) {	/* illegal utf8 val indicates range */
		    t++;
		    tlast = (I32)utf8n_to_uvchr(t, tend - t, &ulen, flags);
		    t += ulen;
		}
		else
		    tlast = tfirst;
	    }

	    /* now see if we need more "r" chars */
	    if (rfirst > rlast) {
		if (r < rend) {
		    rfirst = (I32)utf8n_to_uvchr(r, rend - r, &ulen, flags);
		    r += ulen;
		    if (r < rend && *r == ILLEGAL_UTF8_BYTE) {	/* illegal utf8 val indicates range */
			r++;
			rlast = (I32)utf8n_to_uvchr(r, rend - r, &ulen, flags);
			r += ulen;
		    }
		    else
			rlast = rfirst;
		}
		else {
		    if (!havefinal++)
			final = rlast;
		    rfirst = rlast = 0xffffffff;
		}
	    }

	    /* now see which range will peter out first, if either. */
	    tdiff = tlast - tfirst;
	    rdiff = rlast - rfirst;
	    tcount += tdiff + 1;
	    rcount += rdiff + 1;

	    if (tdiff <= rdiff)
		diff = tdiff;
	    else
		diff = rdiff;

	    if (rfirst == 0xffffffff) {
		diff = tdiff;	/* oops, pretend rdiff is infinite */
		if (diff > 0)
		    Perl_sv_catpvf(aTHX_ listsv, "%04lx\t%04lx\tXXXX\n",
				   (long)tfirst, (long)tlast);
		else
		    Perl_sv_catpvf(aTHX_ listsv, "%04lx\t\tXXXX\n", (long)tfirst);
	    }
	    else {
		if (diff > 0)
		    Perl_sv_catpvf(aTHX_ listsv, "%04lx\t%04lx\t%04lx\n",
				   (long)tfirst, (long)(tfirst + diff),
				   (long)rfirst);
		else
		    Perl_sv_catpvf(aTHX_ listsv, "%04lx\t\t%04lx\n",
				   (long)tfirst, (long)rfirst);

		if (rfirst + diff > max)
		    max = rfirst + diff;
		if (!grows)
		    grows = (tfirst < rfirst &&
			     UVCHR_SKIP(tfirst) < UVCHR_SKIP(rfirst + diff));
		rfirst += diff + 1;
	    }
	    tfirst += diff + 1;
	}

        /* compile listsv into a swash and attach to o */

	none = ++max;
	if (del)
	    del = ++max;

	if (max > 0xffff)
	    bits = 32;
	else if (max > 0xff)
	    bits = 16;
	else
	    bits = 8;

	swash = MUTABLE_SV(swash_init("utf8", "", listsv, bits, none));
        op_gv_set(o, (GV*)swash);
#ifdef USE_ITHREADS
	SvPADTMP_on(swash);
        SvREADONLY_on(swash);
#endif
	SvREFCNT_dec(listsv);
	SvREFCNT_dec(transv);

	if (!del && havefinal && rlen)
	    (void)hv_store(MUTABLE_HV(SvRV(swash)), "FINAL", 5,
			   newSVuv((UV)final), 0);

	Safefree(tsave);
	Safefree(rsave);

	tlen = tcount;
	rlen = rcount;
	if (r < rend)
	    rlen++;
	else if (rlast == 0xffffffff)
	    rlen = 0;

	goto warnins;
    }

    /* Non-utf8 case: set o->op_pv to point to a simple 256+ entry lookup
     * table. Entries with the value -1 indicate chars not to be
     * translated, while -2 indicates a search char without a
     * corresponding replacement char under /d.
     *
     * Normally, the table has 256 slots. However, in the presence of
     * /c, the search charlist has an implicit \x{100}-\x{7fffffff}
     * added, and if there are enough replacement chars to start pairing
     * with the \x{100},... search chars, then a larger (> 256) table
     * is allocated.
     *
     * In addition, regardless of whether under /c, an extra slot at the
     * end is used to store the final repeating char, or -3 under an empty
     * replacement list, or -2 under /d; which makes the runtime code
     * easier.
     *
     * The toker will have already expanded char ranges in t and r.
     */

    /* Initially allocate 257-slot table: 256 for basic (non /c) usage,
     * plus final slot for repeat/-2/-3. Later we realloc if excess > * 0.
     * The OPtrans_map struct already contains one slot; hence the -1.
     */
    struct_size = sizeof(OPtrans_map) + (256 - 1 + 1)*sizeof(short);
    tbl = (OPtrans_map*)PerlMemShared_calloc(struct_size, 1);
    tbl->size = 256;
    cPVOPo->op_pv = (char*)tbl;

    if (complement) {
        SSize_t excess;

        /* in this branch, j is a count of 'consumed' (i.e. paired off
         * with a search char) replacement chars (so j <= rlen always)
         */
	for (i = 0; i < (I32)tlen; i++)
	    tbl->map[t[i]] = -1;

	for (i = 0, j = 0; i < 256; i++) {
	    if (!tbl->map[i]) {
		if (j == (I32)rlen) {
		    if (del)
			tbl->map[i] = -2;
		    else if (rlen)
			tbl->map[i] = r[j-1];
		    else
			tbl->map[i] = (short)i;
		}
		else {
		    tbl->map[i] = r[j++];
		}
                if (   tbl->map[i] >= 0
                    &&  UVCHR_IS_INVARIANT((UV)i)
                    && !UVCHR_IS_INVARIANT((UV)(tbl->map[i]))
                )
                    grows = 1;
	    }
	}

        assert(j <= (I32)rlen);
        excess = rlen - (SSize_t)j;

        if (excess) {
            /* More replacement chars than search chars:
             * store excess replacement chars at end of main table.
             */

            struct_size += excess;
            tbl = (OPtrans_map*)PerlMemShared_realloc(tbl,
                        struct_size + excess * sizeof(short));
            tbl->size += excess;
            cPVOPo->op_pv = (char*)tbl;

            for (i = 0; i < (I32)excess; i++)
                tbl->map[i + 256] = r[j+i];
        }
        else {
            /* no more replacement chars than search chars */
            if (!rlen && !del && !squash)
                o->op_private |= OPpTRANS_IDENTICAL;
        }

        tbl->map[tbl->size] = del ? -2 : rlen ? r[rlen - 1] : -3;
    }
    else {
	if (!rlen && !del) {
	    r = t; rlen = tlen;
	    if (!squash)
		o->op_private |= OPpTRANS_IDENTICAL;
	}
	else if (!squash && rlen == tlen && memEQ((char*)t, (char*)r, tlen)) {
	    o->op_private |= OPpTRANS_IDENTICAL;
	}

	for (i = 0; i < 256; i++)
	    tbl->map[i] = -1;
	for (i = 0, j = 0; i < (I32)tlen; i++,j++) {
	    if (j >= (I32)rlen) {
		if (del) {
		    if (tbl->map[t[i]] == -1)
			tbl->map[t[i]] = -2;
		    continue;
		}
		--j;
	    }
	    if (tbl->map[t[i]] == -1) {
                if (     UVCHR_IS_INVARIANT(t[i])
                    && ! UVCHR_IS_INVARIANT(r[j]))
		    grows = 1;
		tbl->map[t[i]] = r[j];
	    }
	}
        tbl->map[tbl->size] = del ? -1 : rlen ? -1 : -3;
    }

    /* both non-utf8 and utf8 code paths end up here */

  warnins:
    if(del && rlen == tlen) {
	Perl_ck_warner(aTHX_ packWARN(WARN_MISC), "Useless use of /d modifier in transliteration operator"); 
    } else if(rlen > tlen && !complement) {
	Perl_ck_warner(aTHX_ packWARN(WARN_MISC), "Replacement list is longer than search list");
    }

    if (grows)
	o->op_private |= OPpTRANS_GROWS;
    op_free(expr);
    op_free(repl);

    return o;
}


/*
=for apidoc Am|OP *|newPMOP|I32 type|I32 flags

Constructs, checks, and returns an op of any pattern matching type.
C<type> is the opcode.  C<flags> gives the eight bits of C<op_flags>
and, shifted up eight bits, the eight bits of C<op_private>.

=cut
*/

OP *
Perl_newPMOP(pTHX_ I32 type, I32 flags)
{
    dVAR;
    PMOP *pmop;

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_PMOP
	|| type == OP_CUSTOM);

    NewOp(1101, pmop, 1, PMOP);
    OpTYPE_set(pmop, type);
    pmop->op_flags = (U8)flags;
    pmop->op_private = (U8)(0 | (flags >> 8));
    if (PL_opargs[type] & OA_RETSCALAR)
	scalar((OP *)pmop);

    if (PL_hints & HINT_RE_TAINT)
	pmop->op_pmflags |= PMf_RETAINT;
#ifdef USE_LOCALE_CTYPE
    if (IN_LC_COMPILETIME(LC_CTYPE)) {
	set_regex_charset(&(pmop->op_pmflags), REGEX_LOCALE_CHARSET);
    }
    else
#endif
         if (IN_UNI_8_BIT) {
	set_regex_charset(&(pmop->op_pmflags), REGEX_UNICODE_CHARSET);
    }
    if (PL_hints & HINT_RE_FLAGS) {
        SV *reflags = Perl_refcounted_he_fetch_pvn(aTHX_
         PL_compiling.cop_hints_hash, STR_WITH_LEN("reflags"), 0, 0
        );
        if (reflags && SvOK(reflags)) pmop->op_pmflags |= SvIV(reflags);
        reflags = Perl_refcounted_he_fetch_pvn(aTHX_
         PL_compiling.cop_hints_hash, STR_WITH_LEN("reflags_charset"), 0, 0
        );
        if (reflags && SvOK(reflags)) {
            set_regex_charset(&(pmop->op_pmflags), (regex_charset)SvIV(reflags));
        }
    }


#ifdef USE_ITHREADS
    assert(SvPOK(PL_regex_pad[0]));
    if (SvCUR(PL_regex_pad[0])) {
	/* Pop off the "packed" IV from the end.  */
	SV *const repointer_list = PL_regex_pad[0];
	const char *p = SvEND(repointer_list) - sizeof(IV);
	const IV offset = *((IV*)p);

	assert(SvCUR(repointer_list) % sizeof(IV) == 0);

	SvEND_set(repointer_list, p);

	pmop->op_pmoffset = offset;
	/* This slot should be free, so assert this:  */
	assert(PL_regex_pad[offset] == UNDEF);
    } else {
	SV * const repointer = UNDEF;
	av_push(PL_regex_padav, repointer);
	pmop->op_pmoffset = av_tindex(PL_regex_padav);
	PL_regex_pad = AvARRAY(PL_regex_padav);
    }
#endif

    return CHECKOP(type, pmop);
}

static void
S_set_haseval(pTHX)
{
    PADOFFSET i = 1;
    PL_cv_has_eval = 1;
    /* Any pad names in scope are potentially lvalues.  */
    for (; i < PadnamelistMAXNAMED(PL_comppad_name); i++) {
	PADNAME *pn = PAD_COMPNAME_SV(i);
	if (!pn || !PadnameLEN(pn))
	    continue;
	if (PadnameOUTER(pn) || PadnameIN_SCOPE(pn, PL_cop_seqmax))
	    S_mark_padname_lvalue(aTHX_ pn);
    }
}

/* Given some sort of match op o, and an expression expr containing a
 * pattern, either compile expr into a regex and attach it to o (if it's
 * constant), or convert expr into a runtime regcomp op sequence (if it's
 * not)
 *
 * Flags currently has 2 bits of meaning:
 * 1: isreg indicates that the pattern is part of a regex construct, eg
 * $x =~ /pattern/ or split /pattern/, as opposed to $x =~ $pattern or
 * split "pattern", which aren't. In the former case, expr will be a list
 * if the pattern contains more than one term (eg /a$b/).
 * 2: The pattern is for a split.
 *
 * When the pattern has been compiled within a new anon CV (for
 * qr/(?{...})/ ), then floor indicates the savestack level just before
 * the new sub was created
 */

OP *
Perl_pmruntime(pTHX_ OP *o, OP *expr, OP *repl, UV flags, I32 floor)
{
    PMOP *pm;
    LOGOP *rcop;
    I32 repl_has_vars = 0;
    bool is_trans = (IS_TYPE(o, TRANS) || IS_TYPE(o, TRANSR));
    bool is_compiletime;
    bool has_code;
    bool isreg    = cBOOL(flags & 1);
    bool is_split = cBOOL(flags & 2);

    PERL_ARGS_ASSERT_PMRUNTIME;

    if (is_trans && repl) {
        return pmtrans(o, expr, repl);
    }

    /* find whether we have any runtime or code elements;
     * at the same time, temporarily set the op_next of each DO block;
     * then when we LINKLIST, this will cause the DO blocks to be excluded
     * from the op_next chain (and from having LINKLIST recursively
     * applied to them). We fix up the DOs specially later */

    is_compiletime = 1;
    has_code = 0;
    if (IS_TYPE(expr, LIST)) {
	OP *o;
	for (o = OpFIRST(expr); o; o = OpSIBLING(o)) {
	    if (IS_NULL_OP(o) && OpSPECIAL(o)) {
		has_code = 1;
		assert(!OpNEXT(o));
		if (UNLIKELY(!OpHAS_SIBLING(o))) {
		    assert(PL_parser && PL_parser->error_count);
		    /* This can happen with qr/ (?{(^{})/.  Just fake up
		       the op we were expecting to see, to avoid crashing
		       elsewhere.  */
		    op_sibling_splice(expr, o, 0,
				      newSVOP(OP_CONST, 0, SV_NO));
		}
		OpNEXT(o) = OpSIBLING(o);
	    }
	    else if (ISNT_TYPE(o, CONST) && ISNT_TYPE(o, PUSHMARK))
		is_compiletime = 0;
	}
    }
    else if (ISNT_TYPE(expr, CONST))
	is_compiletime = 0;

    LINKLIST(expr);

    /* fix up DO blocks; treat each one as a separate little sub;
     * also, mark any arrays as LIST/REF */

    if (IS_TYPE(expr, LIST)) {
	OP *o;
	for (o = OpFIRST(expr); o; o = OpSIBLING(o)) {

            if (IS_TYPE(o, PADAV) || IS_TYPE(o, RV2AV)) {
                assert( !(o->op_flags & OPf_WANT));
                /* push the array rather than its contents. The regex
                 * engine will retrieve and join the elements later */
                o->op_flags |= (OPf_WANT_LIST | OPf_REF);
                continue;
            }

	    if (!(IS_NULL_OP(o) && OpSPECIAL(o)))
		continue;
	    OpNEXT(o) = NULL; /* undo temporary hack from above */
	    scalar(o);
	    LINKLIST(o);
	    if (IS_TYPE(OpFIRST(o), LEAVE)) {
		LISTOP *leaveop = cLISTOPx(OpFIRST(o));
		/* skip ENTER */
		assert(IS_TYPE(OpFIRST(leaveop), ENTER));
		assert(OpHAS_SIBLING(OpFIRST(leaveop)));
		OpNEXT(o) = OpSIBLING(OpFIRST(leaveop));
		/* skip leave */
		assert(OpKIDS(leaveop));
		assert(OpNEXT(OpLAST(leaveop)) == (OP*)leaveop);
		OpNEXT(leaveop) = NULL; /* stop on last op */
		op_null((OP*)leaveop);
	    }
	    else {
		/* skip SCOPE */
		OP *scope = OpFIRST(o);
		assert(IS_TYPE(scope, SCOPE));
		assert(OpKIDS(scope));
		OpNEXT(scope) = NULL; /* stop on last op */
		op_null(scope);
	    }

	    if (is_compiletime)
		/* runtime finalizes as part of finalizing whole tree */
                optimize_optree(o);

	    /* have to peep the DOs individually as we've removed it from
	     * the op_next chain */
	    CALL_PEEP(o);
            S_prune_chain_head(&(OpNEXT(o)));
	    if (is_compiletime)
		/* runtime finalizes as part of finalizing whole tree */
		finalize_optree(o);
	}
    }
    else if (IS_TYPE(expr, PADAV) || IS_TYPE(expr, RV2AV)) {
        assert( !(expr->op_flags  & OPf_WANT));
        /* push the array rather than its contents. The regex
         * engine will retrieve and join the elements later */
        expr->op_flags |= (OPf_WANT_LIST | OPf_REF);
    }

    PL_hints |= HINT_BLOCK_SCOPE;
    pm = (PMOP*)o;
    assert(floor==0 || (pm->op_pmflags & PMf_HAS_CV));

    if (is_compiletime) {
	U32 rx_flags = pm->op_pmflags & RXf_PMf_COMPILETIME;
	regexp_engine const *eng = current_re_engine();

        if (is_split) {
            /* make engine handle split ' ' specially */
            pm->op_pmflags |= PMf_SPLIT;
            rx_flags |= RXf_SPLIT;
        }

	if (!has_code || !eng->op_comp) {
	    /* compile-time simple constant pattern */

	    if ((pm->op_pmflags & PMf_HAS_CV) && !has_code) {
		/* whoops! we guessed that a qr// had a code block, but we
		 * were wrong (e.g. /[(?{}]/ ). Throw away the PL_compcv
		 * that isn't required now. Note that we have to be pretty
		 * confident that nothing used that CV's pad while the
		 * regex was parsed, except maybe op targets for \Q etc.
		 * If there were any op targets, though, they should have
		 * been stolen by constant folding.
		 */
#ifdef DEBUGGING
		SSize_t i = 0;
		assert(PadnamelistMAXNAMED(PL_comppad_name) == 0);
		while (++i <= AvFILLp(PL_comppad)) {
#  ifdef USE_PAD_RESET
                    /* under USE_PAD_RESET, pad swipe replaces a swiped
                     * folded constant with a fresh padtmp */
		    assert(!PL_curpad[i] || SvPADTMP(PL_curpad[i]));
#  else
		    assert(!PL_curpad[i]);
#  endif
		}
#endif
		/* But we know that one op is using this CV's slab. */
		cv_forget_slab(PL_compcv);
		LEAVE_SCOPE(floor);
		pm->op_pmflags &= ~PMf_HAS_CV;
	    }

	    PM_SETRE(pm,
		eng->op_comp
		    ? eng->op_comp(aTHX_ NULL, 0, expr, eng, NULL, NULL,
					rx_flags, pm->op_pmflags)
		    : Perl_re_op_compile(aTHX_ NULL, 0, expr, eng, NULL, NULL,
					rx_flags, pm->op_pmflags)
	    );
	    op_free(expr);
	}
	else {
	    /* compile-time pattern that includes literal code blocks */
	    REGEXP* re = eng->op_comp(aTHX_ NULL, 0, expr, eng, NULL, NULL,
			rx_flags,
			(pm->op_pmflags |
			    ((PL_hints & HINT_RE_EVAL) ? PMf_USE_RE_EVAL : 0))
		    );
	    PM_SETRE(pm, re);
	    if (pm->op_pmflags & PMf_HAS_CV) {
		CV *cv;
		/* this QR op (and the anon sub we embed it in) is never
		 * actually executed. It's just a placeholder where we can
		 * squirrel away expr in op_code_list without the peephole
		 * optimiser etc processing it for a second time */
		OP *qr = newPMOP(OP_QR, 0);
		((PMOP*)qr)->op_code_list = expr;

		/* handle the implicit sub{} wrapped round the qr/(?{..})/ */
		SvREFCNT_inc_simple_void(PL_compcv);
		cv = newATTRSUB(floor, 0, NULL, NULL, qr);
		ReANY(re)->qr_anoncv = cv;

		/* attach the anon CV to the pad so that
		 * pad_fixup_inner_anons() can find it */
		(void)pad_add_anon(cv, o->op_type);
		SvREFCNT_inc_simple_void(cv);
	    }
	    else {
		pm->op_code_list = expr;
	    }
	}
    }
    else {
	/* runtime pattern: build chain of regcomp etc ops */
	PADOFFSET cv_targ = 0;
	bool reglist;

	reglist = isreg && IS_TYPE(expr, LIST);
	if (reglist)
	    op_null(expr);

	if (has_code) {
	    pm->op_code_list = expr;
	    /* don't free op_code_list; its ops are embedded elsewhere too */
	    pm->op_pmflags |= PMf_CODELIST_PRIVATE;
	}

        if (is_split)
            /* make engine handle split ' ' specially */
            pm->op_pmflags |= PMf_SPLIT;

	/* the OP_REGCMAYBE is a placeholder in the non-threaded case
	 * to allow its op_next to be pointed past the regcomp and
	 * preceding stacking ops;
	 * OP_REGCRESET is there to reset taint before executing the
	 * stacking ops */
	if (pm->op_pmflags & PMf_KEEP || TAINTING_get)
	    expr = newUNOP((TAINTING_get ? OP_REGCRESET : OP_REGCMAYBE),0,expr);

	if (pm->op_pmflags & PMf_HAS_CV) {
	    /* we have a runtime qr with literal code. This means
	     * that the qr// has been wrapped in a new CV, which
	     * means that runtime consts, vars etc will have been compiled
	     * against a new pad. So... we need to execute those ops
	     * within the environment of the new CV. So wrap them in a call
	     * to a new anon sub. i.e. for
	     *
	     *     qr/a$b(?{...})/,
	     *
	     * we build an anon sub that looks like
	     *
	     *     sub { "a", $b, '(?{...})' }
	     *
	     * and call it, passing the returned list to regcomp.
	     * Or to put it another way, the list of ops that get executed
	     * are:
	     *
	     *     normal              PMf_HAS_CV
	     *     ------              -------------------
	     *                         pushmark (for regcomp)
	     *                         pushmark (for entersub)
	     *                         anoncode
	     *                         srefgen
	     *                         entersub
	     *     regcreset                  regcreset
	     *     pushmark                   pushmark
	     *     const("a")                 const("a")
	     *     gvsv(b)                    gvsv(b)
	     *     const("(?{...})")          const("(?{...})")
	     *                                leavesub
	     *     regcomp             regcomp
	     */

	    SvREFCNT_inc_simple_void(PL_compcv);
	    CvLVALUE_on(PL_compcv);
	    /* these lines are just an unrolled newANONATTRSUB */
	    expr = newSVOP(OP_ANONCODE, 0,
		    MUTABLE_SV(newATTRSUB(floor, 0, NULL, NULL, expr)));
	    cv_targ = expr->op_targ;
	    expr = newUNOP(OP_REFGEN, 0, expr);

	    expr = list(force_list(newUNOP(OP_ENTERSUB, 0, scalar(expr)), 1));
	}

        rcop = S_alloc_LOGOP(aTHX_ OP_REGCOMP, scalar(expr), o);
	rcop->op_flags |=  ((PL_hints & HINT_RE_EVAL) ? OPf_SPECIAL : 0)
			   | (reglist ? OPf_STACKED : 0);
	rcop->op_targ = cv_targ;

	/* /$x/ may cause an eval, since $x might be qr/(?{..})/  */
	if (PL_hints & HINT_RE_EVAL)
	    S_set_haseval(aTHX);

	/* establish postfix order */
	if (IS_TYPE(expr, REGCRESET) || IS_TYPE(expr, REGCMAYBE)) {
	    LINKLIST(expr);
	    OpNEXT(rcop) = expr;
	    OpNEXT(OpFIRST(expr)) = (OP*)rcop;
	}
	else {
	    OpNEXT(rcop) = LINKLIST(expr);
	    OpNEXT(expr) = (OP*)rcop;
	}

	op_prepend_elem(o->op_type, scalar((OP*)rcop), o);
    }

    if (repl) {
	OP *curop = repl;
	bool konst;
	/* If we are looking at s//.../e with a single statement, get past
	   the implicit do{}. */
	if (IS_NULL_OP(curop) && OpKIDS(curop)
            && IS_TYPE(OpFIRST(curop), SCOPE)
            && OpKIDS(OpFIRST(curop)))
         {
            OP *sib;
	    OP *kid = OpFIRST(OpFIRST(curop));
	    if (IS_NULL_OP(kid) && (sib = OpSIBLING(kid))
	     && !OpHAS_SIBLING(sib))
		curop = sib;
	}
	if (IS_CONST_OP(curop))
	    konst = TRUE;
	else if (( (IS_TYPE(curop, RV2SV)
		 || IS_TYPE(curop, RV2AV)
		 || IS_TYPE(curop, RV2HV)
		 || IS_TYPE(curop, RV2GV))
		   && OpFIRST(curop)
		   && IS_TYPE(OpFIRST(curop), GV))
		|| IS_TYPE(curop, PADSV)
		|| IS_TYPE(curop, PADAV)
		|| IS_TYPE(curop, PADHV)
		|| IS_TYPE(curop, PADANY)) {
	    repl_has_vars = 1;
	    konst = TRUE;
	}
	else konst = FALSE;
	if (konst
	    && !(repl_has_vars
		 && (!PM_GETRE(pm)
		     || !RX_PRELEN(PM_GETRE(pm))
		     || RX_EXTFLAGS(PM_GETRE(pm)) & RXf_EVAL_SEEN)))
	{
	    pm->op_pmflags |= PMf_CONST;	/* const for long enough */
	    op_prepend_elem(o->op_type, scalar(repl), o);
	}
	else {
            rcop = S_alloc_LOGOP(aTHX_ OP_SUBSTCONT, scalar(repl), o);
	    rcop->op_private = 1;

	    /* establish postfix order */
	    OpNEXT(rcop) = LINKLIST(repl);
	    OpNEXT(repl) = (OP*)rcop;

	    pm->op_pmreplrootu.op_pmreplroot = scalar((OP*)rcop);
	    assert(!(pm->op_pmflags & PMf_ONCE));
	    pm->op_pmstashstartu.op_pmreplstart = LINKLIST(rcop);
	    OpNEXT(rcop) = NULL;
	}
    }

    return (OP*)pm;
}

/*
=for apidoc Am|OP *|newSVOP|I32 type|I32 flags|SV *sv

Constructs, checks, and returns an op of any type that involves an
embedded SV.  C<type> is the opcode.  C<flags> gives the eight bits
of C<op_flags>.  C<sv> gives the SV to embed in the op; this function
takes ownership of one reference to it.

=cut
*/

OP *
Perl_newSVOP(pTHX_ I32 type, I32 flags, SV *sv)
{
    dVAR;
    SVOP *svop;

    PERL_ARGS_ASSERT_NEWSVOP;

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_SVOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_PVOP_OR_SVOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_FILESTATOP
	|| type == OP_CUSTOM);

    NewOp(1101, svop, 1, SVOP);
    OpTYPE_set(svop, type);
    svop->op_sv = sv;
    svop->op_next = (OP*)svop;
    svop->op_flags = (U8)flags;
    svop->op_private = (U8)(0 | (flags >> 8));
    if (PL_opargs[type] & OA_RETSCALAR)
	scalar((OP*)svop);
    if (PL_opargs[type] & OA_TARGET)
	svop->op_targ = pad_alloc(type, SVs_PADTMP);
    svop = (SVOP*)CHECKOP(type, svop);
    if (!OpRETTYPE((OP*)svop))
        OpRETTYPE_set((OP*)svop, OpTYPE_RET(type));
    return (OP*)svop;
}

/*
=for apidoc Am|OP *|newDEFSVOP|

Constructs and returns an op to access C<$_>, either as a lexical
variable (if declared as C<my $_>) in the current scope, or the
global C<$_>.

=cut
*/

OP *
Perl_newDEFSVOP(pTHX)
{
    const PADOFFSET offset = pad_findmy_pvs("$_", 0);
    if (offset == NOT_IN_PAD || PAD_COMPNAME_FLAGS_isOUR(offset)) {
	return newSVREF(newGVOP(OP_GV, 0, PL_defgv));
    }
    else {
	OP * const o = newOP(OP_PADSV, 0);
	o->op_targ = offset;
	return o;
    }
}

#ifdef USE_ITHREADS

/*
=for apidoc Am|OP *|newPADOP|I32 type|I32 flags|SV *sv

Constructs, checks, and returns an op of any type that involves a
reference to a pad element.  C<type> is the opcode.  C<flags> gives the
eight bits of C<op_flags>.  A pad slot is automatically allocated, and
is populated with C<sv>; this function takes ownership of one reference
to it.

This function only exists if Perl has been compiled to use ithreads.

=cut
*/

OP *
Perl_newPADOP(pTHX_ I32 type, I32 flags, SV *sv)
{
    dVAR;
    PADOP *padop;
    PADOFFSET po;

    PERL_ARGS_ASSERT_NEWPADOP;

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_SVOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_PVOP_OR_SVOP
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_FILESTATOP
	|| type == OP_CUSTOM);

    NewOp(1101, padop, 1, PADOP);
    OpTYPE_set(padop, type);
    assert(PL_curpad == AvARRAY(PL_comppad));
    po = AvFILLp(PL_comppad);
#ifdef USE_PAD_REUSE
    /* TODO: check PAD_REUSE_MRU, allow cvref also. Better check for READONLY */
    if (isGV(sv) && PL_curpad[po] == sv) {
        padop->op_padix = po;		/* reuse the last GV slot */
    } else
#endif
    {
        /* XXX: cvref also? */
        po = padop->op_padix =
            pad_alloc(type, isGV(sv) ? SVf_READONLY : SVs_PADTMP);
        sv_free(PAD_SVl(po));
        PAD_SETSV(po, sv);
    }
    assert(sv);
    padop->op_next = (OP*)padop;
    padop->op_flags = (U8)flags;
    if (PL_opargs[type] & OA_RETSCALAR)
	scalar((OP*)padop);
    if (PL_opargs[type] & OA_TARGET)
	padop->op_targ = pad_alloc(type, SVs_PADTMP);
    return CHECKOP(type, padop);
}

#endif /* USE_ITHREADS */

/*
=for apidoc Am|OP *|newGVOP|I32 type|I32 flags|GV *gv

Constructs, checks, and returns an op of any type that involves an
embedded reference to a GV.  C<type> is the opcode.  C<flags> gives the
eight bits of C<op_flags>.  C<gv> identifies the GV that the op should
reference; calling this function does not transfer ownership of any
reference to it.

=cut
*/

OP *
Perl_newGVOP(pTHX_ I32 type, I32 flags, GV *gv)
{
    PERL_ARGS_ASSERT_NEWGVOP;

#ifdef USE_ITHREADS
    return newPADOP(type, flags, SvREFCNT_inc_simple_NN(gv));
#else
    return newSVOP(type, flags, SvREFCNT_inc_simple_NN(gv));
#endif
}

/*
=for apidoc Am|OP *|newPVOP|I32 type|I32 flags|char *pv

Constructs, checks, and returns an op of any type that involves an
embedded C-level pointer (PV).  C<type> is the opcode.  C<flags> gives
the eight bits of C<op_flags>.  C<pv> supplies the C-level pointer.
Depending on the op type, the memory referenced by C<pv> may be freed
when the op is destroyed.  If the op is of a freeing type, C<pv> must
have been allocated using C<PerlMemShared_malloc>.

=cut
*/

OP *
Perl_newPVOP(pTHX_ I32 type, I32 flags, char *pv)
{
    dVAR;
    PVOP *pvop;
    const bool utf8 = cBOOL(flags & SVf_UTF8);

    flags &= ~SVf_UTF8;

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_PVOP_OR_SVOP
	|| type == OP_RUNCV || type == OP_CUSTOM
	|| (PL_opargs[type] & OA_CLASS_MASK) == OA_LOOPEXOP);

    NewOp(1101, pvop, 1, PVOP);
    OpTYPE_set(pvop, type);
    pvop->op_pv = pv;
    pvop->op_next = (OP*)pvop;
    pvop->op_flags = (U8)flags;
    pvop->op_private = utf8 ? OPpPV_IS_UTF8 : 0;
    if (PL_opargs[type] & OA_RETSCALAR)
	scalar((OP*)pvop);
    if (PL_opargs[type] & OA_TARGET)
	pvop->op_targ = pad_alloc(type, SVs_PADTMP);
    return CHECKOP(type, pvop);
}

void
Perl_package(pTHX_ OP *o)
{
    SV *const sv = cSVOPo->op_sv;

    PERL_ARGS_ASSERT_PACKAGE;

    SAVEGENERICSV(PL_curstash);
    save_item(PL_curstname);

    PL_curstash = (HV *)SvREFCNT_inc(gv_stashsv(sv, GV_ADD));

    sv_setsv(PL_curstname, sv);

    PL_hints |= HINT_BLOCK_SCOPE;
    PL_parser->copline = NOLINE;

    op_free(o);
}

void
Perl_package_version( pTHX_ OP *v )
{
    U32 savehints = PL_hints;
    PERL_ARGS_ASSERT_PACKAGE_VERSION;
    PL_hints &= ~HINT_STRICT_VARS;
    sv_setsv( GvSV(gv_fetchpvs("VERSION", GV_ADDMULTI, SVt_PV)), cSVOPx(v)->op_sv );
    PL_hints = savehints;
    op_free(v);
}

void
Perl_utilize(pTHX_ int aver, I32 floor, OP *version, OP *idop, OP *arg)
{
    OP *pack;
    OP *imop;
    OP *veop;
    SV *use_version = NULL;

    PERL_ARGS_ASSERT_UTILIZE;

    if (ISNT_TYPE(idop, CONST))
	Perl_croak(aTHX_ "Module name must be constant");

    veop = NULL;

    if (version) {
	SV * const vesv = ((SVOP*)version)->op_sv;

	if (!arg && !SvNIOKp(vesv)) {
	    arg = version;
	}
	else {
	    OP *pack;
	    SV *meth;

	    if (ISNT_TYPE(version, CONST) || !SvNIOKp(vesv))
		Perl_croak(aTHX_ "Version number must be a constant number");

	    /* Make copy of idop so we don't free it twice */
	    pack = newSVOP(OP_CONST, 0, newSVsv(((SVOP*)idop)->op_sv));

	    /* Fake up a method call to VERSION */
	    meth = newSVpvs_share("VERSION");
	    veop = op_convert_list(OP_ENTERSUB, OPf_STACKED|OPf_SPECIAL,
			    op_append_elem(OP_LIST,
					op_prepend_elem(OP_LIST, pack, version),
					newMETHOP_named(OP_METHOD_NAMED, 0, meth)));
	}
    }

    /* Fake up an import/unimport */
    if (arg && IS_TYPE(arg, STUB)) {
	imop = arg;		/* no import on explicit () */
    }
    else if (SvNIOKp(((SVOP*)idop)->op_sv)) {
	imop = NULL;		/* use 5.0; */
	if (aver)
	    use_version = ((SVOP*)idop)->op_sv;
	else
	    idop->op_private |= OPpCONST_NOVER;
    }
    else {
	SV *meth;

	/* Make copy of idop so we don't free it twice */
	pack = newSVOP(OP_CONST, 0, newSVsv(((SVOP*)idop)->op_sv));

	/* Fake up a method call to import/unimport */
	meth = aver
	    ? newSVpvs_share("import") : newSVpvs_share("unimport");
	imop = op_convert_list(OP_ENTERSUB, OPf_STACKED|OPf_SPECIAL,
		       op_append_elem(OP_LIST,
				   op_prepend_elem(OP_LIST, pack, arg),
				   newMETHOP_named(OP_METHOD_NAMED, 0, meth)
		       ));
    }

    /* Fake up the BEGIN {}, which does its thing immediately. */
    newATTRSUB(floor,
	newSVOP(OP_CONST, 0, newSVpvs_share("BEGIN")),
	NULL,
	NULL,
	op_append_elem(OP_LINESEQ,
	    op_append_elem(OP_LINESEQ,
	        newSTATEOP(0, NULL, newUNOP(OP_REQUIRE, 0, idop)),
	        newSTATEOP(0, NULL, veop)),
	    newSTATEOP(0, NULL, imop) ));

    if (use_version) {
	/* Enable the
	 * feature bundle that corresponds to the required version. */
	use_version = sv_2mortal(new_version(use_version));
	S_enable_feature_bundle(aTHX_ use_version);

	/* If a version >= 5.11.0 is requested, strictures are on by default!
           TODO:
           This needs to be replaced by a single bit to denote argless default
           import vs argful special import. */
	if (vcmp(use_version,
		 sv_2mortal(upg_version(newSVnv(5.011000), FALSE))) >= 0) {
	    if (!(PL_hints & HINT_EXPLICIT_STRICT_REFS))
		PL_hints |= HINT_STRICT_REFS;
	    if (!(PL_hints & HINT_EXPLICIT_STRICT_SUBS))
		PL_hints |= HINT_STRICT_SUBS;
	    if (!(PL_hints & HINT_EXPLICIT_STRICT_VARS))
		PL_hints |= HINT_STRICT_VARS;
            /* use strict names >= use 5.026, hashpairs >= use 5.027 */
#ifdef USE_CPERL
            if (vcmp(use_version,
                     sv_2mortal(upg_version(newSVnv(5.026000), FALSE))) >= 0) {
# if defined(HINT_STRICT_NAMES) && HINT_STRICT_NAMES
                if (!(PL_hints & HINT_EXPLICIT_STRICT_REFS))
                    PL_hints |= HINT_STRICT_NAMES;
# endif
                if (vcmp(use_version,
                         sv_2mortal(upg_version(newSVnv(5.027000), FALSE))) >= 0) {
                    if (!(PL_hints & HINT_EXPLICIT_STRICT_REFS))
                        PL_hints |= HINT_STRICT_HASHPAIRS;
                }
            }
#endif
        }
	/* otherwise they are off */
	else {
	    if (!(PL_hints & HINT_EXPLICIT_STRICT_REFS))
		PL_hints &= ~HINT_STRICT_REFS;
	    if (!(PL_hints & HINT_EXPLICIT_STRICT_SUBS))
		PL_hints &= ~HINT_STRICT_SUBS;
	    if (!(PL_hints & HINT_EXPLICIT_STRICT_VARS))
		PL_hints &= ~HINT_STRICT_VARS;
	}
    }

    /* The "did you use incorrect case?" warning used to be here.
     * The problem is that on case-insensitive filesystems one
     * might get false positives for "use" (and "require"):
     * "use Strict" or "require CARP" will work.  This causes
     * portability problems for the script: in case-strict
     * filesystems the script will stop working.
     *
     * The "incorrect case" warning checked whether "use Foo"
     * imported "Foo" to your namespace, but that is wrong, too:
     * there is no requirement nor promise in the language that
     * a Foo.pm should or would contain anything in package "Foo".
     *
     * There is very little Configure-wise that can be done, either:
     * the case-sensitivity of the build filesystem of Perl does not
     * help in guessing the case-sensitivity of the runtime environment.
     */

    PL_hints |= HINT_BLOCK_SCOPE;
    PL_parser->copline = NOLINE;
    COP_SEQMAX_INC; /* Purely for B::*'s benefit */
}

/*
=head1 Embedding Functions

=for apidoc load_module

Loads the module whose name is pointed to by the string part of C<name>.
Note that the actual module name, not its filename, should be given.
Eg, "Foo::Bar" instead of "Foo/Bar.pm". ver, if specified and not NULL,
provides version semantics similar to C<use Foo::Bar VERSION>. The optional
trailing arguments can be used to specify arguments to the module's C<import()>
method, similar to C<use Foo::Bar VERSION LIST>; their precise handling depends
on the flags. The flags argument is a bitwise-ORed collection of any of
C<PERL_LOADMOD_DENY>, C<PERL_LOADMOD_NOIMPORT>, or C<PERL_LOADMOD_IMPORT_OPS>
(or 0 for no flags).

If C<PERL_LOADMOD_NOIMPORT> is set, the module is loaded as if with an empty
import list, as in C<use Foo::Bar ()>; this is the only circumstance in which
the trailing optional arguments may be omitted entirely. Otherwise, if
C<PERL_LOADMOD_IMPORT_OPS> is set, the trailing arguments must consist of
exactly one C<OP*>, containing the op tree that produces the relevant import
arguments. Otherwise, the trailing arguments must all be C<SV*> values that
will be used as import arguments; and the list must be terminated with C<(SV*)
NULL>. If neither C<PERL_LOADMOD_NOIMPORT> nor C<PERL_LOADMOD_IMPORT_OPS> is
set, the trailing C<NULL> pointer is needed even if no import arguments are
desired. The reference count for each specified C<SV*> argument is
decremented. In addition, the C<name> argument is modified.

If C<PERL_LOADMOD_DENY> is set, the module is loaded as if with C<no> rather
than C<use>.

=cut */

void
Perl_load_module(pTHX_ U32 flags, SV *name, SV *ver, ...)
{
    va_list args;

    PERL_ARGS_ASSERT_LOAD_MODULE;

    va_start(args, ver);
    vload_module(flags, name, ver, &args);
    va_end(args);
}

#ifdef PERL_IMPLICIT_CONTEXT
void
Perl_load_module_nocontext(U32 flags, SV *name, SV *ver, ...)
{
    dTHX;
    va_list args;
    PERL_ARGS_ASSERT_LOAD_MODULE_NOCONTEXT;
    va_start(args, ver);
    vload_module(flags, name, ver, &args);
    va_end(args);
}
#endif

void
Perl_vload_module(pTHX_ U32 flags, SV *name, SV *ver, va_list *args)
{
    OP *veop, *imop;
    OP * const modname = newSVOP(OP_CONST, 0, name);

    PERL_ARGS_ASSERT_VLOAD_MODULE;

    modname->op_private |= OPpCONST_BARE;
    if (ver) {
	veop = newSVOP(OP_CONST, 0, ver);
    }
    else
	veop = NULL;
    if (flags & PERL_LOADMOD_NOIMPORT) {
	imop = sawparens(newNULLLIST());
    }
    else if (flags & PERL_LOADMOD_IMPORT_OPS) {
	imop = va_arg(*args, OP*);
    }
    else {
	SV *sv;
	imop = NULL;
	sv = va_arg(*args, SV*);
	while (sv) {
	    imop = op_append_elem(OP_LIST, imop, newSVOP(OP_CONST, 0, sv));
	    sv = va_arg(*args, SV*);
	}
    }

    /* utilize() fakes up a BEGIN { require ..; import ... }, so make sure
     * that it has a PL_parser to play with while doing that, and also
     * that it doesn't mess with any existing parser, by creating a tmp
     * new parser with lex_start(). This won't actually be used for much,
     * since pp_require() will create another parser for the real work.
     * The ENTER/LEAVE pair protect callers from any side effects of use.  */

    ENTER;
    SAVEVPTR(PL_curcop);
    lex_start(NULL, NULL, LEX_START_SAME_FILTER);
    utilize(!(flags & PERL_LOADMOD_DENY), start_subparse(FALSE, 0),
	    veop, modname, imop);
    LEAVE;
}

PERL_STATIC_INLINE OP *
S_new_entersubop(pTHX_ GV *gv, OP *arg)
{
    PERL_ARGS_ASSERT_NEW_ENTERSUBOP;
    return newUNOP(OP_ENTERSUB, OPf_STACKED,
		   newLISTOP(OP_LIST, 0, arg,
			     newUNOP(OP_RV2CV, 0,
				     newGVOP(OP_GV, 0, gv))));
}

OP *
Perl_dofile(pTHX_ OP *term, I32 force_builtin)
{
    OP *doop;
    GV *gv;

    PERL_ARGS_ASSERT_DOFILE;

    if (!force_builtin && (gv = gv_override("do", 2))) {
	doop = new_entersubop(gv, term);
    }
    else {
	doop = newUNOP(OP_DOFILE, 0, scalar(term));
    }
    return doop;
}

/*
=head1 Optree construction

=for apidoc Am|OP *|newSLICEOP|I32 flags|OP *subscript|OP *listval

Constructs, checks, and returns an C<lslice> (list slice) op.  C<flags>
gives the eight bits of C<op_flags>, except that C<OPf_KIDS> will
be set automatically, and, shifted up eight bits, the eight bits of
C<op_private>, except that the bit with value 1 or 2 is automatically
set as required.  C<listval> and C<subscript> supply the parameters of
the slice; they are consumed by this function and become part of the
constructed op tree.

=cut
*/

OP *
Perl_newSLICEOP(pTHX_ I32 flags, OP *subscript, OP *listval)
{
    return newBINOP(OP_LSLICE, flags,
	    list(force_list(subscript, 1)),
	    list(force_list(listval,   1)) );
}

#define ASSIGN_LIST   1
#define ASSIGN_REF    2

static I32
S_assignment_type(pTHX_ const OP *o)
{
    unsigned type;
    U8 flags;
    U8 ret;

    if (!o)
	return TRUE;

    if (IS_TYPE(o, SREFGEN))
    {
	OP * const kid = OpFIRST(OpFIRST(o));
	type = kid->op_type;
	flags = o->op_flags | kid->op_flags;
	if (!(flags & OPf_PARENS)
	  && (IS_TYPE(kid, RV2AV) || IS_TYPE(kid, PADAV) ||
	      IS_TYPE(kid, RV2HV) || IS_TYPE(kid, PADHV) ))
	    return ASSIGN_REF;
	ret = ASSIGN_REF;
    } else {
        if ((IS_NULL_OP(o)) && (OpKIDS(o)))
	    o = OpFIRST(o);
	flags = o->op_flags;
	type = o->op_type;
	ret = 0;
    }

    if (type == OP_COND_EXPR) {
        OP * const sib = OpSIBLING(OpFIRST(o));
        const I32 t = assignment_type(sib);
        const I32 f = assignment_type(OpSIBLING(sib));

	if (t == ASSIGN_LIST && f == ASSIGN_LIST)
	    return ASSIGN_LIST;
	if ((t == ASSIGN_LIST) ^ (f == ASSIGN_LIST))
	    yyerror("Assignment to both a list and a scalar");
	return FALSE;
    }

    if (type == OP_LIST &&
	(flags & OPf_WANT) == OPf_WANT_SCALAR &&
	o->op_private & OPpLVAL_INTRO)
	return ret;

    if (type == OP_LIST     || flags & OPf_PARENS  ||
	type == OP_RV2AV    || type == OP_RV2HV    ||
	type == OP_ASLICE   || type == OP_HSLICE   ||
        type == OP_KVASLICE || type == OP_KVHSLICE || type == OP_REFGEN ||
        type == OP_PADAV    || type == OP_PADHV)
	return TRUE;

    if (type == OP_RV2SV)
	return ret;

    /* $self->field for @field or %field */
    else if (type == OP_ENTERSUB) {
        if (method_field_type((OP*)o) > METHOD_FIELD_SCALAR)
            return ASSIGN_LIST;
    }

    return ret;
}

static OP *
S_newONCEOP(pTHX_ OP *initop, OP *padop)
{
    const PADOFFSET target = padop->op_targ;
    OP *const other = newOP(OP_PADSV,
			    padop->op_flags
			    | ((padop->op_private & ~OPpLVAL_INTRO) << 8));
    OP *const first = newOP(OP_NULL, 0);
    OP *const nullop = newCONDOP(0, first, initop, other);
    /* XXX targlex disabled for now; see ticket #124160
	newCONDOP(0, first, S_maybe_targlex(aTHX_ initop), other);
     */
    OP *const condop = first->op_next;

    OpTYPE_set(condop, OP_ONCE);
    other->op_targ = target;
    nullop->op_flags |= OPf_WANT_SCALAR;

    /* Store the initializedness of state vars in a separate
       pad entry.  */
    condop->op_targ =
      pad_add_name_pvn("$", 1, padadd_NO_DUP_CHECK|padadd_STATE, 0, 0);
    /* hijacking PADSTALE for uninitialized state variables */
    SvPADSTALE_on(PAD_SVl(condop->op_targ));

    return nullop;
}

/*
=for apidoc Am|OP *|newASSIGNOP|I32 flags|OP *left|I32 optype|OP *right

Constructs, checks, and returns an assignment op.  C<left> and C<right>
supply the parameters of the assignment; they are consumed by this
function and become part of the constructed op tree.

If C<optype> is C<OP_ANDASSIGN>, C<OP_ORASSIGN>, or C<OP_DORASSIGN>, then
a suitable conditional optree is constructed.  If C<optype> is the opcode
of a binary operator, such as C<OP_BIT_OR>, then an op is constructed that
performs the binary operation and assigns the result to the left argument.
Either way, if C<optype> is non-zero then C<flags> has no effect.

If C<optype> is zero, then a plain scalar or list assignment is
constructed.  Which type of assignment it is is automatically determined.
C<flags> gives the eight bits of C<op_flags>, except that C<OPf_KIDS>
will be set automatically, and, shifted up eight bits, the eight bits
of C<op_private>, except that the bit with value 1 or 2 is automatically
set as required.

=cut
*/

OP *
Perl_newASSIGNOP(pTHX_ I32 flags, OP *left, I32 optype, OP *right)
{
    OP *o;
    I32 assign_type;

    if (optype) {
	if (optype == OP_ANDASSIGN || optype == OP_ORASSIGN || optype == OP_DORASSIGN) {
            right = scalar(right);
	    return newLOGOP(optype, 0,
		op_lvalue(scalar(left), optype),
		newBINOP(OP_SASSIGN, OPpASSIGN_BACKWARDS<<8, right, right));
	}
	else {
	    return newBINOP(optype, OPf_STACKED,
		op_lvalue(scalar(left), optype), scalar(right));
	}
    }

    if ((assign_type = assignment_type(left)) == ASSIGN_LIST) {
	OP *state_var_op = NULL;
	static const char no_list_state[] = "Initialization of state variables"
	    " in list currently forbidden";
	OP *curop;

	if (IS_TYPE(left, ASLICE) || IS_TYPE(left, HSLICE))
	    left->op_private &= ~ OPpSLICEWARNING;

	PL_modcount = 0;
	left = op_lvalue(left, OP_AASSIGN);
	curop = list(force_list(left, 1));
	o = newBINOP(OP_AASSIGN, flags, list(force_list(right, 1)), curop);
	o->op_private = (U8)(0 | (flags >> 8));

	if (OP_TYPE_IS_OR_WAS(left, OP_LIST)) {
	    OP* lop = OpFIRST(left), *vop, *eop;
	    if (  !(left->op_flags & OPf_PARENS) &&
		    lop->op_type == OP_PUSHMARK &&
		    (vop = OpSIBLING(lop)) &&
		    (vop->op_type == OP_PADAV || vop->op_type == OP_PADHV) &&
		    !(vop->op_flags & OPf_PARENS) &&
		    (vop->op_private & (OPpLVAL_INTRO|OPpPAD_STATE)) ==
			(OPpLVAL_INTRO|OPpPAD_STATE) &&
		    (eop = OpSIBLING(vop)) &&
                    IS_TYPE(eop, ENTERSUB) &&
		    !OpHAS_SIBLING(eop)) {
		state_var_op = vop;
	    } else {
                while (lop) {
                    if (OP_IS_PADVAR(lop->op_type)
                        && (lop->op_private & OPpPAD_STATE))
                        yyerror(no_list_state);
                    lop = OpSIBLING(lop);
                }
	    }
	}
	else if (  (left->op_private & OPpLVAL_INTRO)
                && (left->op_private & OPpPAD_STATE)
		&& OP_IS_PADVAR(left->op_type) )
        {
		/* All single variable list context state assignments, hence
		   state ($a) = ...
		   (state $a) = ...
		   state @a = ...
		   state (@a) = ...
		   (state @a) = ...
		   state %a = ...
		   state (%a) = ...
		   (state %a) = ...
		*/
                if (left->op_flags & OPf_PARENS)
		    yyerror(no_list_state);
		else
		    state_var_op = left;
	}

        /* optimise @a = split(...) into:
         * @{expr}:              split(..., @{expr}) (where @a is not flattened)
         * @a, my @a, local @a:  split(...)          (where @a is attached to
         *                                            the split op itself)
         */

	if (right && IS_TYPE(right, SPLIT)
            && !(right->op_private & OPpSPLIT_ASSIGN)) {
            OP *gvop = NULL;

            if ( (IS_TYPE(left, RV2AV) && IS_TYPE((gvop = OpFIRST(left)), GV))
               || IS_TYPE(left, PADAV) ) {
                /* @pkg or @lex, but not 'local @pkg' nor 'my @lex' */
                OP *tmpop;
                if (gvop) {
#ifdef USE_ITHREADS
                    ((PMOP*)right)->op_pmreplrootu.op_pmtargetoff
                        = cPADOPx(gvop)->op_padix;
                    cPADOPx(gvop)->op_padix = 0;	/* steal it */
#else
                    ((PMOP*)right)->op_pmreplrootu.op_pmtargetgv
                        = MUTABLE_GV(cSVOPx(gvop)->op_sv);
                    cSVOPx(gvop)->op_sv = NULL;	/* steal it */
#endif
                    right->op_private |=
                        left->op_private & OPpOUR_INTRO;
                }
                else {
                    ((PMOP*)right)->op_pmreplrootu.op_pmtargetoff = left->op_targ;
                    left->op_targ = 0;	/* steal it */
                    right->op_private |= OPpSPLIT_LEX;
                }
                right->op_private |= left->op_private & OPpLVAL_INTRO;

            detach_split:
                tmpop = OpFIRST(OpFIRST(o)); /* to pushmark */
                /* detach rest of siblings from o subtree,
                 * and free subtree */
                op_sibling_splice(OpFIRST(o), tmpop, 1, NULL);
                op_free(o);			/* blow off assign */
                right->op_private |= OPpSPLIT_ASSIGN;
                right->op_flags &= ~OPf_WANT;
                /* "I don't know and I don't care." */
                return right;
            }
            else if (IS_TYPE(left, RV2AV)) {
                /* @{expr} */

                OP *pushop = OpFIRST(OpLAST(o));
                assert(OpSIBLING(pushop) == left);
                /* Detach the array ...  */
                op_sibling_splice(OpLAST(o), pushop, 1, NULL);
                /* ... and attach it to the split.  */
                op_sibling_splice(right, OpLAST(right), 0, left);
                right->op_flags |= OPf_STACKED;
                /* Detach split and expunge aassign as above.  */
                goto detach_split;
            }
            else if (PL_modcount < RETURN_UNLIMITED_NUMBER
                  && IS_CONST_OP(OpLAST(right)))
            {
                /* convert split(...,0) to split(..., PL_modcount+1) */
                SV ** const svp = &((SVOP*)OpLAST(right))->op_sv;
                SV * const sv = *svp;
                if (SvIOK(sv) && SvIVX(sv) == 0) {
                    if (right->op_private & OPpSPLIT_IMPLIM) {
                        /* our own SV, created in ck_split */
                        SvREADONLY_off(sv);
                        sv_setiv(sv, PL_modcount+1);
                    }
                    else {
                        /* SV may belong to someone else */
                        SvREFCNT_dec(sv);
                        *svp = newSViv(PL_modcount+1);
                    }
                }
            }
	}

	if (state_var_op)
	    o = S_newONCEOP(aTHX_ o, state_var_op);
	return o;
    }
    if (assign_type == ASSIGN_REF)
	return newBINOP(OP_REFASSIGN, flags, scalar(right), left);
    if (!right)
	right = newOP(OP_UNDEF, 0);
    if (IS_TYPE(right, READLINE)) {
	right->op_flags |= OPf_STACKED;
	return newBINOP(OP_NULL, flags, op_lvalue(scalar(left), OP_SASSIGN),
		scalar(right));
    }
    else {
	o = newBINOP(OP_SASSIGN, flags,
                     scalar(right), op_lvalue(scalar(left), OP_SASSIGN) );
    }
    return o;
}

/*
=for apidoc Am|OP *|newSTATEOP|I32 flags|char *label|OP *o

Constructs a state op (COP).  The state op is normally a C<nextstate> op,
but will be a C<dbstate> op if debugging is enabled for currently-compiled
code.  The state op is populated from C<PL_curcop> (or C<PL_compiling>).
If C<label> is non-null, it supplies the name of a label to attach to
the state op; this function takes ownership of the memory pointed at by
C<label>, and will free it.  C<flags> gives the eight bits of C<op_flags>
for the state op.

If C<o> is null, the state op is returned.  Otherwise the state op is
combined with C<o> into a C<lineseq> list op, which is returned.  C<o>
is consumed by this function and becomes part of the returned op tree.

=cut
*/

OP *
Perl_newSTATEOP(pTHX_ I32 flags, char *label, OP *o)
{
    dVAR;
    const U32 seq = intro_my();
    const U32 utf8 = flags & SVf_UTF8;
    COP *cop;

    PL_parser->parsed_sub = 0;

    flags &= ~SVf_UTF8;

    NewOp(1101, cop, 1, COP);
    if (PERLDB_LINE && CopLINE(PL_curcop) && PL_curstash != PL_debstash) {
        OpTYPE_set(cop, OP_DBSTATE);
    }
    else {
        OpTYPE_set(cop, OP_NEXTSTATE);
    }
    cop->op_flags = (U8)flags;
    CopHINTS_set(cop, PL_hints);
#ifdef VMS
    if (VMSISH_HUSHED) cop->op_private |= OPpHUSH_VMSISH;
#endif
    cop->op_next = (OP*)cop;

    cop->cop_seq = seq;
    cop->cop_warnings = DUP_WARNINGS(PL_curcop->cop_warnings);
    CopHINTHASH_set(cop, cophh_copy(CopHINTHASH_get(PL_curcop)));
    if (label) {
	cop_store_label(cop, label, strlen(label), utf8);

	PL_hints |= HINT_BLOCK_SCOPE;
	/* It seems that we need to defer freeing this pointer, as other parts
	   of the grammar end up wanting to copy it after this op has been
	   created. */
	SAVEFREEPV(label);
    }

    if (PL_parser->preambling != NOLINE) {
        CopLINE_set(cop, PL_parser->preambling);
        PL_parser->copline = NOLINE;
    }
    else if (PL_parser->copline == NOLINE)
        CopLINE_set(cop, CopLINE(PL_curcop));
    else {
	CopLINE_set(cop, PL_parser->copline);
	PL_parser->copline = NOLINE;
    }
#ifdef USE_ITHREADS
    CopFILE_set(cop, CopFILE(PL_curcop));	/* XXX share in a pvtable? */
#else
    CopFILEGV_set(cop, CopFILEGV(PL_curcop));
#endif
    CopSTASH_set(cop, PL_curstash);

    if (IS_TYPE(cop, DBSTATE)) {
	/* This line can have a breakpoint - store the cop as IV */
	AV *av = CopFILEAVx(PL_curcop);
	if (av) {
	    SV * const * const svp = av_fetch(av, CopLINE(cop), FALSE);
	    if (svp && *svp != UNDEF ) {
		(void)SvIOK_on(*svp);
		SvIV_set(*svp, PTR2IV(cop));
	    }
	}
    }

    if (flags & OPf_SPECIAL)
	op_null((OP*)cop);
    return op_prepend_elem(OP_LINESEQ, (OP*)cop, o);
}

/*
=for apidoc Am|OP *|newLOGOP|I32 type|I32 flags|OP *first|OP *other

Constructs, checks, and returns a logical (flow control) op.  C<type>
is the opcode.  C<flags> gives the eight bits of C<op_flags>, except
that C<OPf_KIDS> will be set automatically, and, shifted up eight bits,
the eight bits of C<op_private>, except that the bit with value 1 is
automatically set.  C<first> supplies the expression controlling the
flow, and C<other> supplies the side (alternate) chain of ops; they are
consumed by this function and become part of the constructed op tree.

=cut
*/

OP *
Perl_newLOGOP(pTHX_ I32 type, I32 flags, OP *first, OP *other)
{
    PERL_ARGS_ASSERT_NEWLOGOP;

    return new_logop(type, flags, &first, &other);
}

static OP *
S_search_const(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_SEARCH_CONST;

    switch (o->op_type) {
	case OP_CONST:
	    return o;
	case OP_NULL:
	    if (OpKIDS(o))
		return search_const(OpFIRST(o));
	    break;
        case OP_PADSV: /* search_const is called immed. from newLOGOP/CONDOP.
                          there was no time to constant fold it yet. */
            if (o->op_targ && SvREADONLY(PAD_SVl(o->op_targ))) {
		o = ck_pad(o);
                return IS_CONST_OP(o) ? o : NULL;
            }
            break;
	case OP_LEAVE:
	case OP_SCOPE:
	case OP_LINESEQ:
	{
	    OP *kid;
	    if (!OpKIDS(o))
		return NULL;
	    kid = OpFIRST(o);
	    do {
		switch (kid->op_type) {
		    case OP_ENTER:
		    case OP_NULL:
		    case OP_NEXTSTATE:
		    case OP_SIGNATURE:
			kid = OpSIBLING(kid);
			break;
		    default:
			if (kid != OpLAST(o))
			    return NULL;
			goto last;
		}
	    } while (kid);
	    if (!kid)
		kid = OpLAST(o);
          last:
	    return search_const(kid);
	}
    }

    return NULL;
}

static OP *
S_new_logop(pTHX_ I32 type, I32 flags, OP** firstp, OP** otherp)
{
    dVAR;
    LOGOP *logop;
    OP *o;
    OP *first;
    OP *other;
    OP *cstop = NULL;
    int prepend_not = 0;

    PERL_ARGS_ASSERT_NEW_LOGOP;

    first = *firstp;
    other = *otherp;

    /* [perl #59802]: Warn about things like "return $a or $b", which
       is parsed as "(return $a) or $b" rather than "return ($a or
       $b)".  NB: This also applies to xor, which is why we do it
       here.
     */
    switch (first->op_type) {
    case OP_NEXT:
    case OP_LAST:
    case OP_REDO:
	/* XXX: Perhaps we should emit a stronger warning for these.
	   Even with the high-precedence operator they don't seem to do
	   anything sensible.

	   But until we do, fall through here.
         */
    case OP_RETURN:
    case OP_EXIT:
    case OP_DIE:
    case OP_GOTO:
	/* XXX: Currently we allow people to "shoot themselves in the
	   foot" by explicitly writing "(return $a) or $b".

	   Warn unless we are looking at the result from folding or if
	   the programmer explicitly grouped the operators like this.
	   The former can occur with e.g.

		use constant FEATURE => ( $] >= ... );
		sub { not FEATURE and return or do_stuff(); }
	 */
	if (!first->op_folded && !(first->op_flags & OPf_PARENS))
	    Perl_ck_warner(aTHX_ packWARN(WARN_SYNTAX),
	                   "Possible precedence issue with control flow operator");
	/* XXX: Should we optimze this to "return $a;" (i.e. remove
	   the "or $b" part)?
	*/
	break;
    }

    if (type == OP_XOR)		/* Not short circuit, but here by precedence. */
	return newBINOP(type, flags, scalar(first), scalar(other));

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_LOGOP
	|| type == OP_CUSTOM);

    scalarboolean(first);

    /* search for a constant op that could let us fold the test */
    if ((cstop = search_const(first))) {
	if (cstop->op_private & OPpCONST_STRICT)
	    no_bareword_allowed(cstop);
	else if ((cstop->op_private & OPpCONST_BARE))
		Perl_ck_warner(aTHX_ packWARN(WARN_BAREWORD),
                               "Bareword found in conditional");
	if ((type == OP_AND &&  SvTRUE(((SVOP*)cstop)->op_sv)) ||
	    (type == OP_OR  && !SvTRUE(((SVOP*)cstop)->op_sv)) ||
	    (type == OP_DOR && !SvOK(((SVOP*)cstop)->op_sv))) {
            /* Elide the (constant) lhs, since it can't affect the outcome */
	    *firstp = NULL;
	    if (IS_CONST_OP(other))
		other->op_private |= OPpCONST_SHORTCIRCUIT;
	    op_free(first);
	    if (IS_TYPE(other, LEAVE))
		other = newUNOP(OP_NULL, OPf_SPECIAL, other);
	    else if (IS_TYPE(other, MATCH)
	          || IS_TYPE(other, SUBST)
	          || IS_TYPE(other, TRANSR)
	          || IS_TYPE(other, TRANS))
		/* Mark the op as being unbindable with =~ */
		other->op_flags |= OPf_SPECIAL;

	    other->op_folded = 1;
	    return other;
	}
	else {
            /* Elide the rhs, since the outcome is entirely determined by
             * the (constant) lhs */

	    /* check for C<my $x if 0>, or C<my($x,$y) if 0> */
	    const OP *o2 = other;
	    if ( ! (IS_TYPE(o2, LIST)
		    && ( o2 = OpFIRST(o2) )
		    && IS_TYPE(o2, PUSHMARK)
		    && ( o2 = OpSIBLING(o2)) )
	    )
		o2 = other;
	    if (IS_PADxV_OP(o2)
		&& o2->op_private & OPpLVAL_INTRO
		&& !(o2->op_private & OPpPAD_STATE))
	    {
		Perl_ck_warner_d(aTHX_ packWARN(WARN_DEPRECATED),
                                "Deprecated use of my() in false conditional. "
                                "This will be a fatal error in Perl 5.30");
	    }

	    *otherp = NULL;
	    if (IS_CONST_OP(cstop))
		cstop->op_private |= OPpCONST_SHORTCIRCUIT;
            op_free(other);
	    return first;
	}
    }
    else if (OpKIDS(first) && type != OP_DOR
	&& ckWARN(WARN_MISC)) /* [#24076] Don't warn for <FH> err FOO. */
    {
	const OP * const k1 = OpFIRST(first);
	const OP * const k2 = OpSIBLING(k1);
	OPCODE warnop = 0;
	switch (first->op_type)
	{
	case OP_NULL:
	    if (OP_TYPE_IS(k2, OP_READLINE)
                && OpSTACKED(k2) && OpWANT_SCALAR(k1)) /* k1? */
	    {
		warnop = k2->op_type;
	    }
	    break;

	case OP_SASSIGN:
	    if (IS_TYPE(k1, READDIR)
             || OP_TYPE_IS_OR_WAS_NN(k1, OP_GLOB)
             || IS_TYPE(k1, EACH)
             || IS_TYPE(k1, AEACH))
	    {
		warnop = (IS_NULL_OP(k1)
			  ? (OPCODE)k1->op_targ : k1->op_type);
	    }
	    break;
	}
	if (warnop) {
	    const line_t oldline = CopLINE(PL_curcop);
            /* This ensures that warnings are reported at the first line
               of the construction, not the last.  */
	    CopLINE_set(PL_curcop, PL_parser->copline);
	    Perl_warner(aTHX_ packWARN(WARN_MISC),
		 "Value of %s%s can be \"0\"; test with defined()",
		 PL_op_desc[warnop],
		 ((warnop == OP_READLINE || warnop == OP_GLOB)
		  ? " construct" : "() operator"));
	    CopLINE_set(PL_curcop, oldline);
	}
    }

    if (UNLIKELY(!other))
	return first;

    /* optimize AND and OR ops that have NOTs as children */
    if (IS_TYPE(first, NOT)
        && OpKIDS(first)
        && (OpSPECIAL(first) /* unless ($x) { } */
            || IS_TYPE(other, NOT))  /* if (!$x && !$y) { } */
        ) {
        if (type == OP_AND || type == OP_OR) {
            if (type == OP_AND)
                type = OP_OR;
            else
                type = OP_AND;
            op_null(first);
            if (IS_TYPE(other, NOT)) { /* !a AND|OR !b => !(a OR|AND b) */
                op_null(other);
                prepend_not = 1; /* prepend a NOT op later */
            }
        }
    }

    logop = S_alloc_LOGOP(aTHX_ type, first, LINKLIST(other));
    logop->op_flags |= (U8)flags;
    logop->op_private = (U8)(1 | (flags >> 8));

    /* establish postfix order */
    OpNEXT(logop) = LINKLIST(first);
    OpNEXT(first) = (OP*)logop;
    assert(!OpHAS_SIBLING(first));
    op_sibling_splice((OP*)logop, first, 0, other);

    CHECKOP(type,logop);

    o = newUNOP(prepend_not ? OP_NOT : OP_NULL,
		PL_opargs[type] & OA_RETSCALAR ? OPf_WANT_SCALAR : 0,
		(OP*)logop);
    OpNEXT(other) = o;

    return o;
}

/*
=for apidoc Am|OP *|newCONDOP|I32 flags|OP *first|OP *trueop|OP *falseop

Constructs, checks, and returns a conditional-expression (C<cond_expr>)
op.  C<flags> gives the eight bits of C<op_flags>, except that C<OPf_KIDS>
will be set automatically, and, shifted up eight bits, the eight bits of
C<op_private>, except that the bit with value 1 is automatically set.
C<first> supplies the expression selecting between the two branches,
and C<trueop> and C<falseop> supply the branches; they are consumed by
this function and become part of the constructed op tree.

=cut
*/

OP *
Perl_newCONDOP(pTHX_ I32 flags, OP *first, OP *trueop, OP *falseop)
{
    dVAR;
    LOGOP *logop;
    OP *start;
    OP *o;
    OP *cstop;

    PERL_ARGS_ASSERT_NEWCONDOP;

    if (!falseop)
	return newLOGOP(OP_AND, 0, first, trueop);
    if (!trueop)
	return newLOGOP(OP_OR, 0, first, falseop);

    scalarboolean(first);
    if ((cstop = search_const(first))) {
	/* Left or right arm of the conditional?  */
	const bool left = SvTRUE(((SVOP*)cstop)->op_sv);
	OP *live = left ? trueop : falseop;
	OP *const dead = left ? falseop : trueop;
        if (cstop->op_private & OPpCONST_BARE &&
	    cstop->op_private & OPpCONST_STRICT) {
	    no_bareword_allowed(cstop);
	}
        op_free(first);
        op_free(dead);
	if (IS_TYPE(live, LEAVE))
	    live = newUNOP(OP_NULL, OPf_SPECIAL, live);
	else if (IS_TYPE(live, MATCH) || IS_TYPE(live, SUBST)
              || IS_TYPE(live, TRANS) || IS_TYPE(live, TRANSR))
	    /* Mark the op as being unbindable with =~ */
	    live->op_flags |= OPf_SPECIAL;
	live->op_folded = 1;
	return live;
    }
    logop = S_alloc_LOGOP(aTHX_ OP_COND_EXPR, first, LINKLIST(trueop));
    logop->op_flags |= (U8)flags;
    logop->op_private = (U8)(1 | (flags >> 8));
    logop->op_next = LINKLIST(falseop);

    CHECKOP(OP_COND_EXPR, /* that's logop->op_type */
	    logop);

    /* establish postfix order */
    start = LINKLIST(first);
    OpNEXT(first) = (OP*)logop;

    /* make first, trueop, falseop siblings */
    op_sibling_splice((OP*)logop, first,  0, trueop);
    op_sibling_splice((OP*)logop, trueop, 0, falseop);

    o = newUNOP(OP_NULL, 0, (OP*)logop);

    OpNEXT(trueop) = OpNEXT(falseop) = o;

    OpNEXT(o) = start;
    return o;
}

/*
=for apidoc Am|OP *|newRANGE|I32 flags|OP *left|OP *right

Constructs and returns a C<range> op, with subordinate C<flip> and
C<flop> ops.  C<flags> gives the eight bits of C<op_flags> for the
C<flip> op and, shifted up eight bits, the eight bits of C<op_private>
for both the C<flip> and C<range> ops, except that the bit with value
1 is automatically set.  C<left> and C<right> supply the expressions
controlling the endpoints of the range; they are consumed by this function
and become part of the constructed op tree.

=cut
*/

OP *
Perl_newRANGE(pTHX_ I32 flags, OP *left, OP *right)
{
    LOGOP *range;
    OP *flip;
    OP *flop;
    OP *leftstart;
    OP *o;
    const U32 padflag = padadd_NO_DUP_CHECK|padadd_STATE;

    PERL_ARGS_ASSERT_NEWRANGE;

    range = S_alloc_LOGOP(aTHX_ OP_RANGE, left, LINKLIST(right));
    range->op_flags = OPf_KIDS;
    leftstart = LINKLIST(left);
    range->op_private = (U8)(1 | (flags >> 8));

    /* make left and right siblings */
    op_sibling_splice((OP*)range, left, 0, right);

    OpNEXT(range) = (OP*)range;
    flip = newUNOP(OP_FLIP, flags, (OP*)range);
    flop = newUNOP(OP_FLOP, 0, flip);
    o = newUNOP(OP_NULL, 0, flop);
    LINKLIST(flop);
    OpNEXT(range) = leftstart;

    OpNEXT(left) = flip;
    OpNEXT(right) = flop;

    range->op_targ = pad_add_name_pvn("$", 1, padflag, 0, 0);
    sv_upgrade(PAD_SV(range->op_targ), SVt_PVNV);
    flip->op_targ = pad_add_name_pvn("$", 1, padflag, 0, 0);;
    sv_upgrade(PAD_SV(flip->op_targ), SVt_PVNV);
    SvPADTMP_on(PAD_SV(flip->op_targ));

    flip->op_private = IS_CONST_OP(left)  ? OPpFLIP_LINENUM : 0;
    flop->op_private = IS_CONST_OP(right) ? OPpFLIP_LINENUM : 0;

    /* check barewords before they might be optimized aways */
    if (flip->op_private && cSVOPx(left)->op_private & OPpCONST_STRICT)
	no_bareword_allowed(left);
    if (flop->op_private && cSVOPx(right)->op_private & OPpCONST_STRICT)
	no_bareword_allowed(right);

    OpNEXT(flip) = o;
    if (!flip->op_private || !flop->op_private)
	LINKLIST(o);		/* blow off optimizer unless constant */

    return o;
}

/*
=for apidoc Am|OP *|newLOOPOP|I32 flags|I32 debuggable|OP *expr|OP *block

Constructs, checks, and returns an op tree expressing a loop.  This is
only a loop in the control flow through the op tree; it does not have
the heavyweight loop structure that allows exiting the loop by C<last>
and suchlike.  C<flags> gives the eight bits of C<op_flags> for the
top-level op, except that some bits will be set automatically as required.
C<expr> supplies the expression controlling loop iteration, and C<block>
supplies the body of the loop; they are consumed by this function and
become part of the constructed op tree.  C<debuggable> is currently
unused and should always be 1.

=cut
*/

OP *
Perl_newLOOPOP(pTHX_ I32 flags, I32 debuggable PERL_UNUSED_DECL,
               OP *expr, OP *block)
{
    OP* listop;
    OP* o;
    const bool once = OP_TYPE_IS(block, OP_NULL) && OpSPECIAL(block);

    PERL_UNUSED_ARG(debuggable);

    if (expr) {
	if (once && (
              (IS_CONST_OP(expr) && !SvTRUE(((SVOP*)expr)->op_sv))
           || (  IS_TYPE(expr, NOT)
              && IS_CONST_OP(OpFIRST(expr))
	      && SvTRUE(cSVOPx_sv(OpFIRST(expr)))
	      )
	   ))
	    /* Return the block now, so that S_new_logop does not try to
	       fold it away. */
	    return block;	/* do {} while 0 does once */
	if (   IS_TYPE(expr, READLINE)
	    || IS_TYPE(expr, READDIR)
            || IS_TYPE(expr, GLOB)
            || IS_TYPE(expr, EACH) || IS_TYPE(expr, AEACH)
	    || OP_TYPE_IS_OR_WAS_NN(expr, OP_GLOB)) {
	    expr = newUNOP(OP_DEFINED, 0,
		newASSIGNOP(0, newDEFSVOP(), 0, expr) );
	} else if (OpKIDS(expr)) {
	    const OP * const k1 = OpFIRST(expr);
	    const OP * const k2 = k1 ? OpSIBLING(k1) : NULL;
	    switch (expr->op_type) {
	      case OP_NULL:
                  if (k2 && (IS_TYPE(k2, READLINE) || IS_TYPE(k2, READDIR))
		      && OpSTACKED(k2)
		      && OpWANT_SCALAR(k1))
		    expr = newUNOP(OP_DEFINED, 0, expr);
		break;

	      case OP_SASSIGN:
                  if (k1 && (IS_TYPE(k1, READDIR) /* READLINE? */
                      || OP_TYPE_IS_OR_WAS_NN(k1, OP_GLOB)
                      || IS_TYPE(k1, EACH)
                      || IS_TYPE(k1, AEACH)))
		    expr = newUNOP(OP_DEFINED, 0, expr);
		break;
	    }
	}
    }

    /* if block is null, the next op_append_elem() would put UNSTACK, a scalar
     * op, in listop. This is wrong. [perl #27024] */
    if (!block)
	block = newOP(OP_NULL, 0);
    listop = op_append_elem(OP_LINESEQ, block, newOP(OP_UNSTACK, 0));
    o = new_logop(OP_AND, 0, &expr, &listop);

    if (once) {
	ASSUME(listop);
    }

    if (listop)
	OpNEXT(OpLAST(listop)) = LINKLIST(o);

    if (once && o != listop)
    {
	assert(IS_TYPE(OpFIRST(o), AND)
            || IS_TYPE(OpFIRST(o), OR));
	OpNEXT(o) = OpOTHER(OpFIRST(o));
    }

    if (o == listop)
	o = newUNOP(OP_NULL, 0, o);	/* or do {} while 1 loses outer block */

    o->op_flags |= flags;
    o = op_scope(o);
    o->op_flags |= OPf_SPECIAL;	/* suppress cx_popblock() curpm restoration*/
    return o;
}

/*
=for apidoc Am|OP *|newWHILEOP|I32 flags|UNUSED I32 debuggable|LOOP *loop|OP *expr|OP *block|OP *cont|I32 has_my

Constructs, checks, and returns an op tree expressing a C<while> or
C<for>/C<foreach> loop or a single C<block> run only once.
This is a heavyweight loop, with structure that allows exiting the loop
by C<last> and suchlike.

C<loop> is an optional C<enterloop> op to use in the loop. With a
C<foreach> loop is is an C<enteriter> op. This op contains the five
main control paths: first, last, redoop, nextop, lastop.  C<first>
being the list iterator, C<last> being the iteration variable,
C<redoop> the C<block> plus C<cont>, C<nextop> the C<cont> or an
C<unstack> op, C<lastop> a C<leaveloop> op, which is also the false
condition of the C<expr> (i.e. C<< expr->op_next >>).

C<expr> supplies the loop's controlling expression. With a C<foreach>
loop it is the C<iter> op, with C<while> the while expression, with
a single block it is C<NULL>.

C<block> supplies the main body of the loop, and C<cont> optionally
supplies a C<continue> block that operates as a second half of the
body.  All of these optree inputs are consumed by this function and
become part of the constructed op tree.

C<flags> gives the eight bits of C<op_flags> for the C<leaveloop> op
and, shifted up eight bits, the eight bits of C<op_private> for the
C<leaveloop> op, except that (in both cases) some bits will be set
automatically.  C<debuggable> is currently unused and should always be
1.  C<has_my> can be supplied as C<true> to force the loop body to be
enclosed in its own scope.

=cut
*/

OP *
Perl_newWHILEOP(pTHX_ I32 flags, I32 debuggable PERL_UNUSED_DECL, LOOP *loop,
	OP *expr, OP *block, OP *cont, I32 has_my)
{
    dVAR;
    OP *redo;
    OP *next = NULL;
    LISTOP *listop;
    OP *o;
    U8 loopflags = 0;
    bool expr_is_iter = FALSE;

    PERL_UNUSED_ARG(debuggable);

    if (expr) {
	if (IS_TYPE(expr, READLINE)
         || IS_TYPE(expr, READDIR)
         || OP_TYPE_IS_OR_WAS(expr, OP_GLOB)
         || IS_TYPE(expr, EACH) || IS_TYPE(expr, AEACH)) {
	    expr = newUNOP(OP_DEFINED, 0,
		newASSIGNOP(0, newDEFSVOP(), 0, expr) );
	} else if (OpKIDS(expr)) {
	    const OP * const k1 = OpFIRST(expr);
	    const OP * const k2 = (k1) ? OpSIBLING(k1) : NULL;
	    switch (expr->op_type) {
	      case OP_NULL:
                  if (k2 && (IS_TYPE(k2, READLINE) || IS_TYPE(k2, READDIR))
                      && OpSTACKED(k2) && OpWANT_SCALAR(k1))
		    expr = newUNOP(OP_DEFINED, 0, expr);
		break;

	      case OP_SASSIGN:
                  if (k1 && (IS_TYPE(k1, READDIR) /* READLINE? */
                      || OP_TYPE_IS_OR_WAS(k1, OP_GLOB)
                      || IS_TYPE(k1, EACH) || IS_TYPE(k1, AEACH)))
		    expr = newUNOP(OP_DEFINED, 0, expr);
		break;
	    }
	}
    }

    if (!block)
	block = newOP(OP_NULL, 0);
    else if (cont || has_my) {
	block = op_scope(block);
    }

    if (cont) {
	next = LINKLIST(cont);
    }
    if (expr) {
	OP * const unstack = newOP(OP_UNSTACK, 0);
        expr_is_iter = OP_IS_ITER(expr->op_type);
	if (!next)
	    next = unstack;
	cont = op_append_elem(OP_LINESEQ, cont, unstack);
        expr_is_iter = OP_IS_ITER(expr->op_type);
    }

    assert(block);
    listop = (LISTOP*)op_append_list(OP_LINESEQ, block, cont);
    assert(listop);
    redo = LINKLIST((OP*)listop);

    if (expr) {
	scalar((OP*)listop);
        if (!expr_is_iter) {
            o = new_logop(OP_AND, 0, &expr, (OP**)&listop);
            if (o == expr && IS_CONST_OP(o) && !SvTRUE(cSVOPo->op_sv)) {
                op_free((OP*)loop);
                return expr;		/* listop already freed by new_logop */
            }
        } else {
            OP* oth = OpNEXT(listop);
            o = scalar(expr);
            OpFIRST(o) = newOP(OP_NULL, 0); /* nasty dummy */
            OpNEXT(OpFIRST(o)) = expr;
            OpOTHER(o) = oth;    /* continue with block, skip lineseq */
            /* possibly skip NULL in inner loop also */
            if (IS_TYPE(OpNEXT(oth), NULL)) {
                OpNEXT(oth) = OpNEXT(OpNEXT(oth));
            }
            OpMORESIB_set(OpFIRST(o), (OP*)listop);
            OpLASTSIB_set((OP*)listop, o);
        }
        OpNEXT(OpLAST(listop)) = (o == (OP*)listop) ? redo : LINKLIST(o);
    }
    else
	o = (OP*)listop;

    if (!loop) {
	NewOp(1101,loop,1,LOOP);
        OpTYPE_set(loop, OP_ENTERLOOP);
	OpNEXT(loop) = (OP*)loop;
    }

    o = newBINOP(OP_LEAVELOOP, 0, (OP*)loop, o);

    loop->op_redoop = redo;
    loop->op_lastop = o;
    o->op_private |= loopflags;
    if (expr_is_iter) {
        /*OpNEXT(expr) = o;*/
        OpLASTSIB_set(expr, o);
    }

    if (next) {
	loop->op_nextop = next;
#if 0
        if (0 && expr_is_iter && OpFIRST(loop)) {
            bool has_loop_var;
            next = OpSIBLING(OpFIRST(loop));   /* from */
            has_loop_var = OpLAST(loop) != next;
            OpNEXT(OpFIRST(loop)) = LINKLIST(next);
            OpNEXT(OpLAST(loop)) = (OP*)loop; /* and loop var back to loop */
            OpNEXT(loop) = expr; /* and loop to iter, but this
                                    link is later destroyed by linklist
                                    to the sibling. */
            if (has_loop_var) {
                OP* last = OpLAST(loop); /* the loop var tree */
                /* We cannot collapse RV2GV+GV to a GVSV itervar, sv is for \$refs only */
                if (OpKIDS(last)) { /* SV ref itervar */
                    last = OpFIRST(last);
                    OpNEXT(last) = OpLAST(loop);
                }
                OpNEXT(next) = last;         /* range -> loopvar */
                OpNEXT(OpLAST(next)) = last; /* end of range -> loopvar */
            }
        }
#endif
    }
    else {
	loop->op_nextop = o;
    }

    o->op_flags |= flags;
    o->op_private |= (flags >> 8);
    return o;
}

/*
=for apidoc Am|OP *|newFOROP|I32 flags|OP *sv|OP *expr|OP *block|OP *cont

Constructs, checks, and returns an op tree expressing a C<foreach>
loop (iteration through a list of values).  This is a heavyweight loop,
with structure that allows exiting the loop by C<last> and suchlike.

C<sv> optionally supplies the variable that will be aliased to each
item in turn; if null, it defaults to C<$_> (either lexical or global).
C<expr> supplies the list of values to iterate over.  C<block> supplies
the main body of the loop, and C<cont> optionally supplies a C<continue>
block that operates as a second half of the body.  All of these optree
inputs are consumed by this function and become part of the constructed
op tree.

C<flags> gives the eight bits of C<op_flags> for the C<leaveloop>
op and, shifted up eight bits, the eight bits of C<op_private> for
the C<leaveloop> op, except that (in both cases) some bits will be set
automatically.

=cut
*/

OP *
Perl_newFOROP(pTHX_ I32 flags, OP *sv, OP *expr, OP *block, OP *cont)
{
    dVAR;
    LOOP *loop;
    OP *wop;
    PADOFFSET padoff = 0;
    I32 iterflags = 0;
    I32 iterpflags = 0;
    OPCODE optype = OP_ITER;

    PERL_ARGS_ASSERT_NEWFOROP;

    if (sv) {
	if (IS_TYPE(sv, RV2SV)) {	/* symbol table variable */
	    iterpflags = sv->op_private & OPpOUR_INTRO; /* for our $x () */
            OpTYPE_set(sv, OP_RV2GV);

	    /* The op_type check is needed to prevent a possible segfault
	     * if the loop variable is undeclared and 'strict vars' is in
	     * effect. This is illegal but is nonetheless parsed, so we
	     * may reach this point with an OP_CONST where we're expecting
	     * an OP_GV.
	     */
	    if (IS_TYPE(OpFIRST(sv), GV)
	     && cGVOPx_gv(OpFIRST(sv)) == PL_defgv)
		iterpflags |= OPpITER_DEF;
	}
	else if (IS_TYPE(sv, PADSV)) { /* private variable */
	    iterpflags = sv->op_private & OPpLVAL_INTRO; /* for my $x () */
	    padoff = sv->op_targ;
            sv->op_targ = 0;
            op_free(sv);
	    sv = NULL;
	    PAD_COMPNAME_GEN_set(padoff, PERL_INT_MAX);
	}
	else if (OP_TYPE_WAS_NN(sv, OP_SREFGEN))
	    NOOP;
	else
	    Perl_croak(aTHX_ "Can't use %s for loop variable", PL_op_desc[sv->op_type]);
	if (padoff) {
	    PADNAME * const pn = PAD_COMPNAME(padoff);
	    const char * const name = PadnamePV(pn);

	    if (PadnameLEN(pn) == 2 && name[0] == '$' && name[1] == '_')
		iterpflags |= OPpITER_DEF;
	}
    }
    else {
        const PADOFFSET offset = pad_findmy_pvs("$_", 0);
	if (offset == NOT_IN_PAD || PAD_COMPNAME_FLAGS_isOUR(offset)) {
	    sv = newGVOP(OP_GV, 0, PL_defgv);
	}
	else {
	    padoff = offset;
	}
	iterpflags |= OPpITER_DEF;
    }

    if (IS_TYPE(expr, RV2AV) || IS_TYPE(expr, PADAV)) {
	expr = op_lvalue(force_list(scalar(ref(expr, OP_ITER)), 1), OP_GREPSTART);
        optype = OP_ITER_ARY;
	iterflags |= OPf_STACKED;
    }
    else if (IS_NULL_OP(expr) && OpKIDS(expr) &&
             IS_TYPE(OpFIRST(expr), FLOP))
    {
	/* Basically turn for($x..$y) into the same as for($x,$y), but we
	 * set the STACKED flag to indicate that these values are to be
	 * treated as min/max values by 'pp_enteriter'.
	 */
	const UNOP* const flip = (UNOP*)OpFIRST(OpFIRST(expr));
	LOGOP* const range = (LOGOP*)OpFIRST(flip);
	OP* const left  = OpFIRST(range);
	OP* const right = OpSIBLING(left);
        SV *leftsv, *rightsv;
	LISTOP* listop;

        if (IS_CONST_OP(left) && IS_CONST_OP(right)
            && SvIOK(leftsv = cSVOPx_sv(left))
            && SvIOK(rightsv = cSVOPx_sv(right)))
        {
            if (UNLIKELY(SvIV(rightsv) < SvIV(leftsv)))
                DIE(aTHX_ "Invalid for range iterator (%" IVdf " .. %" IVdf ")",
                    SvIV(leftsv), SvIV(rightsv));
#ifdef DEBUGGING
            /* TODO: unroll loop for small constant ranges, if the body is not too big */
            if (SvIV(rightsv)-SvIV(leftsv) <= PERL_MAX_UNROLL_LOOP_COUNT) {
                DEBUG_kv(Perl_deb(aTHX_ "TODO unroll loop (%" IVdf "..%" IVdf ")\n",
                                  SvIV(leftsv), SvIV(rightsv)));
                /* TODO easy with op_clone_oplist from feature/gh23-inline-subs */
            }
#endif
            optype = OP_ITER_LAZYIV;
        }
	range->op_flags &= ~OPf_KIDS;
        /* detach range's children */
        op_sibling_splice((OP*)range, NULL, -1, NULL);

	listop = (LISTOP*)newLISTOP(OP_LIST, 0, left, right);
	OpNEXT(OpFIRST(listop)) = OpNEXT(range);
	OpNEXT(left) = OpOTHER(range);
	OpNEXT(right) = (OP*)listop;
	OpNEXT(listop) = OpFIRST(listop);

	op_free(expr);
	expr = (OP*)(listop);
        op_null(expr);
	iterflags |= OPf_STACKED;
    }
    else {
        expr = op_lvalue(force_list(expr, 1), OP_GREPSTART);
    }

    loop = (LOOP*)op_convert_list(OP_ENTERITER, iterflags,
                                  op_append_elem(OP_LIST, list(expr),
                                                 scalar(sv)));
    assert(!OpNEXT(loop));
    /* for my  $x () sets OPpLVAL_INTRO;
     * for our $x () sets OPpOUR_INTRO */
    loop->op_private = (U8)iterpflags;
    if (loop->op_slabbed
     && DIFF(loop, OpSLOT(loop)->opslot_next)
	 < SIZE_TO_PSIZE(sizeof(LOOP)))
    {
	LOOP *tmp;
	NewOp(1234,tmp,1,LOOP);
	Copy(loop,tmp,1,LISTOP);
#ifdef PERL_OP_PARENT
        assert(OpLAST(loop)->op_sibparent == (OP*)loop);
        OpLASTSIB_set(OpLAST(loop), (OP*)tmp); /*point back to new parent */
#endif
	S_op_destroy(aTHX_ (OP*)loop);
	loop = tmp;
    }
    else if (!loop->op_slabbed)
    {
	loop = (LOOP*)PerlMemShared_realloc(loop, sizeof(LOOP));
#ifdef PERL_OP_PARENT
        OpLASTSIB_set(OpLAST(loop), (OP*)loop);
#endif
    }
    loop->op_targ = padoff;
    wop = newWHILEOP(flags, 1, loop, newOP(optype, OPf_KIDS),
                     block, cont, 0);
    return wop;
}

/*
=for apidoc Am|OP *|newLOOPEX|I32 type|OP *label

Constructs, checks, and returns a loop-exiting op (such as C<goto>
or C<last>).  C<type> is the opcode.  C<label> supplies the parameter
determining the target of the op; it is consumed by this function and
becomes part of the constructed op tree.

=cut
*/

OP*
Perl_newLOOPEX(pTHX_ I32 type, OP *label)
{
    OP *o = NULL;

    PERL_ARGS_ASSERT_NEWLOOPEX;

    assert((PL_opargs[type] & OA_CLASS_MASK) == OA_LOOPEXOP
	|| type == OP_CUSTOM);

    if (type != OP_GOTO) {
	/* "last()" means "last" */
	if (IS_TYPE(label, STUB) && OpPARENS(label)) {
	    o = newOP(type, OPf_SPECIAL);
	}
        /* "last(1,a) means last a. 1 is skipped */
	else if (UNLIKELY(IS_TYPE(label, LIST) && OpKIDS(label))) {
            OP* op = OpSIBLING(OpFIRST(label));
            if ( op && OpSIBLING(op) && IS_CONST_OP(op) )
		Perl_ck_warner(aTHX_ packWARN(WARN_MISC),
                               "Useless use of constant in list at %s()",
                               PL_op_name[type]);
	}
    }
    else {
	/* Check whether it's going to be a goto &function */
	if (IS_SUB_OP(label) && !OpSTACKED(label))
	    label = newUNOP(OP_REFGEN, 0, op_lvalue(label, OP_REFGEN));
    }

    /* Check for a constant argument */
    if (IS_CONST_OP(label)) {
        SV * const sv = ((SVOP *)label)->op_sv;
        STRLEN l;
        const char *s = SvPV_const(sv,l);
        if (l == strlen(s)) {
            o = newPVOP(type,
                        SvUTF8(((SVOP*)label)->op_sv),
                        savesharedpv(SvPV_nolen_const(((SVOP*)label)->op_sv)));
        }
    }
    
    /* If we have already created an op, we do not need the label. */
    if (o)
        op_free(label);
    else o = newUNOP(type, OPf_STACKED, label);

    PL_hints |= HINT_BLOCK_SCOPE;
    return o;
}

/* if the condition is a literal array or hash
   (or @{ ... } etc), make a reference to it.
 */
static OP *
S_ref_array_or_hash(pTHX_ OP *cond)
{
    if (cond && (IS_TYPE(cond, RV2AV)
        || IS_TYPE(cond, PADAV)
        || IS_TYPE(cond, RV2HV)
        || IS_TYPE(cond, PADHV)))
	return newUNOP(OP_REFGEN, 0, op_lvalue(cond, OP_REFGEN));

    else if (cond && (IS_TYPE(cond, ASLICE)
             ||  IS_TYPE(cond, KVASLICE)
             ||  IS_TYPE(cond, HSLICE)
             ||  IS_TYPE(cond, KVHSLICE))) {

	/* anonlist now needs a list from this op, was previously used in
	 * scalar context */
	cond->op_flags &= ~(OPf_WANT_SCALAR | OPf_REF);
	cond->op_flags |= OPf_WANT_LIST;

	return newANONLIST(op_lvalue(cond, OP_ANONLIST));
    }

    else
	return cond;
}

/* These construct the optree fragments representing given()
   and when() blocks.

   entergiven and enterwhen are LOGOPs; the op_other pointer
   points up to the associated leave op. We need this so we
   can put it in the context and make break/continue work.
   (Also, of course, pp_enterwhen will jump straight to
   op_other if the match fails.)
 */

static OP *
S_newGIVWHENOP(pTHX_ OP *cond, OP *block,
		   I32 enter_opcode, I32 leave_opcode,
		   PADOFFSET entertarg)
{
    dVAR;
    LOGOP *enterop;
    OP *o;

    PERL_ARGS_ASSERT_NEWGIVWHENOP;

    enterop = S_alloc_LOGOP(aTHX_ enter_opcode, block, NULL);
    enterop->op_targ = ((entertarg == NOT_IN_PAD) ? 0 : entertarg);
    enterop->op_private = 0;

    o = newUNOP(leave_opcode, 0, (OP *) enterop);

    if (cond) {
        /* prepend cond if we have one */
        op_sibling_splice((OP*)enterop, NULL, 0, scalar(cond));

	OpNEXT(o) = LINKLIST(cond);
	OpNEXT(cond) = (OP *) enterop;
    }
    else {
	/* This is a default {} block */
	enterop->op_flags |= OPf_SPECIAL;
	o      ->op_flags |= OPf_SPECIAL;

	OpNEXT(o) = (OP *) enterop;
    }

    CHECKOP(enter_opcode, enterop); /* Currently does nothing, since
    				       entergiven and enterwhen both
    				       use ck_null() */

    OpNEXT(enterop) = LINKLIST(block);
    OpNEXT(block) = OpOTHER(enterop) = o;
    if (enterop->op_targ) o->op_targ = enterop->op_targ;

    return o;
}

/* Does this look like a boolean operation? For these purposes
   a boolean operation is:
     - a subroutine call [*]
     - a logical connective
     - a comparison operator
     - a filetest operator, with the exception of -s -M -A -C
     - defined(), exists() or eof()
     - /$re/ or $foo =~ /$re/
   
   [*] possibly surprising
 */
static bool
S_looks_like_bool(pTHX_ const OP *o)
{
    PERL_ARGS_ASSERT_LOOKS_LIKE_BOOL;

    switch(o->op_type) {
	case OP_OR:
	case OP_DOR:
	    return looks_like_bool(OpFIRST(o));

	case OP_AND:
        {
            OP* sibl = OpSIBLING(OpFIRST(o));
            ASSUME(sibl);
	    return (
                looks_like_bool(OpFIRST(o))
	     && looks_like_bool(sibl));
        }

	case OP_NULL:
	case OP_SCALAR:
	    return (
		OpKIDS(o)
	    && looks_like_bool(OpFIRST(o)));

	case OP_ENTERSUB:
	case OP_ENTERXSSUB:

	case OP_NOT:	case OP_XOR:

	case OP_EQ:	case OP_NE:	case OP_LT:
	case OP_GT:	case OP_LE:	case OP_GE:
	case OP_I_EQ:	case OP_I_NE:	case OP_I_LT:
	case OP_I_GT:	case OP_I_LE:	case OP_I_GE:
	case OP_S_EQ:	case OP_S_NE:	case OP_S_LT:
	case OP_S_GT:	case OP_S_LE:	case OP_S_GE:
	
	case OP_SMARTMATCH:
	
	case OP_FTRREAD:  case OP_FTRWRITE: case OP_FTREXEC:
	case OP_FTEREAD:  case OP_FTEWRITE: case OP_FTEEXEC:
	case OP_FTIS:     case OP_FTEOWNED: case OP_FTROWNED:
	case OP_FTZERO:   case OP_FTSOCK:   case OP_FTCHR:
	case OP_FTBLK:    case OP_FTFILE:   case OP_FTDIR:
	case OP_FTPIPE:   case OP_FTLINK:   case OP_FTSUID:
	case OP_FTSGID:   case OP_FTSVTX:   case OP_FTTTY:
	case OP_FTTEXT:   case OP_FTBINARY:
	
	case OP_DEFINED: case OP_EXISTS:
	case OP_MATCH:	 case OP_EOF:

	case OP_FLOP:

	    return TRUE;
	
	case OP_CONST:
	    /* Detect comparisons that have been optimized away */
	    if (cSVOPo->op_sv == SV_YES
	    ||  cSVOPo->op_sv == SV_NO)
	    
		return TRUE;
	    else
		return FALSE;

	/* FALLTHROUGH */
	default:
	    return FALSE;
    }
}

/*
=for apidoc Am|OP *|newGIVENOP|OP *cond|OP *block|PADOFFSET defsv_off

Constructs, checks, and returns an op tree expressing a C<given> block.
C<cond> supplies the expression that will be locally assigned to a lexical
variable, and C<block> supplies the body of the C<given> construct; they
are consumed by this function and become part of the constructed op tree.
C<defsv_off> is the pad offset of the scalar lexical variable that will
be affected.  If it is 0, the global C<$_> will be used.

=cut
*/

OP *
Perl_newGIVENOP(pTHX_ OP *cond, OP *block, PADOFFSET defsv_off)
{
    PERL_ARGS_ASSERT_NEWGIVENOP;
    return newGIVWHENOP(
    	ref_array_or_hash(cond),
    	block,
	OP_ENTERGIVEN, OP_LEAVEGIVEN,
	defsv_off);
}

/*
=for apidoc Am|OP *|newWHENOP|OP *cond|OP *block

Constructs, checks, and returns an op tree expressing a C<when> block.
C<cond> supplies the test expression, and C<block> supplies the block
that will be executed if the test evaluates to true; they are consumed
by this function and become part of the constructed op tree.  C<cond>
will be interpreted DWIMically, often as a comparison against C<$_>,
and may be null to generate a C<default> block.

=cut
*/

OP *
Perl_newWHENOP(pTHX_ OP *cond, OP *block)
{
    OP *cond_op;
    const bool cond_llb = (!cond || looks_like_bool(cond));

    PERL_ARGS_ASSERT_NEWWHENOP;

    if (cond_llb)
	cond_op = cond;
    else {
	cond_op = newBINOP(OP_SMARTMATCH, OPf_SPECIAL,
		newDEFSVOP(),
		scalar(ref_array_or_hash(cond)));
    }
    
    return newGIVWHENOP(cond_op, block, OP_ENTERWHEN, OP_LEAVEWHEN, 0);
}

/* must not conflict with SVf_UTF8 */
#define CV_CKPROTO_CURSTASH	0x1

void
Perl_cv_ckproto_len_flags(pTHX_ const CV *cv, const GV *gv, const char *p,
		    const STRLEN len, const U32 flags)
{
    SV *name = NULL, *msg;
    const char * cvp = SvROK(cv)
			? SvTYPE(SvRV_const(cv)) == SVt_PVCV
			   ? (cv = (const CV *)SvRV_const(cv), CvPROTO(cv))
			   : ""
			: CvPROTO(cv);
    STRLEN clen = CvPROTOLEN(cv), plen = len;

    PERL_ARGS_ASSERT_CV_CKPROTO_LEN_FLAGS;

    if (p == NULL && cvp == NULL)
	return;

    if (!ckWARN_d(WARN_PROTOTYPE))
	return;

    if (p && cvp) {
	p   = strip_spaces(p, &plen);
	cvp = strip_spaces(cvp, &clen);
	if ((flags & SVf_UTF8) == SvUTF8(cv)) {
	    if (plen == clen && memEQ(cvp, p, plen))
		return;
	} else {
	    if (flags & SVf_UTF8) {
		if (bytes_cmp_utf8((const U8 *)cvp, clen, (const U8 *)p, plen) == 0)
		    return;
            }
	    else {
		if (bytes_cmp_utf8((const U8 *)p, plen, (const U8 *)cvp, clen) == 0)
		    return;
	    }
	}
    }

    msg = sv_newmortal();

    if (gv)
    {
	if (isGV(gv))
	    gv_efullname3(name = sv_newmortal(), gv, NULL);
	else if (SvPOK(gv) && *SvPVX((SV *)gv) == '&')
	    name = newSVpvn_flags(SvPVX((SV *)gv)+1, SvCUR(gv)-1, SvUTF8(gv)|SVs_TEMP);
	else if (flags & CV_CKPROTO_CURSTASH || SvROK(gv)) {
	    name = sv_2mortal(newSVhek(HvNAME_HEK(PL_curstash)));
	    sv_catpvs(name, "::");
	    if (SvROK(gv)) {
		assert (SvTYPE(SvRV_const(gv)) == SVt_PVCV);
		assert (CvNAMED(SvRV_const(gv)));
		sv_cathek(name, CvNAME_HEK(MUTABLE_CV(SvRV_const(gv))));
	    }
	    else sv_catsv(name, (SV *)gv);
	}
	else name = (SV *)gv;
    }
    sv_setpvs(msg, "Prototype mismatch:");
    if (name)
	Perl_sv_catpvf(aTHX_ msg, " sub %" SVf, SVfARG(name));
    if (cvp)
	Perl_sv_catpvf(aTHX_ msg, " (%" UTF8f ")",
	    UTF8fARG(SvUTF8(cv),clen,cvp)
	);
    else
	sv_catpvs(msg, ": none");
    sv_catpvs(msg, " vs ");
    if (p)
	Perl_sv_catpvf(aTHX_ msg, "(%" UTF8f ")", UTF8fARG(flags & SVf_UTF8,len,p));
    else
	sv_catpvs(msg, "none");
    Perl_warner(aTHX_ packWARN(WARN_PROTOTYPE), "%" SVf, SVfARG(msg));
}

/*static void const_sv_xsub(pTHX_ CV* cv);
  static void const_av_xsub(pTHX_ CV* cv);*/

/*

=head1 Optree Manipulation Functions

=for apidoc cv_const_sv

If C<cv> is a constant sub eligible for inlining, returns the constant
value returned by the sub.  Otherwise, returns C<NULL>.

Constant subs can be created with C<newCONSTSUB> or as described in
L<perlsub/"Constant Functions">.

=cut
*/
SV *
Perl_cv_const_sv(const CV *const cv)
{
    SV *sv;
    if (!cv)
	return NULL;
    if (!(SvTYPE(cv) == SVt_PVCV || SvTYPE(cv) == SVt_PVFM))
	return NULL;
    sv = CvCONST(cv) ? MUTABLE_SV(CvXSUBANY(cv).any_ptr) : NULL;
    if (sv && SvTYPE(sv) == SVt_PVAV) return NULL;
    return sv;
}

SV *
Perl_cv_const_sv_or_av(const CV * const cv)
{
    if (!cv)
	return NULL;
    if (SvROK(cv)) return SvRV((SV *)cv);
    assert (SvTYPE(cv) == SVt_PVCV || SvTYPE(cv) == SVt_PVFM);
    return CvCONST(cv) ? MUTABLE_SV(CvXSUBANY(cv).any_ptr) : NULL;
}

/*
=for apidoc s|SV*    |op_const_sv    |NN const OP *o|NN CV *cv|bool allow_lex

op_const_sv:  examine an optree to determine whether it's in-lineable
              into a single CONST op.
It walks the tree in exec order (next), not in tree order (sibling, first).

Can be called in 2 ways:

!allow_lex
	look for a single OP_CONST with attached value: return the value

allow_lex && !CvCONST(cv);

	examine the clone prototype, and if contains only a single
	OP_CONST, return the value; or if it contains a single PADSV ref-
	erencing an outer lexical, turn on CvCONST to indicate the CV is
	a candidate for "constizing" at clone time, and return NULL.
=cut
*/

static SV *
S_op_const_sv(pTHX_ const OP *o, CV *cv, bool allow_lex)
{
    SV *sv = NULL;
    bool padsv = FALSE;
    PERL_ARGS_ASSERT_OP_CONST_SV;

    do {
	const OPCODE type = o->op_type;

	if (type == OP_NEXTSTATE || type == OP_DBSTATE
            || type == OP_NULL   || type == OP_LINESEQ
            || type == OP_PUSHMARK) {
            o = OpNEXT(o);
            continue;
        }
	if (type == OP_LEAVESUB)
	    break;
	if (sv)
	    return NULL;
	if (type == OP_CONST && cSVOPo->op_sv)
	    sv = cSVOPo->op_sv;
	else if (type == OP_UNDEF && !o->op_private) {
	    sv = newSV(0);
	    SAVEFREESV(sv);
	}
	else if (allow_lex && type == OP_PADSV) {
            if (PAD_COMPNAME_FLAGS(o->op_targ) & PADNAMEt_OUTER) {
                sv = UNDEF; /* an arbitrary non-null value */
                padsv = TRUE;
            }
            else
                return NULL;
	}
	else {
	    return NULL;
	}
        o = OpNEXT(o);
    } while (o);

    if (padsv) {
	CvCONST_on(cv);
	return NULL;
    }
    DEBUG_k(Perl_deb(aTHX_ "op_const_sv: inlined SV 0x%p\n", sv));
#ifdef DEBUGGING
    if (sv) {
        DEBUG_kv(Perl_sv_dump(aTHX_ sv));
    }
#endif
    return sv;
}

/* cv_do_inline needs to translate the args,
 * handle args: shift, = @_ or just accept SIGNATURED subs with PERL_FAKE_SIGNATURE.
 * with a OP_SIGNATURE it is easier. without need to populate @_.
 * if arg is call-by-value make a copy.
 * adjust or add targs,
 * with local need to add SAVETMPS/FREETMPS.
 * maybe keep ENTER/LEAVE
 *
 * $lhs = call(...); => $lhs = do {...inlined...};
 */

#ifdef PERL_INLINE_SUBS
static OP*
S_cv_do_inline(pTHX_ const OP *o, const OP *cvop, CV *cv, bool meth)
{
    /* WIP splice inlined ENTERSUB into the current body */
    const OP *pushmarkop = o;
    PERL_ARGS_ASSERT_CV_DO_INLINE;

    /*assert(o); the pushmark
    assert(cv);*/
    assert(IS_TYPE(o, PUSHMARK));
    assert(IS_TYPE(cvop, ENTERSUB));
    /* first translate the args to the temp vars */

    if (meth) { /* push self */
        if (UNLIKELY(OP_TYPE_IS(o->op_next, OP_GVSV))) { /* $self->meth not,
                                                as we don't know the run-time dispatch */
            DEBUG_k(deb("rpeep: skip inline $self->%s\n", HEK_KEY(CvNAME_HEK(cv))));
            return (OP*)pushmarkop;
        }
        if (OP_TYPE_IS(o->op_next, OP_CONST)) { /* pkg->meth yes, if pkg::meth exists */
            /* my $self = const pv */
        }
    }
    for (; o != cvop; o = o->op_next) {
	const OPCODE type = o->op_type;
	if (type == OP_GV && meth) {
	    return NULL;
	}
    }
    return (OP*)pushmarkop;
}
#endif

static void
S_already_defined(pTHX_ CV *const cv, OP * const block, OP * const o,
			PADNAME * const name, SV ** const const_svp)
{
    assert (cv);
    assert (o || name);
    assert (const_svp);
    if (!block) {
	if (CvFLAGS(PL_compcv)) {
	    /* might have had built-in attrs applied */
	    const bool pureperl = !CvISXSUB(cv) && CvROOT(cv);
	    if (CvLVALUE(PL_compcv) && ! CvLVALUE(cv) && pureperl
	     && ckWARN(WARN_MISC))
	    {
		/* protect against fatal warnings leaking compcv */
		SAVEFREESV(PL_compcv);
		Perl_warner(aTHX_ packWARN(WARN_MISC),
                    "lvalue attribute ignored after the subroutine has been defined");
		SvREFCNT_inc_simple_void_NN(PL_compcv);
	    }
	    CvFLAGS(cv) |=
		(CvFLAGS(PL_compcv) & CVf_BUILTIN_ATTRS
		  & ~(CVf_LVALUE * pureperl));
	}
	return;
    }

    /* redundant check for speed: */
    if (CvCONST(cv) || ckWARN(WARN_REDEFINE)) {
	const line_t oldline = CopLINE(PL_curcop);
	SV *namesv = o
	    ? cSVOPo->op_sv
	    : sv_2mortal(newSVpvn_utf8(
		PadnamePV(name)+1,PadnameLEN(name)-1, PadnameUTF8(name)
	      ));
	if (PL_parser && PL_parser->copline != NOLINE)
            /* This ensures that warnings are reported at the first
               line of a redefinition, not the last.  */
	    CopLINE_set(PL_curcop, PL_parser->copline);
	/* protect against fatal warnings leaking compcv */
	SAVEFREESV(PL_compcv);
	report_redefined_cv(namesv, cv, const_svp);
	SvREFCNT_inc_simple_void_NN(PL_compcv);
	CopLINE_set(PL_curcop, oldline);
    }
    SAVEFREESV(cv);
    return;
}

CV *
Perl_newMYSUB(pTHX_ I32 floor, OP *o, OP *proto, OP *attrs, OP *block)
{
    CV **spot;
    SV **svspot;
    const char *ps;
    CV *cv = NULL;
    CV *compcv = PL_compcv;
    SV *const_sv = NULL;
    PADNAME *name;
    CV *outcv = CvOUTSIDE(PL_compcv);
    CV *clonee = NULL;
    HEK *hek = NULL;
    OP *start = NULL;
#ifdef PERL_DEBUG_READONLY_OPS
    OPSLAB *slab = NULL;
#endif
    STRLEN ps_len = 0; /* init it to avoid false uninit warning from icc */
    PADOFFSET pax = o->op_targ;
    U32 ps_utf8 = 0;
    bool reusable = FALSE;

    PERL_ARGS_ASSERT_NEWMYSUB;

    PL_hints |= HINT_BLOCK_SCOPE;

    /* Find the pad slot for storing the new sub.
       We cannot use PL_comppad, as it is the pad owned by the new sub.  We
       need to look in CvOUTSIDE and find the pad belonging to the enclos-
       ing sub.  And then we need to dig deeper if this is a lexical from
       outside, as in:
	   my sub foo; sub { sub foo { } }
     */
  redo:
    name = PadlistNAMESARRAY(CvPADLIST(outcv))[pax];
    if (PadnameOUTER(name) && PARENT_PAD_INDEX(name)) {
	pax = PARENT_PAD_INDEX(name);
	outcv = CvOUTSIDE(outcv);
	assert(outcv);
	goto redo;
    }
    svspot =
	&PadARRAY(PadlistARRAY(CvPADLIST(outcv))
			[CvDEPTH(outcv) ? CvDEPTH(outcv) : 1])[pax];
    spot = (CV **)svspot;

    if (!(PL_parser && PL_parser->error_count))
        move_proto_attr(&proto, &attrs, (GV *)PadnameSV(name), FALSE);

    if (proto) {
	assert(IS_CONST_OP(proto));
	ps = SvPV_const(((SVOP*)proto)->op_sv, ps_len);
        ps_utf8 = SvUTF8(((SVOP*)proto)->op_sv);
    }
    else
	ps = NULL;

    if (proto)
        SAVEFREEOP(proto);
    if (attrs)
        SAVEFREEOP(attrs);

    if (PL_parser && PL_parser->error_count) {
	op_free(block);
	SvREFCNT_dec(PL_compcv);
	PL_compcv = 0;
	goto done;
    }

    if (CvDEPTH(outcv) && CvCLONE(compcv)) {
	cv = *spot;
	svspot = (SV **)(spot = &clonee);
    }
    else if (PadnameIsSTATE(name) || CvDEPTH(outcv))
	cv = *spot;
    else {
	assert (SvTYPE(*spot) == SVt_PVCV);
	if (CvNAMED(*spot))
	    hek = CvNAME_HEK(*spot);
	else {
            dVAR;
	    U32 hash;
	    PERL_HASH(hash, PadnamePV(name)+1, PadnameLEN(name)-1);
	    CvNAME_HEK_set(*spot, hek =
		share_hek(
		    PadnamePV(name)+1,
		    (PadnameLEN(name)-1) * (PadnameUTF8(name) ? -1 : 1),
		    hash
		)
	    );
	    CvLEXICAL_on(*spot);
	}
	cv = PadnamePROTOCV(name);
	svspot = (SV **)(spot = &PadnamePROTOCV(name));
    }

    if (block) {
	/* This makes sub {}; work as expected.  */
	if (IS_TYPE(block, STUB)) {
	    const line_t l = PL_parser->copline;
	    op_free(block);
	    block = newSTATEOP(0, NULL, 0);
	    PL_parser->copline = l;
	}
	block = CvLVALUE(compcv)
	     || (cv && CvLVALUE(cv) && !CvROOT(cv) && !CvXSUB(cv))
		   ? newUNOP(OP_LEAVESUBLV, 0,
			     op_lvalue(scalarseq(block), OP_LEAVESUBLV))
		   : newUNOP(OP_LEAVESUB, 0, scalarseq(block));
	start = LINKLIST(block);
	OpNEXT(block) = NULL;
        if (ps && !*ps && !attrs && !CvLVALUE(compcv))
            const_sv = op_const_sv(start, compcv, FALSE);
    }

    if (cv) {
        const bool exists = cBOOL(CvROOT(cv) || CvXSUB(cv));

        /* if the subroutine doesn't exist and wasn't pre-declared
         * with a prototype, assume it will be AUTOLOADed,
         * skipping the prototype check
         */
        if (exists || SvPOK(cv))
            cv_ckproto_len_flags(cv, (GV *)PadnameSV(name), ps, ps_len,
                                 ps_utf8);
	/* already defined? */
	if (exists) {
	    S_already_defined(aTHX_ cv, block, NULL, name, &const_sv);
            if (block)
		cv = NULL;
	    else {
		if (attrs)
                    goto attrs;
		/* just a "sub foo;" when &foo is already defined */
		SAVEFREESV(compcv);
		goto done;
	    }
	}
	else if (CvDEPTH(outcv) && CvCLONE(compcv)) {
	    cv = NULL;
	    reusable = TRUE;
	}
    }

    if (const_sv) {
	SvREFCNT_inc_simple_void_NN(const_sv);
	SvFLAGS(const_sv) |= SVs_PADTMP;
	if (cv) {
	    assert(!CvROOT(cv) && !CvCONST(cv));
	    cv_forget_slab(cv);
	}
	else {
	    cv = MUTABLE_CV(newSV_type(SVt_PVCV));
	    CvFILE_set_from_cop(cv, PL_curcop);
	    CvSTASH_set(cv, PL_curstash);
	    *spot = cv;
	}
        SvPVCLEAR(MUTABLE_SV(cv));  /* prototype is "" */
	CvXSUBANY(cv).any_ptr = const_sv;
	CvXSUB(cv) = S_const_sv_xsub;
	CvCONST_on(cv);
	CvISXSUB_on(cv);
	PoisonPADLIST(cv);
	CvFLAGS(cv) |= CvMETHOD(compcv);
	op_free(block);
	SvREFCNT_dec(compcv);
	PL_compcv = NULL;
	goto setname;
    }

    /* Checking whether outcv is CvOUTSIDE(compcv) is not sufficient to
       determine whether this sub definition is in the same scope as its
       declaration.  If this sub definition is inside an inner named pack-
       age sub (my sub foo; sub bar { sub foo { ... } }), outcv points to
       the package sub.  So check PadnameOUTER(name) too.
     */
    if (outcv == CvOUTSIDE(compcv) && !PadnameOUTER(name)) { 
	assert(!CvWEAKOUTSIDE(compcv));
	SvREFCNT_dec(CvOUTSIDE(compcv));
	CvWEAKOUTSIDE_on(compcv);
    }
    /* XXX else do we have a circular reference? */

    if (cv) {	/* must reuse cv in case stub is referenced elsewhere */
	/* transfer PL_compcv to cv */
	if (block) {
	    cv_flags_t preserved_flags =
		CvFLAGS(cv) & (CVf_BUILTIN_ATTRS|CVf_NAMED);
	    PADLIST *const temp_padl = CvPADLIST(cv);
	    CV *const temp_cv = CvOUTSIDE(cv);
	    const cv_flags_t other_flags =
		CvFLAGS(cv) & (CVf_SLABBED|CVf_WEAKOUTSIDE);
	    OP * const cvstart = CvSTART(cv);

	    SvPOK_off(cv);
	    CvFLAGS(cv) = CvFLAGS(compcv) | preserved_flags;
	    CvOUTSIDE(cv) = CvOUTSIDE(compcv);
	    CvOUTSIDE_SEQ(cv) = CvOUTSIDE_SEQ(compcv);
	    CvPADLIST_set(cv, CvPADLIST(compcv));
	    CvOUTSIDE(compcv) = temp_cv;
	    CvPADLIST_set(compcv, temp_padl);
	    CvSTART(cv) = CvSTART(compcv);
	    CvSTART(compcv) = cvstart;
	    CvFLAGS(compcv) &= ~(CVf_SLABBED|CVf_WEAKOUTSIDE);
	    CvFLAGS(compcv) |= other_flags;

	    if (CvFILE(cv) && CvDYNFILE(cv)) {
		Safefree(CvFILE(cv));
	    }

	    /* inner references to compcv must be fixed up ... */
	    pad_fixup_inner_anons(CvPADLIST(cv), compcv, cv);
	    if (PERLDB_INTER)/* Advice debugger on the new sub. */
                ++PL_sub_generation;
	}
	else {
	    /* Might have had built-in attributes applied -- propagate them. */
	    CvFLAGS(cv) |= (CvFLAGS(compcv) & CVf_BUILTIN_ATTRS);
	}
	/* ... before we throw it away */
	SvREFCNT_dec(compcv);
	PL_compcv = compcv = cv;
    }
    else {
	cv = compcv;
	*spot = cv;
    }

  setname:
    CvLEXICAL_on(cv);
    if (!CvNAME_HEK(cv)) {
	if (hek) (void)share_hek_hek(hek);
	else {
            dVAR;
	    U32 hash;
	    PERL_HASH(hash, PadnamePV(name)+1, PadnameLEN(name)-1);
	    hek = share_hek(PadnamePV(name)+1,
		      (PadnameLEN(name)-1) * (PadnameUTF8(name) ? -1 : 1),
		      hash);
	}
	CvNAME_HEK_set(cv, hek);
    }

    if (const_sv)
        goto clone;

    CvFILE_set_from_cop(cv, PL_curcop);
    CvSTASH_set(cv, PL_curstash);

    if (ps) {
        SV* const sv = MUTABLE_SV(cv);
	sv_setpvn(sv, ps, ps_len);
        if ( ps_utf8 && !SvUTF8(sv)) {
            if (SvIsCOW(sv)) sv_uncow(sv, 0);
            SvUTF8_on(sv);
        }
    }

    if (block) {
        /* If we assign an optree to a PVCV, then we've defined a subroutine that
           the debugger could be able to set a breakpoint in, so signal to
           pp_entereval that it should not throw away any saved lines at scope
           exit.  */
       
        PL_breakable_sub_gen++;
#ifdef PERL_DEBUG_READONLY_OPS
        slab = (OPSLAB *)CvSTART(cv);
#endif
        process_optree(cv, block, start);
    }

  attrs:
    if (attrs) {
	/* Need to do a C<use attributes $stash_of_cv,\&cv,@attrs>. */
	apply_attrs(PL_curstash, MUTABLE_SV(cv), attrs);
    }

    if (block) {
	if (PERLDB_SUBLINE && PL_curstash != PL_debstash) {
	    SV * const tmpstr = sv_newmortal();
	    GV * const db_postponed = gv_fetchpvs("DB::postponed",
						  GV_ADDMULTI, SVt_PVHV);
	    HV *hv;
	    SV * const sv = Perl_newSVpvf(aTHX_ "%s:%ld-%ld",
					  CopFILE(PL_curcop),
					  (long)PL_subline,
					  (long)CopLINE(PL_curcop));
	    if (HvNAME_HEK(PL_curstash)) {
		sv_sethek(tmpstr, HvNAME_HEK(PL_curstash));
		sv_catpvs(tmpstr, "::");
	    }
	    else
                sv_setpvs(tmpstr, "__ANON__::");

	    sv_catpvn_flags(tmpstr, PadnamePV(name)+1, PadnameLEN(name)-1,
			    PadnameUTF8(name) ? SV_CATUTF8 : SV_CATBYTES);
	    (void)hv_store(GvHV(PL_DBsub), SvPVX_const(tmpstr),
		    SvUTF8(tmpstr) ? -(I32)SvCUR(tmpstr) : (I32)SvCUR(tmpstr), sv, 0);
	    hv = GvHVn(db_postponed);
	    if (HvTOTALKEYS(hv) > 0 && hv_exists(hv, SvPVX_const(tmpstr), SvUTF8(tmpstr) ? -(I32)SvCUR(tmpstr) : (I32)SvCUR(tmpstr))) {
		CV * const pcv = GvCV(db_postponed);
		if (pcv) {
		    dSP;
		    PUSHMARK(SP);
		    XPUSHs(tmpstr);
		    PUTBACK;
		    call_sv(MUTABLE_SV(pcv), G_DISCARD);
		}
	    }
	}
    }

  clone:
    if (clonee) {
	assert(CvDEPTH(outcv));
	spot = (CV **)
	    &PadARRAY(PadlistARRAY(CvPADLIST(outcv))[CvDEPTH(outcv)])[pax];
	if (reusable)
            cv_clone_into(clonee, *spot);
	else *spot = cv_clone(clonee);
	SvREFCNT_dec_NN(clonee);
	cv = *spot;
    }

    if (CvDEPTH(outcv) && !reusable && PadnameIsSTATE(name)) {
	PADOFFSET depth = CvDEPTH(outcv);
	while (--depth) {
	    SV *oldcv;
	    svspot = &PadARRAY(PadlistARRAY(CvPADLIST(outcv))[depth])[pax];
	    oldcv = *svspot;
	    *svspot = SvREFCNT_inc_simple_NN(cv);
	    SvREFCNT_dec(oldcv);
	}
    }

  done:
    if (PL_parser)
	PL_parser->copline = NOLINE;
    LEAVE_SCOPE(floor);
#ifdef PERL_DEBUG_READONLY_OPS
    if (slab)
	Slab_to_ro(slab);
#endif
    op_free(o);
    return cv;
}

/*
=for apidoc m|CV *|newATTRSUB_x|I32 floor|OP *o|OP *proto|OP *attrs|OP *block|bool o_is_gv

Construct a Perl subroutine, also performing some surrounding jobs.

This function is expected to be called in a Perl compilation context,
and some aspects of the subroutine are taken from global variables
associated with compilation.  In particular, C<PL_compcv> represents
the subroutine that is currently being compiled.  It must be non-null
when this function is called, and some aspects of the subroutine being
constructed are taken from it.  The constructed subroutine may actually
be a reuse of the C<PL_compcv> object, but will not necessarily be so.

If C<block> is null then the subroutine will have no body, and for the
time being it will be an error to call it.  This represents a forward
subroutine declaration such as S<C<sub foo ($$);>>.  If C<block> is
non-null then it provides the Perl code of the subroutine body, which
will be executed when the subroutine is called.  This body includes
any argument unwrapping code resulting from a subroutine signature or
similar.  The pad use of the code must correspond to the pad attached
to C<PL_compcv>.  The code is not expected to include a C<leavesub> or
C<leavesublv> op; this function will add such an op.  C<block> is consumed
by this function and will become part of the constructed subroutine.

C<proto> specifies the subroutine's prototype, unless one is supplied
as an attribute (see below).  If C<proto> is null, then the subroutine
will not have a prototype.  If C<proto> is non-null, it must point to a
C<const> op whose value is a string, and the subroutine will have that
string as its prototype.  If a prototype is supplied as an attribute, the
attribute takes precedence over C<proto>, but in that case C<proto> should
preferably be null.  In any case, C<proto> is consumed by this function.

C<attrs> supplies attributes to be applied the subroutine.  A handful of
attributes take effect by built-in means, being applied to C<PL_compcv>
immediately when seen.  Other attributes are collected up and attached
to the subroutine by this route.  C<attrs> may be null to supply no
attributes, or point to a C<const> op for a single attribute, or point
to a C<list> op whose children apart from the C<pushmark> are C<const>
ops for one or more attributes.  Each C<const> op must be a string,
giving the attribute name optionally followed by parenthesised arguments,
in the manner in which attributes appear in Perl source.  The attributes
will be applied to the sub by this function.  C<attrs> is consumed by
this function.

If C<o_is_gv> is false and C<o> is null, then the subroutine will
be anonymous.  If C<o_is_gv> is false and C<o> is non-null, then C<o>
must point to a C<const> op, which will be consumed by this function,
and its string value supplies a name for the subroutine.  The name may
be qualified or unqualified, and if it is unqualified then a default
stash will be selected in some manner.  If C<o_is_gv> is true, then C<o>
doesn't point to an C<OP> at all, but is instead a cast pointer to a C<GV>
by which the subroutine will be named.

If there is already a subroutine of the specified name, then the new
sub will either replace the existing one in the glob or be merged with
the existing one.  A warning may be generated about redefinition.

If the subroutine has one of a few special names, such as C<BEGIN> or
C<END>, then it will be claimed by the appropriate queue for automatic
running of phase-related subroutines.  In this case the relevant glob will
be left not containing any subroutine, even if it did contain one before.
In the case of C<BEGIN>, the subroutine will be executed and the reference
to it disposed of before this function returns.

The function returns a pointer to the constructed subroutine.  If the sub
is anonymous then ownership of one counted reference to the subroutine
is transferred to the caller.  If the sub is named then the caller does
not get ownership of a reference.  In most such cases, where the sub
has a non-phase name, the sub will be alive at the point it is returned
by virtue of being contained in the glob that names it.  A phase-named
subroutine will usually be alive by virtue of the reference owned by the
phase's automatic run queue.  But a C<BEGIN> subroutine, having already
been executed, will quite likely have been destroyed already by the
time this function returns, making it erroneous for the caller to make
any use of the returned pointer.  It is the caller's responsibility to
ensure that it knows which of these situations applies.

=cut
*/

/* _x = extended */
CV *
Perl_newATTRSUB_x(pTHX_ I32 floor, OP *o, OP *proto, OP *attrs,
                  OP *block, bool o_is_gv)
{
    GV *gv;
    const char *ps;
    CV *cv = NULL;     /* the previous CV with this name, if any */
    SV *const_sv;
    STRLEN ps_len = 0; /* init it to avoid false uninit warning from icc */
    U32 ps_utf8 = 0;
    const bool ec = cBOOL(PL_parser && PL_parser->error_count);
    /* If the subroutine has no body, no attributes, and no builtin attributes
       then it's just a sub declaration, and we may be able to get away with
       storing with a placeholder scalar in the symbol table, rather than a
       full CV.  If anything is present then it will take a full CV to
       store it.  */
    const I32 gv_fetch_flags
	= ec ? GV_NOADD_NOINIT :
        (block || attrs || (CvFLAGS(PL_compcv) & CVf_BUILTIN_ATTRS))
	? GV_ADDMULTI : GV_ADDMULTI | GV_NOINIT;
    STRLEN namlen = 0;
    const char * const name =
	 o ? SvPV_const(o_is_gv ? (SV *)o : cSVOPo->op_sv, namlen) : NULL;
    OP *start = NULL;
    bool has_name;
    bool name_is_utf8 = o && !o_is_gv && SvUTF8(cSVOPo->op_sv);
    bool evanescent = FALSE;
#ifdef PERL_DEBUG_READONLY_OPS
    OPSLAB *slab = NULL;
#endif

    if (o_is_gv) {
	gv = (GV*)o;
	o = NULL;
	has_name = TRUE;
    } else if (name) {
	/* Try to optimise and avoid creating a GV.  Instead, the CV’s name
	   hek and CvSTASH pointer together can imply the GV.  If the name
	   contains a package name, then GvSTASH(CvGV(cv)) may differ from
	   CvSTASH, so forego the optimisation if we find any.
	   Also, we may be called from load_module at run time, so
	   PL_curstash (which sets CvSTASH) may not point to the stash the
	   sub is stored in.  */
	const I32 flags =
	   ec ? GV_NOADD_NOINIT
	      :   PL_curstash != CopSTASH(PL_curcop)
	       || memchr(name, ':', namlen)
#ifndef PERL_NO_QUOTE_PKGSEPERATOR
               || memchr(name, '\'', namlen)
#endif
		    ? gv_fetch_flags
		    : GV_ADDMULTI | GV_NOINIT | GV_NOTQUAL;
	gv = gv_fetchsv(cSVOPo->op_sv, flags, SVt_PVCV);
	has_name = TRUE;
    } else if (PERLDB_NAMEANON && CopLINE(PL_curcop)) {
	SV * const sv = sv_newmortal();
	Perl_sv_setpvf(aTHX_ sv, "%s[%s:%" IVdf "]",
		       PL_curstash ? "__ANON__" : "__ANON__::__ANON__",
		       CopFILE(PL_curcop), (IV)CopLINE(PL_curcop));
	gv = gv_fetchsv(sv, gv_fetch_flags, SVt_PVCV);
	has_name = TRUE;
    } else if (PL_curstash) {
	gv = gv_fetchpvs("__ANON__", gv_fetch_flags, SVt_PVCV);
	has_name = FALSE;
    } else {
	gv = gv_fetchpvs("__ANON__::__ANON__", gv_fetch_flags, SVt_PVCV);
	has_name = FALSE;
    }

    if (!ec) {
        if (isGV(gv)) {
            move_proto_attr(&proto, &attrs, gv, FALSE);
        } else {
            assert(cSVOPo);
            move_proto_attr(&proto, &attrs, (GV *)cSVOPo->op_sv, TRUE);
        }
    }

    if (proto) {
        if (ISNT_TYPE(proto, CONST))
            Perl_croak(aTHX_ "panic: wrong function prototype %s for %s",
                       OP_NAME(proto), name);
	ps = SvPV_const(((SVOP*)proto)->op_sv, ps_len);
        ps_utf8 = SvUTF8(((SVOP*)proto)->op_sv);
    }
    else
	ps = NULL;

    if (o)
        SAVEFREEOP(o);
    if (proto)
        SAVEFREEOP(proto);
    if (attrs)
        SAVEFREEOP(attrs);

    if (ec) {
	op_free(block);

	if (name)
            SvREFCNT_dec(PL_compcv);
	else
            cv = PL_compcv;

	PL_compcv = 0;
	if (name && block) {
	    const char *s = (char *) my_memrchr(name, ':', namlen);
	    s = s ? s+1 : name;
	    if (strEQc(s, "BEGIN")) {
		if (PL_in_eval & EVAL_KEEPERR)
		    Perl_croak_nocontext("BEGIN not safe after errors--compilation aborted");
		else {
                    SV * const errsv = ERRSV;
		    /* force display of errors found but not reported */
		    sv_catpvs(errsv, "BEGIN not safe after errors--compilation aborted");
		    Perl_croak_nocontext("%" SVf, SVfARG(errsv));
		}
	    }
	}
	goto done;
    }

    if (!block && SvTYPE(gv) != SVt_PVGV) {
        /* If we are not defining a new sub and the existing one is not a
           full GV + CV... */
        if (attrs || (CvFLAGS(PL_compcv) & CVf_BUILTIN_ATTRS)) {
            /* We are applying attributes to an existing sub, so we need it
               upgraded if it is a constant.  */
            if (SvROK(gv) && SvTYPE(SvRV(gv)) != SVt_PVCV)
                gv_init_pvn(gv, PL_curstash, name, namlen,
                            SVf_UTF8 * name_is_utf8);
        }
        else {			/* Maybe prototype now, and had at maximum
				   a prototype or const/sub ref before.  */
            if (SvTYPE(gv) > SVt_NULL) {
                cv_ckproto_len_flags((const CV *)gv,
                                     o ? (const GV *)cSVOPo->op_sv : NULL, ps,
                                     ps_len, ps_utf8);
            }
            if (!SvROK(gv)) {
                SV* const sv = MUTABLE_SV(gv);
                if (ps) {
                    sv_setpvn(sv, ps, ps_len);
                    if ( ps_utf8 && !SvUTF8(sv)) {
                        if (SvIsCOW(sv)) sv_uncow(sv, 0);
                        SvUTF8_on(sv);
                    }
                }
                else
                    sv_setiv(sv, -1);
            }

            if (!SvROK(gv)) {
                if (ps) {
                    sv_setpvn(MUTABLE_SV(gv), ps, ps_len);
                    if (ps_utf8)
                        SvUTF8_on(MUTABLE_SV(gv));
                }
                else
                    sv_setiv(MUTABLE_SV(gv), -1);
            }

            SvREFCNT_dec(PL_compcv);
            cv = PL_compcv = NULL;
            goto done;
        }
    }

    cv = (!name || (isGV(gv) && GvCVGEN(gv)))
	? NULL
	: isGV(gv)
	    ? GvCV(gv)
	    : SvROK(gv) && SvTYPE(SvRV(gv)) == SVt_PVCV
		? (CV *)SvRV(gv)
		: NULL;

    if (block) {
	assert(PL_parser);
	/* This makes sub {}; work as expected.  */
	if (IS_TYPE(block, STUB)) {
	    const line_t l = PL_parser->copline;
	    op_free(block);
	    block = newSTATEOP(0, NULL, 0);
	    PL_parser->copline = l;
	}
	block = CvLVALUE(PL_compcv)
	     || (cv && CvLVALUE(cv) && !CvROOT(cv) && !CvXSUB(cv)
		    && (!isGV(gv) || !GvASSUMECV(gv)))
		   ? newUNOP(OP_LEAVESUBLV, 0,
			     op_lvalue(scalarseq(block), OP_LEAVESUBLV))
		   : newUNOP(OP_LEAVESUB, 0, scalarseq(block));
	start = LINKLIST(block);
	OpNEXT(block) = NULL;
        /* XXX attrs might be :const */
        if (ps && !*ps && !attrs && !CvLVALUE(PL_compcv))
            const_sv = op_const_sv(start, PL_compcv,
                                   cBOOL(CvCLONE(PL_compcv)));
        else
            const_sv = NULL;
    }

    if (!block
#ifndef USE_CPERL_not_yet
        /* allow inlining of constant bodies on cperl even without empty proto*/
        || !ps || *ps /* perl5: sub x{1} => no proto, so not inlinable */
#endif
        /* the core attrs are already applied and attrs will be empty.
           we need to keep the cv to call user-attrs on it. */
        || attrs
	|| CvLVALUE(PL_compcv)
	) {
	const_sv = NULL;
    } else
        /* check the body if it's in-lineable.
           TODO: return an OP* to be able to inline more ops than just one SV*.
           TODO: should :const enforce inlining?
           TODO: has $const :const = 1; method x { $self->{const} }
         */
	const_sv = op_const_sv(start, PL_compcv, cBOOL(CvCLONE(PL_compcv)));

    if (SvPOK(gv) || (SvROK(gv) && SvTYPE(SvRV(gv)) != SVt_PVCV)) {
	cv_ckproto_len_flags((const CV *)gv,
			     o ? (const GV *)cSVOPo->op_sv : NULL, ps,
			     ps_len, ps_utf8|CV_CKPROTO_CURSTASH);
	if (SvROK(gv)) {
	    /* All the other code for sub redefinition warnings expects the
	       clobbered sub to be a CV.  Instead of making all those code
	       paths more complex, just inline the RV version here.  */
	    const line_t oldline = CopLINE(PL_curcop);
	    assert(IN_PERL_COMPILETIME);
	    if (PL_parser && PL_parser->copline != NOLINE)
		/* This ensures that warnings are reported at the first
		   line of a redefinition, not the last.  */
		CopLINE_set(PL_curcop, PL_parser->copline);
	    /* protect against fatal warnings leaking compcv */
	    SAVEFREESV(PL_compcv);

	    if (ckWARN(WARN_REDEFINE)
	     || (  ckWARN_d(WARN_REDEFINE)
		&& (  !const_sv || SvRV(gv) == const_sv
		   || sv_cmp(SvRV(gv), const_sv)  ))) {
                assert(cSVOPo);
		Perl_warner(aTHX_ packWARN(WARN_REDEFINE),
			  "Constant subroutine %" SVf " redefined",
			  SVfARG(cSVOPo->op_sv));
            }

	    SvREFCNT_inc_simple_void_NN(PL_compcv);
	    CopLINE_set(PL_curcop, oldline);
	    SvREFCNT_dec(SvRV(gv));
	}
    }

    if (cv) {
        const bool exists = cBOOL(CvROOT(cv) || CvXSUB(cv));

        /* if the subroutine doesn't exist and wasn't pre-declared
         * with a prototype, assume it will be AUTOLOADed,
         * skipping the prototype check
         */
        if (exists || SvPOK(cv))
            cv_ckproto_len_flags(cv, gv, ps, ps_len, ps_utf8);
	/* already defined (or promised)? */
	if (exists || (isGV(gv) && GvASSUMECV(gv))) {
	    S_already_defined(aTHX_ cv, block, o, NULL, &const_sv);
            if (block)
		cv = NULL;
	    else {
		if (attrs)
                    goto attrs;
		/* just a "sub foo;" when &foo is already defined */
		SAVEFREESV(PL_compcv);
		goto done;
	    }
	}
    }

    /* inline the SV* by creating a CONSTSUB constant.
       note that we cannot inline OP*'s here yet, as const_sv && cv is
       used for something else.
     */
    if (const_sv) {
	SvREFCNT_inc_simple_void_NN(const_sv);
	SvFLAGS(const_sv) |= SVs_PADTMP;
	if (cv) { /* we need to keep the ENTERSUB */
            /* use an intermediate XS call to a dummy const_sv_xsub with
               the any_ptr as value*/
	    assert(!CvROOT(cv) && !CvCONST(cv));
	    cv_forget_slab(cv);
            SvPVCLEAR(MUTABLE_SV(cv));  /* prototype is "" */
	    CvXSUBANY(cv).any_ptr = const_sv;
	    CvXSUB(cv) = S_const_sv_xsub;
	    CvCONST_on(cv);
	    CvISXSUB_on(cv);
	    PoisonPADLIST(cv);
	    CvFLAGS(cv) |= CvMETHOD(PL_compcv);
	}
	else {
	    if (isGV(gv) || CvMETHOD(PL_compcv)) {
		if (name && isGV(gv))
		    GvCV_set(gv, NULL);
		cv = newCONSTSUB_flags(
		    NULL, name, namlen, name_is_utf8 ? SVf_UTF8 : 0,
		    const_sv);
		assert(cv);
		assert(SvREFCNT((SV*)cv) != 0);
		CvFLAGS(cv) |= CvMETHOD(PL_compcv);
	    }
	    else {
		if (!SvROK(gv)) {
		    SV_CHECK_THINKFIRST_COW_DROP((SV *)gv);
		    prepare_SV_for_RV((SV *)gv);
		    SvOK_off((SV *)gv);
		    SvROK_on(gv);
		}
		SvRV_set(gv, const_sv);
	    }
	}
	op_free(block);
	SvREFCNT_dec(PL_compcv);
	PL_compcv = NULL;
	goto done;
    }

    /* don't copy new BEGIN CV to old BEGIN CV - RT #129099 */
    if (name && cv && *name == 'B' && strEQ(name, "BEGIN"))
        cv = NULL;

    if (cv) {				/* must reuse cv if autoloaded */
	/* transfer PL_compcv to cv */
	if (block) {
	    cv_flags_t existing_builtin_attrs = CvFLAGS(cv) & CVf_BUILTIN_ATTRS;
	    PADLIST *const temp_av = CvPADLIST(cv);
	    CV *const temp_cv = CvOUTSIDE(cv);
	    const cv_flags_t other_flags =
		CvFLAGS(cv) & (CVf_SLABBED|CVf_WEAKOUTSIDE);
	    OP * const cvstart = CvSTART(cv);

	    if (isGV(gv)) {
		CvGV_set(cv,gv);
		assert(!CvCVGV_RC(cv));
		assert(CvGV(cv) == gv);
	    }
	    else {
		dVAR;
		U32 hash;
		PERL_HASH(hash, name, namlen);
                if (UNLIKELY(namlen > I32_MAX))
                    Perl_croak(aTHX_ "panic: name too long (%" UVuf ")", (UV) namlen);
		CvNAME_HEK_set(cv,
			       share_hek(name,
					 name_is_utf8
					    ? -(I32)namlen
					    :  (I32)namlen,
					 hash));
	    }

	    SvPOK_off(cv);
	    CvFLAGS(cv) = CvFLAGS(PL_compcv) | existing_builtin_attrs
					     | CvNAMED(cv);
	    CvOUTSIDE(cv) = CvOUTSIDE(PL_compcv);
	    CvOUTSIDE_SEQ(cv) = CvOUTSIDE_SEQ(PL_compcv);
	    CvPADLIST_set(cv,CvPADLIST(PL_compcv));
	    CvOUTSIDE(PL_compcv) = temp_cv;
	    CvPADLIST_set(PL_compcv, temp_av);
	    CvSTART(cv) = CvSTART(PL_compcv);
	    CvSTART(PL_compcv) = cvstart;
	    CvFLAGS(PL_compcv) &= ~(CVf_SLABBED|CVf_WEAKOUTSIDE);
	    CvFLAGS(PL_compcv) |= other_flags;

	    if (CvFILE(cv) && CvDYNFILE(cv)) {
		Safefree(CvFILE(cv));
            }
	    CvFILE_set_from_cop(cv, PL_curcop);
	    CvSTASH_set(cv, PL_curstash);

	    /* inner references to PL_compcv must be fixed up ... */
	    pad_fixup_inner_anons(CvPADLIST(cv), PL_compcv, cv);
	    if (PERLDB_INTER)/* Advice debugger on the new sub. */
                ++PL_sub_generation;
            DEBUG_Xv(padlist_dump(CvPADLIST(cv)));
	}
	else {
	    /* Might have had built-in attributes applied -- propagate them. */
	    CvFLAGS(cv) |= (CvFLAGS(PL_compcv) & CVf_BUILTIN_ATTRS);
	}
	/* ... before we throw it away */
	SvREFCNT_dec(PL_compcv);
	PL_compcv = cv;
    }
    else {
	cv = PL_compcv;
	if (name && isGV(gv)) {
	    GvCV_set(gv, cv);
	    GvCVGEN(gv) = 0;
	    if (HvENAME_HEK(GvSTASH(gv)))
		/* sub Foo::bar { (shift)+1 } */
		gv_method_changed(gv);
	}
	else if (name) {
	    if (!SvROK(gv)) {
		SV_CHECK_THINKFIRST_COW_DROP((SV *)gv);
		prepare_SV_for_RV((SV *)gv);
		SvOK_off((SV *)gv);
		SvROK_on(gv);
	    }
	    SvRV_set(gv, (SV *)cv);
	}
    }
    assert(cv);
    assert(SvREFCNT((SV*)cv) != 0);

    if (!CvHASGV(cv)) {
	if (isGV(gv))
            CvGV_set(cv, gv);
	else {
            dVAR;
	    U32 hash;
	    PERL_HASH(hash, name, namlen);
            if (UNLIKELY(namlen > I32_MAX))
                Perl_croak(aTHX_ "panic: name too long (%" UVuf ")", (UV) namlen);
	    CvNAME_HEK_set(cv, share_hek(name,
					 name_is_utf8
					    ? -(I32)namlen
					    :  (I32)namlen,
					 hash));
	}
	CvFILE_set_from_cop(cv, PL_curcop);
	CvSTASH_set(cv, PL_curstash);
    }

    if (ps) {
        SV* const sv = MUTABLE_SV(cv);
	sv_setpvn(sv, ps, ps_len);
        if ( ps_utf8 && !SvUTF8(sv) ) {
            if (SvIsCOW(sv)) sv_uncow(sv, 0);
            SvUTF8_on(sv);
        }
    }

    if (block) {
        /* If we assign an optree to a PVCV, then we've defined a subroutine that
           the debugger could be able to set a breakpoint in, so signal to
           pp_entereval that it should not throw away any saved lines at scope
           exit.  */
       
        PL_breakable_sub_gen++;
#ifdef PERL_DEBUG_READONLY_OPS
        slab = (OPSLAB *)CvSTART(cv);
#endif
        process_optree(cv, block, start);
    }

  attrs:
    if (attrs) {
	/* Need to do a C<use attributes $stash_of_cv,\&cv,@attrs>. */
	HV *stash = name && !CvNAMED(cv) && GvSTASH(CvGV(cv))
			? GvSTASH(CvGV(cv))
			: PL_curstash;
	if (!name) {
            SAVEFREESV(cv);
        }
	apply_attrs(stash, MUTABLE_SV(cv), attrs);
	if (!name)
            SvREFCNT_inc_simple_void_NN(cv);
    }

    if (block && has_name) {
	if (PERLDB_SUBLINE && PL_curstash != PL_debstash) {
	    SV * const tmpstr = cv_name(cv, NULL, CV_NAME_NOMAIN);
	    GV * const db_postponed = gv_fetchpvs("DB::postponed",
						  GV_ADDMULTI, SVt_PVHV);
	    HV *hv;
            I32 klen = SvUTF8(tmpstr) ? -(I32)SvCUR(tmpstr) : (I32)SvCUR(tmpstr);
	    SV * const sv = Perl_newSVpvf(aTHX_ "%s:%ld-%ld",
					  CopFILE(PL_curcop),
					  (long)PL_subline,
					  (long)CopLINE(PL_curcop));
	    (void)hv_store(GvHV(PL_DBsub), SvPVX_const(tmpstr), klen, sv, 0);
	    hv = GvHVn(db_postponed);
	    if (HvTOTALKEYS(hv) > 0 && hv_exists(hv, SvPVX_const(tmpstr), klen)) {
		CV * const pcv = GvCV(db_postponed);
		if (pcv) {
		    dSP;
		    PUSHMARK(SP);
		    XPUSHs(tmpstr);
		    PUTBACK;
		    call_sv(MUTABLE_SV(pcv), G_DISCARD);
		}
	    }
	}

        if (name) {
            if (PL_parser && PL_parser->error_count)
                clear_special_blocks(name, gv, cv);
            else
                evanescent = process_special_blocks(floor, name, gv, cv);
        }
    }
    assert(cv);

  done:
    assert(!cv || evanescent || SvREFCNT((SV*)cv) != 0);
    if (PL_parser)
	PL_parser->copline = NOLINE;
    LEAVE_SCOPE(floor);

    assert(!cv || evanescent || SvREFCNT((SV*)cv) != 0);
    if (!evanescent) {
#ifdef PERL_DEBUG_READONLY_OPS
    if (slab)
	Slab_to_ro(slab);
#endif
    if (cv && name && block && CvOUTSIDE(cv) && !CvEVAL(CvOUTSIDE(cv)))
	pad_add_weakref(cv);
    }
    return cv;
}

static void
S_clear_special_blocks(pTHX_ const char *const fullname,
                       GV *const gv, CV *const cv) {
    const char *colon;
    const char *name;

    PERL_ARGS_ASSERT_CLEAR_SPECIAL_BLOCKS;

    colon = strrchr(fullname,':');
    name = colon ? colon + 1 : fullname;

    if ((*name == 'B' && strEQc(name, "BEGIN"))
     || (*name == 'E' && strEQc(name, "END"))
     || (*name == 'U' && strEQc(name, "UNITCHECK"))
     || (*name == 'C' && strEQc(name, "CHECK"))
     || (*name == 'I' && strEQc(name, "INIT"))) {
        if (!isGV(gv)) {
            (void)CvGV(cv);
            assert(isGV(gv));
        }
        GvCV_set(gv, NULL);
        SvREFCNT_dec_NN(MUTABLE_SV(cv));
    }
}

/* Returns true if the sub has been freed.  */
static bool
S_process_special_blocks(pTHX_ I32 floor, const char *const fullname,
			 GV *const gv,
			 CV *const cv)
{
    const char *const colon = strrchr(fullname,':');
    const char *const name = colon ? colon + 1 : fullname;

    PERL_ARGS_ASSERT_PROCESS_SPECIAL_BLOCKS;

    if (*name == 'B') {
	if (strEQc(name, "BEGIN")) {
	    const I32 oldscope = PL_scopestack_ix;
            dSP;
            (void)CvGV(cv);
	    if (floor) LEAVE_SCOPE(floor);
	    ENTER;
            PUSHSTACKi(PERLSI_REQUIRE);
	    SAVECOPFILE(&PL_compiling);
	    SAVECOPLINE(&PL_compiling);
	    SAVEVPTR(PL_curcop);

	    DEBUG_x( dump_sub(gv) );
	    Perl_av_create_and_push(aTHX_ &PL_beginav, MUTABLE_SV(cv));
	    GvCV_set(gv,0);		/* cv has been hijacked */
	    call_list(oldscope, PL_beginav);

            POPSTACK;
	    LEAVE;
	    return !PL_savebegin;
	}
	else
	    return FALSE;
    } else {
	if (*name == 'E') {
	    if strEQc(name, "END") {
		DEBUG_x( dump_sub(gv) );
		Perl_av_create_and_unshift_one(aTHX_ &PL_endav, MUTABLE_SV(cv));
	    } else
		return FALSE;
	} else if (*name == 'U') {
	    if (strEQc(name, "UNITCHECK")) {
		/* It's never too late to run a unitcheck block */
		Perl_av_create_and_unshift_one(aTHX_ &PL_unitcheckav, MUTABLE_SV(cv));
	    }
	    else
		return FALSE;
	} else if (*name == 'C') {
	    if (strEQc(name, "CHECK")) {
		if (PL_main_start)
		    /* diag_listed_as: Too late to run %s block */
		    Perl_ck_warner(aTHX_ packWARN(WARN_VOID),
				   "Too late to run CHECK block");
		Perl_av_create_and_unshift_one(aTHX_ &PL_checkav, MUTABLE_SV(cv));
	    }
	    else
		return FALSE;
	} else if (*name == 'I') {
	    if (strEQc(name, "INIT")) {
		if (PL_main_start)
		    /* diag_listed_as: Too late to run %s block */
		    Perl_ck_warner(aTHX_ packWARN(WARN_VOID),
				   "Too late to run INIT block");
		Perl_av_create_and_push(aTHX_ &PL_initav, MUTABLE_SV(cv));
	    }
	    else
		return FALSE;
	} else
	    return FALSE;
	DEBUG_x( dump_sub(gv) );
	(void)CvGV(cv);
	GvCV_set(gv,0);		/* cv has been hijacked */
	return FALSE;
    }
}

/*
=for apidoc Am|CV *|newCONSTSUB|HV *stash|const char *name|SV *sv

Behaves like L</newCONSTSUB_flags>, except that C<name> is nul-terminated
rather than of counted length, and no flags are set.  (This means that
C<name> is always interpreted as Latin-1.)

=cut
*/

CV *
Perl_newCONSTSUB(pTHX_ HV *stash, const char *name, SV *sv)
{
    return newCONSTSUB_flags(stash, name, name ? strlen(name) : 0, 0, sv);
}

/*
=for apidoc Am|CV *|newCONSTSUB_flags|HV *stash|const char *name|STRLEN len|U32 flags|SV *sv

Construct a constant subroutine, also performing some surrounding
jobs.  A scalar constant-valued subroutine is eligible for inlining
at compile-time, and in Perl code can be created by S<C<sub FOO () {
123 }>>.  Other kinds of constant subroutine have other treatment.

The subroutine will have an empty prototype and will ignore any arguments
when called.  Its constant behaviour is determined by C<sv>.  If C<sv>
is null, the subroutine will yield an empty list.  If C<sv> points to a
scalar, the subroutine will always yield that scalar.  If C<sv> points
to an array, the subroutine will always yield a list of the elements of
that array in list context, or the number of elements in the array in
scalar context.  This function takes ownership of one counted reference
to the scalar or array, and will arrange for the object to live as long
as the subroutine does.  If C<sv> points to a scalar then the inlining
assumes that the value of the scalar will never change, so the caller
must ensure that the scalar is not subsequently written to.  If C<sv>
points to an array then no such assumption is made, so it is ostensibly
safe to mutate the array or its elements, but whether this is really
supported has not been determined.

The subroutine will have C<CvFILE> set according to C<PL_curcop>.
Other aspects of the subroutine will be left in their default state.
The caller is free to mutate the subroutine beyond its initial state
after this function has returned.

If C<name> is null then the subroutine will be anonymous, with its
C<CvGV> referring to an C<__ANON__> glob.  If C<name> is non-null then the
subroutine will be named accordingly, referenced by the appropriate glob.
C<name> is a string of length C<len> bytes giving a sigilless symbol
name, in UTF-8 if C<flags> has the C<SVf_UTF8> bit set and in Latin-1
otherwise.  The name may be either qualified or unqualified.  If the
name is unqualified then it defaults to being in the stash specified by
C<stash> if that is non-null, or to C<PL_curstash> if C<stash> is null.
The symbol is always added to the stash if necessary, with C<GV_ADDMULTI>
semantics.

C<flags> for the CV should not have bits set other than C<SVf_UTF8>
or C<CVf_NODEBUG> for empty imports.

If there is already a subroutine of the specified name, then the new sub
will replace the existing one in the glob.  A warning may be generated
about the redefinition.

If the subroutine has one of a few special names, such as C<BEGIN> or
C<END>, then it will be claimed by the appropriate queue for automatic
running of phase-related subroutines.  In this case the relevant glob will
be left not containing any subroutine, even if it did contain one before.
Execution of the subroutine will likely be a no-op, unless C<sv> was
a tied array or the caller modified the subroutine in some interesting
way before it was executed.  In the case of C<BEGIN>, the treatment is
buggy: the sub will be executed when only half built, and may be deleted
prematurely, possibly causing a crash.

The function returns a pointer to the constructed subroutine.  If the sub
is anonymous then ownership of one counted reference to the subroutine
is transferred to the caller.  If the sub is named then the caller does
not get ownership of a reference.  In most such cases, where the sub
has a non-phase name, the sub will be alive at the point it is returned
by virtue of being contained in the glob that names it.  A phase-named
subroutine will usually be alive by virtue of the reference owned by
the phase's automatic run queue.  A C<BEGIN> subroutine may have been
destroyed already by the time this function returns, but currently bugs
occur in that case before the caller gets control.  It is the caller's
responsibility to ensure that it knows which of these situations applies.

=cut
*/

CV *
Perl_newCONSTSUB_flags(pTHX_ HV *stash, const char *name, STRLEN len,
                             U32 flags, SV *sv)
{
    CV* cv;
    const char *const file = CopFILE(PL_curcop);

    ENTER;

    if (IN_PERL_RUNTIME) {
	/* at runtime, it's not safe to manipulate PL_curcop: it may be
	 * an op shared between threads. Use a non-shared COP for our
	 * dirty work */
	 SAVEVPTR(PL_curcop);
	 SAVECOMPILEWARNINGS();
	 PL_compiling.cop_warnings = DUP_WARNINGS(PL_curcop->cop_warnings);
	 PL_curcop = &PL_compiling;
    }
    SAVECOPLINE(PL_curcop);
    CopLINE_set(PL_curcop, PL_parser ? PL_parser->copline : NOLINE);

    SAVEHINTS();
    PL_hints &= ~HINT_BLOCK_SCOPE;

    if (stash) {
	SAVEGENERICSV(PL_curstash);
	PL_curstash = (HV *)SvREFCNT_inc_simple_NN(stash);
    }

    /* Protect sv against leakage caused by fatal warnings. */
    if (sv) { SAVEFREESV(sv); }

    /* file becomes the CvFILE. For an XS, it's usually static storage,
       and so doesn't get free()d.  (It's expected to be from the C pre-
       processor __FILE__ directive). But we need a dynamically allocated one,
       and we need it to get freed.  */
    cv = newXS_len_flags(name, len,
			 sv && SvTYPE(sv) == SVt_PVAV
			     ? S_const_av_xsub
			     : S_const_sv_xsub,
			 file ? file : "", "",
			 &sv, XS_DYNAMIC_FILENAME | flags);
    assert(cv);
    assert(SvREFCNT((SV*)cv) != 0);
    CvXSUBANY(cv).any_ptr = SvREFCNT_inc_simple(sv);
    CvCONST_on(cv);

    LEAVE;

    return cv;
}

/*
=for apidoc U||newXS

Used by C<xsubpp> to hook up XSUBs as Perl subs.  C<filename> needs to be
static storage, as it is used directly as CvFILE(), without a copy being made.

=cut
*/

CV *
Perl_newXS(pTHX_ const char *name, XSUBADDR_t subaddr, const char *filename)
{
    PERL_ARGS_ASSERT_NEWXS;
    return newXS_len_flags(
	name, name ? strlen(name) : 0, subaddr, filename, NULL, NULL, 0
    );
}

CV *
Perl_newXS_flags(pTHX_ const char *name, XSUBADDR_t subaddr,
		 const char *const filename, const char *const proto,
		 U32 flags)
{
    PERL_ARGS_ASSERT_NEWXS_FLAGS;
    return newXS_len_flags(
       name, name ? strlen(name) : 0, subaddr, filename, proto, NULL, flags
    );
}

CV *
Perl_newXS_deffile(pTHX_ const char *name, XSUBADDR_t subaddr)
{
    PERL_ARGS_ASSERT_NEWXS_DEFFILE;
    return newXS_len_flags(
        name, strlen(name), subaddr, NULL, NULL, NULL, 0
    );
}

/*
=for apidoc m|CV *|newXS_len_flags|const char *name|STRLEN len|XSUBADDR_t subaddr|const char *const filename|NULLOK const char *const proto|NULLOK SV **const_svp|U32 flags

Construct an XS subroutine, also performing some surrounding jobs.

The subroutine will have the entry point C<subaddr>.  It will have
the prototype specified by the nul-terminated string C<proto>, or
no prototype if C<proto> is null.  The prototype string is copied;
the caller can mutate the supplied string afterwards.  If C<filename>
is non-null, it must be a nul-terminated filename, and the subroutine
will have its C<CvFILE> set accordingly.  By default C<CvFILE> is set to
point directly to the supplied string, which must be static.  If C<flags>
has the C<XS_DYNAMIC_FILENAME> bit set, then a copy of the string will
be taken instead.

Other aspects of the subroutine will be left in their default state.
If anything else needs to be done to the subroutine for it to function
correctly, it is the caller's responsibility to do that after this
function has constructed it.  However, beware of the subroutine
potentially being destroyed before this function returns, as described
below.

If C<name> is null then the subroutine will be anonymous, with its
C<CvGV> referring to an C<__ANON__> glob.  If C<name> is non-null then the
subroutine will be named accordingly, referenced by the appropriate glob.
C<name> is a string of length C<len> bytes giving a sigilless symbol name,
in UTF-8 if C<flags> has the C<SVf_UTF8> bit set and in Latin-1 otherwise.
The name may be either qualified or unqualified, with the stash defaulting
in the same manner as for C<gv_fetchpvn_flags>.  C<flags> may contain
flag bits understood by C<gv_fetchpvn_flags> with the same meaning as
they have there, such as C<GV_ADDWARN>.  The symbol is always added to
the stash if necessary, with C<GV_ADDMULTI> semantics.

If there is already a subroutine of the specified name, then the new sub
will replace the existing one in the glob.  A warning may be generated
about the redefinition.  If the old subroutine was C<CvCONST> then the
decision about whether to warn is influenced by an expectation about
whether the new subroutine will become a constant of similar value.
That expectation is determined by C<const_svp>.  (Note that the call to
this function doesn't make the new subroutine C<CvCONST> in any case;
that is left to the caller.)  If C<const_svp> is null then it indicates
that the new subroutine will not become a constant.  If C<const_svp>
is non-null then it indicates that the new subroutine will become a
constant, and it points to an C<SV*> that provides the constant value
that the subroutine will have.

If the subroutine has one of a few special names, such as C<BEGIN> or
C<END>, then it will be claimed by the appropriate queue for automatic
running of phase-related subroutines.  In this case the relevant glob will
be left not containing any subroutine, even if it did contain one before.
In the case of C<BEGIN>, the subroutine will be executed and the reference
to it disposed of before this function returns, and also before its
prototype is set.  If a C<BEGIN> subroutine would not be sufficiently
constructed by this function to be ready for execution then the caller
must prevent this happening by giving the subroutine a different name.

The function returns a pointer to the constructed subroutine.  If the sub
is anonymous then ownership of one counted reference to the subroutine
is transferred to the caller.  If the sub is named then the caller does
not get ownership of a reference.  In most such cases, where the sub
has a non-phase name, the sub will be alive at the point it is returned
by virtue of being contained in the glob that names it.  A phase-named
subroutine will usually be alive by virtue of the reference owned by the
phase's automatic run queue.  But a C<BEGIN> subroutine, having already
been executed, will quite likely have been destroyed already by the
time this function returns, making it erroneous for the caller to make
any use of the returned pointer.  It is the caller's responsibility to
ensure that it knows which of these situations applies.

=cut
*/

CV *
Perl_newXS_len_flags(pTHX_ const char *name, STRLEN len,
			   XSUBADDR_t subaddr, const char *const filename,
			   const char *const proto, SV **const_svp,
			   U32 flags)
{
    CV *cv;
    bool interleave = FALSE;
    bool evanescent = FALSE;

    PERL_ARGS_ASSERT_NEWXS_LEN_FLAGS;

    {
        GV * const gv = gv_fetchpvn(
			    name ? name : PL_curstash ? "__ANON__" : "__ANON__::__ANON__",
			    name ? len : PL_curstash ? sizeof("__ANON__") - 1:
				sizeof("__ANON__::__ANON__") - 1,
			    GV_ADDMULTI | flags, SVt_PVCV);

        if ((cv = (name ? GvCV(gv) : NULL))) {
            if (GvCVGEN(gv)) {
                /* just a cached method */
                SvREFCNT_dec(cv);
                cv = NULL;
            }
            else if (CvROOT(cv) || CvXSUB(cv) || GvASSUMECV(gv)) {
                /* already defined (or promised) */
                /* Redundant check that allows us to avoid creating an SV
                   most of the time: */
                if (CvCONST(cv) || ckWARN(WARN_REDEFINE)) {
                    report_redefined_cv(newSVpvn_flags(
                                         name,len,(flags&SVf_UTF8)|SVs_TEMP
                                        ),
                                        cv, const_svp);
                }
                /* TODO with CvROOT(cv) it would be nice if the entersub ops using
                   this function could be changed to enterxssub after the fact. For now
                   we are patching the op when being called. */
                interleave = TRUE;
                ENTER;
                SAVEFREESV(cv);
                cv = NULL;
            }
        }
    
        if (cv)				/* must reuse cv if autoloaded */
            cv_undef(cv);
        else {
            cv = MUTABLE_CV(newSV_type(SVt_PVCV));
            if (name) {
                GvCV_set(gv,cv);
                GvCVGEN(gv) = 0;
                if (HvENAME_HEK(GvSTASH(gv)))
                    gv_method_changed(gv); /* newXS */
            }
        }
	assert(cv);
	assert(SvREFCNT((SV*)cv) != 0);

        GvXSCV_on(gv);
        CvGV_set(cv, gv);
        if (filename) {
            /* XSUBs can't be perl lang/perl5db.pl debugged
            if (PERLDB_LINE_OR_SAVESRC)
                (void)gv_fetchfile(filename); */
            assert(!CvDYNFILE(cv)); /* cv_undef should have turned it off */
            if (flags & XS_DYNAMIC_FILENAME) {
                CvDYNFILE_on(cv);
                CvFILE(cv) = savepv(filename);
            } else {
            /* NOTE: not copied, as it is expected to be an external constant string */
                CvFILE(cv) = (char *)filename;
            }
        } else {
            assert((flags & XS_DYNAMIC_FILENAME) == 0 && PL_xsubfilename);
            CvFILE(cv) = (char*)PL_xsubfilename;
        }
        CvISXSUB_on(cv);
        CvXSUB(cv) = subaddr;
#ifndef PERL_IMPLICIT_CONTEXT
        CvHSCXT(cv) = &PL_stack_sp;
#else
        PoisonPADLIST(cv);
#endif

        if (name)
            evanescent = process_special_blocks(0, name, gv, cv);
        else
            CvANON_on(cv);
    } /* <- not a conditional branch */

    assert(cv);
    assert(evanescent || SvREFCNT((SV*)cv) != 0);

    if (!evanescent) sv_setpv(MUTABLE_SV(cv), proto);
    if (interleave) LEAVE;
    assert(evanescent || SvREFCNT((SV*)cv) != 0);
    return cv;
}

CV *
Perl_newSTUB(pTHX_ GV *gv, bool fake)
{
    CV *cv = MUTABLE_CV(newSV_type(SVt_PVCV));
    GV *cvgv;
    PERL_ARGS_ASSERT_NEWSTUB;
    assert(!GvCVu(gv));
    GvCV_set(gv, cv);
    GvCVGEN(gv) = 0;
    if (!fake && GvSTASH(gv) && HvENAME_HEK(GvSTASH(gv)))
	gv_method_changed(gv);
    if (SvFAKE(gv)) {
	cvgv = gv_fetchsv((SV *)gv, GV_ADDMULTI, SVt_PVCV);
	SvFAKE_off(cvgv);
    }
    else cvgv = gv;
    CvGV_set(cv, cvgv);
    CvFILE_set_from_cop(cv, PL_curcop);
    CvSTASH_set(cv, PL_curstash);
    GvMULTI_on(gv);
    return cv;
}

void
Perl_newFORM(pTHX_ I32 floor, OP *o, OP *block)
{
    CV *cv;
    GV *gv;
    OP *start, *root;

    if (PL_parser && PL_parser->error_count) {
	op_free(block);
	goto finish;
    }

    gv = o
	? gv_fetchsv(cSVOPo->op_sv, GV_ADD, SVt_PVFM)
	: gv_fetchpvs("STDOUT", GV_ADD|GV_NOTQUAL, SVt_PVFM);

    GvMULTI_on(gv);
    if ((cv = GvFORM(gv))) {
	if (ckWARN(WARN_REDEFINE)) {
	    const line_t oldline = CopLINE(PL_curcop);
	    if (PL_parser && PL_parser->copline != NOLINE)
		CopLINE_set(PL_curcop, PL_parser->copline);
	    if (o) {
		Perl_warner(aTHX_ packWARN(WARN_REDEFINE),
			    "Format %" SVf " redefined", SVfARG(cSVOPo->op_sv));
	    } else {
		/* diag_listed_as: Format %s redefined */
		Perl_warner(aTHX_ packWARN(WARN_REDEFINE),
			    "Format STDOUT redefined");
	    }
	    CopLINE_set(PL_curcop, oldline);
	}
	SvREFCNT_dec(cv);
    }
    cv = PL_compcv;
    GvFORM(gv) = (CV *)SvREFCNT_inc_simple_NN(cv);
    CvGV_set(cv, gv);
    CvFILE_set_from_cop(cv, PL_curcop);


    root = newUNOP(OP_LEAVEWRITE, 0, scalarseq(block));
    start = LINKLIST(root);
    OpNEXT(root) = NULL;
    process_optree(cv, root, start);
    cv_forget_slab(cv);

  finish:
    op_free(o);
    if (PL_parser)
	PL_parser->copline = NOLINE;
    LEAVE_SCOPE(floor);
    PL_compiling.cop_seq = 0;
}

OP *
Perl_newANONLIST(pTHX_ OP *o)
{
    return op_convert_list(OP_ANONLIST, OPf_SPECIAL, o);
}

OP *
Perl_newANONHASH(pTHX_ OP *o)
{
    return op_convert_list(OP_ANONHASH, OPf_SPECIAL, o);
}

OP *
Perl_newANONSUB(pTHX_ I32 floor, OP *proto, OP *block)
{
    return newANONATTRSUB(floor, proto, NULL, block);
}

OP *
Perl_newANONATTRSUB(pTHX_ I32 floor, OP *proto, OP *attrs, OP *block)
{
    SV * const cv = MUTABLE_SV(newATTRSUB(floor, 0, proto, attrs, block));
    OP * anoncode;
    if (LIKELY(cv))
        anoncode = newSVOP(OP_ANONCODE, 0, cv);
    else
	Perl_croak(aTHX_ "panic: newANONATTRSUB. empty cv");
    if (CvANONCONST(cv))
	anoncode = newUNOP(OP_ANONCONST, 0,
			   op_convert_list(OP_ENTERSUB,
					   OPf_STACKED|OPf_WANT_SCALAR,
					   anoncode));
    return newUNOP(OP_REFGEN, 0, anoncode);
}

OP *
Perl_oopsAV(pTHX_ OP *o)
{
    dVAR;

    PERL_ARGS_ASSERT_OOPSAV;

    switch (o->op_type) {
    case OP_PADSV:
    case OP_PADHV:
        OpTYPE_set(o, OP_PADAV);
	return ref(o, OP_RV2AV);

    case OP_RV2SV:
    case OP_RV2HV:
        OpTYPE_set(o, OP_RV2AV);
	ref(o, OP_RV2AV);
	break;

    default:
	Perl_ck_warner_d(aTHX_ packWARN(WARN_INTERNAL), "oops: oopsAV");
	break;
    }
    return o;
}

OP *
Perl_oopsHV(pTHX_ OP *o)
{
    dVAR;

    PERL_ARGS_ASSERT_OOPSHV;

    switch (o->op_type) {
    case OP_PADSV:
    case OP_PADAV:
        OpTYPE_set(o, OP_PADHV);
	return ref(o, OP_RV2HV);

    case OP_RV2SV:
    case OP_RV2AV:
        OpTYPE_set(o, OP_RV2HV);
        /* rv2hv steals the bottom bit for its own uses */
        OpPRIVATE(o) &= ~OPpARG1_MASK;
	ref(o, OP_RV2HV);
	break;

    default:
	Perl_ck_warner_d(aTHX_ packWARN(WARN_INTERNAL), "oops: oopsHV");
	break;
    }
    return o;
}

OP *
Perl_newAVREF(pTHX_ OP *o)
{
    dVAR;

    PERL_ARGS_ASSERT_NEWAVREF;

    if (IS_TYPE(o, PADANY)) {
        OpTYPE_set(o, OP_PADAV);
        /* Note: the op is not yet chained properly */
	return CHECKOP(OP_PADAV, o);
    }
    else if (IS_TYPE(o, RV2AV) || IS_TYPE(o, PADAV)) {
	Perl_croak(aTHX_ "Can't use an array as a reference");
    }
    return newUNOP(OP_RV2AV, 0, scalar(o));
}

OP *
Perl_newGVREF(pTHX_ I32 type, OP *o)
{
    if (type == OP_MAPSTART || type == OP_GREPSTART || type == OP_SORT)
	return newUNOP(OP_NULL, 0, o);
    return ref(newUNOP(OP_RV2GV, OPf_REF, o), type);
}

OP *
Perl_newHVREF(pTHX_ OP *o)
{
    dVAR;

    PERL_ARGS_ASSERT_NEWHVREF;

    if (IS_TYPE(o, PADANY)) {
        OpTYPE_set(o, OP_PADHV);
	return o;
    }
    else if (IS_TYPE(o, RV2HV) || IS_TYPE(o, PADHV)) {
	Perl_croak(aTHX_ "Can't use a hash as a reference");
    }
    return newUNOP(OP_RV2HV, 0, scalar(o));
}

OP *
Perl_newCVREF(pTHX_ I32 flags, OP *o)
{
    if (IS_TYPE(o, PADANY)) {
	dVAR;
        OpTYPE_set(o, OP_PADCV);
    }
    return newUNOP(OP_RV2CV, flags, scalar(o));
}

OP *
Perl_newSVREF(pTHX_ OP *o)
{
    dVAR;

    PERL_ARGS_ASSERT_NEWSVREF;

    if (IS_TYPE(o, PADANY)) {
        OpTYPE_set(o, OP_PADSV);
        scalar(o);
	return o;
    }
    return newUNOP(OP_RV2SV, 0, scalar(o));
}

/*
=head1 Check routines

A check routine is called at the end of the "newOP" creation routines.
So at the point that a ck_ routine fires, we have no idea what the
context is, either upward in the syntax tree, or either forward or
backward in the execution order.

Lexical slots (op_targ) are also not yet known, this is done at the
end of a check function in op_std_init(o).
For more see the comments at the top of F<op.c> for details.

See F<regen/opcodes> which opcode calls which check function.
Not all ops have a specific check function.

ck_fun is a generic arity type checker, ck_type a generic type checker for 
un- and binops.

fold_constants(op_integerize(op_std_init(o))) is the default treatment,
i.e. fold constants, apply use integer optimizations and initialize the
op_targ for uninitialized pads.

Prototypes are generated by F<regen/embed_lib.pl> by scanning
F<regen/opcodes>, check functions are not in F<embed.fnc>.

=cut
*/

/*
=for apidoc ck_anoncode
CHECK callback for anoncode (s$	S)

Creates an anon pad.

=cut
*/
OP *
Perl_ck_anoncode(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_ANONCODE;

    cSVOPo->op_targ = pad_add_anon((CV*)cSVOPo->op_sv, o->op_type);
    cSVOPo->op_sv = NULL;
    return o;
}

/*
=for apidoc io_hints
Apply $^H{open_IN} or $^H{open_OUT} io hints, by setting op_private bits
for raw or crlf.

=cut
*/
static void
S_io_hints(pTHX_ OP *o)
{
#if O_BINARY != 0 || O_TEXT != 0
    HV * const table =
	PL_hints & HINT_LOCALIZE_HH ? GvHV(PL_hintgv) : NULL;;
    PERL_ARGS_ASSERT_IO_HINTS;
    if (table) {
	SV **svp = hv_fetchs(table, "open_IN", FALSE);
	if (svp && *svp) {
	    STRLEN len = 0;
	    const char *d = SvPV_const(*svp, len);
	    const I32 mode = mode_from_discipline(d, len);
            /* bit-and:ing with zero O_BINARY or O_TEXT would be useless. */
#  if O_BINARY != 0
	    if (mode & O_BINARY)
		o->op_private |= OPpOPEN_IN_RAW;
#  endif
#  if O_TEXT != 0
	    if (mode & O_TEXT)
		o->op_private |= OPpOPEN_IN_CRLF;
#  endif
	}

	svp = hv_fetchs(table, "open_OUT", FALSE);
	if (svp && *svp) {
	    STRLEN len = 0;
	    const char *d = SvPV_const(*svp, len);
	    const I32 mode = mode_from_discipline(d, len);
            /* bit-and:ing with zero O_BINARY or O_TEXT would be useless. */
#  if O_BINARY != 0
	    if (mode & O_BINARY)
		o->op_private |= OPpOPEN_OUT_RAW;
#  endif
#  if O_TEXT != 0
	    if (mode & O_TEXT)
		o->op_private |= OPpOPEN_OUT_CRLF;
#  endif
	}
    }
#else
    PERL_ARGS_ASSERT_IO_HINTS;
    PERL_UNUSED_CONTEXT;
    PERL_UNUSED_ARG(o);
#endif
}

/*
=for apidoc ck_backtick
CHECK callback for `` and qx (tu%	S?)

Handle readpipe overrides, the missing default argument
and apply $^H{open_IN} or $^H{open_OUT} io hints.

TODO: Handle cperl macro `` unquote syntax here later.
=cut
*/
OP *
Perl_ck_backtick(pTHX_ OP *o)
{
    GV *gv;
    OP *newop = NULL;
    OP *sibl;
    PERL_ARGS_ASSERT_CK_BACKTICK;
    o = ck_fun(o);
    /* qx and `` have a null pushmark; CORE::readpipe has only one kid. */
    if (OpKIDS(o) && (sibl = OpSIBLING(OpFIRST(o)))
        && (gv = gv_override("readpipe", 8)))
    {
        /* detach rest of siblings from o and its first child */
        op_sibling_splice(o, OpFIRST(o), -1, NULL);
	newop = new_entersubop(gv, sibl);
    }
    else if (!OpKIDS(o)) {
	newop = newUNOP(OP_BACKTICK, 0,	newDEFSVOP());
    }
    /* ck_fun is better than this. It enforces proper context. */
#if 0
    else if ( (sibl = OpFIRST(o)) && IS_TYPE(sibl, LIST) &&
              (sibl = OpSIBLING(OpFIRST(sibl))) &&
              OpHAS_SIBLING(sibl) ) /* e.g. readpipe("proc",1,2) */
    {
        too_many_arguments_pv(o, OP_NAME(o), 0);
    }
#endif
    if (newop) {
	op_free(o);
	return newop;
    }
    S_io_hints(aTHX_ o);
    return o;
}

/*
=for apidoc ck_bitop
CHECK callback for all bitops, if generic, integer or string variants.

Integerize the results (as if under use integer), and handle some warnings.

=cut
*/
OP *
Perl_ck_bitop(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_BITOP;

    o->op_private = (U8)(PL_hints & HINT_INTEGER);

    if (!OpSTACKED(o) /* Not an assignment */
        && OP_IS_INFIX_BIT(o->op_type))
    {
	const OP * const left = OpFIRST(o);
	const OP * const right = OpSIBLING(left);
	if ((OP_IS_NUMCOMPARE(left->op_type) &&
		(left->op_flags & OPf_PARENS) == 0) ||
	    (OP_IS_NUMCOMPARE(right->op_type) &&
		(right->op_flags & OPf_PARENS) == 0))
	    Perl_ck_warner(aTHX_ packWARN(WARN_PRECEDENCE),
			  "Possible precedence problem on bitwise %s operator",
			   IS_TYPE(o, BIT_OR)
			 ||IS_TYPE(o, I_BIT_OR)  ? "|"
			:  IS_TYPE(o, BIT_AND)
			 ||IS_TYPE(o, I_BIT_AND) ? "&"
			:  IS_TYPE(o, BIT_XOR)
			 ||IS_TYPE(o, I_BIT_XOR) ? "^"
			:  IS_TYPE(o, S_BIT_OR)  ? "|."
			:  IS_TYPE(o, S_BIT_AND) ? "&." : "^."
			   );
    }
    return ck_type(o);
}

PERL_STATIC_INLINE bool
is_dollar_bracket(pTHX_ const OP * const o)
{
    const OP *kid;
    PERL_UNUSED_CONTEXT;
    return IS_TYPE(o, RV2SV) && OpKIDS(o)
	&& (kid = OpFIRST(o))
	&& IS_TYPE(kid, GV)
	&& strEQc(GvNAME(cGVOPx_gv(kid)), "[");
}

/*
=for apidoc ck_cmp
CHECK callback for numeric comparisons (all but *cmp)
Optimize index() == -1 or < 0 into OPpINDEX_BOOLNEG,
ditto != -1 or >= 0 into OPpTRUEBOOL.

Warn on $[  (did you mean $] ?)

=cut
*/
OP *
Perl_ck_cmp(pTHX_ OP *o)
{
    OP *indexop, *constop, *start;
    SV *sv;
    IV iv;
    bool is_eq;
    bool neg;
    bool reverse;
    bool iv0;

    PERL_ARGS_ASSERT_CK_CMP;

    is_eq = (   o->op_type == OP_EQ
             || o->op_type == OP_NE
             || o->op_type == OP_I_EQ
             || o->op_type == OP_I_NE);

    if (!is_eq && ckWARN(WARN_SYNTAX)) {
	const OP *kid = OpFIRST(o);
	if (kid &&
            (
		(   is_dollar_bracket(aTHX_ kid)
                    && OP_TYPE_IS(OpSIBLING(kid), OP_CONST)
		)
	     || (   IS_CONST_OP(kid)
		 && (kid = OpSIBLING(kid)) && is_dollar_bracket(aTHX_ kid)
                )
	   )
        )
	    Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
			"$[ used in %s (did you mean $] ?)", OP_DESC(o));
    }

    /* convert (index(...) == -1) and variations into
     *   (r)index/BOOL(,NEG)
     */

    reverse = FALSE;

    indexop = OpFIRST(o);
    constop = OpSIBLING(indexop);
    start = NULL;
    if (IS_CONST_OP(indexop)) {
        constop = indexop;
        indexop = OpSIBLING(constop);
        start = constop;
        reverse = TRUE;
    }

    if (indexop->op_type != OP_INDEX && indexop->op_type != OP_RINDEX)
        return ck_type(o);

    /* ($lex = index(....)) == -1 */
    if (indexop->op_private & OPpTARGET_MY)
        return o;

    if (!IS_CONST_OP(constop))
        return ck_type(o);

    sv = cSVOPx_sv(constop);
    if (!(sv && SvIOK_notUV(sv)))
        return ck_type(o);

    iv = SvIVX(sv);
    if (iv != -1 && iv != 0)
        return ck_type(o);
    iv0 = (iv == 0);

    if (o->op_type == OP_LT || o->op_type == OP_I_LT) {
        if (!(iv0 ^ reverse))
            return ck_type(o);
        neg = iv0;
    }
    else if (o->op_type == OP_LE || o->op_type == OP_I_LE) {
        if (iv0 ^ reverse)
            return ck_type(o);
        neg = !iv0;
    }
    else if (o->op_type == OP_GE || o->op_type == OP_I_GE) {
        if (!(iv0 ^ reverse))
            return ck_type(o);
        neg = !iv0;
    }
    else if (o->op_type == OP_GT || o->op_type == OP_I_GT) {
        if (iv0 ^ reverse)
            return ck_type(o);
        neg = iv0;
    }
    else if (o->op_type == OP_EQ || o->op_type == OP_I_EQ) {
        if (iv0)
            return o;
        neg = TRUE;
    }
    else {
        assert(o->op_type == OP_NE || o->op_type == OP_I_NE);
        if (iv0)
            return o;
        neg = FALSE;
    }

    indexop->op_flags &= ~OPf_PARENS;
    indexop->op_flags |= (o->op_flags & OPf_PARENS);
    indexop->op_private |= OPpTRUEBOOL;
    if (neg)
        indexop->op_private |= OPpINDEX_BOOLNEG;
    /* cut out the index op and free the eq,const ops */
    (void)op_sibling_splice(o, start, 1, NULL);
    op_free(o);

    return ck_type(indexop);
}

/*
=for apidoc ck_concat
CHECK callback for concat

Handles STACKED.
Leaves out op_integerize, as concat is for strings only.
=cut
*/
OP *
Perl_ck_concat(pTHX_ OP *o)
{
    const OP * const kid = OpFIRST(o);

    PERL_ARGS_ASSERT_CK_CONCAT;
    PERL_UNUSED_CONTEXT;

    /* reuse the padtmp returned by the concat child */
    if (IS_TYPE(kid, CONCAT) && !(kid->op_private & OPpTARGET_MY)
        && !(OpFIRST(kid)->op_flags & OPf_MOD))
    {
        o->op_flags |= OPf_STACKED;
        o->op_private |= OPpCONCAT_NESTED;
        return fold_constants(op_std_init(o));
    }
    return o;
}

/*
=for apidoc ck_spair
CHECK callback for chop, chomp and refgen with optional lists

Transforms single-element lists into the single argument variant op
srefgen, schop, schomp.

=cut
*/
OP *
Perl_ck_spair(pTHX_ OP *o)
{
    dVAR;

    PERL_ARGS_ASSERT_CK_SPAIR;

    if (OpKIDS(o)) {
	OP* newop;
	OP* kid;
        OP* kidkid;
	const OPCODE type = o->op_type;
	o = modkids(ck_fun(o), type);
	kid    = OpFIRST(o);
	kidkid = OpFIRST(kid);
	newop = OpSIBLING(kidkid);
	if (newop) {
	    const OPCODE type = newop->op_type;
	    if (OpHAS_SIBLING(newop))
		return o;
	    if (IS_TYPE(o, REFGEN)
	     && (  type == OP_RV2CV
		|| (  !(newop->op_flags & OPf_PARENS)
		   && (  type == OP_RV2AV || type == OP_PADAV
		      || type == OP_RV2HV || type == OP_PADHV))))
	    	NOOP; /* OK (allow srefgen for \@a and \%h) */
	    else if (OP_GIMME(newop,0) != G_SCALAR)
		return o;
	}
        /* excise first sibling */
        op_sibling_splice(kid, NULL, 1, NULL);
	op_free(kidkid);
    }
    /* transforms OP_REFGEN into OP_SREFGEN, OP_CHOP into OP_SCHOP,
     * and OP_CHOMP into OP_SCHOMP */
    o->op_ppaddr = PL_ppaddr[++o->op_type];
    return ck_fun(o);
}

/*
=for apidoc ck_delete
CHECK callback for delete (%	S	"(:Str):Void")

Handle array and hash elements and slices.

=cut
*/
OP *
Perl_ck_delete(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_DELETE;

    o = ck_fun(o);
    DEBUG_k(Perl_deb(aTHX_ "ck_delete: %s\n", OP_NAME(o)));
    o->op_private = 0;
    if (OpKIDS(o)) {
	OP * const kid = OpFIRST(o);
        DEBUG_k(PerlIO_printf(Perl_debug_log, "\t%s\n", OP_NAME(kid)));
	switch (kid->op_type) {
	case OP_ASLICE:
	    o->op_flags |= OPf_SPECIAL;
	    /* FALLTHROUGH */
	case OP_HSLICE:
	    o->op_private |= OPpSLICE;
	    break;
	case OP_AELEM:
	    o->op_flags |= OPf_SPECIAL;
	    /* FALLTHROUGH */
	case OP_HELEM:
	    break;
	case OP_KVASLICE:
            o->op_flags |= OPf_SPECIAL;
            /* FALLTHROUGH */
	case OP_KVHSLICE:
            o->op_private |= OPpKVSLICE;
            break;
	default:
	    Perl_croak(aTHX_ "delete argument is not a HASH or ARRAY "
			     "element or slice");
	}
	if (kid->op_private & OPpLVAL_INTRO)
	    o->op_private |= OPpLVAL_INTRO;
	op_null(kid);
    }
    return o;
}

/*
=for apidoc ck_eof
CHECK callback for getc and eof (is%	F?)

Esp. set the missing default argument to *ARGV
=cut
*/
OP *
Perl_ck_eof(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_EOF;

    DEBUG_k(Perl_deb(aTHX_ "ck_eof: %s\n", OP_NAME(o)));
    if (OpKIDS(o)) {
	OP *kid;
	if (IS_TYPE(OpFIRST(o), STUB)) {
	    OP * const newop
		= newUNOP(o->op_type, OPf_SPECIAL, newGVOP(OP_GV, 0, PL_argvgv));
	    op_free(o);
	    o = newop;
	}
	o = ck_fun(o);
	kid = OpFIRST(o);
        DEBUG_k(PerlIO_printf(Perl_debug_log, "\t%s\n", OP_NAME(kid)));
	if (IS_TYPE(kid, RV2GV))
	    kid->op_private |= OPpALLOW_FAKE;
    }
    return o;
}

/*
=for apidoc ck_eval
CHECK callback for entereval (du%	S?)
and entertry (d|)

...
=cut
*/
OP *
Perl_ck_eval(pTHX_ OP *o)
{
    dVAR;

    PERL_ARGS_ASSERT_CK_EVAL;

    DEBUG_k(Perl_deb(aTHX_ "ck_eval: %s\n", OP_NAME(o)));
    PL_hints |= HINT_BLOCK_SCOPE;
    if (OpKIDS(o)) {
	SVOP * const kid = (SVOP*)OpFIRST(o);
	assert(kid);
        DEBUG_k(PerlIO_printf(Perl_debug_log, "\t%s\n", OP_NAME(kid)));

	if (IS_TYPE(o, ENTERTRY)) {
	    LOGOP *enter;

            /* cut whole sibling chain free from o */
            op_sibling_splice(o, NULL, -1, NULL);
	    op_free(o);

            enter = S_alloc_LOGOP(aTHX_ OP_ENTERTRY, NULL, NULL);

	    /* establish postfix order */
	    OpNEXT(enter) = (OP*)enter;

	    o = op_prepend_elem(OP_LINESEQ, (OP*)enter, (OP*)kid);
            OpTYPE_set(o, OP_LEAVETRY);
	    OpOTHER(enter) = o;
	    return o;
	}
	else {
	    scalar((OP*)kid);
	    S_set_haseval(aTHX);
	}
    }
    else {
	const U8 priv = o->op_private;
	op_free(o);
        /* the newUNOP will recursively call ck_eval(), which will handle
         * all the stuff at the end of this function, like adding
         * OP_HINTSEVAL
         */
        DEBUG_k(PerlIO_printf(Perl_debug_log, "\tentereval %d\n", priv));
	return newUNOP(OP_ENTEREVAL, priv <<8, newDEFSVOP());
    }
    o->op_targ = (PADOFFSET)PL_hints;
    if (o->op_private & OPpEVAL_BYTES) o->op_targ &= ~HINT_UTF8;
    if ((PL_hints & HINT_LOCALIZE_HH) != 0
     && !(o->op_private & OPpEVAL_COPHH) && GvHV(PL_hintgv)) {
	/* Store a copy of %^H that pp_entereval can pick up. */
	OP *hhop = newSVOP(OP_HINTSEVAL, 0,
			   MUTABLE_SV(hv_copy_hints_hv(GvHV(PL_hintgv))));
        /* append hhop to only child  */
        op_sibling_splice(o, OpFIRST(o), 0, hhop);

	o->op_private |= OPpEVAL_HAS_HH;
    }
    if (!(o->op_private & OPpEVAL_BYTES) && FEATURE_UNIEVAL_IS_ENABLED)
        o->op_private |= OPpEVAL_UNICODE;
    return o;
}

/*
=for apidoc ck_exec
CHECK callback for system and exec (imsT@	S? L)

If as list or string.

=cut
*/
OP *
Perl_ck_exec(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_EXEC;

    DEBUG_k(Perl_deb(aTHX_ "ck_exec: %s\n", OP_NAME(o)));
    if (OpSTACKED(o)) {
        OP *kid;
	o = ck_fun(o);
	kid = OpSIBLING(OpFIRST(o));
        DEBUG_k(PerlIO_printf(Perl_debug_log, "\t%s\n", OP_NAME(kid)));
	if (IS_TYPE(kid, RV2GV))
	    op_null(kid);
    }
    else
	o = listkids(o);
    return o;
}

/*
=for apidoc ck_exists
CHECK callback for exists (is%	S	"(:Str):Bool")

Handle hash or array elements, and ref subs.

=cut
*/
OP *
Perl_ck_exists(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_EXISTS;

    o = ck_fun(o);
    DEBUG_k(Perl_deb(aTHX_ "ck_exists: %s\n", OP_NAME(o)));
    if (OpKIDS(o)) {
	OP * const kid = OpFIRST(o);
        DEBUG_k(PerlIO_printf(Perl_debug_log, "\t%s\n", OP_NAME(kid)));
	if (IS_SUB_OP(kid)) {
	    (void) ref(kid, o->op_type);
	    if (ISNT_TYPE(kid, RV2CV)
                && !(PL_parser && PL_parser->error_count))
		Perl_croak(aTHX_
			  "exists argument is not a subroutine name");
	    o->op_private |= OPpEXISTS_SUB;
	}
	else if (IS_TYPE(kid, AELEM))
	    o->op_flags |= OPf_SPECIAL;
	else if (ISNT_TYPE(kid, HELEM))
	    Perl_croak(aTHX_ "exists argument is not a HASH or ARRAY "
			     "element or a subroutine");
	op_null(kid);
    }
    return o;
}

/*
=for apidoc ck_rvconst
CHECK callback for rv2[gsc]const (ds1	R	"(:Ref):Scalar")

Error on bareword constants, initialize the symbol.

=cut
*/
OP *
Perl_ck_rvconst(pTHX_ OP *o)
{
    dVAR;
    SVOP * const kid = (SVOP*)OpFIRST(o);

    PERL_ARGS_ASSERT_CK_RVCONST;

#ifdef HINT_M_VMSISH_STATUS
    if (IS_TYPE(o, RV2SV)) {
        HV* const hinthv = PL_hints & HINT_LOCALIZE_HH
            ? GvHV(PL_hintgv) : NULL;
        SV ** const svp = hv_fetchs(hinthv, "strict", FALSE);
        if (svp && SvIOK(*svp)) {
            if (SvIV(*svp) & HINT_M_VMSISH_STATUS)
                OpPRIVATE(o) |= OPpHINT_STRICT_NAMES;
        }
    }
#else
    if (IS_TYPE(o, RV2SV) && PL_hints & HINT_STRICT_NAMES)
        OpPRIVATE(o) |= OPpHINT_STRICT_NAMES; /* 4 */
#endif
    if (IS_TYPE(o, RV2HV))
        /* rv2hv steals the bottom bit for its own uses */
        OpPRIVATE(o) &= ~OPpARG1_MASK; /* 1 */

    OpPRIVATE(o) |= (PL_hints & HINT_STRICT_REFS); /* 2 */
    if (IS_CONST_OP(kid)) {
	int iscv;
	GV *gv;
	SV * const kidsv = kid->op_sv;
        DEBUG_k(Perl_deb(aTHX_ "ck_rvconst: %s %s\n", OP_NAME(o), OP_NAME(kid)));
        DEBUG_kv(op_dump(o));

	/* Is it a constant from cv_const_sv()? */
	if ((SvROK(kidsv) || isGV_with_GP(kidsv)) && SvREADONLY(kidsv)) {
	    return o;
	}
	if (SvTYPE(kidsv) == SVt_PVAV)
            return o;
	if ((OpPRIVATE(o) & HINT_STRICT_REFS) && (OpPRIVATE(kid) & OPpCONST_BARE)) {
	    const char *badthing;
	    switch (o->op_type) {
	    case OP_RV2SV:
		badthing = "a SCALAR";
		break;
	    case OP_RV2AV:
		badthing = "an ARRAY";
		break;
	    case OP_RV2HV:
		badthing = "a HASH";
		break;
	    default:
		badthing = NULL;
		break;
	    }
	    if (badthing)
		Perl_croak(aTHX_
			   "Can't use bareword (\"%" SVf "\") as %s ref while \"strict refs\" in use",
			   SVfARG(kidsv), badthing);
	}
#if 0
        /* TODO Could also be scope null-const, not detected here.
           This also rejects all our existing magic names, like "$!".
         */
        if (IS_TYPE(o, RV2SV) && OpPRIVATE(o) & OPpHINT_STRICT_NAMES) {
            int normalize;
            DEBUG_kv(Perl_deb("op check strict names \"%" SVf "\"\n", SVfARG(kidsv)));
            (void)valid_ident(kidsv, TRUE, TRUE, &normalize);
        }
#endif
	/*
	 * This is a little tricky.  We only want to add the symbol if we
	 * didn't add it in the lexer.  Otherwise we get duplicate strict
	 * warnings.  But if we didn't add it in the lexer, we must at
	 * least pretend like we wanted to add it even if it existed before,
	 * or we get possible typo warnings.  OPpCONST_ENTERED says
	 * whether the lexer already added THIS instance of this symbol.
	 */
	iscv = IS_TYPE(o, RV2CV) ? GV_NOEXPAND|GV_ADDMULTI : 0;
	gv = gv_fetchsv(kidsv,
		IS_TYPE(o, RV2CV)
			&& o->op_private & OPpMAY_RETURN_CONSTANT
		    ? GV_NOEXPAND
		    : iscv | !(kid->op_private & OPpCONST_ENTERED),
		iscv
		    ? SVt_PVCV
		    : IS_TYPE(o, RV2SV)
			? SVt_PV
			: IS_TYPE(o, RV2AV)
			    ? SVt_PVAV
			    : IS_TYPE(o, RV2HV)
				? SVt_PVHV
				: SVt_PVGV);
	if (gv) {
	    if (!isGV(gv)) {
		assert(iscv);
		assert(SvROK(gv));
		if (!(o->op_private & OPpMAY_RETURN_CONSTANT)
		  && SvTYPE(SvRV(gv)) != SVt_PVCV)
		    gv_fetchsv(kidsv, GV_ADDMULTI, SVt_PVCV);
	    }
            OpTYPE_set(kid, OP_GV);
            SvREFCNT_dec(kid->op_sv);
            op_gv_set((OP*)kid, gv);
	    kid->op_private = 0;
	    /* FAKE globs in the symbol table cause weird bugs (#77810) */
	    SvFAKE_off(gv);
	}
    } else {
        DEBUG_k(Perl_deb(aTHX_ "ck_rvconst: %s %s\n", OP_NAME(o), OP_NAME(kid)));
        /*DEBUG_kv(op_dump(o));*/
    }
    return o;
}

/*
=for apidoc ck_ftst
CHECK callback for stat, lstat (u- F?) and the -X file tests (isu-	F-+)

Handle _ and a missing optional arg.

=cut
*/
OP *
Perl_ck_ftst(pTHX_ OP *o)
{
    dVAR;
    const I32 type = o->op_type;

    PERL_ARGS_ASSERT_CK_FTST;
    DEBUG_k(Perl_deb(aTHX_ "ck_ftst: %s\n", OP_NAME(o)));
    DEBUG_kv(op_dump(o));

    if (o->op_flags & OPf_REF) {
	NOOP;
    }
    else if (OpKIDS(o) && ISNT_TYPE(OpFIRST(o), STUB)) {
	SVOP * const kid = (SVOP*)OpFIRST(o);
	const OPCODE kidtype = kid->op_type;
        DEBUG_k(PerlIO_printf(Perl_debug_log, "\t%s\n", OP_NAME(kid)));

	if (kidtype == OP_CONST && (kid->op_private & OPpCONST_BARE)
	 && !kid->op_folded) {
	    OP * const newop = newGVOP(type, OPf_REF,
		gv_fetchsv(kid->op_sv, GV_ADD, SVt_PVIO));
	    op_free(o);
	    return newop;
	}

        if ((kidtype == OP_RV2AV || kidtype == OP_PADAV) && ckWARN(WARN_SYNTAX)) {
            SV *name = S_op_varname_subscript(aTHX_ (OP*)kid, 2);
            if (name) {
                /* diag_listed_as: Array passed to stat will be coerced to a scalar%s */
                Perl_warner(aTHX_ packWARN(WARN_SYNTAX), "%s (did you want stat %" SVf "?)",
                            array_passed_to_stat, name);
            }
            else {
                /* diag_listed_as: Array passed to stat will be coerced to a scalar%s */
                Perl_warner(aTHX_ packWARN(WARN_SYNTAX), "%s", array_passed_to_stat);
            }
       }
	scalar((OP *) kid);
	if ((PL_hints & HINT_FILETEST_ACCESS) && OP_IS_FILETEST_ACCESS(o->op_type))
	    o->op_private |= OPpFT_ACCESS;
	if (type != OP_STAT && type != OP_LSTAT
            && PL_check[kidtype] == Perl_ck_ftst
            && kidtype != OP_STAT && kidtype != OP_LSTAT
        ) {
	    o->op_private |= OPpFT_STACKED;
	    kid->op_private |= OPpFT_STACKING;
	    if (kidtype == OP_FTTTY && (
		   !(kid->op_private & OPpFT_STACKED)
		|| kid->op_private & OPpFT_AFTER_t
	       ))
		o->op_private |= OPpFT_AFTER_t;
	}
    }
    else {
	op_free(o);
	if (type == OP_FTTTY) {
            DEBUG_k(PerlIO_printf(Perl_debug_log, "\tref stdin\n"));
	    o = newGVOP(type, OPf_REF, PL_stdingv);
        }
	else {
            DEBUG_k(PerlIO_printf(Perl_debug_log, "\tdefsvop\n"));
	    o = newUNOP(type, 0, newDEFSVOP());
        }
    }
    return o;
}

/*
=for apidoc ck_fun
CHECK callback for the rest

check and fix arguments of internal op calls,
but not entersub user-level signatured or prototyped calls.
throw arity errors, unify arg list, e.g. add scalar cast, add $_ ...
=cut
*/
OP *
Perl_ck_fun(pTHX_ OP *o)
{
    const int type = o->op_type;
    I32 oa = PL_opargs[type] >> OASHIFT;

    PERL_ARGS_ASSERT_CK_FUN;
    DEBUG_k(Perl_deb(aTHX_ "ck_fun: %s\n", OP_NAME(o)));
    /*DEBUG_kv(op_dump(o));*/

    if (OpSTACKED(o)) {
	if ((oa & OA_OPTIONAL) && (oa >> 4) && !((oa >> 4) & OA_OPTIONAL))
	    oa &= ~OA_OPTIONAL;
	else
	    return no_fh_allowed(o);
    }
    if (PL_opargs[type] & OA_OTHERINT || NUM_OP_TYPE_VARIANTS(type))
        o = ck_type(o);

    if (OpKIDS(o)) {
        OP *prev_kid = NULL;
        OP *kid = OpFIRST(o);
        I32 numargs = 0;
	bool seen_optional = FALSE;

	if (OP_TYPE_IS_OR_WAS_NN(kid, OP_PUSHMARK)) {
	    prev_kid = kid;
	    kid = OpSIBLING(kid);
	}
	if (kid && IS_TYPE(kid, COREARGS)) {
	    bool optional = FALSE;
	    while (oa) {
		numargs++;
		if (oa & OA_OPTIONAL) optional = TRUE;
		oa = oa >> 4;
	    }
	    if (optional) o->op_private |= numargs;
	    return o;
	}

	while (oa) {
	    if (oa & OA_OPTIONAL || (oa & 7) == OA_LIST) {
		if (!kid && !seen_optional && PL_opargs[type] & OA_DEFGV) {
		    kid = newDEFSVOP();
                    /* append kid to chain */
                    op_sibling_splice(o, prev_kid, 0, kid);
                }
		seen_optional = TRUE;
	    }
	    if (!kid) break;

	    numargs++;
	    switch (oa & 7) {
	    case OA_SCALAR:
		/* list seen where single (scalar) arg expected? */
		if (numargs == 1 && !(oa >> 4)
		    && IS_TYPE(kid, LIST) && type != OP_SCALAR)
		{
		    return too_many_arguments_pv(o,PL_op_desc[type], 0);
		}
		if (type != OP_DELETE) scalar(kid);
		break;
	    case OA_LIST:
		if (oa < 16) {
		    kid = 0;
		    continue;
		}
		else
		    list(kid);
		break;
	    case OA_AVREF:
		if ((type == OP_PUSH || type == OP_UNSHIFT)
		    && !OpHAS_SIBLING(kid))
		    Perl_ck_warner(aTHX_ packWARN(WARN_SYNTAX),
				   "Useless use of %s with no values",
				   PL_op_desc[type]);

		if (IS_CONST_OP(kid)
                    && (  !SvROK(cSVOPx_sv(kid)) 
                        || SvTYPE(SvRV(cSVOPx_sv(kid))) != SVt_PVAV  )
                    )
		    bad_type_pv(numargs, "array", o, kid);
		else if (ISNT_TYPE(kid, RV2AV) && ISNT_TYPE(kid, PADAV)) {
                    yyerror_pv(Perl_form(aTHX_ "Experimental %s on scalar is now forbidden",
                                         PL_op_desc[type]), 0);
		}
                else {
                    op_lvalue(kid, type);
                }
		break;
	    case OA_HVREF:
		if (ISNT_TYPE(kid, RV2HV) && ISNT_TYPE(kid, PADHV))
		    bad_type_pv(numargs, "hash", o, kid);
		op_lvalue(kid, type);
		break;
	    case OA_CVREF:
		{
                    /* replace kid with newop in chain */
		    OP * const newop =
                        S_op_sibling_newUNOP(aTHX_ o, prev_kid, OP_NULL, 0);
		    OpNEXT(newop) = newop;
		    kid = newop;
		}
		break;
	    case OA_FILEREF:
		if (ISNT_TYPE(kid, GV) && ISNT_TYPE(kid, RV2GV)) {
		    if (IS_CONST_OP(kid) &&
			(kid->op_private & OPpCONST_BARE))
		    {
			OP * const newop = newGVOP(OP_GV, 0,
			    gv_fetchsv(((SVOP*)kid)->op_sv, GV_ADD, SVt_PVIO));
                        /* replace kid with newop in chain */
                        op_sibling_splice(o, prev_kid, 1, newop);
			op_free(kid);
			kid = newop;
		    }
		    else if (IS_TYPE(kid, READLINE)) {
			/* neophyte patrol: open(<FH>), close(<FH>) etc. */
			bad_type_pv(numargs, "HANDLE", o, kid);
		    }
		    else {
			I32 flags = OPf_SPECIAL;
			I32 priv = 0;
			PADOFFSET targ = 0;

			/* is this op a FH constructor? */
			if (is_handle_constructor(o,numargs)) {
                            const char *name = NULL;
			    STRLEN len = 0;
                            U32 name_utf8 = 0;
			    bool want_dollar = TRUE;

			    flags = 0;
			    /* Set a flag to tell rv2gv to vivify
			     * need to "prove" flag does not mean something
			     * else already - NI-S 1999/05/07
			     */
			    priv = OPpDEREF;
			    if (IS_TYPE(kid, PADSV)) {
				PADNAME * const pn
				    = PAD_COMPNAME_SV(kid->op_targ);
				name = PadnamePV (pn);
				len  = PadnameLEN(pn);
				name_utf8 = PadnameUTF8(pn);
			    }
			    else if (IS_TYPE(kid, RV2SV)
				  && IS_TYPE(OpFIRST(kid), GV))
			    {
				GV * const gv = cGVOPx_gv(OpFIRST(kid));
				name = GvNAME(gv);
				len = GvNAMELEN(gv);
                                name_utf8 = GvNAMEUTF8(gv) ? SVf_UTF8 : 0;
			    }
			    else if (IS_TYPE(kid, AELEM)
				  || IS_TYPE(kid, HELEM))
			    {
				 OP *firstop;
				 OP *op = OpFIRST(kid);
				 name = NULL;
				 if (op) {
				      SV *tmpstr = NULL;
				      const char * const a =
					   IS_TYPE(kid, AELEM) ?
					   "[]" : "{}";
				      if ((IS_TYPE(op, RV2AV) ||
					   IS_TYPE(op, RV2HV)) &&
					  (firstop = OpFIRST(op)) &&
					  (IS_TYPE(firstop, GV))) {
					   /* packagevar $a[] or $h{} */
					   GV * const gv = cGVOPx_gv(firstop);
					   if (gv)
						tmpstr =
						     Perl_newSVpvf(aTHX_
								   "%s%c...%c",
								   GvNAME(gv),
								   a[0], a[1]);
				      }
				      else if (IS_TYPE(op, PADAV)
					    || IS_TYPE(op, PADHV)) {
					   /* lexicalvar $a[] or $h{} */
					   const char * const padname =
						PAD_COMPNAME_PV(op->op_targ);
					   if (padname)
						tmpstr =
						     Perl_newSVpvf(aTHX_
								   "%s%c...%c",
								   padname + 1,
								   a[0], a[1]);
				      }
				      if (tmpstr) {
					   name = SvPV_const(tmpstr, len);
                                           name_utf8 = SvUTF8(tmpstr);
					   sv_2mortal(tmpstr);
				      }
				 }
				 if (!name) {
				      name = "__ANONIO__";
				      len = 10;
				      want_dollar = FALSE;
				 }
				 op_lvalue(kid, type);
			    }
			    if (name) {
				SV *namesv;
				targ = pad_alloc(OP_RV2GV, SVf_READONLY);
				namesv = PAD_SVl(targ);
				if (want_dollar && *name != '$')
				    sv_setpvs(namesv, "$");
				else
                                    SvPVCLEAR(namesv);
				sv_catpvn(namesv, name, len);
                                if ( name_utf8 ) SvUTF8_on(namesv);
			    }
			}
                        scalar(kid);
                        kid = S_op_sibling_newUNOP(aTHX_ o, prev_kid,
                                    OP_RV2GV, flags);
                        kid->op_targ = targ;
                        kid->op_private |= priv;
		    }
		}
		scalar(kid);
		break;
	    case OA_SCALARREF:
		if ((type == OP_UNDEF || type == OP_POS)
		    && numargs == 1 && !(oa >> 4)
		    && IS_TYPE(kid, LIST))
		    return too_many_arguments_pv(o,PL_op_desc[type], 0);
                if (UNLIKELY(type == OP_STUDY))
                    scalar(kid);
                else
                    op_lvalue(scalar(kid), type);
		break;
	    }
	    oa >>= 4;
	    prev_kid = kid;
	    kid = OpSIBLING(kid);
	}
	/* FIXME - should the numargs or-ing move after the too many
         * arguments check? */
	o->op_private |= numargs;
	if (kid)
	    return too_many_arguments_pv(o,OP_DESC(o), 0);
	listkids(o);
    }
    else if (PL_opargs[type] & OA_DEFGV) {
	/* Ordering of these two is important to keep f_map.t passing.  */
	op_free(o);
	return newUNOP(type, 0, newDEFSVOP());
    }

    if (oa) {
	while (oa & OA_OPTIONAL)
	    oa >>= 4;
	if (oa && oa != OA_LIST)
	    return too_few_arguments_pv(o,OP_DESC(o), 0);
    }
    return o;
}

/*
=for apidoc ck_glob
CHECK callback for glob (t@	S?)

glob defaults its first arg to $_

Also handles initializing an optional external File::Glob hook on
certain platforms.
=cut
*/
OP *
Perl_ck_glob(pTHX_ OP *o)
{
    GV *gv;

    PERL_ARGS_ASSERT_CK_GLOB;

    o = ck_fun(o);
    if ((OpKIDS(o)) && !OpHAS_SIBLING(OpFIRST(o)))
	op_append_elem(OP_GLOB, o, newDEFSVOP()); /* glob() => glob($_) */

    if (!(OpSPECIAL(o)) && (gv = gv_override("glob", 4)))
    {
	/* convert
	 *     glob
	 *       \ null - const(wildcard)
	 * into
	 *     null
	 *       \ enter
	 *            \ list
	 *                 \ mark - glob - rv2cv
	 *                             |        \ gv(CORE::GLOBAL::glob)
	 *                             |
	 *                              \ null - const(wildcard)
	 */
	o->op_flags |= OPf_SPECIAL;
	o->op_targ = pad_alloc(OP_GLOB, SVs_PADTMP);
	o = new_entersubop(gv, o);
	o = newUNOP(OP_NULL, 0, o);
	o->op_targ = OP_GLOB; /* hint at what it used to be: eg in newWHILEOP */
	return o;
    }
    else o->op_flags &= ~OPf_SPECIAL;
#if !defined(PERL_EXTERNAL_GLOB)
    if (!PL_globhook) {
	ENTER;
	Perl_load_module(aTHX_ PERL_LOADMOD_NOIMPORT,
			       newSVpvs("File::Glob"), NULL, NULL, NULL);
	LEAVE;
    }
#endif /* !PERL_EXTERNAL_GLOB */
    gv = (GV *)newSV(0);
    gv_init(gv, 0, "", 0, 0);
    gv_IOadd(gv);
    op_append_elem(OP_GLOB, o, newGVOP(OP_GV, 0, gv));
    SvREFCNT_dec_NN(gv); /* newGVOP increased it */
    scalarkids(o);
    return o;
}

/*
=for apidoc ck_grep
CHECK callback for grepstart and mapstart (m@	C L)

Handles BLOCK and ordinary comma style, throwing an error if the
comma-less version is not on a BLOCK.

Applies lexical $_ optimization or handles the default $_.

=cut
*/
OP *
Perl_ck_grep(pTHX_ OP *o)
{
    LOGOP *gwop;
    OP *kid;
    const OPCODE type = IS_TYPE(o, GREPSTART) ? OP_GREPWHILE : OP_MAPWHILE;
    PADOFFSET offset;

    PERL_ARGS_ASSERT_CK_GREP;

    /* don't allocate gwop here, as we may leak it if PL_parser->error_count > 0 */

    if (OpSTACKED(o)) {
	kid = OpFIRST(OpSIBLING(OpFIRST(o)));
	if (ISNT_TYPE(kid, SCOPE) && ISNT_TYPE(kid, LEAVE))
	    return no_fh_allowed(o);
	o->op_flags &= ~OPf_STACKED;
    }
    kid = OpSIBLING(OpFIRST(o));
    if (type == OP_MAPWHILE)
	list(kid);
    else
	scalar(kid);
    o = ck_fun(o);
    if (PL_parser && PL_parser->error_count)
	return o;
    kid = OpSIBLING(OpFIRST(o));
    if (ISNT_TYPE(kid, NULL))
	Perl_croak(aTHX_ "panic: ck_grep, type=%u", (unsigned) kid->op_type);
    kid = OpFIRST(kid);

    gwop = S_alloc_LOGOP(aTHX_ type, o, LINKLIST(kid));
    OpNEXT(kid) = (OP*)gwop;
    offset = pad_findmy_pvs("$_", 0);
    if (offset == NOT_IN_PAD || PAD_COMPNAME_FLAGS_isOUR(offset)) {
	o->op_private = gwop->op_private = 0;
	gwop->op_targ = pad_alloc(type, SVs_PADTMP);
    }
    else {
	o->op_private = gwop->op_private = OPpGREP_LEX;
	gwop->op_targ = o->op_targ = offset;
    }

    kid = OpSIBLING(OpFIRST(o));
    for (kid = OpSIBLING(kid); kid; kid = OpSIBLING(kid))
	op_lvalue(kid, OP_GREPSTART);

    return (OP*)gwop;
}

/*
=for apidoc ck_index
CHECK callback for index, rindex (sT@	S S S?)

Does compile-time fbm (Boyer-Moore) compilation on a constant string.
=cut
*/
OP *
Perl_ck_index(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_INDEX;

    if (OpKIDS(o)) {
	OP *kid = OpSIBLING(OpFIRST(o));	/* get past pushmark */
	if (kid)
	    kid = OpSIBLING(kid);			/* get past "big" */
	if (kid && IS_CONST_OP(kid)) {
	    const bool save_taint = TAINT_get;
	    SV *sv = kSVOP->op_sv;
	    if (   (!SvPOK(sv) || SvNIOKp(sv) || isREGEXP(sv))
                && SvOK(sv) && !SvROK(sv))
            {
		sv = newSV(0);
		sv_copypv(sv, kSVOP->op_sv);
		SvREFCNT_dec_NN(kSVOP->op_sv);
		kSVOP->op_sv = sv;
	    }
	    if (SvOK(sv)) fbm_compile(sv, 0);
	    TAINT_set(save_taint);
#ifdef NO_TAINT_SUPPORT
            PERL_UNUSED_VAR(save_taint);
#endif
	}
    }
    return ck_fun(o);
}

/*
=for apidoc ck_lfun
CHECK callback for {i_,}{pre,post}{inc,dec} (dIs1	S) and sprintf.

Turns on MOD on all kids, setting it to a lvalue function.
See L</modkids>.
=cut
*/
OP *
Perl_ck_lfun(pTHX_ OP *o)
{
    const OPCODE type = o->op_type;
    PERL_ARGS_ASSERT_CK_LFUN;

    return modkids(ck_fun(o), type);
}

/*
=for apidoc ck_defined
CHECK callback for defined (isu%	S?	"(:Scalar):Bool")

Errors now on @array and %hash arguments.

Also calls L</ck_rfun>, turning the argument into a reference, which is
still useful for defined &sub, not calling sub, just checking if &sub has a body.
=cut
*/
OP *
Perl_ck_defined(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_DEFINED;

    if ((OpKIDS(o))) {
	switch (OpFIRST(o)->op_type) {
	case OP_RV2AV:
	case OP_PADAV:
	    Perl_croak(aTHX_ "Can't use 'defined(@array)'"
			     " (Maybe you should just omit the defined()?)");
            NOT_REACHED; /* NOTREACHED */
            break;
	case OP_RV2HV:
	case OP_PADHV:
	    Perl_croak(aTHX_ "Can't use 'defined(%%hash)'"
			     " (Maybe you should just omit the defined()?)");
            NOT_REACHED; /* NOTREACHED */
	    break;
	default:
	    /* no warning */
	    break;
	}
    }
    return ck_rfun(o);
}

/*
=for apidoc ck_readline
CHECK callback for readline, the <> op. (t%	F?	"(:Scalar?):Any")

Adds C<*ARGV> if missing.
=cut
*/
OP *
Perl_ck_readline(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_READLINE;

    if (OpKIDS(o)) {
	 OP *kid = OpFIRST(o);
	 if (IS_TYPE(kid, RV2GV)) kid->op_private |= OPpALLOW_FAKE;
	 if ( IS_TYPE(kid, LIST) &&
              (kid = OpSIBLING(OpFIRST(kid))) &&
              OpSIBLING(kid) ) /* e.g. readline(1,2) */
              too_many_arguments_pv(o, OP_NAME(o), 0);
         return o; /* ck_fun(o); fails a few tests */
    }
    else {
	OP * const newop
	    = newUNOP(OP_READLINE, 0, newGVOP(OP_GV, 0, PL_argvgv));
	op_free(o);
	return newop;
    }
}

/*
=for apidoc ck_rfun
CHECK callback for lock (s%	R)

Calls L</refkids> to turn the argument into a reference.

Remember that lock can be called on everything, scalar, ref, array, hash or sub,
but internally we better work with a scalar reference.
=cut
*/
OP *
Perl_ck_rfun(pTHX_ OP *o)
{
    const OPCODE type = o->op_type;

    PERL_ARGS_ASSERT_CK_RFUN;

    return refkids(ck_fun(o), type);
}

/*
=for apidoc ck_listiob
CHECK callback for prtf,print,say (ims@	F? L)

Checks for the 1st bareword filehandle argument, if without comma.
And if list argument was provided, or add $_.
=cut
*/
OP *
Perl_ck_listiob(pTHX_ OP *o)
{
    OP *kid;

    PERL_ARGS_ASSERT_CK_LISTIOB;

    kid = OpFIRST(o);
    if (!kid) {
	o = force_list(o, 1);
	kid = OpFIRST(o);
    }
    if (IS_TYPE(kid, PUSHMARK))
	kid = OpSIBLING(kid);
    if (kid && OpSTACKED(o))
	kid = OpSIBLING(kid);
    else if (kid && !OpHAS_SIBLING(kid)) {		/* print HANDLE; */
	if (IS_CONST_OP(kid) && kid->op_private & OPpCONST_BARE
            && !kid->op_folded)
        {
	    o->op_flags |= OPf_STACKED;	/* make it a filehandle */
            scalar(kid);
            /* replace old const op with new OP_RV2GV parent */
            kid = S_op_sibling_newUNOP(aTHX_ o, OpFIRST(o),
                                        OP_RV2GV, OPf_REF);
            kid = OpSIBLING(kid);
	}
    }

    if (!kid)
	op_append_elem(o->op_type, o, newDEFSVOP());

    if (IS_TYPE(o, PRTF)) return modkids(listkids(o), OP_PRTF);
    return listkids(o);
}

/*
=for apidoc ck_smartmatch
CHECK callback for smartmatch (s2)

Rearranges the kids to refs if not SPECIAL, and optimizes the
runtime MATCH to a compile-time QR.
=cut
*/
OP *
Perl_ck_smartmatch(pTHX_ OP *o)
{
    dVAR;
    PERL_ARGS_ASSERT_CK_SMARTMATCH;
    if (!OpSPECIAL(o)) {
	OP *first  = OpFIRST(o);
	OP *second = OpSIBLING(first);
	
        DEBUG_k(Perl_deb(aTHX_ "ck_smartmatch: ref kids\n"));
	/* Implicitly take a reference to an array or hash */

        /* remove the original two siblings, then add back the
         * (possibly different) first and second sibs.
         */
        op_sibling_splice(o, NULL, 1, NULL);
        op_sibling_splice(o, NULL, 1, NULL);
	first  = ref_array_or_hash(first);
	second = ref_array_or_hash(second);
        op_sibling_splice(o, NULL, 0, second);
        op_sibling_splice(o, NULL, 0, first);
	
	/* Implicitly take a reference to a regular expression */
	if (IS_TYPE(first, MATCH) && !OpSTACKED(first)) {
            DEBUG_kv(Perl_deb(aTHX_ "ck_smartmatch: match => qr\n"));
            OpTYPE_set(first, OP_QR);
	}
	if (IS_TYPE(second, MATCH) && !OpSTACKED(second)) {
            DEBUG_kv(Perl_deb(aTHX_ "ck_smartmatch: 2nd match => qr\n"));
            OpTYPE_set(second, OP_QR);
        }
    }
    
    return o;
}

/*
=for apidoc maybe_targlex
Sets the possible lexical $_ TARGET_MY optimization, skipping a scalar assignment.
=cut
*/
static OP *
S_maybe_targlex(pTHX_ OP *o)
{
    OP * const kid = OpFIRST(o);
    PERL_ARGS_ASSERT_MAYBE_TARGLEX;
    /* has a disposable target? */
    if (OP_HAS_TARGLEX(kid->op_type)
	&& !OpSTACKED(kid)
	/* Cannot steal the second time! */
	&& !(kid->op_private & OPpTARGET_MY)
	)
    {
	OP * const kkid = OpSIBLING(kid);

	/* Can just relocate the target. */
	if (OP_TYPE_IS(kkid, OP_PADSV)
	    && (!(kkid->op_private & OPpLVAL_INTRO)
	       || kkid->op_private & OPpPAD_STATE))
	{
	    kid->op_targ = kkid->op_targ;
	    kkid->op_targ = 0;
	    /* Now we do not need PADSV and SASSIGN.
	     * Detach kid and free the rest. */
	    op_sibling_splice(o, NULL, 1, NULL);
	    op_free(o);
            assert( OP_HAS_TARGLEX(kid->op_type) );
            DEBUG_kv(Perl_deb(aTHX_ "maybe_targlex: set TARGET_MY on %s\n", OP_NAME(kid)));
	    kid->op_private |= OPpTARGET_MY;	/* Used for context settings */
	    return kid;
	}
    }
    return o;
}

/* 
=for apidoc stash_to_coretype

stash_to_coretype(HV* stash) converts the name of the padname type
to the core_types_t enum.

For native types we still return the non-native counterpart.
PERL_NATIVE_TYPES is implemented in the native type branch,
with escape analysis, upgrading long-enough sequences to native ops
in rpeep.
=cut
*/
PERL_STATIC_INLINE
core_types_t S_stash_to_coretype(pTHX_ const HV* stash)
{
    if (!(UNLIKELY(VALIDTYPE(stash))))
        return type_none;
    {
        const char *name = HvNAME(stash);
        int l = HvNAMELEN(stash);
        if (!name)
            return type_none;
        if (l>6 && memEQc(name, "main::")) {
            name += 6;
            l -= 6;
        }
        /* At first a very naive string check.
           we should really use a PL_coretypes array with stash ptrs */
        if (memEQs(name, l, "int"))
#ifdef PERL_NATIVE_TYPES
            return type_int;
#else
            return type_Int;
#endif
        if (memEQs(name, l, "Int"))
            return type_Int;
        if (memEQs(name, l, "num"))
#ifdef PERL_NATIVE_TYPES
            return type_num;
#else
            return type_Num;
#endif
        if (memEQs(name, l, "Num"))
            return type_Num;
        if (memEQs(name, l, "uint"))
#ifdef PERL_NATIVE_TYPES
            return type_uint;
#else
            return type_UInt;
#endif
        if (memEQs(name, l, "UInt"))
            return type_UInt;
        if (memEQs(name, l, "str"))
#ifdef PERL_NATIVE_TYPES
            return type_str;
#else
            return type_Str;
#endif
        if (memEQs(name, l, "Str"))
            return type_Str;
        if (memEQs(name, l, "Numeric"))
            return type_Numeric;
        if (memEQs(name, l, "Scalar"))
            return type_Scalar;
        return type_Object;
    }
}


/*
=for apidoc op_typed_user

Return the type as core_types_t enum of the op.
User-defined types are only returned as type_Object,
get the name of those with S_typename().

TODO: add defined return types of all ops, and
user-defined CV types for entersub.

u8 returns 0 or 1 (HEKf_UTF8), not SVf_UTF8

=cut
*/
static core_types_t
S_op_typed_user(pTHX_ OP* o, char** usertype, int* u8)
{
    core_types_t t;
    PERL_ARGS_ASSERT_OP_TYPED_USER;

    /* descend into aggregate types: aelem-padav -> padav,
       shift padav -> padav */
    switch (o->op_type) {
    case OP_PADAV:
    case OP_PADHV:
    case OP_PADSV: {
        PADNAME * const pn = PAD_COMPNAME(ck_pad(o)->op_targ);
        if (UNLIKELY(o->op_targ && SvMAGICAL(PAD_SV(o->op_targ))))
            return type_none;
        t = stash_to_coretype(PadnameTYPE(pn));
        if (usertype && t == type_Object) {
            OpRETTYPE_set(o, t);
            *usertype = (char*)typename(PadnameTYPE(pn));
            *u8 = HvNAMEUTF8(PadnameTYPE(pn));
        }
        return t;
    }
    case OP_AELEMFAST:   /* do not exist at initial compile-time */
    case OP_AELEMFAST_LEX:
    case OP_AELEMFAST_LEX_U:
    case OP_CONST: {
        SV *sv = cSVOPx(o)->op_sv;
        switch (SvTYPE(sv)) {
        case SVt_IV:
            if (!SvROK(sv)) return SvUOK(sv) ? type_UInt : type_Int;
            else {
                SV* rv = SvRV(sv); 
                if (SvTYPE(rv) >= SVt_PVMG && SvOBJECT(rv) && VALIDTYPE(SvSTASH(rv))) {
                    if (usertype) {
                        HV *stash = SvSTASH(rv);
                        *usertype = (char*)typename(stash);
                        *u8 = HvNAMEUTF8(stash);
                    }
                    return type_Object;
                }
                return type_Scalar; /* or Ref, but we don't do Ref isa Scalar yet  */
            }
        case SVt_NULL:   return type_none;
        case SVt_PV:
            return (o->op_private & OPpCONST_BARE) /* typeglob (filehandle) */
                   ? type_Scalar : type_Str;
        case SVt_NV:     return type_Num;
            /* numified strings as const, stay conservative */
        case SVt_PVIV:   return type_Scalar; /* no POK check */
        case SVt_PVNV:   return type_Scalar; /* no POK check */
        case SVt_PVAV:   return type_Array;
        case SVt_PVHV:   return type_Hash;
        case SVt_PVCV:   return type_Sub;
        case SVt_REGEXP: return type_Regexp;
        default:
            {
                HV* stash = SvSTASH(sv);
                if (usertype && stash) {
                    *usertype = (char*)typename(stash);
                    *u8 = HvNAMEUTF8(stash);
                }
                return stash ? type_Object : type_Scalar;
            }
        }
        break;
    }
    case OP_RV2AV: {
        OP* kid = OpFIRST(o);
        /* check types of some special vars: @ARGV => Str */
        if (OP_TYPE_IS(kid, OP_GV)) {
            if (cGVOPx_gv(kid) == gv_fetchpvs("ARGV", 0, SVt_PV))
                return type_Str;
        }
        break;
    }
    case OP_RV2SV: {
        OP* kid = OpFIRST(o);
        if (OP_TYPE_IS(kid, OP_NULL))
            kid = S_op_next_nn(kid);
        /* check types of some special vars: $^O => Str */
        if (OP_TYPE_IS(kid, OP_GV)) {
            GV* gv = cGVOPx_gv(kid);
            /* XXX This is probably slow. Maybe checking the name is faster */
            if (   gv == gv_fetchpvs("^O", 0, SVt_PV)
                || gv == gv_fetchpvs("ARGV", 0, SVt_PV)
                || gv == gv_fetchpvs("0", 0, SVt_PV)
                || gv == gv_fetchpvs("^X", 0, SVt_PV) )
                return type_Str;
        }
        break;
    }
    case OP_RV2CV:
    case OP_ENTERSUB:
        /* This is wrong: The first slot inside a function is not
           the first slot from outside. CvPADLIST(cv)[0][0] it would be.
           PADNAME * const pn = PAD_COMPNAME(0);
           if (pn != &PL_padname_undef) {
            return stash_to_coretype(PadnameTYPE(pn));
        } else */
        {   /* typed methods: */
            OP* pop = OpSIBLING(OpFIRST(o));
            OP *m;
            /* XXX We should really check if Mu::new is still pristine.
               But better document the required ctor behavior. */
            /* CLASS->new -> always typed */
            if ( pop && (m = OpSIBLING(pop)) &&
                 IS_TYPE(pop, CONST) &&
                 IS_TYPE(m, METHOD_NAMED) &&
                 SvPOK(cMETHOPx_meth(m)) &&
                 /* One of the default Mu constructors */
                 (strEQc(SvPVX(cMETHOPx_meth(m)), "new")
               || strEQc(SvPVX(cMETHOPx_meth(m)), "CREATE") ))
            {
                HV *stash = gv_stashsv(cSVOPx_sv(pop),0);
                if (stash && HvCLASS(stash)) {
                    t = stash_to_coretype(stash);
                    if (usertype && t == type_Object) {
                        *usertype = (char*)typename(stash);
                        *u8 = HvNAMEUTF8(stash);
                    }
                    return t;
                }
            }
            /* typed $classobj->field:
               $obj->meth has PAD_COMPNAME($obj) a PadnameTYPE of HvCLASS. */
            if ( pop && (m = OpSIBLING(pop)) &&
                 IS_TYPE(pop, PADSV) &&
                 IS_TYPE(m, METHOD_NAMED) &&
                 SvPOK(cMETHOPx_meth(m)) )
            {
                SV *field = cMETHOPx_meth(m);
                HV *klass = PadnameTYPE(PAD_COMPNAME(pop->op_targ));
                PADOFFSET po;
                if (klass &&
                    HvCLASS(klass) &&
                    (po = field_pad(klass, SvPVX(field), SvCUR(field))
                          != NOT_IN_PAD))
                {
                    PADNAME * const pnf = PAD_COMPNAME(po);
                    const HV *stash = pnf ? PadnameTYPE(pnf) : NULL;
                    if (stash) {
                        t = stash_to_coretype(stash);
                        if (usertype && t == type_Object) {
                            *usertype = (char*)typename(stash);
                            *u8 = HvNAMEUTF8(stash);
                        }
                        return t;
                    }
                }
            }
        /*return type_none;*/
        }
    case OP_SHIFT:
    case OP_UNSHIFT:
    case OP_POP:
    case OP_PUSH:
    case OP_AELEM:
    case OP_HELEM:
        if (OpKIDS(o)) {
            /* check if the list is typed */
            t = op_typed_user(OpFIRST(o), usertype, u8);
            /* untyped array/hash does return Array/Hash, untyped lower */
            if (t < type_Array)
                return t;
        }
        break;
    default:
        break;
    } /* switch */
    /* else */
    t = (core_types_t)(PL_op_type[o->op_type] & 0xff);
    return t == type_Void ? type_none : t;
}

PERL_STATIC_INLINE
core_types_t S_op_typed(pTHX_ OP* o)
{
    PERL_ARGS_ASSERT_OP_TYPED;
    return S_op_typed_user(aTHX_ o, NULL, 0);
}

/* on is_assign copies the right type to the left */
STATIC void
S_op_check_type(pTHX_ OP* o, OP* left, OP* right, bool is_assign)
{
    const core_types_t t_left = (const core_types_t)op_typed(left);
    PERL_ARGS_ASSERT_OP_CHECK_TYPE;
    /* check types, same as for an argument check */
    if (t_left > type_none) {
/* the safe variant to PAD_COMPNAME */
#define PAD_NAME(pad_ix) padnamelist_fetch(PL_comppad_name, pad_ix)
        DEBUG_kv(Perl_deb(aTHX_ "ck op types %s: %s <=> %s\n", OP_NAME(o),
                          OP_NAME(left), OP_NAME(right)));
        if (IS_TYPE(left, AELEM) ||
            IS_TYPE(left, AELEM_U) ||
            IS_TYPE(left, HELEM))
            _op_check_type(PAD_NAME(OpFIRST(left)->op_targ), right, OP_DESC(o));
        else if (IS_TYPE(left, PADSV))
            _op_check_type(PAD_NAME(left->op_targ), right, OP_DESC(o));
        else if (IS_TYPE(left, PADAV) || IS_TYPE(left, PADHV))
            _op_check_type(PAD_NAME(left->op_targ), right, OP_DESC(o));
        /* TODO CvTYPED -> entersub
        else if (IS_TYPE(left, ENTERSUB) && OpPRIVATE(left) & OPpLVAL_INTRO)
            _op_check_type(PAD_NAME(left->op_targ), right, OP_DESC(o));
        */
#undef PAD_NAME
    } else if (is_assign) {
        const core_types_t t_right = (const core_types_t)op_typed(right);
        DEBUG_kv(Perl_deb(aTHX_ "ck_sassign: set type %d\n", (int)t_right));
        OpRETTYPE_set(left, t_right);
        if (IS_TYPE(left, PADSV) &&
            OpRETTYPE(right) == type_Object &&
            left->op_targ)
        {
            /* set the lhs typestash */
            PADNAME *pn = PAD_COMPNAME(left->op_targ);
            char *usertype = NULL;
            int  u8;
            op_typed_user(right, &usertype, &u8);
            if (usertype) {
                HV *typ = gv_stashpvn(usertype, strlen(usertype), u8 ? SVf_UTF8 : 0);
                PadnameTYPE(pn) = MUTABLE_HV(SvREFCNT_inc(MUTABLE_SV(typ)));
                DEBUG_kv(Perl_deb(aTHX_ "ck_sassign: set type %s\n", usertype));
            }
        }
    }
}

/*
=for apidoc ck_sassign
CHECK callback for sassign (s2	S S	"(:Scalar,:Scalar):Scalar")

Esp. handles state var initialization and tries to optimize away the
assignment for a lexical C<$_> via L</maybe_targlex>.

Checks types.

TODO: constant folding with OpSPECIAL
=cut
*/
OP *
Perl_ck_sassign(pTHX_ OP *o)
{
    dVAR;
    OP * const right = OpFIRST(o);
    OP * const left  = OpLAST(o);

    PERL_ARGS_ASSERT_CK_SASSIGN;

    if (OpHAS_SIBLING(right)) {
	OP *kright = OpSIBLING(right);
	/* For state variable assignment with attributes, kright is a list op
	   whose op_last is a padsv. */
	if ((IS_TYPE(kright, PADSV) ||
	     (OP_TYPE_IS_OR_WAS(kright, OP_LIST) &&
	      IS_TYPE((kright = OpLAST(kright)), PADSV)))
             && (OpPRIVATE(kright) & (OPpLVAL_INTRO|OPpPAD_STATE))
		    == (OPpLVAL_INTRO|OPpPAD_STATE)) {
	    return S_newONCEOP(aTHX_ o, kright);
	}
        if (IS_TYPE(right, SHIFT) && OpSPECIAL(right))
            return o; /* skip type check on implicit shift @_ */
    }

    DEBUG_kv(Perl_deb(aTHX_ "ck_sassign: check types\n"));
    op_check_type(o, left, right, TRUE);
    return S_maybe_targlex(aTHX_ o);
}

/*
=for apidoc ck_aassign
CHECK callback for aassign (t2	L L	"(:List,:List):List")

Checks types and adds C<OPpMAP_PAIR> to C<%hash = map>.

TODO: constant folding with OpSPECIAL
TODO: fill lhs AvFILLp with gh210-computedsizearydecl
=cut
*/
OP *
Perl_ck_aassign(pTHX_ OP *o)
{
    /* null->pushmark->elems... */
    OP * right = OpFIRST(o);
    OP * left  = OpLAST(o);

    PERL_ARGS_ASSERT_CK_AASSIGN;
    if (!(right && OpKIDS(right)
          && OP_TYPE_IS_OR_WAS_NN(right, OP_LIST)))
        return o;
    if (!(left && OpKIDS(left)
          && OP_TYPE_IS_OR_WAS_NN(left, OP_LIST)))
        return o;

    left = OpFIRST(left);
    if (IS_TYPE(left, PUSHMARK) || IS_TYPE(left, PADRANGE))
        left = OpSIBLING(left);
    right = OpFIRST(right);
    if (IS_TYPE(right, PUSHMARK) || IS_TYPE(right, PADRANGE))
        right = OpSIBLING(right);

    DEBUG_kv(Perl_deb(aTHX_ "ck_aassign: check types\n"));
    while (left && right) {
        /* my int %a; my str %b; %a = %b; (...) = (...); */
        op_check_type(o, left, right, TRUE);
        if (IS_TYPE(left, RV2HV) || IS_TYPE(left, PADHV)) {
            if (PL_hints & HINT_STRICT_HASHPAIRS) {
                AV* av = NULL;
                DEBUG_kv(Perl_deb(aTHX_ "ck_aassign: strict hashpairs\n"));
                if (IS_TYPE(right, PADAV)) {
                    av = (AV*)pad_findmy_real(right->op_targ, PL_compcv);
                    OpPRIVATE(right) |= OPpHASHPAIRS;
                } else if (IS_TYPE(right, RV2AV) && OpKIDS(right)) {
                    OP *k = OpFIRST(right);
                    OpPRIVATE(right) |= OPpHASHPAIRS;
                    if (IS_TYPE(k, CONST))
                        av = (AV*)cSVOPx_sv(k);
                    /* defer to run-time with GV, esp. with %hash = @_; */
                } else if (IS_TYPE(right, MAPWHILE)) {
                    OpPRIVATE(right) |= OPpHASHPAIRS;
                }
                if (av && (AvFILL(av)+1) % 2) {
                    qerror(Perl_mess(aTHX_
                        "Only pairs in hash assignment allowed while \"strict hashpairs\","
                        " got %" IVdf " elements", (IV)AvFILL(av)+1));
                    OpPRIVATE(right) &= ~OPpHASHPAIRS;
                }
            }
            if (IS_TYPE(right, MAPWHILE)) {
                OpPRIVATE(right) |= OPpMAP_HASH;
                DEBUG_kv(Perl_deb(aTHX_ "ck_aassign: %%hash = map_hash\n"));
            }
        }
        if (left == OpNEXT(left))  /* not yet LINKLIST'ed */
            break;
        if (right == OpNEXT(right))
            break;
        left  = OpNEXT(left);
        right = OpNEXT(right);
    }

    return o;
}

/*
=for apidoc ck_match
CHECK callback for match,qr,subst,trans,transr

Sets TARGET_MY and the targ offset on my $_ (not with qr),
which avoids runtime lookup of the global $_.

Note: This optimization was removed in perl5 with 5.24. In perl5 you have
to fight with other dynamic default topics in blocks, overwriting each other.
=cut
*/
OP *
Perl_ck_match(pTHX_ OP *o)
{
    PERL_UNUSED_CONTEXT;
    PERL_ARGS_ASSERT_CK_MATCH;

    if (ISNT_TYPE(o, QR) && PL_compcv) {
	const PADOFFSET offset = pad_findmy_pvs("$_", 0);
	if (offset != NOT_IN_PAD && !(PAD_COMPNAME_FLAGS_isOUR(offset))) {
	    o->op_targ = offset;
            DEBUG_kv(Perl_deb(aTHX_ "ck_match: esp. set TARGET_MY on %s\n", OP_NAME(o)));
            /*assert( OP_HAS_TARGLEX(o->op_type) ); they have not */
	    o->op_private |= OPpTARGET_MY;
	}
    }
    return o;
}

/*
=for apidoc ck_method
CHECK callback for method (d.)

Creates one of the 4 METHOP ops. Checks for static SUPER:: calls.
See also L</ck_subr>
=cut
*/
OP *
Perl_ck_method(pTHX_ OP *o)
{
    SV *sv, *methsv, *rclass;
    const char* method;
#ifndef PERL_NO_QUOTE_PKGSEPERATOR
    char* compatptr;
#endif
    int utf8;
    STRLEN len, nsplit = 0, i;
    OP* new_op;
    OP * const kid = OpFIRST(o);

    PERL_ARGS_ASSERT_CK_METHOD;
    if (ISNT_TYPE(kid, CONST)) return o;

    sv = kSVOP->op_sv;

#ifndef PERL_NO_QUOTE_PKGSEPERATOR
    /* replace ' with :: */
    while ((compatptr = (char *) memchr(SvPVX(sv), '\'',
                                        SvEND(sv) - SvPVX(sv) )))
    {
        *compatptr = ':';
        sv_insert(sv, compatptr - SvPVX_const(sv), 0, ":", 1);
    }
#endif

    method = SvPVX_const(sv);
    len = SvCUR(sv);
    utf8 = SvUTF8(sv) ? -1 : 1;

    for (i = len - 1; i > 0; --i) if (method[i] == ':') {
        nsplit = i+1;
        break;
    }

    methsv = newSVpvn_share(method+nsplit, utf8*(len - nsplit), 0);

    if (!nsplit) { /* $proto->method() */
        op_free(o);
        return newMETHOP_named(OP_METHOD_NAMED, 0, methsv);
    }

    if (memEQs(method, nsplit, "SUPER::")) { /* $proto->SUPER::method() */
        op_free(o);
        return newMETHOP_named(OP_METHOD_SUPER, 0, methsv);
    }

    /* $proto->MyClass::method() and $proto->MyClass::SUPER::method() */
    if (nsplit >= 9 && strBEGINs(method+nsplit-9, "::SUPER::")) {
        rclass = newSVpvn_share(method, utf8*(nsplit-9), 0);
        new_op = newMETHOP_named(OP_METHOD_REDIR_SUPER, 0, methsv);
    } else {
        rclass = newSVpvn_share(method, utf8*(nsplit-2), 0);
        new_op = newMETHOP_named(OP_METHOD_REDIR, 0, methsv);
    }
#ifdef USE_ITHREADS
    op_relocate_sv(&rclass, &cMETHOPx(new_op)->op_rclass_targ);
#else
    cMETHOPx(new_op)->op_rclass_sv = rclass;
#endif
    op_free(o);
    return new_op;
}

OP *
Perl_ck_null(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_NULL;
    PERL_UNUSED_CONTEXT;
    return o;
}

OP *
Perl_ck_open(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_OPEN;

    S_io_hints(aTHX_ o);
    {
	 /* In case of three-arg dup open remove strictness
	  * from the last arg if it is a bareword. */
	 OP * const first = OpFIRST(o); /* The pushmark. */
	 OP * const last  = OpLAST(o);  /* The bareword. */
	 OP *oa;
	 const char *mode;

	 if (IS_CONST_OP(last) &&		/* The bareword. */
	     (last->op_private & OPpCONST_BARE) &&
	     (last->op_private & OPpCONST_STRICT) &&
	     (oa = OpSIBLING(first)) &&		/* The fh. */
	     (oa = OpSIBLING(oa)) &&			/* The mode. */
	     IS_CONST_OP(oa) &&
	     SvPOK(((SVOP*)oa)->op_sv) &&
	     (mode = SvPVX_const(((SVOP*)oa)->op_sv)) &&
	     mode[0] == '>' && mode[1] == '&' &&	/* A dup open. */
	     (last == OpSIBLING(oa)))			/* The bareword. */
	      last->op_private &= ~OPpCONST_STRICT;
    }
    return ck_fun(o);
}

OP *
Perl_ck_prototype(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_PROTOTYPE;
    if (!OpKIDS(o)) {
	op_free(o);
	return newUNOP(OP_PROTOTYPE, 0, newDEFSVOP());
    }
    return o;
}

OP *
Perl_ck_refassign(pTHX_ OP *o)
{
    OP * const right = OpFIRST(o);
    OP * const left  = OpSIBLING(right);
    OP *varop        = OpFIRST(OpFIRST(left));
    bool stacked = 0;

    PERL_ARGS_ASSERT_CK_REFASSIGN;
    assert (left);
    assert (IS_TYPE(left, SREFGEN));

    o->op_private = 0;
    /* we use OPpPAD_STATE in refassign to mean either of those things,
     * and the code assumes the two flags occupy the same bit position
     * in the various ops below */
    assert(OPpPAD_STATE == OPpOUR_INTRO);

    switch (varop->op_type) {
    case OP_PADAV:
	o->op_private |= OPpLVREF_AV;
	goto settarg;
    case OP_PADHV:
	o->op_private |= OPpLVREF_HV;
        /* FALLTHROUGH */
    case OP_PADSV:
      settarg:
        o->op_private |= (varop->op_private & (OPpLVAL_INTRO|OPpPAD_STATE));
	o->op_targ = varop->op_targ;
	varop->op_targ = 0;
	PAD_COMPNAME_GEN_set(o->op_targ, PERL_INT_MAX);
	break;

    case OP_RV2AV:
	o->op_private |= OPpLVREF_AV;
	goto checkgv;
        NOT_REACHED; /* NOTREACHED */
    case OP_RV2HV:
	o->op_private |= OPpLVREF_HV;
        /* FALLTHROUGH */
    case OP_RV2SV:
      checkgv:
        o->op_private |= (varop->op_private & (OPpLVAL_INTRO|OPpOUR_INTRO));
	if (ISNT_TYPE(OpFIRST(varop), GV)) goto bad;
      detach_and_stack:
	/* Point varop to its GV kid, detached.  */
	varop = op_sibling_splice(varop, NULL, -1, NULL);
	stacked = TRUE;
	break;
    case OP_RV2CV: {
	OP * const kidparent = OpSIBLING(OpFIRST(OpFIRST(varop)));
	OP * const kid = OpFIRST(kidparent);
	o->op_private |= OPpLVREF_CV;
	if (IS_TYPE(kid, GV)) {
	    varop = kidparent;
	    goto detach_and_stack;
	}
	if (ISNT_TYPE(kid, PADCV))	goto bad;
	o->op_targ = kid->op_targ;
	kid->op_targ = 0;
	break;
    }
    /* Note: The typed and unchecked variants cannot handle LVAL_INTRO
       nor LVREF, so they'l error. */
    case OP_AELEM:
    case OP_HELEM:
        o->op_private |= (varop->op_private & OPpLVAL_INTRO);
	o->op_private |= OPpLVREF_ELEM;
	op_null(varop);
	stacked = TRUE;
	/* Detach varop.  */
	op_sibling_splice(OpFIRST(left), NULL, -1, NULL);
	break;
    default:
      bad:
	/* diag_listed_as: Can't modify reference to %s in %s assignment */
	yyerror(Perl_form(aTHX_ "Can't modify reference to %s in scalar "
				"assignment",
				 OP_DESC(varop)));
	return o;
    }
    if (!FEATURE_REFALIASING_IS_ENABLED)
	Perl_croak(aTHX_
		  "Experimental aliasing via reference not enabled");
    Perl_ck_warner_d(aTHX_
		     packWARN(WARN_EXPERIMENTAL__REFALIASING),
		    "Aliasing via reference is experimental");
    if (stacked) {
	o->op_flags |= OPf_STACKED;
	op_sibling_splice(o, right, 1, varop);
    }
    else {
	o->op_flags &=~ OPf_STACKED;
	op_sibling_splice(o, right, 1, NULL);
    }
    op_free(left);
    return o;
}

OP *
Perl_ck_repeat(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_REPEAT;

    if (OpFIRST(o)->op_flags & OPf_PARENS) {
        OP* kids;
	o->op_private |= OPpREPEAT_DOLIST;
        kids = op_sibling_splice(o, NULL, 1, NULL); /* detach first kid */
        kids = force_list(kids, 1); /* promote it to a list */
        op_sibling_splice(o, NULL, 0, kids); /* and add back */
    }
    else
	scalar(o);
    return o;
}

STATIC void
S__share_hek(pTHX_ char *s, STRLEN len, SV* sv, U32 const was_readonly)
{
    dVAR;
    HEK *hek;
    U32 hash;
    PERL_HASH(hash, s, len);
    if (UNLIKELY(len > I32_MAX))
        Perl_croak(aTHX_ "panic: name too long (%" UVuf ")", (UV)len);
    hek = share_hek(s, (I32)len * (SvUTF8(sv) ? -1 : 1), hash);
    sv_sethek(sv, hek);
    unshare_hek(hek);
    SvFLAGS(sv) |= was_readonly;
}

OP *
Perl_ck_require(pTHX_ OP *o)
{
    GV* gv;

    PERL_ARGS_ASSERT_CK_REQUIRE;

    if (OpKIDS(o)) {	/* Shall we supply missing .pm? */
	SVOP * const kid = (SVOP*)OpFIRST(o);
	char *s;
	STRLEN len;

        if (IS_CONST_OP(kid)) {
            SV * const sv = kid->op_sv;
            U32 const was_readonly = SvREADONLY(sv);
            if (kid->op_private & OPpCONST_BARE) {
                const char *end;
                bool disallowed = FALSE;

                if (was_readonly)
                    SvREADONLY_off(sv);
                if (SvIsCOW(sv))
                    sv_force_normal_flags(sv, 0);

                s = SvPVX(sv);
                len = SvCUR(sv);
                end = s + len;
                if (s == end)
                    DIE(aTHX_ "Bareword in require maps to empty filename");
                if (len >= 1 && memchr(s, 0, len-1))
                    /* diag_listed_as: Bareword in require contains "%s" */
                    DIE(aTHX_ "Bareword in require contains \"\\0\"");
                if (len >= 2 && s[0] == ':' && s[1] == ':')
                    disallowed = TRUE;

                for (; s < end; s++) {
                    if (*s == ':' && s[1] == ':') {
                        *s = '/';
                        Move(s+2, s+1, end - s - 1, char);
                        --end;
                    }
                }
                SvEND_set(sv, end);
                sv_catpvs(sv, ".pm");
                s = SvPVX(sv);
                len = SvCUR(sv);

                if (disallowed)
                    Perl_croak(aTHX_ "Bareword in require maps to disallowed filename \"%s\"",
                               s);

                S__share_hek(aTHX_ s, len, sv, was_readonly);
            }
            else if (SvPOK(sv) && !SvNIOK(sv) && !SvGMAGICAL(sv) && !SvVOK(sv)) {
                s = SvPV(sv, len);
                if (SvREFCNT(sv) > 1) {
                    kid->op_sv = newSVpvn_share
                        (s, SvUTF8(sv) ? -(SSize_t)len : (SSize_t)len, 0);
                    SvREFCNT_dec_NN(sv);
                }
                else {
                    if (was_readonly) SvREADONLY_off(sv);
                    S__share_hek(aTHX_ s, len, sv, was_readonly);
                }
            }
	}
    }

    if (!(OpSPECIAL(o)) /* Wasn't written as CORE::require */
	/* handle override, if any */
     && (gv = gv_override("require", 7))) {
	OP *kid, *newop;
	if (OpKIDS(o)) {
	    kid = OpFIRST(o);
            op_sibling_splice(o, NULL, -1, NULL);
	}
	else {
	    kid = newDEFSVOP();
	}
	op_free(o);
	newop = new_entersubop(gv, kid);
	return newop;
    }

    return ck_fun(o);
}

OP *
Perl_ck_return(pTHX_ OP *o)
{
    OP *kid;

    PERL_ARGS_ASSERT_CK_RETURN;

    kid = OpSIBLING(OpFIRST(o));
    if (PL_compcv && CvLVALUE(PL_compcv)) {
	for (; kid; kid = OpSIBLING(kid))
	    op_lvalue(kid, OP_LEAVESUBLV);
    }

    return o;
}

OP *
Perl_ck_select(pTHX_ OP *o)
{
    dVAR;
    OP* kid;

    PERL_ARGS_ASSERT_CK_SELECT;

    if (OpKIDS(o)) {
        kid = OpSIBLING(OpFIRST(o));     /* get past pushmark */
        if (kid && OpHAS_SIBLING(kid)) {
            OpTYPE_set(o, OP_SSELECT);
	    o = ck_fun(o);
	    return fold_constants(op_integerize(op_std_init(o)));
	}
    }
    o = ck_fun(o);
    kid = OpSIBLING(OpFIRST(o));    /* get past pushmark */
    if (kid && IS_TYPE(kid, RV2GV))
	kid->op_private &= ~HINT_STRICT_REFS;
    return o;
}

/* pop|shift s%	A? */
OP *
Perl_ck_shift(pTHX_ OP *o)
{
    const I32 type = o->op_type;

    PERL_ARGS_ASSERT_CK_SHIFT;

    if (!OpKIDS(o)) {
	OP *argop;

	if (PL_compcv && !CvUNIQUE(PL_compcv)) {
	    o->op_flags |= OPf_SPECIAL;
            DEBUG_k(Perl_deb(aTHX_ "ck_shift: %s SPECIAL\n", OP_NAME(o)));
	    return o;
	}

	argop = newUNOP(OP_RV2AV, 0, scalar(newGVOP(OP_GV, 0, PL_argvgv)));
        DEBUG_k(Perl_deb(aTHX_ "ck_shift: rv2av $_\n"));
	op_free(o);
	return newUNOP(type, 0, scalar(argop));
    }
    DEBUG_k(Perl_deb(aTHX_ "ck_shift: %s scalar\n", OP_NAME(o)));
    return scalar(ck_fun(o));
}

OP *
Perl_ck_sort(pTHX_ OP *o)
{
    OP *firstkid;
    OP *kid;
    HV * const hinthv =
	PL_hints & HINT_LOCALIZE_HH ? GvHV(PL_hintgv) : NULL;
    U8 stacked;

    PERL_ARGS_ASSERT_CK_SORT;

    if (hinthv) {
        SV ** const svp = hv_fetchs(hinthv, "sort", FALSE);
        if (svp) {
            const I32 sorthints = (I32)SvIV(*svp);
            if ((sorthints & HINT_SORT_QUICKSORT) != 0)
                o->op_private |= OPpSORT_QSORT;
            if ((sorthints & HINT_SORT_STABLE) != 0)
                o->op_private |= OPpSORT_STABLE;
            if ((sorthints & HINT_SORT_UNSTABLE) != 0)
                o->op_private |= OPpSORT_UNSTABLE;
        }
    }

    if (OpSTACKED(o))
	simplify_sort(o);
    firstkid = OpSIBLING(OpFIRST(o));		/* get past pushmark */

    if ((stacked = OpSTACKED(o))) {	/* may have been cleared */
	OP *kid = OpFIRST(firstkid);		/* get past null */

        /* if the first arg is a code block, process it and mark sort as
         * OPf_SPECIAL */
	if (IS_TYPE(kid, SCOPE) || IS_TYPE(kid, LEAVE)) {
	    LINKLIST(kid);
	    if (IS_TYPE(kid, LEAVE))
                op_null(kid);			/* wipe out leave */
	    /* Prevent execution from escaping out of the sort block. */
	    OpNEXT(kid) = 0;

	    /* provide scalar context for comparison function/block */
	    kid = scalar(firstkid);
	    OpNEXT(kid) = kid;
	    o->op_flags |= OPf_SPECIAL;
	}
	else if (IS_CONST_OP(kid) && kid->op_private & OPpCONST_BARE) {
	    char tmpbuf[TOKENBUF_SIZE];
	    STRLEN len;
	    PADOFFSET off;
	    const char * const name = SvPV(kSVOP_sv, len);
	    *tmpbuf = '&';
	    assert (len < TOKENBUF_SIZE);
	    Copy(name, tmpbuf+1, len, char);
	    off = pad_findmy_pvn(tmpbuf, len+1, 0); /* all pads are UTF8 */
	    if (off != NOT_IN_PAD) {
		if (PAD_COMPNAME_FLAGS_isOUR(off)) {
		    SV * const fq =
			newSVhek(HvNAME_HEK(PAD_COMPNAME_OURSTASH(off)));
		    sv_catpvs(fq, "::");
		    sv_catsv(fq, kSVOP_sv);
		    SvREFCNT_dec_NN(kSVOP_sv);
		    kSVOP->op_sv = fq;
		}
		else {
		    OP * const padop = newOP(OP_PADCV, 0);
		    padop->op_targ = off;
                    /* replace the const op with the pad op */
                    op_sibling_splice(firstkid, NULL, 1, padop);
		    op_free(kid);
		}
	    }
	}

	firstkid = OpSIBLING(firstkid);
    }

    for (kid = firstkid; kid; kid = OpSIBLING(kid)) {
	/* provide list context for arguments */
	list(kid);
	if (stacked)
	    op_lvalue(kid, OP_GREPSTART);
    }

    return o;
}

/* for sort { X } ..., where X is one of
 *   $a <=> $b, $b <=> $a, $a cmp $b, $b cmp $a
 * elide the second child of the sort (the one containing X),
 * and set these flags as appropriate
	OPpSORT_NUMERIC;
	OPpSORT_INTEGER;
	OPpSORT_DESCEND;
 * Also, check and warn on lexical $a, $b.
 */

static void
S_simplify_sort(pTHX_ OP *o)
{
    OP *kid = OpSIBLING(OpFIRST(o));	/* get past pushmark */
    OP *k;
    GV *gv;
    const char *gvname;
    int descending;
    bool have_scopeop;

    PERL_ARGS_ASSERT_SIMPLIFY_SORT;

    kid = OpFIRST(kid);				/* get past null */
    if (!(have_scopeop = IS_TYPE(kid, SCOPE)) && ISNT_TYPE(kid, LEAVE))
	return;
    kid = OpLAST(kid);				/* get past scope */
    switch(kid->op_type) {
	case OP_CMP:
	case OP_I_CMP:
	case OP_S_CMP:
	    if (!have_scopeop) goto padkids;
	    break;
	default:
	    return;
    }
    k = kid;						/* remember this node*/
    if (   ISNT_TYPE(OpFIRST(kid), RV2SV)
        || ISNT_TYPE(OpLAST(kid),  RV2SV))
    {
	/*
	   Warn about my($a) or my($b) in a sort block, *if* $a or $b is
	   then used in a comparison.  This catches most, but not
	   all cases.  For instance, it catches
	       sort { my($a); $a <=> $b }
	   but not
	       sort { my($a); $a < $b ? -1 : $a == $b ? 0 : 1; }
	   (although why you'd do that is anyone's guess).
	*/

       padkids:
	if (!ckWARN(WARN_SYNTAX)) return;
	kid = OpFIRST(kid);
	do {
	    if (IS_TYPE(kid, PADSV)) {
		PADNAME * const name = PAD_COMPNAME(kid->op_targ);
		if (PadnameLEN(name) == 2 && *PadnamePV(name) == '$'
		 && (  PadnamePV(name)[1] == 'a'
		    || PadnamePV(name)[1] == 'b'  ))
		    /* diag_listed_as: "my %s" used in sort comparison */
		    Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
				     "\"%s %s\" used in sort comparison",
				      PadnameIsSTATE(name)
					? "state"
					: "my",
				      PadnamePV(name));
	    }
	} while ((kid = OpSIBLING(kid)));
	return;
    }
    kid = OpFIRST(kid);				/* get past cmp */
    if (ISNT_TYPE(OpFIRST(kid), GV))
	return;
    kid = OpFIRST(kid);				/* get past rv2sv */
    gv = kGVOP_gv;
    if (GvSTASH(gv) != PL_curstash)
	return;
    gvname = GvNAME(gv);
    if (*gvname == 'a' && gvname[1] == '\0')
	descending = 0;
    else if (*gvname == 'b' && gvname[1] == '\0')
	descending = 1;
    else
	return;

    kid = k;						/* back to cmp */
    /* already checked above that it is rv2sv */
    kid = OpLAST(kid);				/* down to 2nd arg */
    if (ISNT_TYPE(OpFIRST(kid), GV))
	return;
    kid = OpFIRST(kid);				/* get past rv2sv */
    gv = kGVOP_gv;
    if (GvSTASH(gv) != PL_curstash)
	return;
    gvname = GvNAME(gv);
    if ( descending
	 ? !(*gvname == 'a' && gvname[1] == '\0')
	 : !(*gvname == 'b' && gvname[1] == '\0'))
	return;
    o->op_flags &= ~(OPf_STACKED | OPf_SPECIAL);
    if (descending)
	o->op_private |= OPpSORT_DESCEND;
    if (IS_TYPE(k, CMP))
	o->op_private |= OPpSORT_NUMERIC;
    if (IS_TYPE(k, I_CMP))
	o->op_private |= OPpSORT_NUMERIC | OPpSORT_INTEGER;
    kid = OpSIBLING(OpFIRST(o));
    /* cut out and delete old block (second sibling) */
    op_sibling_splice(o, OpFIRST(o), 1, NULL);
    op_free(kid);
}

OP *
Perl_ck_split(pTHX_ OP *o)
{
    dVAR;
    OP *kid;
    OP *sibs;

    PERL_ARGS_ASSERT_CK_SPLIT;

    assert(o->op_type == OP_LIST);
    if (OpSTACKED(o))
	return no_fh_allowed(o);

    kid = OpFIRST(o);
    /* delete leading NULL node, then add a CONST if no other nodes */
    assert(kid->op_type == OP_NULL);
    op_sibling_splice(o, NULL, 1,
	OpHAS_SIBLING(kid) ? NULL : newSVOP(OP_CONST, 0, newSVpvs(" ")));
    op_free(kid);
    kid = OpFIRST(o);

    if (ISNT_TYPE(kid, MATCH) || OpSTACKED(kid)) {
        /* remove match expression, and replace with new optree with
         * a match op at its head */
        op_sibling_splice(o, NULL, 1, NULL);
        /* pmruntime will handle split " " behavior with flag==2 */
        kid = pmruntime(newPMOP(OP_MATCH, 0), kid, NULL, 2, 0);
        op_sibling_splice(o, NULL, 0, kid);
    }

    assert(kid->op_type == OP_MATCH || kid->op_type == OP_SPLIT);

    if (((PMOP *)kid)->op_pmflags & PMf_GLOBAL) {
      Perl_ck_warner(aTHX_ packWARN(WARN_REGEXP),
		     "Use of /g modifier is meaningless in split");
    }

    /* eliminate the split op, and move the match op (plus any children)
     * into its place, then convert the match op into a split op. i.e.
     *
     *  SPLIT                    MATCH                 SPLIT(ex-MATCH)
     *    |                        |                     |
     *  MATCH - A - B - C   =>     R - A - B - C   =>    R - A - B - C
     *    |                        |                     |
     *    R                        X - Y                 X - Y
     *    |
     *    X - Y
     *
     * (R, if it exists, will be a regcomp op)
     */

    op_sibling_splice(o, NULL, 1, NULL); /* detach match op from o */
    sibs = op_sibling_splice(o, NULL, -1, NULL); /* detach any other sibs */
    op_sibling_splice(kid, cLISTOPx(kid)->op_last, 0, sibs); /* and reattach */
    OpTYPE_set(kid, OP_SPLIT);
    kid->op_flags   = (o->op_flags | (kid->op_flags & OPf_KIDS));
    kid->op_private = o->op_private;
    op_free(o);
    o = kid;
    kid = sibs; /* kid is now the string arg of the split */

    if (!kid) {
	kid = newDEFSVOP();
	op_append_elem(OP_SPLIT, o, kid);
    }
    scalar(kid);

    kid = OpSIBLING(kid);
    if (!kid) {
        kid = newSVOP(OP_CONST, 0, newSViv(0));
	op_append_elem(OP_SPLIT, o, kid);
	o->op_private |= OPpSPLIT_IMPLIM;
    }
    scalar(kid);

    if (OpHAS_SIBLING(kid))
	return too_many_arguments_pv(o,OP_DESC(o), 0);

    return o;
}

OP *
Perl_ck_stringify(pTHX_ OP *o)
{
    OP * const kid = OpSIBLING(OpFIRST(o));
    PERL_ARGS_ASSERT_CK_STRINGIFY;
    if ((   IS_TYPE(kid, JOIN) || IS_TYPE(kid, QUOTEMETA)
         || IS_TYPE(kid, LC)   || IS_TYPE(kid, LCFIRST)
         || IS_TYPE(kid, UC)   || IS_TYPE(kid, UCFIRST))
	&& !OpHAS_SIBLING(kid)) /* syntax errs can leave extra children */
    {
	op_sibling_splice(o, OpFIRST(o), -1, NULL);
	op_free(o);
	return kid;
    }
    return ck_fun(o);
}
	
OP *
Perl_ck_join(pTHX_ OP *o)
{
    OP * const kid = OpSIBLING(OpFIRST(o));

    PERL_ARGS_ASSERT_CK_JOIN;

    if (kid && IS_TYPE(kid, MATCH)) {
	if (ckWARN(WARN_SYNTAX)) {
            const REGEXP *re = PM_GETRE(kPMOP);
            const SV *msg = re
                    ? newSVpvn_flags( RX_PRECOMP_const(re), RX_PRELEN(re),
                                            SVs_TEMP | ( RX_UTF8(re) ? SVf_UTF8 : 0 ) )
                    : newSVpvs_flags( "STRING", SVs_TEMP );
	    Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
			"/%" SVf "/ should probably be written as \"%" SVf "\"",
			SVfARG(msg), SVfARG(msg));
	}
    }
    if (kid
     && (IS_CONST_OP(kid) /* an innocent, unsuspicious separator */
	|| (IS_TYPE(kid, PADSV) && !(kid->op_private & OPpLVAL_INTRO))
        || (IS_TYPE(kid, RV2SV) && IS_TYPE(OpFIRST(kid), GV)
            && !(kid->op_private & (OPpLVAL_INTRO|OPpOUR_INTRO)))))
    {
	const OP * const bairn = OpSIBLING(kid); /* the list */
	if (bairn && !OpHAS_SIBLING(bairn) /* single-item list */
            && OP_GIMME_SCALAR(bairn))
	{
	    OP * const ret = op_convert_list(OP_STRINGIFY, OPf_FOLDED,
			         op_sibling_splice(o, kid, 1, NULL));
	    op_free(o);
	    return ret;
	}
    }

    return ck_fun(o);
}

/*
=for apidoc Am|CV *|rv2cv_op_cv|OP *cvop|U32 flags

Examines an op, which is expected to identify a subroutine at runtime,
and attempts to determine at compile time which subroutine it identifies.
This is normally used during Perl compilation to determine whether
a prototype can be applied to a function call.  C<cvop> is the op
being considered, normally an C<rv2cv> op.  A pointer to the identified
subroutine is returned, if it could be determined statically, and a null
pointer is returned if it was not possible to determine statically.

Currently, the subroutine can be identified statically if the RV that the
C<rv2cv> is to operate on is provided by a suitable C<gv> or C<const> op.
A C<gv> op is suitable if the GV's CV slot is populated.  A C<const> op is
suitable if the constant value must be an RV pointing to a CV.  Details of
this process may change in future versions of Perl.  If the C<rv2cv> op
has the C<OPpENTERSUB_AMPER> flag set then no attempt is made to identify
the subroutine statically: this flag is used to suppress compile-time
magic on a subroutine call, forcing it to use default runtime behaviour.

If C<flags> has the bit C<RV2CVOPCV_MARK_EARLY> set, then the handling
of a GV reference is modified.  If a GV was examined and its CV slot was
found to be empty, then the C<gv> op has the C<OPpEARLY_CV> flag set.
If the op is not optimised away, and the CV slot is later populated with
a subroutine having a prototype, that flag eventually triggers the warning
"called too early to check prototype".

If C<flags> has the bit C<RV2CVOPCV_RETURN_NAME_GV> set, then instead
of returning a pointer to the subroutine it returns a pointer to the
GV giving the most appropriate name for the subroutine in this context.
Normally this is just the C<CvGV> of the subroutine, but for an anonymous
(C<CvANON>) subroutine that is referenced through a GV it will be the
referencing GV.  The resulting C<GV*> is cast to C<CV*> to be returned.
A null pointer is returned as usual if there is no statically-determinable
subroutine.

=cut
*/

/* shared by toke.c:yylex */
CV *
Perl_find_lexical_cv(pTHX_ PADOFFSET off)
{
    PADNAME *name = PAD_COMPNAME(off);
    CV *compcv = PL_compcv;
    while (PadnameOUTER(name)) {
	assert(PARENT_PAD_INDEX(name));
	compcv = CvOUTSIDE(compcv);
	name = PadlistNAMESARRAY(CvPADLIST(compcv))
		[off = PARENT_PAD_INDEX(name)];
    }
    assert(!PadnameIsOUR(name));
    if (!PadnameIsSTATE(name) && PadnamePROTOCV(name)) {
	return PadnamePROTOCV(name);
    }
    return (CV *)AvARRAY(PadlistARRAY(CvPADLIST(compcv))[1])[off];
}

CV *
Perl_rv2cv_op_cv(pTHX_ OP *cvop, U32 flags)
{
    OP *rvop;
    CV *cv;
    GV *gv;
    PERL_ARGS_ASSERT_RV2CV_OP_CV;
    if (flags & ~RV2CVOPCV_FLAG_MASK)
	Perl_croak(aTHX_ "panic: rv2cv_op_cv bad flags %x", (unsigned)flags);
    if (ISNT_TYPE(cvop, RV2CV))
	return NULL;
    if (cvop->op_private & OPpENTERSUB_AMPER)
	return NULL;
    if (!(cvop->op_flags & OPf_KIDS))
	return NULL;
    rvop = OpFIRST(cvop);
    switch (rvop->op_type) {
	case OP_GV: {
	    gv = cGVOPx_gv(rvop);
	    if (!isGV(gv)) {
		if (SvROK(gv) && SvTYPE(SvRV(gv)) == SVt_PVCV) {
		    cv = MUTABLE_CV(SvRV(gv));
		    gv = NULL;
		    break;
		}
		if (flags & RV2CVOPCV_RETURN_STUB)
		    return (CV *)gv;
		else return NULL;
	    }
	    cv = GvCVu(gv);
	    if (!cv) {
		if (flags & RV2CVOPCV_MARK_EARLY)
		    rvop->op_private |= OPpEARLY_CV;
		return NULL;
	    }
	} break;
	case OP_CONST: {
	    SV *rv = cSVOPx_sv(rvop);
	    if (!SvROK(rv))
		return NULL;
	    cv = (CV*)SvRV(rv);
	    gv = NULL;
	} break;
	case OP_PADCV: {
	    cv = find_lexical_cv(rvop->op_targ);
	    gv = NULL;
	} break;
	default: {
	    return NULL;
	} NOT_REACHED; /* NOTREACHED */
    }
    if (SvTYPE((SV*)cv) != SVt_PVCV)
	return NULL;
    if (flags & (RV2CVOPCV_RETURN_NAME_GV|RV2CVOPCV_MAYBE_NAME_GV)) {
	if ((!CvANON(cv) || !gv) && !CvLEXICAL(cv)
	 && ((flags & RV2CVOPCV_RETURN_NAME_GV) || !CvNAMED(cv)))
	    gv = CvGV(cv);
	return (CV*)gv;
    } else {
	return cv;
    }
}

/*
=for apidoc s	|int	|can_class_typecheck|NN const HV* const stash

Returns 1 if this class has a compile-time @ISA
or we are already at the run-time phase.
This is not called for coretypes, coretypes would always return 1.

Check for class or package types. Does the class has an compile-time
ISA to allow compile-time checks? #249
HvCLASS: Is it a cperl class? Does it use base or fields?
If not cannot do this check before run-time.

(Essentially cperl classes are just syntactic and performance
optimized sugar over base/fields with roles and multi-dispatch
support. We don't invent anything new, we just fix what p5p broke.)

=cut
*/
STATIC int
S_can_class_typecheck(pTHX_ const HV* const stash)
{
    PERL_ARGS_ASSERT_CAN_CLASS_TYPECHECK;
    if (UNLIKELY(PL_phase >= PERL_PHASE_RUN))
        return 1;
    else if (HvCLASS(stash)) {
        const AV* isa = mro_get_linear_isa((HV*)stash);
        return AvFILLp(isa) ? 1 : 0;
    } else
        return 0;
}

/* 
=for apidoc s	|int	|match_user_type|NN const HV* const dstash \
					|NN const char* aname|bool au8

Match a usertype from argument (aname+au8) to
the declared usertype name of a variable (dstash).
Searches dstash in @aname::ISA (contravariant, for arguments).

On return-type checks the arguments get in reversed (covariant).

Note that old-style package ISA's are created dynamically.
Only classes with compile-time known ISA's can be checked at compile-time.
Which are currently: use base/fields using Internals::HvCLASS,
and later the perl6 syntax class Name is Parent {}
=cut
*/
STATIC int
S_match_user_type(pTHX_ const HV* const dstash,
                  const char* aname, bool au8)
{
    const SV * const dname = newSVhek(HvENAME_HEK(dstash)
                                      ? HvENAME_HEK(dstash)
                                      : HvNAME_HEK(dstash));
    const HV* astash = gv_stashpvn(aname, strlen(aname), au8 ? SVf_UTF8 : 0);
    PERL_ARGS_ASSERT_MATCH_USER_TYPE;

    if (astash == dstash) /* compare ptrs not strings */
        return 1;
    /* Search dname in @aname::ISA (contravariant).
     * The astash needs to exist, but coretypes are created on the fly. */
    /* Some autocreated coretypes do have an ISA */
    if (!astash)
        astash = find_in_coretypes(aname, strlen(aname));
    if (astash) {
        SSize_t i;
        const AV* isa = mro_get_linear_isa((HV*)astash);
        for (i=0; i<=AvFILLp(isa); i++) {
            SV* ele = AvARRAY(isa)[i]; /* array of shared class name HEKs */
            DEBUG_kv(Perl_deb(aTHX_ "typecheck %s in %s\n", SvPVX_const(dname),
                              SvPVX_const(ele)));
            if (sv_eq(ele, (SV*)dname))
                return 1;
        }
    }
    if (can_class_typecheck(dstash) && ckWARN(WARN_TYPES))
        Perl_warner(aTHX_ packWARN(WARN_TYPES),
                    "Wrong type %s, expected %s", aname, SvPVX_const(dname));
    return 0;
}
 
/*
=for apidoc match_type

Match a coretype from arg or op (atyp) to
the declared stash of a variable (dtyp).
Searches stash in @aname::ISA (contravariant, for arguments).

Added a 4th parameter if to allow inserting a type cast: 
numify. Scalar => Bool/Numeric
Currently castable is only: Scalar/Ref/Sub/Regexp => Bool/Numeric
Maybe allow casting from Scalar/Numeric to Int => int()
and Scalar to Str => stringify()

On atyp == type_Object check the name and its ISA instead.
=cut
*/
PERL_STATIC_INLINE
int S_match_type(pTHX_ const HV* stash, core_types_t atyp, const char* aname,
                 bool au8, int *castable)
{
    core_types_t dtyp = stash_to_coretype(stash);
    int retval;
    PERL_ARGS_ASSERT_MATCH_TYPE;

    if (LIKELY(dtyp == type_none /* no declared type */
               /* or same coretype */
               || (dtyp == atyp && dtyp != type_Object)
               /* or Scalar arg, matches any decl */
               || (atyp == type_Scalar && dtyp <= type_Object)
               ))
        return 1;
    /* we can cast any coretype to another: numify, stringify, but not user-objects.
       but if someone declared a coretype, like int and gets a Str do not cast. */
    *castable = (dtyp >= type_int && dtyp < type_Object);
    /* user-type can inherit from coretypes. e.g. MyInt (isa Int) for int args */
    if (atyp == type_Object) {
        *castable = match_user_type(stash, aname, au8);
        if (can_class_typecheck(stash) || *castable) {
            return *castable;
        }
        else {
            /* We can numify and stringify any object.
               The other way round it is possible to let the user-type inherit
               from the coretype dynamically. */
            const char* dname = HvNAME(stash);
            /* compiler cannot decide on run-time ISA's */
            *castable = 1; /* Does not match yet, but maybe later */
            return dname && strEQ(dname, aname);
        }
    }
    /* and now check the allowed variants */
#define isNumScalar (atyp == type_Numeric || atyp == type_Scalar)
    switch (dtyp) {
    case type_int:
        retval = atyp != type_str  && atyp <= type_UInt;
        *castable = retval || isNumScalar;
        return retval;
    case type_Int:
        retval = (atyp == type_int || atyp == type_UInt || atyp == type_uint);
        *castable = retval || atyp <= type_Num || isNumScalar;
        return retval;
    case type_uint:
        retval = (atyp == type_UInt || atyp == type_Int  || atyp == type_int);
        *castable = retval || atyp <= type_Num || isNumScalar;
        return retval;
    case type_UInt:
        retval = (atyp == type_uint || atyp == type_Int  || atyp == type_int);
        *castable = retval || atyp <= type_Num || isNumScalar;
        return retval;
    case type_num:
        retval = (atyp == type_Num);
        *castable = retval || atyp <= type_Num || isNumScalar;
        return retval;
    case type_Num:
        retval = (atyp == type_num);
        *castable = retval || atyp <= type_Num || isNumScalar;
        return retval;
    case type_Str:
        return atyp == type_str;
    case type_str:
        return atyp == type_Str;
    case type_Numeric:
        return atyp != type_str && atyp <= type_Num;
    case type_Scalar:
        return atyp <= type_Scalar;
    case type_Object:
        /* allow more specific classes, such as coretypes */
        /* we allow MyInt (isa Int) for int args */
        return atyp == type_Object && can_class_typecheck(stash)
            ? match_user_type(stash, aname, au8)
            : atyp <= type_Object;
    case type_Any:
    case type_Void:
        return 1;
    default:
        return 0;
    }
}

/*
=for apidoc s|OP*  |arg_check_type |NULLOK const PADNAME* pn|NN OP* o|NN GV *cvname

Check if the declared static type of the argument from pn can be
fullfilled by the dynamic type of the arg in OP* o (padsv, const,
any return type). If possible add a typecast to C<o> to fullfill it.
contravariant.

Signatures are new, hence much stricter, than return-types and assignments.
=cut
*/
static OP*
S_arg_check_type(pTHX_ const PADNAME* pn, OP* o, GV *cvname)
{
    const HV *type = pn ? PadnameTYPE(pn) : NULL;
    PERL_ARGS_ASSERT_ARG_CHECK_TYPE;
    if (UNLIKELY(VALIDTYPE(type))) {
        /* check type with arg (through aop),
           currently no entersub args and user types */
        char *usertype = NULL;
        int argu8 = 0;
        const char *name = typename(type);
        core_types_t argtype = op_typed_user(o, &usertype, &argu8);
        const char *argname = usertype ? usertype : core_type_name(argtype);
        DEBUG_k(Perl_deb(aTHX_ "ck argtype %s against arg %s\n",
                         name?name:"none", argname));
        o->op_typechecked = 1;
        if (argtype > type_none && argtype < type_Void
            && name && strNE(argname, name))
        {
            int castable = 0;
            /* check aggregate type: Array(int), Hash(str), ... */
            if (!PadnamePV(pn))
                ;
            else if ((argtype == type_Hash &&
                      PadnamePV(pn)[0] == '%' &&
                      IS_TYPE(o, PADHV))
                      ||
                     (argtype == type_Array &&
                      PadnamePV(pn)[0] == '@' &&
                      IS_TYPE(o, PADAV)))
            {
                PADNAME * const xpn = PAD_COMPNAME(o->op_targ);
                argtype = stash_to_coretype(PadnameTYPE(xpn));
            }

            if (!match_type(type, argtype, argname, argu8, &castable)) {
                if (!castable) {
                    bad_type_core(PadnamePV(pn), cvname, argtype,
                                  argname, argu8, name, HvNAMEUTF8(type));
                } else {
                    /* Currently castable is only: Scalar/Ref/Sub/Regexp => Bool/Numeric */
                    /* Maybe allow casting from Scalar/Numeric to Int => int()
                       and Scalar to Str => stringify() */
                    DEBUG_k(Perl_deb(aTHX_
                        "ck arg_check_type: need type cast from %s to %s\n",
                                     argname, name));
                    if (!OpRETTYPE(o))
                        OpRETTYPE_set(o, argtype);
                    switch (argtype) {
                    case type_Bool:
                        set_boolean(o);
                        break;
                    case type_Numeric:
                    case type_Scalar:
                        scalar(o);
                        break;
                    case type_int:
                    case type_Int:
                    case type_uint:
                    case type_UInt:
                        /* o = fold_constants(op_integerize(newUNOP
                           (OP_INT, 0, scalar(o)))); */
                        break;
                    case type_str:
                    case type_Str:
                        break;
                    default:
                        if (ckWARN(WARN_TYPES))
                            Perl_warner(aTHX_  packWARN(WARN_TYPES),
                              "Need type cast or dynamic inheritence from %s to %s",
                              argname, name);
                        break;
                    }
                }
            /*} else {*/
                /* mark argument as already typechecked, to avoid it at run-time.
                   but only when we start typechecking run-time. */
                /*o->op_typechecked = 1;*/
            }
        }
    }
    return o;
}

/*
=for apidoc s|bool  |is_types_strict

Check if the current lexical block has C<use types 'strict'> enabled.

=cut
*/
PERL_STATIC_INLINE bool
S_is_types_strict(pTHX)
{
    if (isLEXWARN_off)
        return FALSE;
    return ! specialWARN(PL_curcop->cop_warnings) &&
        isWARNf_on(((STRLEN *)PL_curcop->cop_warnings), unpackWARN1(WARN_TYPES));
}

/*
=for apidoc s|OP*  |_op_check_type |NULLOK const PADNAME* pn|NN OP* o|NN const char *opdesc

Check if the declared static type of the op (i.e. assignment) from the
lhs pn can be fullfilled by the dynamic type of the rhs in OP* o
(padsv, const, any return type). If possible add a typecast to o to
fullfill it.

Different to arg_check_type a type violation is not fatal, it only throws
a compile-time warning when no applicable type-conversion can be applied.
Return-types and assignments are passed through the type inferencer and 
applied to old constructs, not signatures, hence not so strict.

Contravariant: Enables you to use a more generic (less derived) type
than originally specified.

But note this special implicit perl case:
       scalar = list;       # (array|hash)
  <=>  scalar = shift list;
=cut
*/
static OP*
S__op_check_type(pTHX_ const PADNAME* pn, OP* o, const char *opdesc)
{
    const HV *type = pn ? PadnameTYPE(pn) : NULL;
    PERL_ARGS_ASSERT__OP_CHECK_TYPE;
    if (UNLIKELY(VALIDTYPE(type))) {
        /* check type of binop, same as for args */
        char *usertype = NULL;
        int argu8 = 0;
        const char *name = typename(type);
        core_types_t argtype = op_typed_user(o, &usertype, &argu8);
        const char *argname = usertype ? usertype : core_type_name(argtype);
        DEBUG_k(Perl_deb(aTHX_ "ck optype %s against %s\n",
                         name?name:"none",  argname));
        o->op_typechecked = 1;
        if (argtype > type_none && argtype < type_Void
            && name && strNE(argname, name))
        {
            int castable = 0;
            /* check aggregate type: Array(int), Hash(str), ... */
            if (!PadnamePV(pn)) /* Todo: lhs method rettype */
                ;
            /* %a = %b (list = list). no subs yet. */
            else if (  (argtype == type_Array &&
                        PadnamePV(pn)[0] == '@' &&
                        IS_TYPE(o, PADAV))
                    || (argtype == type_Hash &&
                        PadnamePV(pn)[0] == '%' &&
                        IS_TYPE(o, PADHV)) )
            {
                PADNAME * const xpn = PAD_COMPNAME(o->op_targ);
                argtype = stash_to_coretype(PadnameTYPE(xpn));
            }
            /* Check special case: scalar = list;
                                => scalar = shift list; #258.
               Missing:
                 lhs: lvalue subs. rhs: subs => list */
            else if ( (argtype == type_Array &&
                       PadnamePV(pn)[0] == '$' &&
                       IS_TYPE(o, RV2AV))
                   || (argtype == type_Hash &&
                       PadnamePV(pn)[0] == '$' &&
                       IS_TYPE(o, RV2HV)) )
            {
                /* it's an implicit shift */
                core_types_t innertype = op_typed_user(OpFIRST(o), &usertype, &argu8);
                if (usertype) {
                    argtype = type_Object;
                    argname = core_type_name(argtype);
                } else {
                    argtype = innertype;
                    argname = "Scalar";
                }
            }

            /* normal args: contravariant */
            if (!match_type(type, argtype, argname, argu8, &castable))
            {
                /* ignore "Inserting type cast str to Scalar" */
                if (!castable || S_is_types_strict(aTHX)) {
                    S_warn_type_core(aTHX_ PadnamePV(pn),
                                     opdesc, argtype, argname, name);
                } else {
                    /* Currently castable is only: Scalar/Ref/Sub/Regexp => Bool/Numeric */
                    /* Maybe allow casting from Scalar/Numeric to Int => int()
                       and Scalar to Str => stringify() */
                    DEBUG_k(Perl_deb(aTHX_
                        "ck _op_check_type: need type cast from %s to %s\n",
                                     argname, name));
                    if (!OpRETTYPE(o))
                        OpRETTYPE_set(o, argtype);
                    switch (argtype) {
                    case type_Bool:
                        set_boolean(o);
                        break;
                    case type_Numeric:
                    case type_Scalar:
                        /* Adding an int(op) in front makes not much sense here.
                           fold_constants or integerize would. */
                    case type_int:
                    case type_Int:
                    case type_uint:
                    case type_UInt:
                    case type_str:
                    case type_Str:
                        scalar(o);
                        break;
                    default:
                        if (ckWARN(WARN_TYPES))
                          Perl_warner(aTHX_  packWARN(WARN_TYPES),
                              "Need type cast or dynamic inheritence from %s to %s",
                              argname, name);
                        break;
                    }
                }
            }
        }
    }
    return o;
}

/* yet unused */
#if 0
/*
=for apidoc s|OP*  |ret_check_type |NULLOK const PADNAME* pn|NN OP* o|NN const char *opdesc

Check if the declared static type of the return type from the
lhs pn can be fullfilled by the dynamic type of the rhs in OP* o
(padsv, const, any return type). If possible add a typecast to o to
fullfill it.

Different to arg_check_type a type violation is not fatal, it only throws
a compile-time warning when no applicable type-conversion can be applied.
Return-types and assignments are passed through the type inferencer and 
applied to old constructs, not signatures, hence not so strict.

Covariant: Enables you to use a more derived type than originally specified.
=cut
*/
static OP*
S_ret_check_type(pTHX_ const PADNAME* pn, OP* o, const char *opdesc)
{
    const HV *type = pn ? PadnameTYPE(pn) : NULL;
    PERL_ARGS_ASSERT_RET_CHECK_TYPE;
    if (UNLIKELY(VALIDTYPE(type))) {
        /* check type of sub return value or binop */
        char *usertype = NULL;
        int argu8 = 0;
        const char *name = typename(type);
        core_types_t argtype = op_typed_user(o, &usertype, &argu8);
        const char *argname = usertype ? usertype : core_type_name(argtype);
        DEBUG_k(Perl_deb(aTHX_ "ck type %s against %s\n",
                         name?name:"none",  argname));
        o->op_typechecked = 1;
        if (argtype > type_none && argtype < type_Void
            && name && strNE(argname, name))
        {
            int castable = 0;
            HV* dstash = gv_stashpvn(argname, strlen(argname),
                                     argu8 ? SVf_UTF8 : 0);
            if (!dstash && !usertype) {
                /* auto-create a missing coretype, such
                   as for my Bla $a = 0; */
                dstash = find_in_coretypes(argname, strlen(argname));
            }
            /* check aggregate type: Array(int), Hash(str), ... */
            if (!PadnamePV(pn))
                ;
            else if ((argtype == type_Hash &&
                      PadnamePV(pn)[0] == '%' &&
                      IS_TYPE(o, PADHV))
                      ||
                     (argtype == type_Array &&
                      PadnamePV(pn)[0] == '@' &&
                      IS_TYPE(o, PADAV)))
            {
                PADNAME * const xpn = PAD_COMPNAME(o->op_targ);
                dstash = PadnameTYPE(xpn);
                argtype = stash_to_coretype(dstash);
            }

            /* reverse the args: covariant */
            if (!match_type(dstash, stash_to_coretype(type), name,
                            HvNAMEUTF8(type), &castable))
            {
                /* ignore "Inserting type cast str to Scalar" */
                if (!castable || S_is_types_strict(aTHX)) {
                    S_warn_type_core(aTHX_ PadnamePV(pn),
                                     opdesc, argtype, argname, name);
                } else {
                    /* Currently castable is only: Scalar/Ref/Sub/Regexp => Bool/Numeric */
                    /* Maybe allow casting from Scalar/Numeric to Int => int()
                       and Scalar to Str => stringify() */
                    DEBUG_k(Perl_deb(aTHX_
                        "ck ret_check_type: need type cast from %s to %s\n",
                                     argname, name));
                    if (!OpRETTYPE(o))
                        OpRETTYPE_set(o, argtype);
                    switch (argtype) {
                    case type_Bool:
                        set_boolean(o);
                        break;
                    case type_Numeric:
                    case type_Scalar:
                        /* Adding an int(op) in front makes not much sense here.
                           fold_constants or integerize would. */
                    case type_int:
                    case type_Int:
                    case type_uint:
                    case type_UInt:
                    case type_str:
                    case type_Str:
                        scalar(o);
                        break;
                    default:
                        if (ckWARN(WARN_TYPES))
                          Perl_warner(aTHX_  packWARN(WARN_TYPES),
                            "Need type cast or dynamic inheritence from %s to %s",
                            argname, name);
                        break;
                    }
                }
            }
        }
    }
    return o;
}
#endif

#ifdef SIG_DEBUG

/*
Returns the prototype string of a signature.

TODO: use _ when preferred.

use a better sig-based checker (see below).
protos cannot check types, insert type-casts, handle native types
and cannot report the name.

check if method and add default invocant?
*/

static char *
S_signature_proto(pTHX_ CV* cv, STRLEN *protolen)
{
    const UNOP_AUX* o = CvSIGOP(cv);
    UNOP_AUX_item *items = o->op_aux;
    SV *out = newSVpvn_flags("", 0, SVs_TEMP);
    UV actions = (++items)->uv;
    UV action;
    bool first = TRUE;
    DEBUG_k(Perl_deb(aTHX_ "sig_proto: numitems=%lu actions=0x%" UVxf "\n",
                     o->op_aux[-1].uv, items->uv));

    while (1) {
        switch (action = (actions & SIGNATURE_ACTION_MASK)) {
        case SIGNATURE_reload:
            actions = (++items)->uv;
            DEBUG_kv(Perl_deb(aTHX_
                "sig_proto: reload actions=0x%" UVxf " items=0x%" UVxf "\n",
                actions, items->uv));
            continue;
        case SIGNATURE_end:
            DEBUG_kv(Perl_deb(aTHX_
                "sig_proto: end actions=0x%" UVxf " items=0x%" UVxf "\n",
                actions, items->uv));
            goto finish;
        case SIGNATURE_padintro:
            items++;
            DEBUG_kv(Perl_deb(aTHX_
                "sig_proto: padintro actions=0x%" UVxf " items=0x%" UVxf "\n",
                actions, items->uv));
            break;
        case SIGNATURE_arg:
            /* Do NOT add a \ to a SCALAR! */
            sv_catpvs_nomg(out, "$");
            DEBUG_kv(Perl_deb(aTHX_
                "sig_proto: arg actions=0x%" UVxf " items=0x%" UVxf "\n",
                actions, items->uv));
            break;
        case SIGNATURE_arg_default_iv:
        case SIGNATURE_arg_default_const:
        case SIGNATURE_arg_default_padsv:
        case SIGNATURE_arg_default_gvsv:
            items++; /* fall thru */
            DEBUG_kv(Perl_deb(aTHX_
                "sig_proto: argdef actions=0x%" UVxf " items=0x%" UVxf "\n",
                actions, items->uv));
        case SIGNATURE_arg_default_op:
        case SIGNATURE_arg_default_none:
        case SIGNATURE_arg_default_undef:
        case SIGNATURE_arg_default_0:
        case SIGNATURE_arg_default_1:
            DEBUG_kv(Perl_deb(aTHX_
                "sig_proto: argdef-static actions=0x%" UVxf " items=0x%" UVxf "\n",
                actions, items->uv));
            if (first) {
                sv_catpvs_nomg(out, ";");
                first = FALSE;
            }
            sv_catpvs_nomg(out, "$");
            break;
        case SIGNATURE_array:
        case SIGNATURE_hash:
            DEBUG_kv(Perl_deb(aTHX_
                "sig_proto: arr/hash actions=0x%" UVxf " items=0x%" UVxf "\n",
                actions, items->uv));
            if (actions & SIGNATURE_FLAG_ref)
                sv_catpvs_nomg(out, "\\");
            sv_catpvn_nomg(out, action == SIGNATURE_array ? "@": "%", 1);
            break;
        default:
            DEBUG_kv(Perl_deb(aTHX_
                "sig_proto: default actions=0x%" UVxf " items=0x%" UVxf "\n",
                actions, items->uv));
            return NULL;
            /*sv_catpvs_nomg(out, "_");
              goto finish;*/
        }
        actions >>= SIGNATURE_SHIFT;
        /*DEBUG_kv(Perl_deb(aTHX_ "sig_proto: loop actions=0x%" UVxf " items=0x%" UVxf "\n",
              actions, items->uv));*/
    }
  finish:
    *protolen = SvCUR(out);
    if (SvCUR(out)) {
        DEBUG_kv(PerlIO_printf(Perl_debug_log,
                    "signature (%s) => proto \"%s\"\n",
                    SvPVX_const(signature_stringify((OP*)o, cv)), SvPVX_const(out)));
        return SvPVX(out);
    } else {
        return NULL;
    }
}

#endif

/*
=for apidoc Am|OP *|ck_entersub_args_list|OP *entersubop

Performs the default fixup of the arguments part of an C<entersub>
op tree.  This consists of applying list context to each of the
argument ops.  This is the standard treatment used on a call marked
with C<&>, or a method call, or a call through a subroutine reference,
or any other call where the callee can't be identified at compile time,
or a call where the callee has no prototype.

=cut
*/

OP *
Perl_ck_entersub_args_list(pTHX_ OP *entersubop)
{
    OP *aop;

    PERL_ARGS_ASSERT_CK_ENTERSUB_ARGS_LIST;

    aop = OpFIRST(entersubop);
    if (!OpHAS_SIBLING(aop))
	aop = OpFIRST(aop);
    for (aop = OpSIBLING(aop); OpHAS_SIBLING(aop); aop = OpSIBLING(aop)) {
        /* skip the extra attributes->import() call implicitly added in
         * something like foo(my $x : bar) */
        if (IS_TYPE(aop, ENTERSUB) && OpWANT_VOID(aop))
            continue;
        list(aop);
        op_lvalue(aop, OP_ENTERSUB);
    }
    return entersubop;
}

/*
=for apidoc Am|OP *|ck_entersub_args_signature|OP *entersubop|GV *namegv|CV *protosv

Performs the fixup and compile-time checks of the arguments part of an
C<entersub> op tree based on a subroutine signature.  This makes
various modifications to the argument ops, from applying context up to
inserting C<refgen> ops, checking the number and types of arguments,
and adding run-time type casts as directed by the signature.  This is
the standard treatment used on a signatured non-method call, not
marked with C<&>, where the callee can be identified at compile time
and has a signature.

If the argument ops, the args, disagree with the signature, for
example by having an unacceptable number of arguments or a wrong
argument type, a valid op tree is returned anyway.  The error is
reflected in the parser state, normally resulting in a single
exception at the top level of parsing which covers all the compilation
errors that occurred.  In the error message, the callee is referred to
by the name defined by the I<namegv> parameter.

=cut
*/

static const char* const svshorttypenames[SVt_LAST] = {
    "UNDEF",
    "IV",
    "NV",
    "PV",
    "INVLST",
    "PVIV",
    "PVNV",
    "PVMG",
    "REGEXP",
    "GV",
    "PVLV",
    "AV",
    "HV",
    "CV",
    "FM",
    "IO"
};

OP *
Perl_ck_entersub_args_signature(pTHX_ OP *entersubop, GV *namegv, CV *cv)
{
    OP *aop, *cvop;
    UNOP_AUX_item *items;
    const UNOP_AUX* o = CvSIGOP(cv);
    HV* type;
    PADNAMELIST *namepad = PadlistNAMES(CvPADLIST(cv));
    UV actions, params, mand_params, opt_params;
#ifdef DEBUGGING
    UV varcount;
#endif
    PADOFFSET pad_ix = 0;
    I32 arg = 0;
    bool optional = FALSE;
    bool slurpy = FALSE;
#define PAD_NAME(pad_ix) padnamelist_fetch(namepad, pad_ix)
    PERL_ARGS_ASSERT_CK_ENTERSUB_ARGS_SIGNATURE;

    assert(SvTYPE(cv) == SVt_PVCV);
    assert(CvHASSIG(cv));
    assert(o);

#ifdef SIG_DEBUG
    DEBUG_kv((void)S_signature_proto(aTHX_ cv, &actions));
#endif
    
    items   = o->op_aux;
    params  = items->uv;
    mand_params = params >> 16;
    opt_params  = params & ((1<<15)-1);
    actions = (++items)->uv;
    DEBUG_k(Perl_deb(aTHX_
        "ck_sig: %" SVf " arity=%d/%d actions=0x%" UVxf " items=%u\n",
        SVfARG(cv_name((CV *)namegv, NULL, CV_NAME_NOMAIN)),
        (int)mand_params, (int)opt_params, actions, (unsigned)o->op_aux[-1].uv));

    aop = OpFIRST(entersubop);
    if (!OpHAS_SIBLING(aop))
	aop = OpFIRST(aop);
    aop = OpSIBLING(aop);
    for (cvop = aop; OpHAS_SIBLING(cvop); cvop = OpSIBLING(cvop)) ;

    while (aop != cvop) {
	OP* o3 = aop;
        UV action = actions & SIGNATURE_ACTION_MASK;
        switch (action) {
        case SIGNATURE_reload:
            actions = (++items)->uv;
            DEBUG_kv(Perl_deb(aTHX_
                "ck_sig: reload action=%d items=0x%" UVxf " with %d %s op arg\n",
                (int)action, items->uv, (int)arg, OP_NAME(o3)));
            continue; /* no shift, no arg advance */
        case SIGNATURE_end:
            if (!optional || (!slurpy && ((UV)arg >= mand_params + opt_params))) {
                /* args but not in sig */
                SV * const namesv = cv_name((CV *)namegv, NULL, CV_NAME_NOMAIN);
                SV* tmpbuf = newSVpvn_flags(OP_DESC(entersubop),
                                            strlen(OP_DESC(entersubop)),
                                            SVs_TEMP|SvUTF8(namesv));
                sv_catpvs(tmpbuf, " ");
                sv_catsv(tmpbuf, namesv);
                Perl_sv_catpvf(aTHX_ tmpbuf, " exceeding max %d args", (int)arg);
                DEBUG_kv(Perl_deb(aTHX_
                    "ck_sig: end action=%d pad_ix=%d items=0x%" UVxf " with %d %s op arg\n",
                    (int)action, (int)pad_ix, items->uv, (int)arg, OP_NAME(o3)));
                return too_many_arguments_pv(entersubop, SvPVX_const(tmpbuf),
                                             SvUTF8(namesv));
            }
            return entersubop;
        case SIGNATURE_padintro:
            pad_ix = (++items)->uv >> OPpPADRANGE_COUNTSHIFT;
#ifdef DEBUGGING
            if (UNLIKELY(items->iv == -1)) /* [cperl #164] */
                Perl_croak(aTHX_
                      "panic: Missing padintro item in signature of %" SVf,
                      SVfARG(cv_name((CV *)namegv, NULL, CV_NAME_NOMAIN)));
            varcount = items->uv & OPpPADRANGE_COUNTMASK;
            DEBUG_kv(Perl_deb(aTHX_
                "ck_sig: padintro action=%d pad_ix=%d varcount=%d %s "
                "items=0x%" UVxf " with %d %s op arg\n",
                (int)action, (int)pad_ix, (int)varcount,
                PAD_NAME(pad_ix) ? PadnamePV(PAD_NAME(pad_ix)) : "",
                items->uv, (int)arg, OP_NAME(o3)));
#endif
            actions >>= SIGNATURE_SHIFT;
            continue; /* no arg advance */
        case SIGNATURE_arg:
            if (UNLIKELY(actions & SIGNATURE_FLAG_ref)) {
                arg++;
                DEBUG_kv(Perl_deb(aTHX_
                    "ck_sig: arg ref action=%d pad_ix=%d items=0x%" UVxf " with %d %s op arg\n",
                    (int)action, (int)pad_ix, items->uv, (int)arg, OP_NAME(o3)));
                /* \$ accepts any scalar lvalue */
                if (!op_lvalue_flags(scalar(o3), OP_READ, OP_LVALUE_NO_CROAK)) {
                    type = PAD_NAME(pad_ix) ? PadnameTYPE(PAD_NAME(pad_ix)) : NULL;
                    bad_type_gv(arg, namegv, o3, VALIDTYPE(type) ? typename(type) : "scalar");
                }
                pad_ix++;
                scalar(aop);
                break;
            } /* fall through */
            items--;
        case SIGNATURE_arg_default_iv:
        case SIGNATURE_arg_default_const:
        case SIGNATURE_arg_default_padsv:
        case SIGNATURE_arg_default_gvsv:
            items++; /* the default sv/gv */
        case SIGNATURE_arg_default_op:
        case SIGNATURE_arg_default_none:
        case SIGNATURE_arg_default_undef:
        case SIGNATURE_arg_default_0:
        case SIGNATURE_arg_default_1:
            arg++;
            if (UNLIKELY(actions & SIGNATURE_FLAG_skip)) {
                DEBUG_kv(Perl_deb(aTHX_
                    "ck_sig: skip action=%d pad_ix=%d with %d %s op arg items=0x%x\n",
                    (int)action, (int)pad_ix, (int)arg, OP_NAME(o3), (unsigned)items->uv));
                scalar(aop);
                break;
            }
            if (UNLIKELY(action != SIGNATURE_arg)) {
                DEBUG_kv(Perl_deb(aTHX_
                    "ck_sig: default action=%d (default ignored)\n", (int)action));
                optional = TRUE;
                if (actions & SIGNATURE_FLAG_ref) {
                    yyerror(Perl_form(aTHX_ "Reference parameter cannot take default value"));
                    return entersubop;
                }
            }
#ifdef DEBUGGING
            else {
                DEBUG_kv(Perl_deb(aTHX_
                    "ck_sig: arg action=%d pad_ix=%d items=0x%" UVxf " with %d %s op arg\n",
                    (int)action, (int)pad_ix, items->uv, (int)arg, OP_NAME(o3)));
            }
#endif
            assert(pad_ix);
            /* TODO: o3 needs to return a scalar */
            /* TODO: o3 can be modified, with added type cast, similar to scalar */
            aop = S_arg_check_type(aTHX_ PAD_NAME(pad_ix), o3, namegv);
            pad_ix++;
            scalar(aop);
            break;
        case SIGNATURE_array:
        case SIGNATURE_hash:
            aop = S_arg_check_type(aTHX_ PAD_NAME(pad_ix), o3, namegv);
            arg++;
            if (actions & SIGNATURE_FLAG_ref) {
                const PADNAME* pn = PAD_NAME(pad_ix);
                /* o3 needs to be a aref or href. we can typecheck a CONST,
                   but not much else */
                if (IS_CONST_OP(o3)) {
                    const SV* sv = cSVOPx_sv(o3);
                    const svtype t = SvTYPE(sv);
                    if (!(t == SVt_NULL || t == SVt_IV))
                        bad_type_core(PadnamePV(pn), namegv, type_Object, svshorttypenames[t], 0,
                                      action == SIGNATURE_hash ? "HASH reference"
                                      : "ARRAY reference", 0);
                    if (SvROK(sv) && SvTYPE(SvRV_const(sv)) !=
                                       (action == SIGNATURE_hash ? SVt_PVHV : SVt_PVAV))
                        bad_type_core(PadnamePV(pn), namegv, type_Object, svshorttypenames[t], 0,
                                      action == SIGNATURE_hash ? "HASH reference"
                                      : "ARRAY reference", 0);
                } else if (IS_TYPE(o3, ANONHASH) && action == SIGNATURE_array) {
                    bad_type_core(PadnamePV(pn), namegv, type_Object, "HASH reference", 0,
                                  "ARRAY reference", 0);
                } else if (IS_TYPE(o3, ANONLIST) && action == SIGNATURE_hash) {
                    bad_type_core(PadnamePV(pn), namegv, type_Object, "ARRAY reference", 0,
                                  "HASH reference", 0);
                }
                scalar(aop);
                DEBUG_kv(Perl_deb(aTHX_ "ck_sig: ref action=%d pad_ix=%d items=0x%" UVxf " with %d %s op arg\n",
                                  (int)action, (int)pad_ix, items->uv, (int)arg, OP_NAME(o3)));
            } else {
                list(aop);
                optional = TRUE;
                slurpy = TRUE;
                DEBUG_kv(Perl_deb(aTHX_ "ck_sig: slurpy action=%d pad_ix=%d items=0x%" UVxf " with %d %s op arg\n",
                                  (int)action, (int)pad_ix, items->uv, (int)arg, OP_NAME(o3)));
            }
            pad_ix++;
            break;
        }
        actions >>= SIGNATURE_SHIFT;

        op_lvalue(aop, OP_ENTERSUB);
        aop = OpSIBLING(aop);
    }

    if (!optional && aop == cvop) {
        UV action = actions & SIGNATURE_ACTION_MASK;
        /* We ran out of args, but maybe the next action is the first optional */
        if (action == SIGNATURE_padintro) {
            pad_ix = (++items)->uv >> OPpPADRANGE_COUNTSHIFT;
            actions >>= SIGNATURE_SHIFT;
            action = actions & SIGNATURE_ACTION_MASK;
        }
        if (action != SIGNATURE_arg) /* mandatory arg.
                                        there are no 2 consecutive padintros */
            return entersubop;
        else {
            SV * const namesv = cv_name((CV *)namegv, NULL, CV_NAME_NOMAIN);
            SV* tmpbuf = newSVpvn_flags(OP_DESC(entersubop), strlen(OP_DESC(entersubop)),
                                    SVs_TEMP|SvUTF8(namesv));
            sv_catpvs(tmpbuf, " ");
            sv_catsv(tmpbuf, namesv);
            /* with no args provided we haven't seen padintro yet */
            if (pad_ix > 0 && PAD_NAME(pad_ix)) {
                /* diag_listed_as: Not enough arguments for %s */
                yyerror_pv(Perl_form(aTHX_ "Not enough arguments for %s. Missing %s",
                                     SvPVX_const(tmpbuf), PadnamePV(PAD_NAME(pad_ix))),
                           SvUTF8(namesv));
            } else {
                return too_few_arguments_pv(entersubop, SvPVX_const(tmpbuf), SvUTF8(namesv));
            }
        }
    }
#undef PAD_NAME

    return entersubop;
}


/* temp. helper to convert a SIGNATURE op into old-style ops, until
   -d is fixed with tailcalls. [cperl #167]
   But if the last op in the body is a goto, don't consume @_.
   Just pass it on. sig2sig/sig2pp do work fine.

   sub func ($arg1 = default) { ...
   =>
   sub func { my $arg1 = shift || default; ...
*/
static void
S_debug_undo_signature(pTHX_ CV *cv)
{
    const UNOP_AUX* sig = CvSIGOP(cv);
    UNOP_AUX_item *items = sig->op_aux;
    OP *o = newNULLLIST();
    OP* def = NULL;
    OP* lroot = OpFIRST(CvROOT(cv)); /* the lineseq list, not the real leavesub root */
    OP* last = OpLAST(lroot);
    UV actions = (++items)->uv;
    UV action;
    PADOFFSET pad_ix = 0;

    DEBUG_k(Perl_deb(aTHX_ "sig_proto: numitems=%" UVuf " actions=0x%" UVxf "\n",
                     sig->op_aux[-1].uv, items->uv));
    if (IS_TYPE(last, GOTO)) /* don't consume @_ */
        return;

    while (1) {
        switch (action = (actions & SIGNATURE_ACTION_MASK)) {
        case SIGNATURE_reload:
            actions = (++items)->uv;
            continue;
        case SIGNATURE_end:
            goto finish;
        case SIGNATURE_padintro:
            pad_ix = (++items)->uv >> OPpPADRANGE_COUNTSHIFT;
            break;
        case SIGNATURE_arg:
            break;
        case SIGNATURE_arg_default_iv:
            def = newSVOP(OP_CONST, 0, newSViv(items++->iv));
            break;
        case SIGNATURE_arg_default_const:
            def = newSVOP(OP_CONST, 0, UNOP_AUX_item_sv(items++));
            break;
        case SIGNATURE_arg_default_padsv:
            def = newSVOP(OP_CONST, 0, PAD_SVl(items++->pad_offset));
            break;
        case SIGNATURE_arg_default_gvsv:
            def = newSVOP(OP_CONST, 0, GvSVn((GV*)UNOP_AUX_item_sv(items++)));
            break;
        case SIGNATURE_arg_default_op:
            def = (OP*)UNOP_AUX_item_sv(items++);
        case SIGNATURE_arg_default_none:
        case SIGNATURE_arg_default_undef:
            /* shift is enough */
            /*def = newSVOP(OP_CONST, 0, UNDEF);*/
            break;
        case SIGNATURE_arg_default_0:
            def = newSVOP(OP_CONST, 0, newSViv(0));
            break;
        case SIGNATURE_arg_default_1:
            def = newSVOP(OP_CONST, 0, newSViv(1));
            break;
        case SIGNATURE_array:
        case SIGNATURE_hash:
            break;
        default:
            goto finish;
        }
        /* XXX TODO ref */
        if (action >= SIGNATURE_arg && action < SIGNATURE_array) {
            OP *right;
            OP * const left = scalar(newOP(OP_PADSV,
                                (OPf_REF|OPf_MOD|OPf_SPECIAL)|(OPpLVAL_INTRO<<8)));
            left->op_targ = pad_ix;
            CvUNIQUE_off(PL_compcv); /* allow shift without default kid */
            if (def) {
                right = scalar(newUNOP(OP_NULL, 1>>8,
                               newLOGOP(OP_OR, 0, newOP(OP_SHIFT, OPf_SPECIAL), def)));
                def = NULL;
            } else {
                right = newOP(OP_SHIFT, OPf_SPECIAL);
            }
            o = op_append_elem(OP_LINESEQ, o,
                               newBINOP(OP_SASSIGN, OPf_STACKED|OPf_WANT_VOID,
                                        right, left));
        }
        else if (action >= SIGNATURE_array) {
            int base = 1; /* XXX */
            int intro = 1;
            int count = 1;
            OP *left = newOP(action == SIGNATURE_array ? OP_PADAV : OP_PADHV,
                             (OPf_REF|OPf_MOD|OPf_SPECIAL)|(OPpLVAL_INTRO<<8));
            OP *right = newOP(OP_PADRANGE, OPf_SPECIAL);
            left->op_targ = pad_ix;
            right->op_targ = base;
            right->op_private = (OPpLVAL_INTRO | intro | count);
            right = newLISTOP(OP_LIST, 0, right,
                      newUNOP(action == SIGNATURE_array ? OP_RV2AV : OP_RV2HV, 0,
                              newGVOP(OP_GV, 0, PL_defgv)));
            o = op_append_elem(OP_LINESEQ, o,
                               newBINOP(OP_AASSIGN, OPf_STACKED|OPf_WANT_VOID,
                                        right, force_list(left, 1)));
        }
        actions >>= SIGNATURE_SHIFT;
    }
 finish:
    {
        OP *stub = OpFIRST(o);
        OP *bodystart = OpNEXT(OpNEXT(sig)); /* dbstate -> body */
        op_sibling_splice(o, NULL, 1, NULL); /* delete the first stub */
        /* replace the sig with the list of assignments */
        op_sibling_splice(lroot, NULL, 1, OpFIRST(o));
        OpNEXT(last) = NULL;
        OpLAST(o) = last;
        /* we intentionally leak the 2nd o lineseq. That's done everywhere */
        o = CvSTART(cv) = LINKLIST(o);
        OpNEXT(OpFIRST(lroot)) = OpNEXT(sig); /* fixup sassign -> body */
        OpNEXT(OpNEXT(sig)) = bodystart;      /* restore dbstate -> body link */
        OpNEXT(last) = CvROOT(cv); /* fixup link back to new lineseq head */
        op_free(stub);
        op_free((OP*)sig);
        CvHASSIG_off(cv);
    }
    return;
}

/*
=for apidoc Am|OP *|ck_entersub_args_proto|OP *entersubop|GV *namegv|SV *protosv

Performs the fixup of the arguments part of an C<entersub> op tree
based on a subroutine prototype.  This makes various modifications to
the argument ops, from applying context up to inserting C<refgen> ops,
and checking the number and syntactic types of arguments, as directed by
the prototype.  This is the standard treatment used on a subroutine call,
not marked with C<&>, where the callee can be identified at compile time
and has a prototype.

I<protosv> supplies the subroutine prototype or signature to be
applied to the call, or indicates that there is no prototype.  It may
be a normal scalar, in which case if it is defined then the string
value will be used as a prototype, and if it is undefined then there
is no prototype.  Alternatively, for convenience, it may be a
subroutine object (a C<CV*> that has been cast to C<SV*>), of which
the prototype or signature will be used if it has one.  The prototype
(or lack thereof) supplied, in whichever form, does not need to match
the actual callee referenced by the op tree.
If the protosv has no prototype but a signature, the prototype is automatically
created from the signature.

If the argument ops disagree with the prototype, for example by having
an unacceptable number of arguments or a wrong argument type, a valid
op tree is returned anyway.  The error is reflected in the parser
state, normally resulting in a single exception at the top level of
parsing which covers all the compilation errors that occurred.  In the
error message, the callee is referred to by the name defined by the
I<namegv> parameter.

=cut
*/

OP *
Perl_ck_entersub_args_proto(pTHX_ OP *entersubop, GV *namegv, SV *protosv)
{
    STRLEN proto_len;
    const char *proto, *proto_end;
    OP *aop, *prev, *cvop, *parent;
    int optional = 0;
    I32 arg = 0;
    I32 contextclass = 0;
    const char *e = NULL;
    PERL_ARGS_ASSERT_CK_ENTERSUB_ARGS_PROTO;
    if (SvTYPE(protosv) == SVt_PVCV ? (!SvPOK(protosv) && !CvHASSIG((CV*)protosv))
                                    : !SvOK(protosv))
	Perl_croak(aTHX_ "panic: ck_entersub_args_proto CV with no proto, "
		   "flags=%lx", (unsigned long) SvFLAGS(protosv));
    if (SvTYPE(protosv) == SVt_PVCV)
        proto = CvPROTO(protosv), proto_len = CvPROTOLEN(protosv);
    else
        proto = SvPV(protosv, proto_len);
    if (!proto)
        return entersubop;
    proto = strip_spaces(proto, &proto_len);
    proto_end = proto + proto_len;
    parent = entersubop;
    aop = OpFIRST(entersubop);
    if (!OpHAS_SIBLING(aop)) {
        parent = aop;
	aop = OpFIRST(aop);
    }
    prev = aop;
    aop = OpSIBLING(aop);
    for (cvop = aop; OpHAS_SIBLING(cvop); cvop = OpSIBLING(cvop)) ;
    while (aop != cvop) {
	OP* o3 = aop;

	if (proto >= proto_end) {
            /* we really want the sub name here, and maybe decide between
               subroutine, method and multi */
            SV * const namesv = cv_name((CV *)namegv, NULL, CV_NAME_NOMAIN);
            SV* tmpbuf = newSVpvn_flags(OP_DESC(entersubop),
                                        strlen(OP_DESC(entersubop)),
                                        SVs_TEMP|SvUTF8(namesv));
            sv_catpvs(tmpbuf, " ");
            sv_catsv(tmpbuf, namesv);
            return too_many_arguments_pv(entersubop, SvPVX_const(tmpbuf),
                                         SvUTF8(namesv));
	}

	switch (*proto) {
	    case ';':
		optional = 1;
		proto++;
		continue;
	    case '_':
		/* _ must be at the end */
		if (proto[1] && !strchr(";@%", proto[1]))
		    goto oops;
                /* FALLTHROUGH */
	    case '$':
		proto++;
		arg++;
		scalar(aop);
		break;
	    case '%':
	    case '@':
		list(aop);
		arg++;
		break;
	    case '&':
		proto++;
		arg++;
		if (ISNT_TYPE(o3, UNDEF)
                && (ISNT_TYPE(o3, SREFGEN)
                    || (ISNT_TYPE(OpFIRST(OpFIRST(o3)), ANONCODE)
                     && ISNT_TYPE(OpFIRST(OpFIRST(o3)), RV2CV))))
		    bad_type_gv(arg, namegv, o3,
			    arg == 1 ? "block or sub {}" : "sub {}");
		break;
	    case '*':
		/* '*' allows any scalar type, including bareword */
		proto++;
		arg++;
		if (IS_TYPE(o3, RV2GV))
		    goto wrapref;	/* autoconvert GLOB -> GLOBref */
		else if (IS_CONST_OP(o3))
		    o3->op_private &= ~OPpCONST_STRICT;
		scalar(aop);
		break;
	    case '+':
		proto++;
		arg++;
		if (IS_TYPE(o3, RV2AV) ||
		    IS_TYPE(o3, PADAV) ||
		    IS_TYPE(o3, RV2HV) ||
		    IS_TYPE(o3, PADHV)
		) {
		    goto wrapref;
		}
		scalar(aop);
		break;
	    case '[': case ']':
		goto oops;

	    case '\\':
		proto++;
		arg++;
	    again:
		switch (*proto++) {
		    case '[':
			if (contextclass++ == 0) {
			    e = (char *) memchr(proto, ']', proto_end - proto);
			    if (!e || e == proto)
				goto oops;
			}
			else
			    goto oops;
			goto again;

		    case ']':
			if (contextclass) {
			    const char *p = proto;
			    const char *const end = proto;
			    contextclass = 0;
			    while (*--p != '[')
				/* \[$] accepts any scalar lvalue */
				if (*p == '$'
				 && op_lvalue_flags(
				     scalar(o3),
				     OP_READ, /* not entersub */
				     OP_LVALUE_NO_CROAK
				    )) goto wrapref;
			    bad_type_gv(arg, namegv, o3,
				    Perl_form(aTHX_ "one of %.*s",(int)(end - p), p));
			} else
			    goto oops;
			break;
		    case '*':
			if (IS_TYPE(o3, RV2GV))
			    goto wrapref;
			if (!contextclass)
			    bad_type_gv(arg, namegv, o3, "symbol");
			break;
		    case '&':
			if (IS_SUB_OP(o3) && !OpSTACKED(o3))
			    goto wrapref;
			if (!contextclass)
			    bad_type_gv(arg, namegv, o3, "subroutine");
			break;
		    case '$':
			if (IS_TYPE(o3, RV2SV) ||
			    IS_TYPE(o3, PADSV) ||
			    IS_TYPE(o3, HELEM) ||
			    IS_TYPE(o3, AELEM))
			    goto wrapref;
			if (!contextclass) {
			    /* \$ accepts any scalar lvalue */
			    if (op_lvalue_flags(scalar(o3),
                                                OP_READ,  /* not entersub */
                                                OP_LVALUE_NO_CROAK)) goto wrapref;
			    bad_type_gv(arg, namegv, o3, "scalar");
			}
			break;
		    case '@':
			if (IS_TYPE(o3, RV2AV) ||
                            IS_TYPE(o3, PADAV))
			{
			    o3->op_flags &=~ OPf_PARENS;
			    goto wrapref;
			}
			if (!contextclass)
			    bad_type_gv(arg, namegv, o3, "array");
			break;
		    case '%':
			if (IS_TYPE(o3, RV2HV) ||
                            IS_TYPE(o3, PADHV))
			{
			    o3->op_flags &=~ OPf_PARENS;
			    goto wrapref;
			}
			if (!contextclass)
			    bad_type_gv(arg, namegv, o3, "hash");
			break;
		    wrapref:
                        aop = S_op_sibling_newUNOP(aTHX_ parent, prev,
                                                   OP_REFGEN, 0);
			if (contextclass && e) {
			    proto = e + 1;
			    contextclass = 0;
			}
			break;
		    default: goto oops;
		}
		if (contextclass)
		    goto again;
		break;
	    case ' ':
		proto++;
		continue;
	    default:
	    oops: {
		Perl_croak(aTHX_ "Malformed prototype for %" SVf ": %" SVf,
				  SVfARG(cv_name((CV *)namegv, NULL, CV_NAME_NOMAIN)),
				  SVfARG(protosv));
            }
	}

	op_lvalue(aop, OP_ENTERSUB);
	prev = aop;
	aop = OpSIBLING(aop);
    }
    if (aop == cvop && *proto == '_') {
	/* generate an access to $_ */
        op_sibling_splice(parent, prev, 0, newDEFSVOP());
    }
    if (!optional && proto_end > proto &&
	(*proto != '@' && *proto != '%' && *proto != ';' && *proto != '_'))
    {
	SV * const namesv = cv_name((CV *)namegv, NULL, CV_NAME_NOMAIN);
        SV* tmpbuf = newSVpvn_flags(OP_DESC(entersubop), strlen(OP_DESC(entersubop)),
                                    SVs_TEMP|SvUTF8(namesv));
        sv_catpvs(tmpbuf, " ");
        sv_catsv(tmpbuf, namesv);
        return too_few_arguments_pv(entersubop, SvPVX_const(tmpbuf), SvUTF8(namesv));
    }
    return entersubop;
}

/*
=for apidoc Am|OP *|ck_entersub_args_proto_or_list|OP *entersubop|GV *namegv|SV *protosv

Performs the fixup of the arguments part of an C<entersub> op tree
either based on a subroutine signature, prototype or using default
list-context processing.  This is the standard treatment used on a
subroutine call, not marked with C<&>, where the callee can be
identified at compile time.

Note: Methods or computed functions need to do this run-time.

See L<perlapi/ck_entersub_args_signature> for the handling with a
defined C<protosv> signature, and L<perlapi/ck_entersub_args_proto>
with an old-style prototype.

=cut
*/

OP *
Perl_ck_entersub_args_proto_or_list(pTHX_ OP *entersubop,
	GV *namegv, SV *protosv)
{
    PERL_ARGS_ASSERT_CK_ENTERSUB_ARGS_PROTO_OR_LIST;
    /* Which types do arrive here? 99% CV */
    DEBUG_kv(Perl_deb(aTHX_ "ck_entersub %s %" SVf "\n",
                     SvTYPE(protosv) == SVt_PVCV
                       ? "CV" : SvTYPE(protosv) == SVt_PVGV
                       ? "GV" : "RV",
                     SVfARG(cv_name((CV*)protosv, NULL, CV_NAME_NOMAIN))));
    if (LIKELY(SvTYPE(protosv) == SVt_PVCV)) {
        CV* cv = (CV*)protosv;
        if (UNLIKELY(HvCLASS(SvTYPE(namegv) == SVt_PVGV   ? GvSTASH(namegv)
                           : SvTYPE(namegv) == SVt_PVCV && CvSTASH(namegv)
                                                          ? CvSTASH(namegv)
                           : PL_defstash
                     ) && CvMETHOD(cv)))
            Perl_croak(aTHX_ "Invalid subroutine call on class method %" SVf,
                       SVfARG(cv_name(cv,NULL,CV_NAME_NOMAIN)));
        if (CvHASSIG(cv) && CvSIGOP(cv)) {
            if (UNLIKELY(PERLDB_SUB)) {
                (void)ck_entersub_args_signature(entersubop, namegv, cv);
                S_debug_undo_signature(aTHX_ cv);
                return entersubop;
            }
            return ck_entersub_args_signature(entersubop, namegv, cv);
        }
        else {
            /* Try XS call beforehand. Most XS calls are via CV not GV.
               GvXSCV is safe, because CvCONST and CvEXTERN are never set via newXS()
               which sets this flag. */
            if (UNLIKELY(CvISXSUB(cv) && CvROOT(cv) &&
                         GvXSCV(CvGV(cv)) && !PL_perldb))
            {
                DEBUG_k(Perl_deb(aTHX_ "entersub -> xs %" SVf "\n",
                        SVfARG(cv_name(cv, NULL, CV_NAME_NOMAIN))));
                OpTYPE_set(entersubop, OP_ENTERXSSUB);
            }
            if (SvPOK(protosv))
                return ck_entersub_args_proto(entersubop, namegv, protosv);
        }
    }
    else if (SvOK(protosv))
        return ck_entersub_args_proto(entersubop, namegv, protosv);

    return ck_entersub_args_list(entersubop);
}

OP *
Perl_ck_entersub_args_core(pTHX_ OP *entersubop, GV *namegv, SV *protosv)
{
    OP *aop = OpFIRST(entersubop);
    IV cvflags = SvIVX(protosv);
    int opnum = cvflags & 0xffff;

    PERL_ARGS_ASSERT_CK_ENTERSUB_ARGS_CORE;

    if (!opnum) {
	OP *cvop;
	if (!OpHAS_SIBLING(aop))
	    aop = OpFIRST(aop);
	aop = OpSIBLING(aop);
	for (cvop = aop; OpSIBLING(cvop); cvop = OpSIBLING(cvop)) ;
	if (aop != cvop) {
	    SV *namesv = cv_name((CV *)namegv, NULL, CV_NAME_NOTQUAL);
	    yyerror_pv(Perl_form(aTHX_ "Too many arguments for %" SVf,
		SVfARG(namesv)), SvUTF8(namesv));
	}
	
	op_free(entersubop);
	switch(cvflags >> 16) {
	case 'F': return newSVOP(OP_CONST, 0,
                                 newSVpv(CopFILE(PL_curcop),0));
	case 'L': return newSVOP(
	                   OP_CONST, 0,
                           Perl_newSVpvf(aTHX_
	                     "%" IVdf, (IV)CopLINE(PL_curcop)
	                   )
	                 );
	case 'P': return newSVOP(OP_CONST, 0,
	                           (PL_curstash
	                             ? newSVhek(HvNAME_HEK(PL_curstash))
	                             : UNDEF
	                           )
	                        );
	}
	NOT_REACHED; /* NOTREACHED */
    }
    else {
	OP *prev, *cvop, *first, *parent;
	U32 flags = 0;

        parent = entersubop;
        if (!OpHAS_SIBLING(aop)) {
            parent = aop;
	    aop = OpFIRST(aop);
        }
	
	first = prev = aop;
	aop = OpSIBLING(aop);
        /* find last sibling */
	for (cvop = aop;
	     OpHAS_SIBLING(cvop);
	     prev = cvop, cvop = OpSIBLING(cvop))
	    ;
        if (!(cvop->op_private & OPpENTERSUB_NOPAREN)
            /* Usually, OPf_SPECIAL on an op with no args means that it had
             * parens, but these have their own meaning for that flag: */
            && opnum != OP_VALUES && opnum != OP_KEYS && opnum != OP_EACH
            && opnum != OP_DELETE && opnum != OP_EXISTS)
                flags |= OPf_SPECIAL;
        /* excise cvop from end of sibling chain */
        op_sibling_splice(parent, prev, 1, NULL);
	op_free(cvop);
	if (aop == cvop) aop = NULL;

        /* detach remaining siblings from the first sibling, then
         * dispose of original optree */

        if (aop)
            op_sibling_splice(parent, first, -1, NULL);
	op_free(entersubop);

	if (cvflags == (OP_ENTEREVAL | (1<<16)))
	    flags |= OPpEVAL_BYTES <<8;
	
	switch (PL_opargs[opnum] & OA_CLASS_MASK) {
	case OA_UNOP:
	case OA_BASEOP_OR_UNOP:
	case OA_FILESTATOP:
	    return aop ? newUNOP(opnum,flags,aop) : newOP(opnum,flags);
	case OA_BASEOP:
	    if (aop) {
		SV *namesv = cv_name((CV *)namegv, NULL, CV_NAME_NOTQUAL);
		yyerror_pv(Perl_form(aTHX_ "Too many arguments for %" SVf,
		    SVfARG(namesv)), SvUTF8(namesv));
		op_free(aop);
	    }
	    return opnum == OP_RUNCV
		? newPVOP(OP_RUNCV,0,NULL)
		: newOP(opnum,0);
	default:
	    return op_convert_list(opnum,0,aop);
	}
    }
    NOT_REACHED; /* NOTREACHED */
    return entersubop;
}

/*
=for apidoc Am|void|cv_get_call_checker_flags|CV *cv|U32 gflags|Perl_call_checker *ckfun_p|SV **ckobj_p|U32 *ckflags_p

Retrieves the function that will be used to fix up a call to the C<cv>
to override the default signature handling or suppress evaluation of the
args (i.e. macros).
Specifically, the function is applied to an C<entersub> op tree for a
subroutine call, not marked with C<&>, where the callee can be identified
at compile time as C<cv>.

The C-level function pointer is returned in C<*ckfun_p>, an SV argument
for it is returned in C<*ckobj_p>, and control flags are returned in
C<*ckflags_p>.  The function is intended to be called in this manner:

 entersubop = (*ckfun_p)(aTHX_ entersubop, namegv, (*ckobj_p));

In this call, C<entersubop> is a pointer to the C<entersub> op,
which may be replaced by the check function, and C<namegv> supplies
the name that should be used by the check function to refer
to the callee of the C<entersub> op if it needs to emit any diagnostics.
It is permitted to apply the check function in non-standard situations,
such as to a call to a different subroutine or to a method call.

C<namegv> may not actually be a GV.  If the C<CALL_CHECKER_REQUIRE_GV>
bit is clear in C<*ckflags_p>, it is permitted to pass a CV or other SV
instead, anything that can be used as the first argument to L</cv_name>.
If the C<CALL_CHECKER_REQUIRE_GV> bit is set in C<*ckflags_p> then the
check function requires C<namegv> to be a genuine GV.

By default, the check function is
L<Perl_ck_entersub_args_proto_or_list|/ck_entersub_args_proto_or_list>,
the SV parameter is C<cv> itself, and the C<CALL_CHECKER_REQUIRE_GV>
flag is clear.  This implements standard prototype processing.  It can
be changed, for a particular subroutine, by L</cv_set_call_checker_flags>.

If the C<CALL_CHECKER_REQUIRE_GV> bit is set in C<gflags> then it
indicates that the caller only knows about the genuine GV version of
C<namegv>, and accordingly the corresponding bit will always be set in
C<*ckflags_p>, regardless of the check function's recorded requirements.
If the C<CALL_CHECKER_REQUIRE_GV> bit is clear in C<gflags> then it
indicates the caller knows about the possibility of passing something
other than a GV as C<namegv>, and accordingly the corresponding bit may
be either set or clear in C<*ckflags_p>, indicating the check function's
recorded requirements.

C<gflags> is a bitset passed into C<cv_get_call_checker_flags>, in which
only the C<CALL_CHECKER_REQUIRE_GV> bit currently has a defined meaning
(for which see above).  All other bits should be clear.

=for apidoc Am|void|cv_get_call_checker|CV *cv|Perl_call_checker *ckfun_p|SV **ckobj_p

The original form of L</cv_get_call_checker_flags>, which does not return
checker flags.  When using a checker function returned by this function,
it is only safe to call it with a genuine GV as its C<namegv> argument.

=cut
*/

void
Perl_cv_get_call_checker_flags(pTHX_ CV *cv, U32 gflags,
	Perl_call_checker *ckfun_p, SV **ckobj_p, U32 *ckflags_p)
{
    MAGIC *callmg;
    PERL_ARGS_ASSERT_CV_GET_CALL_CHECKER_FLAGS;
    PERL_UNUSED_CONTEXT;
    callmg = SvMAGICAL((SV*)cv) ? mg_find((SV*)cv, PERL_MAGIC_checkcall) : NULL;
    if (callmg) {
	*ckfun_p = DPTR2FPTR(Perl_call_checker, callmg->mg_ptr);
	*ckobj_p = callmg->mg_obj;
	*ckflags_p = (callmg->mg_flags | gflags) & MGf_REQUIRE_GV;
    } else {
	*ckfun_p = Perl_ck_entersub_args_proto_or_list;
	*ckobj_p = (SV*)cv;
	*ckflags_p = gflags & MGf_REQUIRE_GV;
    }
}

void
Perl_cv_get_call_checker(pTHX_ CV *cv, Perl_call_checker *ckfun_p, SV **ckobj_p)
{
    U32 ckflags;
    PERL_ARGS_ASSERT_CV_GET_CALL_CHECKER;
    PERL_UNUSED_CONTEXT;
    cv_get_call_checker_flags(cv, CALL_CHECKER_REQUIRE_GV, ckfun_p, ckobj_p,
	&ckflags);
}

/*
=for apidoc Am|void|cv_set_call_checker_flags|CV *cv|Perl_call_checker ckfun|SV *ckobj|U32 ckflags

Sets the function that will be used to fix up a call to C<cv>.
Specifically, the function is applied to an C<entersub> op tree for a
subroutine call, not marked with C<&>, where the callee can be identified
at compile time as C<cv>.

The C-level function pointer is supplied in C<ckfun>, an SV argument for
it is supplied in C<ckobj>, and control flags are supplied in C<ckflags>.
The function should be defined like this:

    static OP * ckfun(pTHX_ OP *op, GV *namegv, SV *ckobj)

It is intended to be called in this manner:

    entersubop = ckfun(aTHX_ entersubop, namegv, ckobj);

In this call, C<entersubop> is a pointer to the C<entersub> op,
which may be replaced by the check function, and C<namegv> supplies
the name that should be used by the check function to refer
to the callee of the C<entersub> op if it needs to emit any diagnostics.
It is permitted to apply the check function in non-standard situations,
such as to a call to a different subroutine or to a method call.

C<namegv> may not actually be a GV.  For efficiency, perl may pass a
CV or other SV instead.  Whatever is passed can be used as the first
argument to L</cv_name>.  You can force perl to pass a GV by including
C<CALL_CHECKER_REQUIRE_GV> in the C<ckflags>.

C<ckflags> is a bitset, in which only the C<CALL_CHECKER_REQUIRE_GV>
bit currently has a defined meaning (for which see above).  All other
bits should be clear.

The current setting for a particular CV can be retrieved by
L</cv_get_call_checker_flags>.

=for apidoc Am|void|cv_set_call_checker|CV *cv|Perl_call_checker ckfun|SV *ckobj

The original form of L</cv_set_call_checker_flags>, which passes it the
C<CALL_CHECKER_REQUIRE_GV> flag for backward-compatibility.  The effect
of that flag setting is that the check function is guaranteed to get a
genuine GV as its C<namegv> argument.

=cut
*/

void
Perl_cv_set_call_checker(pTHX_ CV *cv, Perl_call_checker ckfun, SV *ckobj)
{
    PERL_ARGS_ASSERT_CV_SET_CALL_CHECKER;
    cv_set_call_checker_flags(cv, ckfun, ckobj, CALL_CHECKER_REQUIRE_GV);
}

void
Perl_cv_set_call_checker_flags(pTHX_ CV *cv, Perl_call_checker ckfun,
				     SV *ckobj, U32 ckflags)
{
    PERL_ARGS_ASSERT_CV_SET_CALL_CHECKER_FLAGS;
    if (ckfun == Perl_ck_entersub_args_proto_or_list && ckobj == (SV*)cv) {
	if (SvMAGICAL((SV*)cv))
	    mg_free_type((SV*)cv, PERL_MAGIC_checkcall);
    } else {
	MAGIC *callmg;
	sv_magic((SV*)cv, UNDEF, PERL_MAGIC_checkcall, NULL, 0);
	callmg = mg_find((SV*)cv, PERL_MAGIC_checkcall);
	assert(callmg);
	if (callmg->mg_flags & MGf_REFCOUNTED) {
	    SvREFCNT_dec(callmg->mg_obj);
	    callmg->mg_flags &= ~MGf_REFCOUNTED;
	}
	callmg->mg_ptr = FPTR2DPTR(char *, ckfun);
	callmg->mg_obj = ckobj;
	if (ckobj != (SV*)cv) {
	    SvREFCNT_inc_simple_void_NN(ckobj);
	    callmg->mg_flags |= MGf_REFCOUNTED;
	}
	callmg->mg_flags = (callmg->mg_flags &~ MGf_REQUIRE_GV)
			 | (U8)(ckflags & MGf_REQUIRE_GV) | MGf_COPY;
    }
}

static void
S_entersub_alloc_targ(pTHX_ OP * const o)
{
    o->op_targ = pad_alloc(OP_ENTERSUB, SVs_PADTMP);
    o->op_private |= OPpENTERSUB_HASTARG;
}

/*
=for apidoc ck_subr
CHECK callback for entersub, enterxssub, both (dm1  L).
See also L</ck_method>
=cut
*/
OP *
Perl_ck_subr(pTHX_ OP *o)
{
    OP *aop, *cvop;
    CV *cv;
    GV *namegv;
    SV **const_class = NULL;

    PERL_ARGS_ASSERT_CK_SUBR;

    aop = OpFIRST(o);
    if (!OpHAS_SIBLING(aop))
	aop = OpFIRST(aop);
    aop = OpSIBLING(aop);
    for (cvop = aop; OpHAS_SIBLING(cvop); cvop = OpSIBLING(cvop)) {
        if (IS_TYPE(cvop, HSLICE) || IS_TYPE(cvop, KVHSLICE)) {
            Perl_ck_warner(aTHX_ packWARN(WARN_SYNTAX),
                           "No autovivification of hash slice anymore");
            cvop->op_private |= OPpSTACKCOPY;
        }
    }
    cv = rv2cv_op_cv(cvop, RV2CVOPCV_MARK_EARLY);
    namegv = cv ? (GV*)rv2cv_op_cv(cvop, RV2CVOPCV_MAYBE_NAME_GV) : NULL;
#if 0
    if (cv && CvPURE(cv)) /* check for method field op. only for rv2cv */
#endif

    /* TODO: static methods, inlining, null removal */
    o->op_private &= ~1;
    o->op_private |= (PL_hints & HINT_STRICT_REFS);
    if (PERLDB_SUB && PL_curstash != PL_debstash)
	o->op_private |= OPpENTERSUB_DB;
    switch (cvop->op_type) {
	case OP_RV2CV:
	    o->op_private |= (cvop->op_private & OPpENTERSUB_AMPER);
	    op_null(cvop);
	    break;
	case OP_METHOD_NAMED:
	    if (IS_CONST_OP(aop)) {
                SV *meth  = cMETHOPx_meth(cvop);
                /* check for static methods, a method field or ctor op: ctor CLASS->new */
                if (LIKELY(SvPOK(meth))) { /* always a shared COW string */
                    SV *pkg   = cSVOPx_sv(aop);
                    HV *stash = gv_stashsv(pkg, SvUTF8(pkg));
                    GV **gvp;
                    /* skip ""->method */
                    if (LIKELY((SvPOK(pkg) ? SvCUR(pkg) : TRUE) &&
                               stash && SvTYPE(stash) == SVt_PVHV)) {
                        /* Mu ctor's */
                        if ( strEQc(SvPVX(meth), "new") ||
                             strEQc(SvPVX(meth), "CREATE") ) {
                            OpRETTYPE_set(o, type_Object);
                        }
                        /* bypass cache and gv overhead */
                        gvp = (GV**)hv_common(stash, meth, NULL, 0, 0,
                                       HV_FETCH_ISEXISTS|HV_FETCH_JUST_SV, NULL, 0);
                        /* static method -> sub */
                        if (gvp) {
                            GV *gv = *gvp;
                            CV* cvf = NULL;
                            HV *cvstash = NULL;
                            if (SvROK(gv) && SvTYPE(SvRV((SV*)gv)) == SVt_PVCV) {
                                cvf = (CV*)SvRV((SV*)gv);
                                /* we'd really need a proper GV here.
                                   see t/op/symbolcache.t */
                                gv = CvGV(cvf);
                                cvstash = GvSTASH(gv);
                            }
                            else if (SvTYPE(gv) == SVt_PVGV) {
                                cvf = GvCV(gv);
                                if (cvf)
                                    cvstash = GvSTASH(CvGV(cvf));
                            }
                            if (cvf) {
                                /* Note: CvSTASH is 0 with a GV. But when the GvSTASH
                                 * contains that method, allow this optimization also. */
                                if (!cvstash)
                                    cvstash = CvSTASH(cvf);
                                /* allow: sub pkg::meth {} pkg->meth */
                                /* TODO: else check class hierarchy */
                                if (HvCLASS(stash) && cvstash == stash) {
                                    if (HvCLASS(stash))
                                        Perl_croak(aTHX_
                                            "Invalid method call on class subroutine %" SVf,
                                            SVfARG(cv_name(cvf,NULL,CV_NAME_NOMAIN)));
                                }
                                if (cvstash == stash) { /* TODO or in subclass */
                                    if (CvISXSUB(cvf) && CvROOT(cvf) &&
                                        GvXSCV(gv) && !PL_perldb)
                                    {
                                        DEBUG_k(Perl_deb(aTHX_ "entersub -> xs %" SVf "\n",
                                            SVfARG(cv_name(cvf, NULL, CV_NAME_NOMAIN))));
                                        OpTYPE_set(o, OP_ENTERXSSUB);
                                    }
                                    /* from METHOP to GV */
                                    OpTYPE_set(cvop, OP_GV);
                                    OpPRIVATE(cvop) |= OPpGV_WASMETHOD;
                                    /* t/op/symbolcache.t needs a replacable GV, not a CV */
                                    op_gv_set(cvop, gv);
                                    DEBUG_k(Perl_deb(aTHX_
                                        "ck_subr: static method call %s->%s => %s::%s\n",
                                        SvPVX_const(pkg), SvPVX_const(meth),
                                        SvPVX_const(pkg), SvPVX_const(meth)));
                                    SvREFCNT_dec(meth);
                                    cvop->op_flags |= OPf_WANT_SCALAR;
                                    o->op_flags |= OPf_STACKED;
                                }
                            }
                        }
                    }
                }
            }
            /* TODO: with typed PADSV check class hierarchy */
            else if (method_field_type(o)) {
                /* TODO: check default accessor and convert to oelem */
                OpRETTYPE_set(o, type_Object);
            }
            /* FALLTHROUGH */
	case OP_METHOD:
	case OP_METHOD_SUPER:
	case OP_METHOD_REDIR:
	case OP_METHOD_REDIR_SUPER:
	    o->op_flags |= OPf_REF;
	    if (IS_CONST_OP(aop)) {
		aop->op_private &= ~OPpCONST_STRICT;
		const_class = &cSVOPx(aop)->op_sv;
	    }
	    else if (IS_TYPE(aop, LIST)) {
		OP * const sib = OpSIBLING(OpFIRST(aop));
		if (OP_TYPE_IS(sib, OP_CONST)) {
		    sib->op_private &= ~OPpCONST_STRICT;
		    const_class = &cSVOPx(sib)->op_sv;
		}
	    }
	    /* make class name a shared cow string to speedup method calls */
	    /* constant string might be replaced with object, f.e. bigint */
	    if (const_class && SvPOK(*const_class)) {
		STRLEN len;
		const char* str = SvPV(*const_class, len);
		if (len) {
		    SV* const shared = newSVpvn_share(
			str, SvUTF8(*const_class)
                             ? -(SSize_t)len : (SSize_t)len, 0);
                    if (SvREADONLY(*const_class))
                        SvREADONLY_on(shared);
		    SvREFCNT_dec(*const_class);
		    *const_class = shared;
		}
	    }
	    break;
    }

    if (!cv) {
	S_entersub_alloc_targ(aTHX_ o);
	return ck_entersub_args_list(o);
    } else {
	Perl_call_checker ckfun;
	SV *ckobj;
	U32 ckflags;
	cv_get_call_checker_flags(cv, 0, &ckfun, &ckobj, &ckflags);
	if (CvISXSUB(cv)) {
            o->op_targ = pad_alloc(OP_ENTERXSSUB, SVs_PADTMP);
            o->op_private |= OPpENTERSUB_HASTARG;
        }
        else if (!CvROOT(cv))
	    S_entersub_alloc_targ(aTHX_ o);

	if (!namegv) {
	    /* The original call checker API guarantees that a GV will be
	       be provided with the right name.  So, if the old API was
	       used (or the REQUIRE_GV flag was passed), we have to reify
	       the CV’s GV, unless this is an anonymous sub.  This is not
	       ideal for lexical subs, as its stringification will include
	       the package.  But it is the best we can do.  */
	    if (ckflags & CALL_CHECKER_REQUIRE_GV) {
		if (!CvANON(cv) && (!CvNAMED(cv) || CvNAME_HEK(cv)))
		    namegv = CvGV(cv);
	    }
	    else namegv = MUTABLE_GV(cv);
	    /* After a syntax error in a lexical sub, the cv that
	       rv2cv_op_cv returns may be a nameless stub. */
	    if (!namegv) return ck_entersub_args_list(o);
	}
	return ckfun(aTHX_ o, namegv, ckobj);
    }
}

/*
=for apidoc ck_svconst
CHECK callback for const (ps$	"():Scalar") and hintseval (s$)

Turns on COW and READONLY for the scalar.
=cut
*/
OP *
Perl_ck_svconst(pTHX_ OP *o)
{
    SV * const sv = cSVOPo->op_sv;
    PERL_ARGS_ASSERT_CK_SVCONST;
    PERL_UNUSED_CONTEXT;
#ifdef PERL_COPY_ON_WRITE
    /* Since the read-only flag may be used to protect a string buffer, we
       cannot do copy-on-write with existing read-only scalars that are not
       already copy-on-write scalars.  To allow $_ = "hello" to do COW with
       that constant, mark the constant as COWable here, if it is not
       already read-only. */
    if (!SvREADONLY(sv) && !SvIsCOW(sv) && SvCANCOW(sv)) {
	SvIsCOW_on(sv);
	CowREFCNT(sv) = 0;
# ifdef PERL_DEBUG_READONLY_COW
	sv_buf_to_ro(sv);
# endif
    }
#endif
    SvREADONLY_on(sv);
    return o;
}

/*
=for apidoc ck_trunc
CHECK callback for truncate (is@	S S)
truncate really behaves as if it had both "S S" and "F S"
i.e. with a bare handle argument turns on SPECIAL and off CONST_STRICT.
=cut
*/
OP *
Perl_ck_trunc(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_TRUNC;

    if (OpKIDS(o)) {
	SVOP *kid = (SVOP*)OpFIRST(o);

	if (IS_NULL_OP(kid))
	    kid = (SVOP*)OpSIBLING(kid);
	if (kid && IS_CONST_OP(kid) &&
	    (kid->op_private & OPpCONST_BARE) &&
	    !kid->op_folded)
	{
	    o->op_flags |= OPf_SPECIAL;
	    kid->op_private &= ~OPpCONST_STRICT;
	}
    }
    return ck_fun(o);
}

/*
=for apidoc ck_substr
CHECK callback for substr (st@	S S S? S?)
turning for the 4 arg variant into an lvalue sub.
=cut
*/
OP *
Perl_ck_substr(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_SUBSTR;

    o = ck_fun(o);
    if ((OpKIDS(o)) && (o->op_private == 4)) {
	OP *kid = OpFIRST(o);

	if (IS_NULL_OP(kid))
	    kid = OpSIBLING(kid);
	if (kid)
	    /* Historically, substr(delete $foo{bar},...) has been allowed
	       with 4-arg substr.  Keep it working by applying entersub
	       lvalue context.  */
	    op_lvalue(kid, OP_ENTERSUB);

    }
    return o;
}

/*
=for apidoc ck_tell
CHECK callback for tell and seek
=cut
*/
OP *
Perl_ck_tell(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_TELL;
    o = ck_fun(o);
    if (OpKIDS(o)) {
        OP *kid = OpFIRST(o);
        if (IS_NULL_OP(kid) && OpHAS_SIBLING(kid)) kid = OpSIBLING(kid);
        if (IS_TYPE(kid, RV2GV)) kid->op_private |= OPpALLOW_FAKE;
    }
    return o;
}

/*
=for apidoc ck_each

CHECK callback for each, valus and keys and its array variants.

Optimizes into the array specific variants, checks for type errors,
and die on the old 5.14 experimental feature which allowed C<each>,
C<keys>, C<push>, C<pop>, C<shift>, C<splice>, C<unshift>, and
C<values> to be called with a scalar argument.
See L<perl5140delta/Syntactical Enhancements>
This experiment is considered unsuccessful, and has been removed.

=cut
*/
OP *
Perl_ck_each(pTHX_ OP *o)
{
    dVAR;
    OP *kid = OpKIDS(o) ? OpFIRST(o) : NULL;
    const unsigned orig_type  = o->op_type;

    PERL_ARGS_ASSERT_CK_EACH;

    if (kid) {
	switch (kid->op_type) {
	    case OP_PADHV:
	    case OP_RV2HV:
		break;
	    case OP_PADAV:
	    case OP_RV2AV:
                OpTYPE_set(o, orig_type == OP_EACH ? OP_AEACH
                            : orig_type == OP_KEYS ? OP_AKEYS
                            :                        OP_AVALUES);
		break;
	    case OP_CONST:
		if (kid->op_private == OPpCONST_BARE
		 || !SvROK(cSVOPx_sv(kid))
		 || (  SvTYPE(SvRV(cSVOPx_sv(kid))) != SVt_PVAV
		    && SvTYPE(SvRV(cSVOPx_sv(kid))) != SVt_PVHV  )
		   )
		    goto bad;
                /* FALLTHROUGH */
	    default:
                qerror(Perl_mess(aTHX_
                    "Experimental %s on scalar is now forbidden",
                     PL_op_desc[orig_type]));
               bad:
                bad_type_pv(1, "hash or array", o, kid);
                return o;
	}
    }
    return ck_fun(o);
}

/*
=for apidoc ck_length
CHECK callback for length, only needed to throw compile-time warnings when
length is mixed up with scalar.

=cut
*/
OP *
Perl_ck_length(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_LENGTH;

    o = ck_fun(o);

    if (ckWARN(WARN_SYNTAX)) {
        const OP *kid = OpKIDS(o) ? OpFIRST(o) : NULL;

        if (kid) {
            SV *name = NULL;
            const bool hash = IS_TYPE(kid, PADHV)
                           || IS_TYPE(kid, RV2HV);
            DEBUG_k(Perl_deb(aTHX_ "ck_length: %s %s\n", OP_NAME(o), OP_NAME(kid)));
            switch (kid->op_type) {
                case OP_PADHV:
                case OP_PADAV:
                case OP_RV2HV:
                case OP_RV2AV:
		    name = S_op_varname(aTHX_ kid);
                    break;
                default:
                    return o;
            }
            if (name)
                Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
                    "length() used on %" SVf " (did you mean \"scalar(%s%" SVf
                    ")\"?)",
                    SVfARG(name), hash ? "keys " : "", SVfARG(name)
                );
            else if (hash)
     /* diag_listed_as: length() used on %s (did you mean "scalar(%s)"?) */
                Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
                    "length() used on %%hash (did you mean \"scalar(keys %%hash)\"?)");
            else
     /* diag_listed_as: length() used on %s (did you mean "scalar(%s)"?) */
                Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
                    "length() used on @array (did you mean \"scalar(@array)\"?)");
        }
    }

    return o;
}

/*
=for apidoc ck_aelem
Check for typed and shaped arrays, and promote ops.

With constant indices throws compile-time "Array index out of bounds"
and "Too many elements" errors.

No natively typed arrays yet.
=cut
*/
OP *
Perl_ck_aelem(pTHX_ OP *o)
{
    PADOFFSET targ = o->op_targ;
    SV* idx;
    OP* avop = OpFIRST(o);
    PERL_ARGS_ASSERT_CK_AELEM;

    if (targ) { /* newPADOP sets it, newOP only with OA_TARGET */
        idx = PAD_SV(targ);
    }
    else {
        OP* ixop = OpLAST(o);
        idx = OP_TYPE_IS(ixop, OP_CONST) ? cSVOPx(ixop)->op_sv : NULL;
    }
    /* compile-time check shaped av with const idx */
    if (OP_TYPE_IS(avop, OP_PADAV) && avop->op_targ &&
        idx && SvIOK(idx))
    {
        PADOFFSET po = avop->op_targ;
        AV* av = MUTABLE_AV(pad_findmy_real(po, PL_compcv));
        if (AvSHAPED(av)) {
            if (UNLIKELY(SvIsUV(idx))) {
                UV ix = SvUV(idx);
                if (ix > (UV)AvFILL(av))
                    Perl_die(aTHX_ "Array index out of bounds %s[%" UVuf "]",
                             PAD_COMPNAME_PV(po), ix);
                else {
                    /* optimizing it here clashes with maybe_multideref.
                       so do it later */
                    /*OpTYPE_set(o, OP_AELEM_U);*/
                    DEBUG_kv(Perl_deb(aTHX_ "ck_%s shape ok %s[%" UVuf "]\n",
                                      PL_op_name[o->op_type],
                                      PAD_COMPNAME_PV(po), ix));
                }
            } else {
                IV ix = SvIVX(idx);
                if (PERL_IABS(ix) > AvFILLp(av))
                    Perl_die(aTHX_ "Array index out of bounds %s[%" IVdf "]",
                             PAD_COMPNAME_PV(po), ix);
                else {
                    /*OpTYPE_set(o, OP_AELEM_U);*/
                    DEBUG_kv(Perl_deb(aTHX_ "ck_%s shape ok %s[%" IVdf "]\n",
                                      PL_op_name[o->op_type],
                                      PAD_COMPNAME_PV(po), ix));
                    if (ix < 0) {
                        ix = AvFILL(av)+1+ix;
                        SvIV_set(idx, ix);
                        DEBUG_kv(Perl_deb(aTHX_ "ck_%s %s[->%" IVdf "]\n",
                                          PL_op_name[o->op_type],
                                          PAD_COMPNAME_PV(po), ix));
                    }
                }
            }
        }
        /* TODO specialize to typed ops */
    }
    if (UNLIKELY(idx && SvIsUV(idx))) {
        UV ix = SvUV(idx);
        if (ix > SSize_t_MAX)
            Perl_die(aTHX_ "Too many elements");
    }

    DEBUG_k(Perl_deb(aTHX_ "ck_%s %s[%" IVdf "]\n", PL_op_name[o->op_type],
                targ ? PAD_COMPNAME_PV(targ) : "?",
                idx ? SvIV(idx) : -99));
    return o;
}

/*
=for apidoc ck_negate
Check the ! op, negate and turn off OPpCONST_STRICT of the argument.
=cut
*/
OP *
Perl_ck_negate(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_NEGATE;
    if (IS_TYPE(o, NEGATE))
	OpFIRST(o)->op_private &= ~OPpCONST_STRICT;
    DEBUG_k(Perl_deb(aTHX_ "ck_negate %s\n", PL_op_name[o->op_type]));
    return ck_type(o);
}

/*
=for apidoc ck_pad

Check for const and types.
Called from newOP/newPADOP this is too early,
the target is attached later. But we also call it from constant folding.
Having an explicit CONST op allows constant optimizations on it.
=cut
*/
OP *
Perl_ck_pad(pTHX_ OP *o)
{
    PERL_ARGS_ASSERT_CK_PAD;
    if (o->op_targ) { /* newPADOP sets it, newOP only with OA_TARGET */
        SV* sv = PAD_SV(o->op_targ);
        /* TODO PAD[AH]V :const */
        if (IS_TYPE(o, PADSV) && SvREADONLY(sv)) {
            dVAR;
#ifdef DEBUGGING
            /* ensure we allocated enough room to upgrade it */
            size_t space = DIFF(OpSLOT(o), OpSLOT(o)->opslot_next);
            assert(space*sizeof(OP*) >= sizeof(SVOP));
#endif
            OpTYPE_set(o, OP_CONST);
            DEBUG_k(Perl_deb(aTHX_ "ck_pad: %s[%s]\n", PL_op_name[o->op_type],
                             PAD_COMPNAME_PV(o->op_targ)));
            cSVOPx(o)->op_sv = SvREFCNT_inc_NN(sv);
            o->op_targ = 0;
            /* no n-children privates. OPpDEREF|OPpPAD_STATE|OPpLVAL_INTRO are invalid */
            assert(!o->op_private);
        }
        /* compile-time check invalid ops on shaped av's. duplicate in rpeep
           when the targ is filled in, or op_next is setup */
        else if (IS_TYPE(o, PADAV)
                 && OpNEXT(o) && OpNEXT(OpNEXT(o))
                 && (sv = pad_findmy_real(o->op_targ, PL_compcv))
                 && AvSHAPED(sv)) {
            OPCODE type = OpNEXT(OpNEXT(o))->op_type;
            /* splice is for now checked at run-time */
            if (type == OP_PUSH  || type == OP_POP
             || type == OP_SHIFT || type == OP_UNSHIFT)
                Perl_die(aTHX_ "Invalid modification of shaped array: %s %s",
                    OP_NAME(OpNEXT(OpNEXT(o))),
                    PAD_COMPNAME_PV(o->op_targ));
            DEBUG_k(Perl_deb(aTHX_ "ck_pad: %s[%s] SHAPED[%d]\n", PL_op_name[o->op_type],
                             PAD_COMPNAME_PV(o->op_targ), (int)AvFILLp(sv)));
        } else {
            /* maybe check typeinfo also, and set some
               SVf_TYPED flag if we still had one. This const
               looses all type info, and is either int|num|str. */
            DEBUG_k(Perl_deb(aTHX_ "ck_pad: %s[%s]\n", PL_op_name[o->op_type],
                             PAD_COMPNAME_PV(o->op_targ)));
        }
    }
    return o;
}

#if 0
/* index for the ")"
   Not used for our simple coretypes yet, needed later for Array()
   i.e. "(:Int,:Int):Int" => ":Int,:Int" */
PERL_STATIC_INLINE
int S_sigtype_args(const char* sig, int *i)
{
    char *p;
    if (sig[0] != '(') return 0;
    if (!(p = strchr(sig, ')'))) return 0;
    *i = p - sig - 1;
    return 1;
}
#endif

/*
=for apidoc match_type1
match an UNOP type with the given arg.

=cut
*/
PERL_STATIC_INLINE
int S_match_type1(const U32 sig, core_types_t arg1)
{
    /* also accept Int as UInt, and UInt as Int */
    return sig == (((U32)arg1 << 24) | 0xffff00)
        || (arg1 == type_Int
            ? sig == (((U32)type_UInt << 24) | 0xffff00)
            : (arg1 == type_UInt
               ? sig == (((U32)type_Int << 24) | 0xffff00) : 0));

}

/*
=for apidoc match_type2
match an BINOP type with the given args.

=cut
*/
PERL_STATIC_INLINE
int S_match_type2(const U32 sig, core_types_t arg1, core_types_t arg2)
{
    /* also accept Int as UInt, and UInt as Int */
    return sig == (((U32)arg1 << 24) | ((U32)arg2 << 16) | 0xff00)
        || (arg2 == type_Int
            ? sig == (((U32)arg1 << 24) | ((U32)type_UInt << 16) | 0xff00)
            : (arg2 == type_UInt
               ? sig == (((U32)arg1 << 24) | ((U32)type_Int << 16) | 0xff00) : 0));
}

/*
=for apidoc ck_type

Check unop and binops for typed args, find specialized match and promote.
Forget about native types (escape analysis) here, use the boxed variants.
We can only unbox them later in rpeep sequences, by adding unbox...box ops.
Set the OpRETTYPE of unops and binops.
=cut
*/
OP *
Perl_ck_type(pTHX_ OP *o)
{
    OPCODE typ = o->op_type;
    OP* a = OpKIDS(o) ? OpFIRST(o) : NULL;    /* defgv */
    core_types_t type1 = a ? op_typed(a) : type_none; /* S? ops with defgv */
    unsigned int oc = PL_opargs[typ] & OA_CLASS_MASK;

    PERL_ARGS_ASSERT_CK_TYPE;

    if (!type1 || type1 >= type_Scalar) {
        return o;
    }
    else if (oc == OA_UNOP || oc == OA_BASEOP_OR_UNOP) {
        const int n = NUM_OP_TYPE_VARIANTS(typ);
        DEBUG_k(Perl_deb(aTHX_ "ck_type: %s(%s:%s)\n", PL_op_name[typ],
                    OP_NAME(a), core_type_name(type1)));
        DEBUG_kv(op_dump(a));
        /* search for typed variants and check matching types */
        if (n) {
            int i;
            for (i=1; i<=n; i++) {
                int v = OP_TYPE_VARIANT(typ, i);
                if (v) {
                    const U32 n2 = PL_op_type[v];
                    DEBUG_k(Perl_deb(aTHX_ "match: %s %s <=> %s %s\n", PL_op_name[typ],
                                     PL_op_type_str[typ],
                                     PL_op_name[v], PL_op_type_str[v]));
                    /* need an Int result, no u_ */
                    if ((PL_hints & HINT_INTEGER) && ((n2 & 0xff) != type_Int))
                        continue;
                    if (match_type1(n2 & 0xffffff00, type1)) {
                        dVAR;
                        if (typ == OP_NEGATE && v == OP_I_NEGATE)
                            return o;
                        DEBUG_kv(Perl_deb(aTHX_ "%s (:%s) => %s %s\n", PL_op_name[typ],
                                          core_type_name(type1),
                                          PL_op_name[v], PL_op_type_str[v]));
                        OpTYPE_set(o, v);
                        OpRETTYPE_set(o, n2 & 0xff);
                        DEBUG_kv(op_dump(o));
                        return o;
                    }
                }
            }
        }
    }
    else if (oc == OA_BINOP) {
        OP* b = OpLAST(o);
        core_types_t type2 = op_typed(b);
        const int n = NUM_OP_TYPE_VARIANTS(typ);
        /* TODO for entersub/enterxssub we should inspect the return type of the
           function, PadnameTYPE of pad[0] */
        DEBUG_k(Perl_deb(aTHX_ "ck_type: %s(%s:%s, %s:%s)\n", PL_op_name[typ],
                    OP_NAME(a), core_type_name(type1),
                    OP_NAME(b), core_type_name(type2)));
        /* Search for typed variants and check matching types */
        /* Note that this shortcut below is not correct, only tuned
           to our current ops */
        if (n && (type1 == type2
             || (type1 == type_int  && type2 == type_Int)
             || (type1 == type_uint && type2 == type_int)
             || (type1 == type_UInt && type2 == type_Int)
             || (type1 == type_Int  && type2 == type_UInt)
            ))
        {
            int i;
            for (i=1; i<=n; i++) {
                int v = OP_TYPE_VARIANT(typ, i);
                if (v) {
                    const U32 n2 = PL_op_type[v];
                    DEBUG_k(Perl_deb(aTHX_ "match: %s %s <=> %s %s\n", PL_op_name[typ],
                                     PL_op_type_str[typ],
                                     PL_op_name[v], PL_op_type_str[v]));
                    if ((PL_hints & HINT_INTEGER) && ((n2 & 0xff) != type_Int)) /* need an Int result, no u_ */
                        continue;
                    if (match_type2(n2 & 0xffffff00, type1, type2)) {
                        dVAR;
                        /* Exception: Even if both / operands are int do not use intdiv.
                           TODO: Only if the lhs result needs to be int. But this needs
                           to be decided in the type checker in rpeep later. */
                        if (typ == OP_DIVIDE && v == OP_I_DIVIDE)
                            return o;
                        DEBUG_kv(Perl_deb(aTHX_ "%s (:%s,:%s) => %s %s\n", PL_op_name[typ],
                                          core_type_name(type1), core_type_name(type2),
                                          PL_op_name[v], PL_op_type_str[v]));
                        OpTYPE_set(o, v);
                        OpRETTYPE_set(o, n2 & 0xff);
                        /* XXX upstream hack:
                           newBINOP skips this if type changed in ck */
                        o = fold_constants(op_integerize(op_std_init(o)));
                        DEBUG_kv(op_dump(o));
                        return o;
                    }
                }
            }
        }
        /*DEBUG_kv(op_dump(a));
          DEBUG_kv(op_dump(b));*/
    }
    else {
        Perl_die(aTHX_ "Invalid op %s for ck_type", OP_NAME(o));
    }
    OpRETTYPE_set(o, OpTYPE_RET(typ));
    return o;
}

/*
=for apidoc ck_nomg

For tie and bless

Check if the first argument is not a typed coretype.
We guarantee coretyped variables to have no magic.

For bless we also require a ref. Check for the most common mistakes
as first argument, which cannot be a ref.

For bless we can predict the result type if the 2nd arg is a constant.
This allows to type the result of the new method.

    sub D3::new {bless[],"D3"};
    my B2 $obj1 = D3->new;

And we disallow the blessing to coretypes. This needs to be done via normal
compile-time declarations, not dynamic blessing.
=cut
*/
OP *
Perl_ck_nomg(pTHX_ OP *o)
{
    OP* a = OpFIRST(o);
    core_types_t argtype;
    PADOFFSET po;

    PERL_ARGS_ASSERT_CK_NOMG;

    if (OP_TYPE_IS_OR_WAS(a, OP_PUSHMARK)) {
        if (OpNEXT(a) && OpNEXT(a) != a)
            a = OpNEXT(a);
        else
            a = OpSIBLING(OpNEXT(a));
    }
    if (IS_TYPE(o, BLESS)) {
        if (OP_TYPE_IS(a, OP_NULL))
            a = OpNEXT(a);
        /* maybe we can check which ops are disallowed here */
        if (a &&
            (IS_TYPE(a, PADAV) ||
             IS_TYPE(a, PADHV) ||
             IS_TYPE(a, LIST)))
            /* diag_listed_as: Can't bless non-reference value */
            Perl_croak(aTHX_ "Can't bless non-reference value (%s)", OP_NAME(a));
        if (IS_TYPE(OpLAST(o), CONST)) {
            OP* b = OpLAST(o);
            SV* name = cSVOPx_sv(b);
            if (SvPOK(name)) {
                /* ignore coretypes: bless $x, "Str" */
                if (find_in_coretypes(SvPVX(name), SvCUR(name)))
                    Perl_warner(aTHX_ packWARN(WARN_TYPES),
                                "Can't bless to coretype %s", SvPVX(name));
                else {
                    OpRETTYPE_set(o, type_Object);
                }
            }
        }
    }
    /* e.g. bless \$, $class */
    if (OP_TYPE_IS(a, OP_SREFGEN)) {
        a = OpFIRST(a);
        if (OP_TYPE_IS_OR_WAS(a, OP_LIST))
            a = OpFIRST(a);
    }
    if (!a || !OP_IS_PADVAR(a->op_type))
        return ck_fun(o);

    argtype = op_typed(a);
    po = a->op_targ;
    DEBUG_kv(Perl_deb(aTHX_ "%s(%s :%s)\n", OP_NAME(o),
                      PAD_COMPNAME(po) ? PAD_COMPNAME_PV(po) : "",
                      core_type_name(argtype)));
    if (argtype > type_none && argtype <= type_Str) {
        Perl_die(aTHX_ "Invalid type %s for %s %s", core_type_name(argtype), OP_NAME(o),
                 PAD_COMPNAME(po) ? PAD_COMPNAME_PV(po) : "");
    }
    return ck_fun(o);
}


/* 
   ---------------------------------------------------------
 
   Common vars in list assignment

   There now follows some enums and static functions for detecting
   common variables in list assignments. Here is a little essay I wrote
   for myself when trying to get my head around this. DAPM.

   ----

   First some random observations:
   
   * If a lexical var is an alias of something else, e.g.
       for my $x ($lex, $pkg, $a[0]) {...}
     then the act of aliasing will increase the reference count of the SV
   
   * If a package var is an alias of something else, it may still have a
     reference count of 1, depending on how the alias was created, e.g.
     in *a = *b, $a may have a refcount of 1 since the GP is shared
     with a single GvSV pointer to the SV. So If it's an alias of another
     package var, then RC may be 1; if it's an alias of another scalar, e.g.
     a lexical var or an array element, then it will have RC > 1.
   
   * There are many ways to create a package alias; ultimately, XS code
     may quite legally do GvSV(gv) = SvREFCNT_inc(sv) for example, so
     run-time tracing mechanisms are unlikely to be able to catch all cases.
   
   * When the LHS is all my declarations, the same vars can't appear directly
     on the RHS, but they can indirectly via closures, aliasing and lvalue
     subs. But those techniques all involve an increase in the lexical
     scalar's ref count.
   
   * When the LHS is all lexical vars (but not necessarily my declarations),
     it is possible for the same lexicals to appear directly on the RHS, and
     without an increased ref count, since the stack isn't refcounted.
     This case can be detected at compile time by scanning for common lex
     vars with PL_generation.
   
   * lvalue subs defeat common var detection, but they do at least
     return vars with a temporary ref count increment. Also, you can't
     tell at compile time whether a sub call is lvalue.
   
    
   So...
         
   A: There are a few circumstances where there definitely can't be any
     commonality:
   
       LHS empty:  () = (...);
       RHS empty:  (....) = ();
       RHS contains only constants or other 'can't possibly be shared'
           elements (e.g. ops that return PADTMPs):  (...) = (1,2, length)
           i.e. they only contain ops not marked as dangerous, whose children
           are also not dangerous;
       LHS ditto;
       LHS contains a single scalar element: e.g. ($x) = (....); because
           after $x has been modified, it won't be used again on the RHS;
       RHS contains a single element with no aggregate on LHS: e.g.
           ($a,$b,$c)  = ($x); again, once $a has been modified, its value
           won't be used again.
   
   B: If LHS are all 'my' lexical var declarations (or safe ops, which
     we can ignore):
   
       my ($a, $b, @c) = ...;
   
       Due to closure and goto tricks, these vars may already have content.
       For the same reason, an element on the RHS may be a lexical or package
       alias of one of the vars on the left, or share common elements, for
       example:
   
           my ($x,$y) = f(); # $x and $y on both sides
           sub f : lvalue { ($x,$y) = (1,2); $y, $x }
   
       and
   
           my $ra = f();
           my @a = @$ra;  # elements of @a on both sides
           sub f { @a = 1..4; \@a }
   
   
       First, just consider scalar vars on LHS:
   
           RHS is safe only if (A), or in addition,
               * contains only lexical *scalar* vars, where neither side's
                 lexicals have been flagged as aliases 
   
           If RHS is not safe, then it's always legal to check LHS vars for
           RC==1, since the only RHS aliases will always be associated
           with an RC bump.
   
           Note that in particular, RHS is not safe if:
   
               * it contains package scalar vars; e.g.:
   
                   f();
                   my ($x, $y) = (2, $x_alias);
                   sub f { $x = 1; *x_alias = \$x; }
   
               * It contains other general elements, such as flattened or
               * spliced or single array or hash elements, e.g.
   
                   f();
                   my ($x,$y) = @a; # or $a[0] or @a{@b} etc 
   
                   sub f {
                       ($x, $y) = (1,2);
                       use feature 'refaliasing';
                       \($a[0], $a[1]) = \($y,$x);
                   }
   
                 It doesn't matter if the array/hash is lexical or package.
   
               * it contains a function call that happens to be an lvalue
                 sub which returns one or more of the above, e.g.
   
                   f();
                   my ($x,$y) = f();
   
                   sub f : lvalue {
                       ($x, $y) = (1,2);
                       *x1 = \$x;
                       $y, $x1;
                   }
   
                   (so a sub call on the RHS should be treated the same
                   as having a package var on the RHS).
   
               * any other "dangerous" thing, such an op or built-in that
                 returns one of the above, e.g. pp_preinc
   
   
           If RHS is not safe, what we can do however is at compile time flag
           that the LHS are all my declarations, and at run time check whether
           all the LHS have RC == 1, and if so skip the full scan.
   
       Now consider array and hash vars on LHS: e.g. my (...,@a) = ...;
   
           Here the issue is whether there can be elements of @a on the RHS
           which will get prematurely freed when @a is cleared prior to
           assignment. This is only a problem if the aliasing mechanism
           is one which doesn't increase the refcount - only if RC == 1
           will the RHS element be prematurely freed.
   
           Because the array/hash is being INTROed, it or its elements
           can't directly appear on the RHS:
   
               my (@a) = ($a[0], @a, etc) # NOT POSSIBLE
   
           but can indirectly, e.g.:
   
               my $r = f();
               my (@a) = @$r;
               sub f { @a = 1..3; \@a }
   
           So if the RHS isn't safe as defined by (A), we must always
           mortalise and bump the ref count of any remaining RHS elements
           when assigning to a non-empty LHS aggregate.
   
           Lexical scalars on the RHS aren't safe if they've been involved in
           aliasing, e.g.
   
               use feature 'refaliasing';
   
               f();
               \(my $lex) = \$pkg;
               my @a = ($lex,3); # equivalent to ($a[0],3)
   
               sub f {
                   @a = (1,2);
                   \$pkg = \$a[0];
               }
   
           Similarly with lexical arrays and hashes on the RHS:
   
               f();
               my @b;
               my @a = (@b);
   
               sub f {
                   @a = (1,2);
                   \$b[0] = \$a[1];
                   \$b[1] = \$a[0];
               }
   
   
   
   C: As (B), but in addition the LHS may contain non-intro lexicals, e.g.
       my $a; ($a, my $b) = (....);
   
       The difference between (B) and (C) is that it is now physically
       possible for the LHS vars to appear on the RHS too, where they
       are not reference counted; but in this case, the compile-time
       PL_generation sweep will detect such common vars.
   
       So the rules for (C) differ from (B) in that if common vars are
       detected, the runtime "test RC==1" optimisation can no longer be used,
       and a full mark and sweep is required
   
   D: As (C), but in addition the LHS may contain package vars.
   
       Since package vars can be aliased without a corresponding refcount
       increase, all bets are off. It's only safe if (A). E.g.
   
           my ($x, $y) = (1,2);
   
           for $x_alias ($x) {
               ($x_alias, $y) = (3, $x); # whoops
           }
   
       Ditto for LHS aggregate package vars.
   
   E: Any other dangerous ops on LHS, e.g.
           (f(), $a[0], @$r) = (...);
   
       this is similar to (E) in that all bets are off. In addition, it's
       impossible to determine at compile time whether the LHS
       contains a scalar or an aggregate, e.g.
   
           sub f : lvalue { @a }
           (f()) = 1..3;

* ---------------------------------------------------------
*/


/* A set of bit flags returned by S_aassign_scan(). Each flag indicates
 * that at least one of the things flagged was seen.
 */

enum {
    AAS_MY_SCALAR       = 0x001, /* my $scalar */
    AAS_MY_AGG          = 0x002, /* aggregate: my @array or my %hash */
    AAS_LEX_SCALAR      = 0x004, /* $lexical */
    AAS_LEX_AGG         = 0x008, /* @lexical or %lexical aggregate */
    AAS_LEX_SCALAR_COMM = 0x010, /* $lexical seen on both sides */
    AAS_PKG_SCALAR      = 0x020, /* $scalar (where $scalar is pkg var) */
    AAS_PKG_AGG         = 0x040, /* package @array or %hash aggregate */
    AAS_DANGEROUS       = 0x080, /* an op (other than the above)
                                         that's flagged OA_DANGEROUS */
    AAS_SAFE_SCALAR     = 0x100, /* produces at least one scalar SV that's
                                        not in any of the categories above */
    AAS_DEFAV           = 0x200  /* contains just a single '@_' on RHS */
};



/*
=for apidoc aassign_padcheck
helper function for S_aassign_scan().

Check a PAD-related op for commonality and/or set its generation number.
Returns a boolean indicating whether its shared.
=cut
*/
static bool
S_aassign_padcheck(pTHX_ OP* o, bool rhs)
{
    PERL_ARGS_ASSERT_AASSIGN_PADCHECK;
    if (PAD_COMPNAME_GEN(o->op_targ) == PERL_INT_MAX)
        /* lexical used in aliasing */
        return TRUE;

    if (rhs)
        return cBOOL(PAD_COMPNAME_GEN(o->op_targ) == (STRLEN)PL_generation);
    else
        PAD_COMPNAME_GEN_set(o->op_targ, PL_generation);

    return FALSE;
}


/*
=for apidoc aassign_scan
Helper function for OPpASSIGN_COMMON* detection in rpeep().
It scans the left or right hand subtree of the aassign op, and returns a
set of flags indicating what sorts of things it found there.
'rhs' indicates whether we're scanning the LHS or RHS. If the former, we
set PL_generation on lexical vars; if the latter, we see if
PL_generation matches.

'top' indicates whether we're recursing or at the top level.
'scalars_p' is a pointer to a counter of the number of scalar SVs seen.
This fn will increment it by the number seen. It's not intended to
be an accurate count (especially as many ops can push a variable
number of SVs onto the stack); rather it's used as to test whether there
can be at most 1 SV pushed; so it's only meanings are "0, 1, many".
=cut
*/

static int
S_aassign_scan(pTHX_ OP* o, bool rhs, bool top, int *scalars_p)
{
    int flags = 0;
    bool kid_top = FALSE;
    PERL_ARGS_ASSERT_AASSIGN_SCAN;

    /* first, look for a solitary @_ on the RHS */
    if (   rhs
        && top
        && (OpKIDS(o))
        && OP_TYPE_IS_OR_WAS_NN(o, OP_LIST)
    ) {
        OP *kid = OpFIRST(o);
        if (   (   IS_TYPE(kid, PUSHMARK)
                || IS_TYPE(kid, PADRANGE)) /* ex-pushmark */
            && ((kid = OpSIBLING(kid)))
            && !OpHAS_SIBLING(kid)
            && IS_TYPE(kid, RV2AV)
            && !(kid->op_flags & OPf_REF)
            && !(kid->op_private & (OPpLVAL_INTRO|OPpMAYBE_LVSUB))
            && OpWANT_LIST(kid)
            && (kid = OpFIRST(kid))
            && IS_TYPE(kid, GV)
            && cGVOPx_gv(kid) == PL_defgv
        )
            flags |= AAS_DEFAV;
    }

    switch (o->op_type) {
    case OP_GVSV:
        (*scalars_p)++;
        return AAS_PKG_SCALAR;

    case OP_PADAV:
    case OP_PADHV:
        (*scalars_p) += 2;
        /* if !top, could be e.g. @a[0,1] */
        if (top && (o->op_flags & OPf_REF))
            return (o->op_private & OPpLVAL_INTRO)
                ? AAS_MY_AGG : AAS_LEX_AGG;
        return AAS_DANGEROUS;

    case OP_PADSV:
        {
            int comm = S_aassign_padcheck(aTHX_ o, rhs)
                        ?  AAS_LEX_SCALAR_COMM : 0;
            (*scalars_p)++;
            return (o->op_private & OPpLVAL_INTRO)
                ? (AAS_MY_SCALAR|comm) : (AAS_LEX_SCALAR|comm);
        }

    case OP_RV2AV:
    case OP_RV2HV:
        (*scalars_p) += 2;
        if (ISNT_TYPE(OpFIRST(o), GV))
            return AAS_DANGEROUS; /* @{expr}, %{expr} */
        /* @pkg, %pkg */
        /* if !top, could be e.g. @a[0,1] */
        if (top && (o->op_flags & OPf_REF))
            return AAS_PKG_AGG;
        return AAS_DANGEROUS;

    case OP_RV2SV:
        (*scalars_p)++;
        if (ISNT_TYPE(OpFIRST(o), GV)) {
            (*scalars_p) += 2;
            return AAS_DANGEROUS; /* ${expr} */
        }
        return AAS_PKG_SCALAR; /* $pkg */

    case OP_SPLIT:
        if (o->op_private & OPpSPLIT_ASSIGN) {
            /* the assign in @a = split() has been optimised away
             * and the @a attached directly to the split op
             * Treat the array as appearing on the RHS, i.e.
             *    ... = (@a = split)
             * is treated like
             *    ... = @a;
             */

            if (o->op_flags & OPf_STACKED)
                /* @{expr} = split() - the array expression is tacked
                 * on as an extra child to split - process kid */
                return S_aassign_scan(aTHX_ cLISTOPo->op_last, rhs,
                                        top, scalars_p);

            /* ... else array is directly attached to split op */
            (*scalars_p) += 2;
            if (PL_op->op_private & OPpSPLIT_LEX)
                return (o->op_private & OPpLVAL_INTRO)
                    ? AAS_MY_AGG : AAS_LEX_AGG;
            else
                return AAS_PKG_AGG;
        }
        (*scalars_p)++;
        /* other args of split can't be returned */
        return AAS_SAFE_SCALAR;

    case OP_UNDEF:
        /* undef counts as a scalar on the RHS:
         *   (undef, $x) = ...;         # only 1 scalar on LHS: always safe
         *   ($x, $y)    = (undef, $x); # 2 scalars on RHS: unsafe
         */
        if (rhs)
            (*scalars_p)++;
        flags = AAS_SAFE_SCALAR;
        break;

    case OP_PUSHMARK:
    case OP_STUB:
        /* these are all no-ops; they don't push a potentially common SV
         * onto the stack, so they are neither AAS_DANGEROUS nor
         * AAS_SAFE_SCALAR */
        return 0;

    case OP_PADRANGE: /* Ignore padrange; checking its siblings is enough */
        break;

    case OP_NULL:
    case OP_LIST:
        /* these do nothing but may have children; but their children
         * should also be treated as top-level */
        kid_top = top;
        break;

    default:
        if (PL_opargs[o->op_type] & OA_DANGEROUS) {
            (*scalars_p) += 2;
            flags = AAS_DANGEROUS;
            break;
        }

        if (   OP_HAS_TARGLEX(o->op_type)
            && (o->op_private & OPpTARGET_MY))
        {
            (*scalars_p)++;
            return S_aassign_padcheck(aTHX_ o, rhs)
                ? AAS_LEX_SCALAR_COMM : AAS_LEX_SCALAR;
        }

        /* if its an unrecognised, non-dangerous op, assume that it
         * it the cause of at least one safe scalar */
        (*scalars_p)++;
        flags = AAS_SAFE_SCALAR;
        break;
    }

    /* XXX this assumes that all other ops are "transparent" - i.e. that
     * they can return some of their children. While this true for e.g.
     * sort and grep, it's not true for e.g. map. We really need a
     * 'transparent' flag added to regen/opcodes
     */
    if (OpKIDS(o)) {
        OP *kid;
        for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid))
            flags |= S_aassign_scan(aTHX_ kid, rhs, kid_top, scalars_p);
    }
    return flags;
}


/*
=for apidoc s||	  inplace_aassign	|NN OP* o
Check for in place reverse and sort assignments like "@a = reverse @a"
and modify the optree to make them work inplace.

=cut
*/
static void
S_inplace_aassign(pTHX_ OP *o) {

    OP *modop, *modop_pushmark;
    OP *oright;
    OP *oleft, *oleft_pushmark;

    PERL_ARGS_ASSERT_INPLACE_AASSIGN;

    assert(OpWANT_VOID(o));

    assert(IS_NULL_OP(OpFIRST(o)));
    modop_pushmark = OpFIRST(OpFIRST(o));
    assert(IS_TYPE(modop_pushmark, PUSHMARK));
    modop = OpSIBLING(modop_pushmark);

    if (ISNT_TYPE(modop, SORT) &&
        ISNT_TYPE(modop, REVERSE))
	return;

    /* no other operation except sort/reverse */
    if (OpHAS_SIBLING(modop))
	return;

    assert(IS_TYPE(OpFIRST(modop), PUSHMARK));
    if (!(oright = OpSIBLING(OpFIRST(modop)))) return;

    if (OpSTACKED(modop)) {
	/* skip sort subroutine/block */
	assert(IS_NULL_OP(oright));
	oright = OpSIBLING(oright);
    }

    assert(IS_NULL_OP(OpSIBLING(OpFIRST(o))));
    oleft_pushmark = OpFIRST(OpSIBLING(OpFIRST(o)));
    assert(IS_TYPE(oleft_pushmark, PUSHMARK));
    oleft = OpSIBLING(oleft_pushmark);

    /* Check the lhs is an array */
    if (!oleft ||
	(ISNT_TYPE(oleft, RV2AV) &&
         ISNT_TYPE(oleft, PADAV))
	|| OpHAS_SIBLING(oleft)
	|| (oleft->op_private & OPpLVAL_INTRO)
    )
	return;

    /* Only one thing on the rhs */
    if (OpHAS_SIBLING(oright))
	return;

    /* check the array is the same on both sides */
    if (IS_TYPE(oleft, RV2AV)) {
	if (ISNT_TYPE(oright, RV2AV)
	    || !OpFIRST(oright)
	    || ISNT_TYPE(OpFIRST(oright), GV)
            || ISNT_TYPE(OpFIRST(oleft), GV)
	    || cGVOPx_gv(OpFIRST(oleft)) != cGVOPx_gv(OpFIRST(oright))
	)
	    return;
    }
    else if (ISNT_TYPE(oright, PADAV)
	|| oright->op_targ != oleft->op_targ
    )
	return;

    /* This actually is an inplace assignment */

    modop->op_private |= OPpSORT_INPLACE;

    /* transfer MODishness etc from LHS arg to RHS arg */
    oright->op_flags = oleft->op_flags;

    /* remove the aassign op and the lhs */
    op_null(o);
    op_null(oleft_pushmark);
    if (IS_TYPE(oleft, RV2AV) && OpFIRST(oleft))
	op_null(OpFIRST(oleft));
    op_null(oleft);
}


/*
=for apidoc maybe_multideref

Given an op_next chain of ops beginning at 'start'
that potentially represent a series of one or more aggregate derefs
(such as $a->[1]{$key}), examine the chain, and if appropriate, convert
the whole chain to a single OP_MULTIDEREF op (maybe with a few
additional ops left in too).

The caller will have already verified that the first few ops in the
chain following 'start' indicate a multideref candidate, and will have
set 'orig_o' to the point further on in the chain where the first index
expression (if any) begins.  'orig_action' specifies what type of
beginning has already been determined by the ops between start..orig_o
(e.g.  $lex_ary[], $pkg_ary->{}, expr->[], etc).

'hints' contains any hints flags that need adding (currently just
OPpHINT_STRICT_REFS) as found in any rv2av/hv skipped by the caller.
=cut
*/
static void
S_maybe_multideref(pTHX_ OP *start, OP *orig_o, UV orig_action, U8 hints)
{
    dVAR;
    UNOP_AUX_item *arg_buf = NULL;
    int pass;
    int index_skip         = -1;    /* don't output index arg on this action */
    bool reset_start_targ  = FALSE; /* start->op_targ needs zeroing */
    PERL_ARGS_ASSERT_MAYBE_MULTIDEREF;

    /* similar to regex compiling, do two passes; the first pass
     * determines whether the op chain is convertible and calculates the
     * buffer size; the second pass populates the buffer and makes any
     * changes necessary to ops (such as moving consts to the pad on
     * threaded builds).
     *
     * NB: for things like Coverity, note that both passes take the same
     * path through the logic tree (except for 'if (pass)' bits), since
     * both passes are following the same op_next chain; and in
     * particular, if it would return early on the second pass, it would
     * already have returned early on the first pass.
     */
#undef PASS2
#define PASS2 pass
    for (pass = 0; pass < 2; pass++) {
        OP *o                = orig_o;
        UV action            = orig_action;
        OP *first_elem_op    = NULL;  /* first seen aelem/helem */
        OP *top_op           = NULL;  /* highest [ah]elem/exists/del/rv2[ah]v */
        UNOP_AUX_item *arg        = arg_buf;
        UNOP_AUX_item *action_ptr = arg_buf;
        int action_count     = 0;     /* number of actions seen so far */
        int action_ix        = 0;     /* action_count % (actions per IV) */
        bool next_is_hash    = FALSE; /* is the next lookup to be a hash? */
        bool is_last         = FALSE; /* no more derefs to follow */
        bool maybe_aelemfast = FALSE; /* we can replace with aelemfast? */

        if (PASS2)
            action_ptr->uv = 0;
        arg++;

        switch (action) {
        case MDEREF_HV_gvsv_vivify_rv2hv_helem:
        case MDEREF_HV_gvhv_helem:
            next_is_hash = TRUE;
            /* FALLTHROUGH */
        case MDEREF_AV_gvsv_vivify_rv2av_aelem:
        case MDEREF_AV_gvav_aelem:
            if (PASS2) {
#ifdef USE_ITHREADS
                arg->pad_offset = cPADOPx(start)->op_padix;
                /* stop it being swiped when nulled */
                cPADOPx(start)->op_padix = 0;
#else
                arg->sv = cSVOPx(start)->op_sv;
                cSVOPx(start)->op_sv = NULL;
#endif
            }
            arg++;
            break;

        case MDEREF_HV_padhv_helem:
        case MDEREF_HV_padsv_vivify_rv2hv_helem:
            next_is_hash = TRUE;
            /* FALLTHROUGH */
        case MDEREF_AV_padav_aelem:
        case MDEREF_AV_padsv_vivify_rv2av_aelem:
            if (PASS2) {
                arg->pad_offset = start->op_targ;
                /* we skip setting op_targ = 0 for now, since the intact
                 * OP_PADXV is needed by S_check_hash_fields_and_hekify */
                reset_start_targ = TRUE;
            }
            arg++;
            break;

        case MDEREF_HV_pop_rv2hv_helem:
            next_is_hash = TRUE;
            /* FALLTHROUGH */
        case MDEREF_AV_pop_rv2av_aelem:
            break;

        default:
            NOT_REACHED; /* NOTREACHED */
            return;
        }

        while (!is_last) {
            /* look for another (rv2av/hv; get index;
             * aelem/helem/exists/delete) sequence */

            OP *kid;
            UV index_type = MDEREF_INDEX_none;
            bool is_deref;
            bool ok;

            if (action_count) {
                /* if this is not the first lookup, consume the rv2av/hv  */

                /* for N levels of aggregate lookup, we normally expect
                 * that the first N-1 [ah]elem ops will be flagged as
                 * /DEREF (so they autovivifiy if necessary), and the last
                 * lookup op not to be.
                 * For other things (like @{$h{k1}{k2}}) extra scope or
                 * leave ops can appear, so abandon the effort in that
                 * case */
                if (ISNT_TYPE(o, RV2AV) && ISNT_TYPE(o, RV2HV)) {
                    if (arg_buf)
                        PerlMemShared_free(arg_buf);
                    return;
                }

                /* rv2av or rv2hv sKR/1 */

                ASSUME(!(o->op_flags & ~(OPf_WANT|OPf_KIDS|OPf_PARENS
                                            |OPf_REF|OPf_MOD|OPf_SPECIAL)));
                if (o->op_flags != (OPf_WANT_SCALAR|OPf_KIDS|OPf_REF)) {
                    if (arg_buf)
                        PerlMemShared_free(arg_buf);
                    return;
                }

                /* at this point, we wouldn't expect any of these
                 * possible private flags:
                 * OPpMAYBE_LVSUB, OPpOUR_INTRO, OPpLVAL_INTRO
                 * OPpTRUEBOOL, OPpMAYBE_TRUEBOOL (rv2hv only)
                 */
                ASSUME(!(o->op_private &
                    ~(OPpHINT_STRICT_REFS|OPpARG1_MASK|OPpSLICEWARNING)));

                hints = (o->op_private & OPpHINT_STRICT_REFS);

                /* make sure the type of the previous /DEREF matches the
                 * type of the next lookup */
                ASSUME(o->op_type == (next_is_hash ? OP_RV2HV : OP_RV2AV));
                top_op = o;

                action = next_is_hash
                            ? MDEREF_HV_vivify_rv2hv_helem
                            : MDEREF_AV_vivify_rv2av_aelem;
                o = OpNEXT(o);
            }

            /* if this is the second pass, and we're at the depth where
             * previously we encountered a non-simple index expression,
             * stop processing the index at this point */
            if (action_count != index_skip) {

                /* look for one or more simple ops that return an array
                 * index or hash key */

                switch (o->op_type) {
                case OP_PADSV:
                    /* it may be a lexical var index */
                    ASSUME(!(o->op_flags & ~(OPf_WANT|OPf_PARENS
                                            |OPf_REF|OPf_MOD|OPf_SPECIAL)));
                    ASSUME(!(o->op_private &
                            ~(OPpPAD_STATE|OPpDEREF|OPpLVAL_INTRO)));

                    if (   OP_GIMME_SCALAR(o)
                        && !(o->op_flags & (OPf_REF|OPf_MOD))
                        && o->op_private == 0)
                    {
                        index_type = MDEREF_INDEX_padsv;
                        if (PASS2) {
                            arg->pad_offset = o->op_targ;
                            /* you can get here via loop oob elimination */
                            if (IS_TYPE(OpNEXT(o), AELEM_U))
                                index_type |= MDEREF_INDEX_uoob;
                        }
                        arg++;
                        o = OpNEXT(o);
                    }
                    break;

                case OP_CONST:
                    if (next_is_hash) {
                        /* it's a constant hash index */
                        if (!(SvFLAGS(cSVOPo_sv) & (SVf_IOK|SVf_NOK|SVf_POK)))
                            /* "use constant foo => FOO; $h{+foo}" for
                             * some weird FOO, can leave you with constants
                             * that aren't simple strings. It's not worth
                             * the extra hassle for those edge cases */
                            break;

                        if (PASS2) {
                            UNOP *rop = NULL;
                            OP * helem_op = OpNEXT(o);

                            ASSUME(   IS_TYPE(helem_op, HELEM)
                                   || IS_NULL_OP(helem_op));
                            if (IS_TYPE(helem_op, HELEM)) {
                                rop = (UNOP*)OpFIRST(helem_op);
                                if (helem_op->op_private & OPpLVAL_INTRO
                                    || ISNT_TYPE(rop, RV2HV))
                                    rop = NULL;
                            }
                            /* is $self->{field} -> aelemfast_lex_u */
#if 0
                            if (PL_parser->in_class && start->op_targ == 1) {
                                ; /* TODO: get class and check if key is a field */
                            }
#endif
                            S_check_hash_fields_and_hekify(aTHX_ rop, cSVOPo);

#ifdef USE_ITHREADS
                            /* Relocate sv to the pad for thread safety */
                            op_relocate_sv(&cSVOPo->op_sv, &o->op_targ);
                            arg->pad_offset = o->op_targ;
                            o->op_targ = 0;
#else
                            arg->sv = cSVOPx_sv(o);
#endif
                        }
                    }
                    else {
                        /* it's a constant array index */
                        IV iv;
                        SV *ix_sv = cSVOPo->op_sv;
                        if (!SvIOK(ix_sv))
                            break;
                        iv = SvIV(ix_sv);

                        if (   action_count == 0
                            && iv >= -128
                            && iv <= 127
                            && (   action == MDEREF_AV_padav_aelem
                                || action == MDEREF_AV_gvav_aelem)
                           ) /* but still need to check for valid op_private */
                            maybe_aelemfast = TRUE;

                        if (PASS2) {
                            if (UNLIKELY(SvIsUV(ix_sv))) {
                                UV ix = SvUV(ix_sv);
                                if (ix > SSize_t_MAX)
                                    Perl_die(aTHX_ "Too many elements");
                            }
                            arg->iv = iv;
                            SvREFCNT_dec_NN(cSVOPo->op_sv);
                        }
                    }
                    index_type = MDEREF_INDEX_const;
                    if (PASS2) {
                        OP *aelem_op = OpNEXT(o);
                        if (IS_TYPE(aelem_op, AELEM_U)) {
                            index_type |= MDEREF_INDEX_uoob;
                        } else if (IS_TYPE(aelem_op, AELEM)) {
                            PADOFFSET targ = OpFIRST(aelem_op)->op_targ;
                            SV* av; /* targ may still be empty here */
                            if (targ
                                && (av = pad_findmy_real(targ, PL_compcv))
                                && AvSHAPED(av)) {
                                if (UNLIKELY(SvIsUV(cSVOPo->op_sv))) {
                                    UV ix = SvUV(cSVOPo->op_sv);
                                    if (ix > (UV)AvFILLp(av))
                                        Perl_die(aTHX_ "Too many elements");
                                    else {
                                        DEBUG_kv(Perl_deb(aTHX_
                                            "mderef %s[%" UVuf "] shape ok -> uoob\n",
                                            PAD_COMPNAME_PV(targ), ix));
                                    }
                                }
                                else if (UNLIKELY(PERL_IABS(arg->iv) > AvFILLp(av)))
                                    Perl_die(aTHX_ "Array index out of bounds %s[%" IVdf "]",
                                             PAD_COMPNAME_PV(targ), arg->iv);
                                else {
                                    DEBUG_kv(Perl_deb(aTHX_
                                        "mderef %s[%" IVdf "] shape ok -> uoob\n",
                                        PAD_COMPNAME_PV(targ), arg->iv));
                                }
                                index_type |= MDEREF_INDEX_uoob;
                            }
                        }
                        /* we've taken ownership of the SV */
                        cSVOPo->op_sv = NULL;
                    }
                    arg++;
                    o = OpNEXT(o);
                    break;

                case OP_GV:
                    /* it may be a package var index */

                    ASSUME(!(o->op_flags & ~(OPf_WANT|OPf_PARENS|OPf_SPECIAL)));
                    ASSUME(!(o->op_private & ~(OPpEARLY_CV)));
                    if (  (o->op_flags & ~(OPf_PARENS|OPf_SPECIAL)) != OPf_WANT_SCALAR
                        || o->op_private != 0
                    )
                        break;

                    kid = OpNEXT(o);
                    if (ISNT_TYPE(kid, RV2SV))
                        break;

                    ASSUME(!(kid->op_flags &
                            ~(OPf_WANT|OPf_KIDS|OPf_MOD|OPf_REF
                             |OPf_SPECIAL|OPf_PARENS)));
                    ASSUME(!(kid->op_private &
                                    ~(OPpARG1_MASK
                                     |OPpHINT_STRICT_NAMES
                                     |OPpHINT_STRICT_REFS|OPpOUR_INTRO
                                     |OPpDEREF|OPpLVAL_INTRO)));
                    if(   (kid->op_flags &~ OPf_PARENS)
                            != (OPf_WANT_SCALAR|OPf_KIDS)
                       || (kid->op_private &
                           ~(OPpARG1_MASK|HINT_STRICT_REFS|OPpHINT_STRICT_NAMES))
                    )
                        break;

                    if (PASS2) {
#ifdef USE_ITHREADS
                        arg->pad_offset = cPADOPx(o)->op_padix;
                        /* stop it being swiped when nulled */
                        cPADOPx(o)->op_padix = 0;
#else
                        arg->sv = cSVOPx(o)->op_sv;
                        cSVOPo->op_sv = NULL;
#endif
                    }
                    arg++;
                    index_type = MDEREF_INDEX_gvsv;
                    o = OpNEXT(kid);
                    break;

                } /* switch */
            } /* action_count != index_skip */

            action |= index_type;

            /* at this point we have either:
             *   * detected what looks like a simple index expression,
             *     and expect the next op to be an [ah]elem, or
             *     an nulled  [ah]elem followed by a delete or exists;
             *  * found a more complex expression, so something other
             *    than the above follows.
             */

            /* possibly an optimised away [ah]elem (where op_next is
             * exists or delete) */
            if (IS_NULL_OP(o))
                o = OpNEXT(o);

            /* at this point we're looking for an OP_AELEM, OP_HELEM,
             * OP_EXISTS or OP_DELETE */

            /* if something like arybase (a.k.a $[ ) is in scope,
             * abandon optimisation attempt */
            /* similarly for customised exists and delete with
               use autovivication */
            if (UNLIKELY
                  (   (IS_TYPE(o, AELEM)  && PL_check[o->op_type] != Perl_ck_aelem)
                   || (IS_TYPE(o, EXISTS) && PL_check[o->op_type] != Perl_ck_exists)
                   || (IS_TYPE(o, DELETE) && PL_check[o->op_type] != Perl_ck_delete))) {
                if (arg_buf)
                    PerlMemShared_free(arg_buf);
                return;
            }

            /* skip aelemfast if private cannot hold all bits */
            if ( (ISNT_TYPE(o, AELEM) && ISNT_TYPE(o, AELEM_U))
                 || (o->op_private &
                     (OPpLVAL_INTRO|OPpLVAL_DEFER|OPpDEREF|OPpMAYBE_LVSUB)))
                maybe_aelemfast = FALSE;

            /* look for aelem/helem/exists/delete. If it's not the last elem
             * lookup, it *must* have OPpDEREF_AV/HV, but not many other
             * flags; if it's the last, then it mustn't have
             * OPpDEREF_AV/HV, but may have lots of other flags, like
             * OPpLVAL_INTRO etc
             */

            if (   index_type == MDEREF_INDEX_none
                   || (ISNT_TYPE(o, AELEM)
                    && ISNT_TYPE(o, AELEM_U)
                    && ISNT_TYPE(o, HELEM)
                    && ISNT_TYPE(o, EXISTS)
                    && ISNT_TYPE(o, DELETE))
            )
                ok = FALSE;
            else {
                /* we have aelem/helem/exists/delete with valid simple index */

                is_deref = (IS_TYPE(o, AELEM)
                         || IS_TYPE(o, AELEM_U)
                         || IS_TYPE(o, HELEM))
                           && (   (o->op_private & OPpDEREF) == OPpDEREF_AV
                               || (o->op_private & OPpDEREF) == OPpDEREF_HV);

                /* This doesn't make much sense but is legal:
                 *    @{ local $x[0][0] } = 1
                 * Since scope exit will undo the autovivification,
                 * don't bother in the first place. The OP_LEAVE
                 * assertion is in case there are other cases of both
                 * OPpLVAL_INTRO and OPpDEREF which don't include a scope
                 * exit that would undo the local - in which case this
                 * block of code would need rethinking.
                 */
                if (is_deref && (o->op_private & OPpLVAL_INTRO)) {
#ifdef DEBUGGING
                    OP *n = OpNEXT(o);
                    while (n && (  n->op_type == OP_NULL
                                || n->op_type == OP_LIST))
                        n = OpNEXT(n);
                    assert(n && n->op_type == OP_LEAVE);
#endif
                    o->op_private &= ~OPpDEREF;
                    is_deref = FALSE;
                }

                if (is_deref) {
                    ASSUME(!(o->op_flags &
                                 ~(OPf_WANT|OPf_KIDS|OPf_MOD|OPf_PARENS)));
                    ASSUME(!(o->op_private & ~(OPpARG2_MASK|OPpDEREF)));

                    ok =    (o->op_flags &~ OPf_PARENS)
                               == (OPf_WANT_SCALAR|OPf_KIDS|OPf_MOD)
                         && !(o->op_private & ~(OPpDEREF|OPpARG2_MASK));
                }
                else if (IS_TYPE(o, EXISTS)) {
                    ASSUME(!(o->op_flags & ~(OPf_WANT|OPf_KIDS|OPf_PARENS
                                |OPf_REF|OPf_MOD|OPf_SPECIAL)));
                    ASSUME(!(o->op_private & ~(OPpARG1_MASK|OPpEXISTS_SUB)));
                    ok =  !(o->op_private & ~OPpARG1_MASK);
                }
                else if (IS_TYPE(o, DELETE)) {
                    ASSUME(!(o->op_flags & ~(OPf_WANT|OPf_KIDS|OPf_PARENS
                                |OPf_REF|OPf_MOD|OPf_SPECIAL)));
                    ASSUME(!(o->op_private &
                                    ~(OPpARG1_MASK|OPpSLICE|OPpLVAL_INTRO)));
                    /* don't handle slices or 'local delete'; the latter
                     * is fairly rare, and has a complex runtime */
                    ok =  !(o->op_private & ~OPpARG1_MASK);
                    if (OP_TYPE_IS_OR_WAS(OpFIRST(o), OP_AELEM))
                        /* skip handling run-time error */
                        ok = (ok && cBOOL(OpSPECIAL(o)));
                }
                else {
                    ASSUME(IS_TYPE(o, AELEM) || IS_TYPE(o, AELEM_U) || IS_TYPE(o, HELEM));
                    ASSUME(!(o->op_flags & ~(OPf_WANT|OPf_KIDS|OPf_MOD
                                            |OPf_PARENS|OPf_REF|OPf_SPECIAL)));
                    ASSUME(!(o->op_private & ~(OPpARG2_MASK|OPpMAYBE_LVSUB
                                    |OPpLVAL_DEFER|OPpDEREF|OPpLVAL_INTRO)));
                    ok = (o->op_private & OPpDEREF) != OPpDEREF_SV;
                    if (PASS2 && IS_TYPE(o, AELEM_U))
                        action |= MDEREF_INDEX_uoob;
                }
            }

            if (ok) {
                if (!first_elem_op)
                    first_elem_op = o;
                top_op = o;
                if (is_deref) {
                    next_is_hash = cBOOL((o->op_private & OPpDEREF) == OPpDEREF_HV);
                    o = OpNEXT(o);
                }
                else {
                    is_last = TRUE;
                    action |= MDEREF_FLAG_last;
                }
            }
            else {
                /* at this point we have something that started
                 * promisingly enough (with rv2av or whatever), but failed
                 * to find a simple index followed by an
                 * aelem/helem/exists/delete. If this is the first action,
                 * give up; but if we've already seen at least one
                 * aelem/helem, then keep them and add a new action with
                 * MDEREF_INDEX_none, which causes it to do the vivify
                 * from the end of the previous lookup, and do the deref,
                 * but stop at that point. So $a[0][expr] will do one
                 * av_fetch, vivify and deref, then continue executing at
                 * expr */
                if (!action_count) {
                    DEBUG_kv(Perl_deb(aTHX_ "no multideref: %s %s\n",
                                      OP_NAME(start), OP_NAME(o)));
                    if (arg_buf)
                        PerlMemShared_free(arg_buf);
                    return;
                }
                is_last = TRUE;
                index_skip = action_count;
                action |= MDEREF_FLAG_last;
                if (index_type != MDEREF_INDEX_none)
                    arg--;
            }

            if (PASS2)
                action_ptr->uv |= (action << (action_ix * MDEREF_SHIFT));
            action_ix++;
            action_count++;
            /* if there's no space for the next action, create a new slot
             * for it *before* we start adding args for that action */
            if ((action_ix + 1) * MDEREF_SHIFT > UVSIZE*8) {
                action_ptr = arg;
                if (PASS2)
                    arg->uv = 0;
                arg++;
                action_ix = 0;
            }
        } /* while !is_last */

        /* success! */
        if (PASS2) {
            OP *mderef;
            OP *p, *q;

            mderef = newUNOP_AUX(OP_MULTIDEREF, 0, NULL, arg_buf);
            if (index_skip == -1) {
                mderef->op_flags = o->op_flags
                        & (OPf_WANT|OPf_MOD|(next_is_hash ? OPf_SPECIAL : 0));
                if (IS_TYPE(o, EXISTS))
                    mderef->op_private = OPpMULTIDEREF_EXISTS;
                else if (IS_TYPE(o, DELETE))
                    mderef->op_private = OPpMULTIDEREF_DELETE;
                else
                    mderef->op_private = o->op_private
                        & (OPpMAYBE_LVSUB|OPpLVAL_DEFER|OPpLVAL_INTRO);
            }
            /* accumulate strictness from every level (although I don't think
             * they can actually vary) */
            mderef->op_private |= hints;

            /* integrate the new multideref op into the optree and the
             * op_next chain.
             *
             * In general an op like aelem or helem has two child
             * sub-trees: the aggregate expression (a_expr) and the
             * index expression (i_expr):
             *
             *     aelem
             *       |
             *     a_expr - i_expr
             *
             * The a_expr returns an AV or HV, while the i-expr returns an
             * index. In general a multideref replaces most or all of a
             * multi-level tree, e.g.
             *
             *     exists
             *       |
             *     ex-aelem
             *       |
             *     rv2av  - i_expr1
             *       |
             *     helem
             *       |
             *     rv2hv  - i_expr2
             *       |
             *     aelem
             *       |
             *     a_expr - i_expr3
             *
             * With multideref, all the i_exprs will be simple vars or
             * constants, except that i_expr1 may be arbitrary in the case
             * of MDEREF_INDEX_none.
             *
             * The bottom-most a_expr will be either:
             *   1) a simple var (so padXv or gv+rv2Xv);
             *   2) a simple scalar var dereferenced (e.g. $r->[0]):
             *      so a simple var with an extra rv2Xv;
             *   3) or an arbitrary expression.
             *
             * 'start', the first op in the execution chain, will point to
             *   1),2): the padXv or gv op;
             *   3):    the rv2Xv which forms the last op in the a_expr
             *          execution chain, and the top-most op in the a_expr
             *          subtree.
             *
             * For all cases, the 'start' node is no longer required,
             * but we can't free it since one or more external nodes
             * may point to it. E.g. consider
             *     $h{foo} = $a ? $b : $c
             * Here, both the op_next and op_other branches of the
             * cond_expr point to the gv[*h] of the hash expression, so
             * we can't free the 'start' op.
             *
             * For expr->[...], we need to save the subtree containing the
             * expression; for the other cases, we just need to save the
             * start node.
             * So in all cases, we null the start op and keep it around by
             * making it the child of the multideref op; for the expr->
             * case, the expr will be a subtree of the start node.
             *
             * So in the simple 1,2 case the  optree above changes to
             *
             *     ex-exists
             *       |
             *     multideref
             *       |
             *     ex-gv (or ex-padxv)
             *
             *  with the op_next chain being
             *
             *  -> ex-gv -> multideref -> op-following-ex-exists ->
             *
             *  In the 3 case, we have
             *
             *     ex-exists
             *       |
             *     multideref
             *       |
             *     ex-rv2xv
             *       |
             *    rest-of-a_expr
             *      subtree
             *
             *  and
             *
             *  -> rest-of-a_expr subtree ->
             *    ex-rv2xv -> multideref -> op-following-ex-exists ->
             *
             *
             * Where the last i_expr is non-simple (i.e. MDEREF_INDEX_none,
             * e.g. $a[0]{foo}[$x+1], the next rv2xv is nulled and the
             * multideref attached as the child, e.g.
             *
             *     exists
             *       |
             *     ex-aelem
             *       |
             *     ex-rv2av  - i_expr1
             *       |
             *     multideref
             *       |
             *     ex-whatever
             *
             */

            /* if we free this op, don't free the pad entry */
            if (reset_start_targ)
                start->op_targ = 0;


            /* Cut the bit we need to save out of the tree and attach to
             * the multideref op, then free the rest of the tree */

            /* find parent of node to be detached (for use by splice) */
            p = first_elem_op;
            if (   orig_action == MDEREF_AV_pop_rv2av_aelem
                || orig_action == MDEREF_HV_pop_rv2hv_helem)
            {
                /* there is an arbitrary expression preceding us, e.g.
                 * expr->[..]? so we need to save the 'expr' subtree */
                if (IS_TYPE(p, EXISTS) || IS_TYPE(p, DELETE))
                    p = OpFIRST(p);
                ASSUME( IS_TYPE(start, RV2AV)
                     || IS_TYPE(start, RV2HV));
            }
            else {
                /* either a padXv or rv2Xv+gv, maybe with an ex-Xelem
                 * above for exists/delete. */
                while (OpKIDS(p) && OpFIRST(p) != start)
                    p = OpFIRST(p);
            }
            ASSUME(OpFIRST(p) == start);

            /* detach from main tree, and re-attach under the multideref */
            op_sibling_splice(mderef, NULL, 0,
                    op_sibling_splice(p, NULL, 1, NULL));
            op_null(start);

            OpNEXT(start) = mderef;
            OpNEXT(mderef) = index_skip == -1 ? OpNEXT(o) : o;

            /* excise and free the original tree, and replace with
             * the multideref op */
            p = op_sibling_splice(top_op, NULL, -1, mderef);
            while (p) {
                q = OpSIBLING(p);
                op_free(p);
                p = q;
            }
            op_null(top_op);
        }
        else {
            Size_t size = arg - arg_buf;

            if (maybe_aelemfast && action_count == 1) {
                DEBUG_kv(Perl_deb(aTHX_ "no multideref %s = > aelemfast\n",
                                  OP_NAME(start)));
                if (arg_buf)
                    PerlMemShared_free(arg_buf);
                return;
            }

            arg_buf = (UNOP_AUX_item*)PerlMemShared_malloc(
                                sizeof(UNOP_AUX_item) * (size + 1));
            /* for dumping etc: store the length in a hidden first slot;
             * we set the op_aux pointer to the second slot */
            arg_buf->uv = size;
            arg_buf++;
        }
    } /* for (pass = ...) */
    DEBUG_kv(Perl_deb(aTHX_ "=> multideref %s %s\n", PL_op_name[start->op_targ],
                      SvPVX(multideref_stringify(OpNEXT(start), NULL))));
#undef PASS2
}

/*
=for apidoc mderef_uoob_targ
check the targ of the first INDEX_padsv of a MDEREF_AV,
compare it with the given targ, and set INDEX_uoob.
=cut
*/
static bool
S_mderef_uoob_targ(pTHX_ OP* o, PADOFFSET targ)
{
    UNOP_AUX_item *items = cUNOP_AUXx(o)->op_aux;
    UV actions = items->uv;
    /* the pad action must be the first */
    int action = actions & MDEREF_ACTION_MASK;
    PERL_ARGS_ASSERT_MDEREF_UOOB_TARG;
    assert(action);
    if ( (action == MDEREF_AV_padav_aelem
       || action == MDEREF_AV_padsv_vivify_rv2av_aelem
#ifdef USE_ITHREADS
       || action == MDEREF_AV_gvav_aelem
       || action == MDEREF_AV_gvsv_vivify_rv2av_aelem
#endif
          )
        && ((actions & MDEREF_INDEX_MASK) == MDEREF_INDEX_padsv)
        && items->pad_offset == targ)
    {
        actions |= MDEREF_INDEX_uoob;
        return TRUE;
    }
    return FALSE;
}

#ifndef USE_ITHREADS
/*
=for apidoc mderef_uoob_gvsv
check the key index sv of the first INDEX_gvsv of a MDEREF_AV,
compare it with the given key, and set INDEX_uoob.

Only available without threads. Threaded perls use L</mderef_uoob_targ> instead.
=cut
*/
static bool
S_mderef_uoob_gvsv(pTHX_ OP* o, SV* idx)
{
    UNOP_AUX_item *items = cUNOP_AUXx(o)->op_aux;
    UV actions = items->uv;
    /* the gvsv action must be the first */
    int action = actions & MDEREF_ACTION_MASK;
    PERL_ARGS_ASSERT_MDEREF_UOOB_GVSV;
    assert(actions);
    if ( (action == MDEREF_AV_gvav_aelem
       || action == MDEREF_AV_gvsv_vivify_rv2av_aelem)
        && ((actions & MDEREF_INDEX_MASK) == MDEREF_INDEX_gvsv)
        && UNOP_AUX_item_sv(items) == idx)
    {
        actions |= MDEREF_INDEX_uoob;
        return TRUE;
    }
    return FALSE;
}
#endif

/*
=for apidoc peep_leaveloop

check loop bounds and possibly turn aelem/mderef/aelemfast_lex into an unchecked faster
aelem_u.

1) if index bound to size/arylen, optimize to unchecked aelem_u
   variants, even without parametrized typed.  need to check the right
   array, and if the loop index is used as is, or within an
   expression.

2) with static bounds check unrolling.

3) with static ranges and shaped arrays, can possibly optimize to aelem_u

Returns TRUE when some op was changed.

=cut
*/
static bool
S_peep_leaveloop(pTHX_ BINOP* leave, OP* from, OP* to)
{
    dVAR;
    SV *fromsv, *tosv;
    IV maxto = 0;
    bool changed = FALSE;
    PERL_ARGS_ASSERT_PEEP_LEAVELOOP;

    if (IS_CONST_OP(from) && IS_CONST_OP(to)
        && SvIOK(fromsv = cSVOPx_sv(from)) && SvIOK(tosv = cSVOPx_sv(to)))
    {
#ifdef DEBUGGING
        /* Unrolling is easier in newFOROP? */
        if (SvIV(tosv)-SvIV(fromsv) <= PERL_MAX_UNROLL_LOOP_COUNT) {
            DEBUG_kv(Perl_deb(aTHX_ "rpeep: possibly unroll loop (%" IVdf "..%" IVdf ")\n",
                              SvIV(fromsv), SvIV(tosv)));
            /* TODO op_clone_oplist from feature/gh23-inline-subs */
        }
#endif
        /* 2. Check all aelem if can aelem_u */
        maxto = SvIV(tosv);
    }

    /* for (0..$#a) { ... $a[$_] ...} */
    if (OP_TYPE_IS_NN(to, OP_AV2ARYLEN) || maxto) {
        OP *kid = OP_TYPE_IS_NN(to, OP_AV2ARYLEN) ? OpFIRST(to) : NULL;
        OP *loop, *iter, *body, *o2;
        SV *idx = MUTABLE_SV(PL_defgv);
#ifdef DEBUGGING
        const char *aname = !kid ? "*"
            : IS_TYPE(kid, GV) ? GvNAME_get(kSVOP_sv)
            : IS_TYPE(kid, PADAV) ? PAD_COMPNAME_PV(kid->op_targ)
            : "";
        char *iname = (char*)"_";
#endif
        /* array can be global: gv -> rv2av, or rv2av(?), or lexical: padav */
        assert(!kid || IS_TYPE(kid, GV) || IS_TYPE(kid, PADAV)
                    || IS_TYPE(kid, RV2AV) );
        /* enteriter->iter->and(other) */
        loop = OpFIRST(leave);
        if (loop->op_private & (OPpLVAL_INTRO|OPpOUR_INTRO)
            && loop->op_targ)
        {
            idx = PAD_SV(loop->op_targ);
#ifdef DEBUGGING
            iname = PAD_COMPNAME_PV(loop->op_targ);
#endif
        } else {
            o2 = OpLAST(loop);
            if (IS_TYPE(o2, RV2GV)) {
                o2 = OpFIRST(o2);
                if (IS_TYPE(o2, GV)) {
                    idx = cSVOPx_sv(o2); /* PVGV or PADOFFSET */
#if defined(DEBUGGING)
#  ifdef USE_ITHREADS
                    iname = GvNAME_get(PAD_SV((PADOFFSET)idx));
#  else
                    iname = GvNAME_get(idx);
#  endif
#endif
                }
            }
        }
        DEBUG_kv(Perl_deb(aTHX_ "rpeep: omit loop bounds checks (from..arylen) for %s[%s]...\n",
                          aname, iname));
        iter = OpNEXT(loop);
        body = OpOTHER(iter);
        /* replace all aelem with aelem_u for this exact array in
           this loop body, if the index is the loop counter */
        for (o2=body; o2 != iter; o2=OpNEXT(o2)) {
            const OPCODE type = o2->op_type;
            SV *av;
            /*DEBUG_kv(Perl_deb(aTHX_ "rpeep: loop oob %s\n", OP_NAME(o2)));*/
            DEBUG_kv(if (type == OP_AELEM && OP_TYPE_IS(OpFIRST(o2), OP_PADAV))
                         Perl_deb(aTHX_ "rpeep: aelem %s vs %s\n",
                                  aname, PAD_COMPNAME_PV(OpFIRST(o2)->op_targ)));
            /* here aelem might not be already optimized to multideref.
               aelem_u is faster, but does no deref so far. */
            if (type == OP_AELEM
                && OP_TYPE_IS(OpFIRST(o2), OP_PADAV)
                && !(o2->op_private & (OPpLVAL_DEFER|OPpLVAL_INTRO|OPpDEREF)))
            {
                if (kid) { /* same lex array */
                    if (kid->op_targ != OpFIRST(o2)->op_targ)
                        continue;
                } else {
                    if /* or any shaped array */
                        (!AvSHAPED(av = pad_findmy_real(OpFIRST(o2)->op_targ, PL_compcv))
                         || (maxto >= AvFILLp(av)))
                    continue;
                }
                if (OpLAST(o2)->op_targ
                    && OpLAST(o2)->op_targ == loop->op_targ) {
                    DEBUG_k(Perl_deb(aTHX_ "loop oob: aelem %s[my %s] => aelem_u\n",
                        kid ? aname : PAD_COMPNAME_PV(OpFIRST(o2)->op_targ),
                        iname));
                    OpTYPE_set(o2, OP_AELEM_U);
                    changed = TRUE;
                } else if (!o2->op_targ && idx) { /* or same gv index */
                    OP* ixop = OpLAST(o2);
                    if (OP_TYPE_IS(ixop, OP_RV2SV)
                        && idx == cSVOPx_sv(OpFIRST(ixop))) {
                        DEBUG_k(Perl_deb(aTHX_ "loop oob: aelem %s[$%s] => aelem_u\n",
                                         aname, iname));
                        OpTYPE_set(o2, OP_AELEM_U);
                        changed = TRUE;
                    }
                }
            } else if (type == OP_MULTIDEREF && !maxto) {
                /* find this padsv item (the first) and set MDEREF_INDEX_uoob */
                /* with threads we also check the targ here and not via gvsv */
                if (loop->op_targ && mderef_uoob_targ(o2, loop->op_targ)) {
                    DEBUG_k(Perl_deb(aTHX_ "loop oob: multideref %s[my %s] => MDEREF_INDEX_uoob\n",
                                     aname, iname));
                    changed = TRUE;
#ifndef USE_ITHREADS
                } else if (!loop->op_targ
                           && mderef_uoob_gvsv(o2, idx)) {
                    DEBUG_k(Perl_deb(aTHX_ "loop oob: multideref %s[$%s] =>  MDEREF_INDEX_uoob\n",
                                     aname, iname));
                    changed = TRUE;
#endif
                }
            }
#if 0
            else if (type == OP_AELEMFAST_LEX
                     /* same array */
                     && o2->op_targ && o2->op_targ == loop->op_targ
                     && (!maxto || (AvSHAPED(kSVOP_sv) && maxto < AvFILLp(kSVOP_sv)))) {
                /* constant index cannot exceed shape. */
                DEBUG_k(Perl_deb(aTHX_ "loop oob: aelemfast_lex %s[%s] => aelemfast_lex_u\n",
                                 aname, iname));
                OpTYPE_set(o2, OP_AELEMFAST_LEX_U);
                changed = TRUE;
            }
#endif
            /* for(1..2){while(){}}
               Skip descending into endless inner loop [cperl #349].
               A loop is always cyclic.
            */
            else if (UNLIKELY(OP_IS_LOOP(type))) {
#ifdef PERL_OP_PARENT
                o2 = o2->op_sibparent;
#else
                return changed;
#endif
            }
        }
        return changed;
    }
    return changed;
}

/*
=for apidoc check_for_bool_cxt

See if the ops following o are such that o will always be executed in
boolean context: that is, the SV which o pushes onto the stack will
only ever be consumed by later ops via SvTRUE(sv) or similar.
If so, set a suitable private flag on o. Normally this will be
bool_flag; but see below why maybe_flag is needed too.

Typically the two flags you pass will be the generic OPpTRUEBOOL and
OPpMAYBE_TRUEBOOL, buts it's possible that for some ops those bits may
already be taken, so you'll have to give that op two different flags.

More explanation of 'maybe_flag' and 'safe_and' parameters.
The binary logical ops &&, ||, // (plus 'if' and 'unless' which use
those underlying ops) short-circuit, which means that rather than
necessarily returning a truth value, they may return the LH argument,
which may not be boolean. For example in $x = (keys %h || -1), keys
should return a key count rather than a boolean, even though its
sort-of being used in boolean context.

So we only consider such logical ops to provide boolean context to
their LH argument if they themselves are in void or boolean context.
However, sometimes the context isn't known until run-time. In this
case the op is marked with the maybe_flag flag it.

Consider the following.

    sub f { ....;  if (%h) { .... } }

This is actually compiled as

    sub f { ....;  %h && do { .... } }

Here we won't know until runtime whether the final statement (and hence
the &&) is in void context and so is safe to return a boolean value.
So mark o with maybe_flag rather than the bool_flag.
Note that there is cost associated with determining context at runtime
(e.g. a call to block_gimme()), so it may not be worth setting (at
compile time) and testing (at runtime) maybe_flag if the scalar verses
boolean costs savings are marginal.

However, we can do slightly better with && (compared to || and //):
this op only returns its LH argument when that argument is false. In
this case, as long as the op promises to return a false value which is
valid in both boolean and scalar contexts, we can mark an op consumed
by && with bool_flag rather than maybe_flag.
For example as long as pp_padhv and pp_rv2hv return SV_ZERO rather
than SV_NO for a false result in boolean context, then it's safe. An
op which promises to handle this case is indicated by setting safe_and
to true.

=cut
*/
static void
S_check_for_bool_cxt(OP*o, bool safe_and, U8 bool_flag, U8 maybe_flag)
{
    OP *lop;
    PERL_ARGS_ASSERT_CHECK_FOR_BOOL_CXT;
    assert(OpWANT_SCALAR(o));

    lop = OpNEXT(o);

    while (lop) {
        switch (lop->op_type) {
        case OP_NULL:
        case OP_SCALAR:
            break;

        /* these two consume the stack argument in the scalar case,
         * and treat it as a boolean in the non linenumber case */
        case OP_FLIP:
        case OP_FLOP:
            if (OpWANT_LIST(lop) || (OpPRIVATE(lop) & OPpFLIP_LINENUM)) {
                lop = NULL;
                break;
            }
            /* FALLTHROUGH */
        /* these never leave the original value on the stack */
        case OP_NOT:
        case OP_XOR:
        case OP_COND_EXPR:
        case OP_GREPWHILE:
            o->op_private |= bool_flag;
            lop = NULL;
            break;

        /* OR DOR and AND evaluate their arg as a boolean, but then may
         * leave the original scalar value on the stack when following the
         * op_next route. If not in void context, we need to ensure
         * that whatever follows consumes the arg only in boolean context
         * too.
         */
        case OP_AND:
            if (safe_and) {
                o->op_private |= bool_flag;
                lop = NULL;
                break;
            }
            /* FALLTHROUGH */
        case OP_OR:
        case OP_DOR:
            if (OpWANT_VOID(lop)) {
                o->op_private |= bool_flag;
                lop = NULL;
            }
            else if (!(OpFLAGS(lop) & OPf_WANT)) {
                /* unknown context - decide at runtime */
                o->op_private |= maybe_flag;
                lop = NULL;
            }
            break;

        default:
            lop = NULL;
            break;
        }

        if (lop)
            lop = OpNEXT(lop);
    }
}


/* returns the next non-null op */

/* mechanism for deferring recursion in rpeep() */

#define MAX_DEFERRED 4

#define DEFER(o) \
  STMT_START { \
    if (defer_ix == (MAX_DEFERRED-1)) { \
        OP **defer = defer_queue[defer_base]; \
        CALL_RPEEP(*defer); \
        S_prune_chain_head(defer); \
	defer_base = (defer_base + 1) % MAX_DEFERRED; \
	defer_ix--; \
    } \
    defer_queue[(defer_base + ++defer_ix) % MAX_DEFERRED] = &(o); \
  } STMT_END

/*
=for apidoc rpeep
The peephole optimizer.  We visit the ops in the order they're to execute.
See the comments at the top of this file for more details about when
peep() is called.

Warning: rpeep is not a real peephole optimizer as other compilers
implement it due to historic ballast. It started more as a glorified
op nullifier. It sets op_opt when done, and does not run it again when
it sees this flag at the op. When it's set it turns the op into NULL.

More important, it sets op_opt to 1 by default, even if it has no intention
to nullify ("optimize away") the current op. Any optimization which wants
to keep the op needs to unset op_opt.

=cut
*/
void
Perl_rpeep(pTHX_ OP *o)
{
    dVAR;
    OP* oldop = NULL;
    OP* oldoldop = NULL;
    OP** defer_queue[MAX_DEFERRED]; /* small queue of deferred branches */
    int defer_base = 0;
    int defer_ix = -1;

    if (!o || o->op_opt)
	return;

    assert(o->op_type != OP_FREED);

    ENTER;
    SAVEOP();
    SAVEVPTR(PL_curcop);
    /*DEBUG_kv(Perl_deb(aTHX_ "rpeep 0x%p\n", o));*/
    for (;; o = OpNEXT(o)) {
	if (o && o->op_opt)
	    o = NULL;
	if (!o) {
	    while (defer_ix >= 0) {
                OP **defer =
                        defer_queue[(defer_base + defer_ix--) % MAX_DEFERRED];
                CALL_RPEEP(*defer);
                S_prune_chain_head(defer);
            }
	    break;
	}

      redo:

        /* oldoldop -> oldop -> o should be a chain of 3 adjacent ops */
        assert(!oldoldop || OpNEXT(oldoldop) == oldop);
        assert(!oldop    || OpNEXT(oldop)    == o);

	/* By default, this op has now been optimised. A couple of cases below
	   clear this again.  */
	o->op_opt = 1;
	PL_op = o;

        /* boxed type promotions done in ck_type.
         * unbox/native todo here:
         * With more than 2 ops with unboxable args, maybe unbox it.
         * e.g. padsv[$a:int] const(iv) add padsv[$b:int] multiply
         *   => padsv[$a:int] const(iv) unbox[2] int_add
         *      padsv[$b:int] unbox int_multiply[BOXRET]
         * OPpBOXRET bit as in box_int
         * (5 with 2 slow ops -> 7 ops with 4 fast ops)
         */

        /* look for a series of 1 or more aggregate derefs, e.g.
         *   $a[1]{foo}[$i]{$k}
         * and replace with a single OP_MULTIDEREF op.
         * Each index must be either a const, or a simple variable,
         *
         * First, look for likely combinations of starting ops,
         * corresponding to (global and lexical variants of)
         *     $a[...]   $h{...}
         *     $r->[...] $r->{...}
         *     (preceding expression)->[...]
         *     (preceding expression)->{...}
         * and if so, call maybe_multideref() to do a full inspection
         * of the op chain and if appropriate, replace with an
         * OP_MULTIDEREF
         */
        {
            UV action;
            OP *o2 = o;
            U8 hints = 0;

            switch (o2->op_type) {
            case OP_GV:
                /* $pkg[..]   :   gv[*pkg]
                 * $pkg->[...]:   gv[*pkg]; rv2sv sKM/DREFAV */

                /* Fail if there are new op flag combinations that we're
                 * not aware of, rather than:
                 *  * silently failing to optimise, or
                 *  * silently optimising the flag away.
                 * If this ASSUME starts failing, examine what new flag
                 * has been added to the op, and decide whether the
                 * optimisation should still occur with that flag, then
                 * update the code accordingly. This applies to all the
                 * other ASSUMEs in the block of code too.
                 */
                ASSUME(!(o2->op_flags &
                            ~(OPf_WANT|OPf_MOD|OPf_PARENS|OPf_SPECIAL)));
                ASSUME(!(o2->op_private & ~(OPpEARLY_CV|OPpGV_WASMETHOD)));

                o2 = OpNEXT(o2);
                /*DEBUG_kv(Perl_deb(aTHX_ "rpeep: o=0x%p\n", o2));*/

                if (IS_TYPE(o2, RV2AV)) {
                    action = MDEREF_AV_gvav_aelem;
                    goto do_deref;
                }

                if (IS_TYPE(o2, RV2HV)) {
                    action = MDEREF_HV_gvhv_helem;
                    goto do_deref;
                }

                if (ISNT_TYPE(o2, RV2SV))
                    break;

                /* at this point we've seen gv,rv2sv, so the only valid
                 * construct left is $pkg->[] or $pkg->{} */

                ASSUME(!OpSTACKED(o2));
                if ((o2->op_flags & (OPf_WANT|OPf_REF|OPf_MOD|OPf_SPECIAL))
                            != (OPf_WANT_SCALAR|OPf_MOD))
                    break;

                ASSUME(!(o2->op_private & ~(OPpARG1_MASK|HINT_STRICT_REFS
                                    |OPpHINT_STRICT_NAMES
                                    |OPpOUR_INTRO|OPpDEREF|OPpLVAL_INTRO)));
                if (o2->op_private & (OPpOUR_INTRO|OPpLVAL_INTRO))
                    break;
                if (   OpDEREF(o2) != OPpDEREF_AV
                    && OpDEREF(o2) != OPpDEREF_HV)
                    break;

                o2 = OpNEXT(o2);
                if (IS_TYPE(o2, RV2AV)) {
                    action = MDEREF_AV_gvsv_vivify_rv2av_aelem;
                    goto do_deref;
                }
                if (IS_TYPE(o2, RV2HV)) {
                    action = MDEREF_HV_gvsv_vivify_rv2hv_helem;
                    goto do_deref;
                }
                break;

            case OP_PADSV:
                /* $lex->[...]: padsv[$lex] sM/DREFAV */

                ASSUME(!(o2->op_flags &
                    ~(OPf_WANT|OPf_PARENS|OPf_REF|OPf_MOD|OPf_SPECIAL)));
                if ((o2->op_flags &
                        (OPf_WANT|OPf_REF|OPf_MOD|OPf_SPECIAL))
                     != (OPf_WANT_SCALAR|OPf_MOD))
                    break;

                ASSUME(!(o2->op_private &
                                ~(OPpPAD_STATE|OPpDEREF|OPpLVAL_INTRO)));
                /* skip if state or intro, or not a deref */
                if (      o2->op_private != OPpDEREF_AV
                       && o2->op_private != OPpDEREF_HV)
                    break;

                o2 = OpNEXT(o2);
                if (IS_TYPE(o2, RV2AV)) {
                    action = MDEREF_AV_padsv_vivify_rv2av_aelem;
                    goto do_deref;
                }
                if (IS_TYPE(o2, RV2HV)) {
                    action = MDEREF_HV_padsv_vivify_rv2hv_helem;
                    goto do_deref;
                }
                break;

            case OP_PADAV:
                /* XXX Note that we don't yet compile-time check a destructive splice.
                   This needs to be done at run-time. We also need to search to find
                   the last pushmark arg. shift and push can have multiple args. 
                   1-arg push is also not caught here.
                   We also have no MDEREF_AV_padav_aelem_u, only a MDEREF_INDEX_uoob */
                if (OpNEXT(o2) && o2->op_targ && AvSHAPED(pad_findmy_real(o2->op_targ, PL_compcv))) {
                    /* 1 arg case */
                    OPCODE type = OpNEXT(o2)->op_type;
                    if (type == OP_PUSH  || type == OP_POP
                     || type == OP_SHIFT || type == OP_UNSHIFT)
                        Perl_die(aTHX_ "Invalid modification of shaped array: %s %s",
                            OP_NAME(OpNEXT(o2)),
                            PAD_COMPNAME_PV(o2->op_targ));
                    /* 2 arg case */
                    if (OpNEXT(OpNEXT(o2))) {
                        OPCODE type = OpNEXT(OpNEXT(o2))->op_type;
                        if (type == OP_PUSH || type == OP_SHIFT)
                            Perl_die(aTHX_ "Invalid modification of shaped array: %s %s",
                                OP_NAME(OpNEXT(OpNEXT(o2))),
                                PAD_COMPNAME_PV(o2->op_targ));
                    }
                }
            case OP_PADHV:
                /*    $lex[..]:  padav[@lex:1,2] sR *
                 * or $lex{..}:  padhv[%lex:1,2] sR */
                ASSUME(!(o2->op_flags & ~(OPf_WANT|OPf_MOD|OPf_PARENS|
                                            OPf_REF|OPf_SPECIAL)));
                if ((o2->op_flags &
                        (OPf_WANT|OPf_REF|OPf_MOD|OPf_SPECIAL))
                     != (OPf_WANT_SCALAR|OPf_REF))
                    break;
                if (o2->op_flags != (OPf_WANT_SCALAR|OPf_REF))
                    break;
                /* OPf_PARENS isn't currently used in this case;
                 * if that changes, let us know! */
                ASSUME(!OpPARENS(o2));

                /* at this point, we wouldn't expect any of the remaining
                 * possible private flags:
                 * OPpPAD_STATE, OPpLVAL_INTRO, OPpTRUEBOOL,
                 * OPpMAYBE_TRUEBOOL, OPpMAYBE_LVSUB
                 *
                 * OPpSLICEWARNING shouldn't affect runtime
                 */
                ASSUME(!(o2->op_private & ~(OPpSLICEWARNING)));

                action = IS_TYPE(o2, PADAV)
                            ? MDEREF_AV_padav_aelem
                            : MDEREF_HV_padhv_helem;
                o2 = OpNEXT(o2);
                S_maybe_multideref(aTHX_ o, o2, action, 0);
                break;


            case OP_RV2AV:
            case OP_RV2HV:
                action = IS_TYPE(o2, RV2AV)
                            ? MDEREF_AV_pop_rv2av_aelem
                            : MDEREF_HV_pop_rv2hv_helem;
                /* FALLTHROUGH */
            do_deref:
                /* (expr)->[...]:  rv2av sKR/1;
                 * (expr)->{...}:  rv2hv sKR/1; */

                ASSUME(IS_TYPE(o2, RV2AV) || IS_TYPE(o2, RV2HV));

                ASSUME(!(o2->op_flags & ~(OPf_WANT|OPf_KIDS|OPf_PARENS
                                |OPf_REF|OPf_MOD|OPf_STACKED|OPf_SPECIAL)));
                if (o2->op_flags != (OPf_WANT_SCALAR|OPf_KIDS|OPf_REF))
                    break;

                /* at this point, we wouldn't expect any of these
                 * possible private flags:
                 * OPpMAYBE_LVSUB, OPpLVAL_INTRO
                 * OPpTRUEBOOL, OPpMAYBE_TRUEBOOL, (rv2hv only)
                 */
                ASSUME(!(o2->op_private &
                    ~(OPpHINT_STRICT_REFS|OPpARG1_MASK|OPpSLICEWARNING
                     |OPpOUR_INTRO)));
                hints |= (o2->op_private & OPpHINT_STRICT_REFS);

                o2 = OpNEXT(o2);
                S_maybe_multideref(aTHX_ o, o2, action, hints);
                /*DEBUG_kv(Perl_deb(aTHX_ "rpeep: o=0x%p mderef\n", o));*/
                break;

            default:
                break;
            }
        }
        /*DEBUG_kv(Perl_deb(aTHX_ "rpeep: o=0x%p oldop->op_next=0x%p break\n",
          o, oldop ? oldop->op_next : NULL));*/

	switch (o->op_type) {
	case OP_DBSTATE:
	    PL_curcop = ((COP*)o);		/* for warnings */
	    break;
	case OP_NEXTSTATE:
	    PL_curcop = ((COP*)o);		/* for warnings */

	    /* Optimise a "return ..." at the end of a sub to just be "...".
	     * This saves 2 ops. Before:
	     * 1  <;> nextstate(main 1 -e:1) v ->2
	     * 4  <@> return K ->5
	     * 2    <0> pushmark s ->3
	     * -    <1> ex-rv2sv sK/1 ->4
	     * 3      <#> gvsv[*cat] s ->4
	     *
	     * After:
	     * -  <@> return K ->-
	     * -    <0> pushmark s ->2
	     * -    <1> ex-rv2sv sK/1 ->-
	     * 2      <$> gvsv(*cat) s ->3
	     */
	    {
		OP *next = OpNEXT(o);
		OP *sibling = OpSIBLING(o);
		if (   OP_TYPE_IS(next, OP_PUSHMARK)
		    && OP_TYPE_IS(sibling, OP_RETURN)
                    && OP_TYPE_IS(OpNEXT(sibling), OP_LINESEQ)
                    && ( OP_TYPE_IS(OpNEXT(OpNEXT(sibling)), OP_LEAVESUB)
                      || OP_TYPE_IS(OpNEXT(OpNEXT(sibling)), OP_LEAVESUBLV))
		    && OpFIRST(sibling) == next
                    && OpHAS_SIBLING(next) && OpNEXT(OpSIBLING(next))
                    && OpNEXT(next)
		) {
		    /* Look through the PUSHMARK's siblings for one that
		     * points to the RETURN */
		    OP *top = OpSIBLING(next);
		    while (top && OpNEXT(top)) {
			if (OpNEXT(top) == sibling) {
			    OpNEXT(top) = OpNEXT(sibling);
			    OpNEXT(o) = OpNEXT(next);
			    break;
			}
			top = OpSIBLING(top);
		    }
		}
	    }

	    /* Optimise 'my $x; my $y;' into 'my ($x, $y);'
             *
	     * This latter form is then suitable for conversion into padrange
	     * later on. Convert:
	     *
	     *   nextstate1 -> padop1 -> nextstate2 -> padop2 -> nextstate3
	     *
	     * into:
	     *
	     *   nextstate1 ->     listop     -> nextstate3
	     *                 /            \
	     *         pushmark -> padop1 -> padop2
	     */
	    if (OpNEXT(o) && IS_PADxV_OP(OpNEXT(o))
		&& !(OpNEXT(o)->op_private & ~OPpLVAL_INTRO)
		&& OP_TYPE_IS(OpNEXT(OpNEXT(o)), OP_NEXTSTATE)
		&& OpNEXT(OpNEXT(OpNEXT(o)))
                  && IS_PADxV_OP(OpNEXT(OpNEXT(OpNEXT(o))))
		&& !(OpNEXT(OpNEXT(OpNEXT(o)))->op_private & ~OPpLVAL_INTRO)
		&& OP_TYPE_IS(OpNEXT(OpNEXT(OpNEXT(OpNEXT(o)))), OP_NEXTSTATE)
		&& (!CopLABEL((COP*)o)) /* Don't mess with labels */
		&& (!CopLABEL((COP*)OpNEXT(OpNEXT(o)))) /* ... */
	    ) {
		OP *pad1, *ns2, *pad2, *ns3, *newop, *newpm;

		pad1 = OpNEXT(o);
		ns2  = OpNEXT(pad1);
                pad2 = OpNEXT(ns2);
                ns3  = OpNEXT(pad2);

                /* we assume here that the op_next chain is the same as
                 * the op_sibling chain */
                assert(OpSIBLING(o)    == pad1);
                assert(OpSIBLING(pad1) == ns2);
                assert(OpSIBLING(ns2)  == pad2);
                assert(OpSIBLING(pad2) == ns3);

                /* excise and delete ns2 */
                op_sibling_splice(NULL, pad1, 1, NULL);
                op_free(ns2);

                /* excise pad1 and pad2 */
                op_sibling_splice(NULL, o, 2, NULL);

                /* create new listop, with children consisting of:
                 * a new pushmark, pad1, pad2. */
		newop = newLISTOP(OP_LIST, 0, pad1, pad2);
		newop->op_flags |= OPf_PARENS;
		newop->op_flags = (newop->op_flags & ~OPf_WANT) | OPf_WANT_VOID;

                /* insert newop between o and ns3 */
                op_sibling_splice(NULL, o, 0, newop);

                /*fixup op_next chain */
                newpm = OpFIRST(newop); /* pushmark */
		OpNEXT(o)     = newpm;
		OpNEXT(newpm) = pad1;
                OpNEXT(pad1)  = pad2;
                OpNEXT(pad2)  = newop; /* listop */
                OpNEXT(newop) = ns3;

		/* Ensure pushmark has this flag if padops do */
		if (pad1->op_flags & OPf_MOD && pad2->op_flags & OPf_MOD) {
		    newpm->op_flags |= OPf_MOD;
		}

		break;
	    }

            /* check loop bounds:
               1) if index bound to size/arylen, optimize to unchecked aelem_u variants,
                  even without parametrized typed.
                  need to check the right array, and if the loop index is used as is, or
                  within an expression.
               2) with static bounds check unrolling.
            */
	    if (OP_TYPE_IS(OpSIBLING(o), OP_LEAVELOOP)) {
                BINOP *leave  = (BINOP*)OpSIBLING(o);
                LISTOP *enter = (LISTOP*)OpFIRST(leave);
                o->op_opt = 0; /* continue */
                if (OpFIRST(enter)) {
                    OP *next = LINKLIST(OpFIRST(enter));
                    OP *from = OpSIBLING(next);
                    OP *to   = OpSIBLING(from);
                    /* fixup/relink LOGOP entry, broken by linklist */
                    if (enter->op_type == OP_ENTERITER) {
                        if (OP_IS_ITER(OpSIBLING(enter)->op_type)) {
                            OpNEXT(enter) = OpSIBLING(enter);
                            OpNEXT(o) = next;
                        }
                    }

                    if (!to) {
                        if (next != o && oldop)
                            OpNEXT(oldop) = o;
                        break;
                    }
                    (void)peep_leaveloop(leave, from, to);
                }
            }

	    /* Two NEXTSTATEs in a row serve no purpose. Except if they happen
	       to carry two labels. For now, take the easier option, and skip
	       this optimisation if the first NEXTSTATE has a label.  */
	    if (!CopLABEL((COP*)o) && !PERLDB_NOOPT) {
		OP *nextop = OpNEXT(o);
		while (nextop && IS_NULL_OP(nextop))
		    nextop = OpNEXT(nextop);

		if (OP_TYPE_IS(nextop, OP_NEXTSTATE)) {
		    op_null(o);
		    if (oldop)
			OpNEXT(oldop) = nextop;
                    o = nextop;
                    /*DEBUG_kv(Perl_deb(aTHX_ "rpeep: o=0x%p\n", o));*/
		    /* Skip (old)oldop assignment since the current oldop's
		       op_next already points to the next op.  */
		    goto redo;
		}
	    }
	    break;

	case OP_CONCAT:
	    if (OpNEXT(o) && IS_TYPE(OpNEXT(o), STRINGIFY)) {
		if (OpNEXT(o)->op_private & OPpTARGET_MY) {
		    if (OpSTACKED(o)) /* chained concats */
			break; /* ignore_optimization */
		    else {
			assert( OP_HAS_TARGLEX(o->op_type) );
			o->op_targ = OpNEXT(o)->op_targ;
			OpNEXT(o)->op_targ = 0;
                        DEBUG_kv(Perl_deb(aTHX_
                            "rpeep: set TARGET_MY on %s\n", OP_NAME(o)));
			o->op_private |= OPpTARGET_MY;
		    }
		}
		op_null(OpNEXT(o));
	    }
	    break;
	case OP_STUB:
	    if ((o->op_flags & OPf_WANT) != OPf_WANT_LIST) {
		break; /* Scalar stub must produce undef.  List stub is noop */
	    }
	    goto nothin;
	case OP_NULL:
	    if (o->op_targ == OP_NEXTSTATE
		|| o->op_targ == OP_DBSTATE)
	    {
		PL_curcop = ((COP*)o);
	    }
#ifdef PERL_REMOVE_OP_NULL
            else if (oldop) {
                DEBUG_k(PL_count_null_ops++);
                OpNEXT(oldop) = OpNEXT(o);
            }
#endif
	    /* XXX: We avoid setting op_seq here to prevent later calls
	       to rpeep() from mistakenly concluding that optimisation
	       has already occurred. This doesn't fix the real problem,
	       though (See 20010220.007 (#5874)). AMS 20010719 */
	    /* op_seq functionality is now replaced by op_opt */
	    o->op_opt = 0;
	    /* FALLTHROUGH */
	case OP_SCALAR:
	case OP_LINESEQ:
	case OP_SCOPE:
	nothin:
	    if (oldop) {
		OpNEXT(oldop) = OpNEXT(o);
		o->op_opt = 0;
		continue;
	    }
	    break;

        case OP_PUSHMARK:
            /* Given
                 5 repeat/DOLIST
                 3   ex-list
                 1     pushmark
                 2     scalar or const
                 4   const[0]
               convert repeat into a stub with no kids.
             */
            if (IS_CONST_OP(OpNEXT(o))
             || (  IS_TYPE(OpNEXT(o), PADSV)
                && !(OpNEXT(o)->op_private & OPpLVAL_INTRO))
             || (  IS_TYPE(OpNEXT(o), GV)
                && IS_TYPE(OpNEXT(OpNEXT(o)), RV2SV)
                && !(OpNEXT(OpNEXT(o))->op_private
                        & (OPpLVAL_INTRO|OPpOUR_INTRO))))
            {
                const OP *kid = OpNEXT(OpNEXT(o));
                if (IS_TYPE(OpNEXT(o), GV))
                   kid = OpNEXT(kid);
                /* kid is now the ex-list.  */
                if (IS_NULL_OP(kid)
                 && IS_CONST_OP((kid = OpNEXT(kid)))
                    /* kid is now the repeat count.  */
                 && IS_TYPE(OpNEXT(kid), REPEAT)
                 && OpNEXT(kid)->op_private & OPpREPEAT_DOLIST
                 && OpWANT_LIST(OpNEXT(kid))
                 && SvIOK(kSVOP_sv) && SvIVX(kSVOP_sv) == 0
                 && oldop)
                {
                    o = OpNEXT(kid); /* repeat */
                    OpNEXT(oldop) = o;
                    op_free(OpFIRST(o));
                    op_free(OpLAST(o));
                    o->op_flags &=~ OPf_KIDS;
                    /* stub is a baseop; repeat is a binop */
                    STATIC_ASSERT_STMT(sizeof(OP) <= sizeof(BINOP));
                    OpTYPE_set(o, OP_STUB);
                    o->op_private = 0;
                    DEBUG_kv(Perl_deb(aTHX_ "rpeep: o=0x%p repeat\n", o));
                    break;
                }
            }

            /* convert static methods to subs, later inline subs */
            if (0) {
                int i = 0, meth = 0;
                OP* o2 = o;
                OP* gvop = NULL;
                /* scan from pushmark to the next entersub call, 4 args with $->$ */
                while (OpNEXT(o) && IS_TYPE(OpNEXT(o), PUSHMARK)) {
                    oldop = o;
                    o = OpNEXT(o);
                }
                for (; o2 && i<8; o2 = o2->op_next, i++) {
                    OPCODE type = o2->op_type;
                    if (type == OP_GV || type == OP_GVSV) {
                        gvop = o2; /* gvsv for variable method parts, left or right */
                    } else if (type == OP_METHOD_NAMED) {
                        /* method name only with pkg->m, not $obj->m */
                        /* TODO: we could speculate and cache an inlined variant for $obj,
                           matching the METHOP rclass */
                        gvop = IS_TYPE(OpNEXT(o), CONST) ? o2 : NULL;
                        meth++;
                    }
                    else if (type == OP_METHOD) /* $obj->$m needs run-time dispatch */
                        break;
                    else if (IS_SUB_TYPE(type))
                        break;
                }
                if (o2 && IS_SUB_OP(o2) && gvop) {
#ifdef USE_ITHREADS
                    SV *gv = PAD_SVl(cPADOPx(gvop)->op_padix);
#else
                    SV *gv = cSVOPx(gvop)->op_sv;
#endif
                    CV* cv = NULL;
                    SV* rcv = NULL;
                    /* for methods only if the static &pkg->cv exists, or the obj is typed */
                    if (gv) {
                        if (SvTYPE(gv) == SVt_PVGV && (cv = GvCV(gv)) &&
                            SvTYPE(cv) == SVt_PVCV) {
                            ;
                        } else if (SvROK(gv) && (cv = (CV*)SvRV((SV*)gv)) && 
                                   SvTYPE(cv) == SVt_PVCV) {
                            rcv = gv;
                        } else if (SvTYPE(gv) == SVt_PV &&
                                   IS_TYPE(OpNEXT(o), CONST) &&
                                   IS_TYPE(gvop, METHOD_NAMED))
                        {
                            SV *name = cSVOPx_sv(OpNEXT(o));
                            /* But do error on ""->method */
                            if (SvTYPE(name) == SVt_PV && SvCUR(name)) {
                                GV **gvp = NULL;
                                GV *gvf = NULL;
                                HV *stash = gv_stashsv(name, SvUTF8(name));
                                if (stash && SvTYPE(stash) == SVt_PVHV) {
                                    /* bypass cache and gv overhead */
                                    gvp = (GV**)hv_common(stash, gv, NULL, 0, 0,
                                             HV_FETCH_ISEXISTS|HV_FETCH_JUST_SV, NULL, 0);
                                }
                                if (gvp) {
                                    /*char *stashname = HvNAME_get(stash);*/
                                    gvf = *gvp;
                                    if (SvROK(gvf) &&
                                        SvTYPE(SvRV((SV*)gvf)) == SVt_PVCV) {
                                        cv = (CV*)SvRV((SV*)gvf);
                                        rcv = (SV*)gvf;
                                        SvREFCNT_inc_simple_void_NN(rcv);
                                    }
                                    else if (SvTYPE(gvf) == SVt_PVGV &&
                                             (cv = GvCV(gvf))) {
                                        ;
                                    }
                                }
                                /* not imported alias, e.g. Exporter */
                                if (cv && CvSTASH(cv) == stash) {
                                    assert(gvf);
                                    /* But a class method called as sub should error.
                                       Detect this earlier than at run-time in the method_named. */
                                    if (HvCLASS(stash))
                                        Perl_croak(aTHX_
                                            "Invalid method call on class subroutine %" SVf,
                                            SVfARG(cv_name(cv,NULL,CV_NAME_NOMAIN)));
                                    /* convert static method to normal sub */
                                    /* See http://blogs.perl.org/users/rurban/2011/06/
                                           how-perl-calls-subs-and-methods.html */
                                    /* remove bareword-ness of class name */
                                    o->op_next->op_private &=
                                        ~(OPpCONST_BARE|OPpCONST_STRICT);
                                    if (CvISXSUB(cv) && CvROOT(cv) &&
                                        GvXSCV(gvf) && !PL_perldb)
                                    {
                                        DEBUG_k(Perl_deb(aTHX_ "entersub -> xs %" SVf "\n",
                                            SVfARG(cv_name(cv, NULL, CV_NAME_NOMAIN))));
                                        OpTYPE_set(o2, OP_ENTERXSSUB);
                                    }
                                    /* from METHOP to GV */
                                    OpTYPE_set(gvop, OP_GV);
                                    OpPRIVATE(gvop) |= OPpGV_WASMETHOD;
        /* Cleaning main::BEGIN converted the attached GV (gv-entersub) via
           sv_unmagic to a PV, which broke the stash{import} entry,
           breaking all subsequent calls. */
#if 0
        /* METH and GV share the same sv* pos, but rather use a cvref.
           The GV is too fragile when &BEGIN is cleared.
           But with the cvref lots of tests fail, eg op/hashassign.t
        */
                                    if (LIKELY((SV*)gvf != rcv)) {
                                        if (!rcv)
                                            rcv = newRV_inc((SV*)cv);
                                        ((SVOP*)gvop)->op_sv = rcv;
                                    }
#else
                                    if (LIKELY(gv != (SV*)gvf && gv != rcv)) {
                                        if (UNLIKELY(rcv))
                                            ((SVOP*)gvop)->op_sv = newRV_inc(rcv);
                                        else
                                            ((SVOP*)gvop)->op_sv = SvREFCNT_inc_NN(gvf);
                                        SvREFCNT_dec(gv);
                                    }
#endif
                                    gvop->op_flags |= OPf_WANT_SCALAR;
                                    o2->op_flags |= OPf_STACKED;
                                    DEBUG_k(Perl_deb(aTHX_
                                        "rpeep: static method call to sub %" SVf "::%" SVf "\n",
                                         SVfARG(name), SVfARG(gv)));
                                    meth = FALSE;
                                }
                            }
                        }
#ifdef PERL_INLINE_SUBS
                        if (cv && CvINLINABLE(cv) && !meth) {
                            if (cop_hints_fetch_pvs(PL_curcop, "inline", REFCOUNTED_HE_EXISTS)) {
                                DEBUG_k(Perl_deb(aTHX_ "rpeep: skip inline sub %" SVf ", no inline\n",
                                    SVfARG(cv_name(cv,NULL,CV_NAME_NOMAIN))));
                            } else {
                                OP* tmp;
                                DEBUG_k(Perl_deb(aTHX_ "rpeep: inline sub %" SVf "\n",
                                    SVfARG(cv_name(cv,NULL,CV_NAME_NOMAIN))));
                                if ((tmp = cv_do_inline(o, o2, cv, FALSE))) {
                                    o = tmp;
                                    if (oldop)
                                        oldop->op_next = o;
                                }
                            }
                        }
#endif
                    }
                }
            }

            /* Convert a series of PAD ops for my vars plus support into a
             * single padrange op. Basically
             *
             *    pushmark -> pad[ahs]v -> pad[ahs]?v -> ... -> (list) -> rest
             *
             * becomes, depending on circumstances, one of
             *
             *    padrange  ----------------------------------> (list) -> rest
             *    padrange  --------------------------------------------> rest
             *
             * where all the pad indexes are sequential and of the same type
             * (INTRO or not).
             * We convert the pushmark into a padrange op, then skip
             * any other pad ops, and possibly some trailing ops.
             * Note that we don't null() the skipped ops, to make it
             * easier for Deparse to undo this optimisation (and none of
             * the skipped ops are holding any resourses). It also makes
             * it easier for find_uninit_var(), as it can just ignore
             * padrange, and examine the original pad ops.
             */
        {
            OP *p;
            OP *followop = NULL; /* the op that will follow the padrange op */
            U8 count = 0;
            U8 intro = 0;
            PADOFFSET base = 0; /* init only to stop compiler whining */
            bool gvoid = 0;     /* init only to stop compiler whining */
            bool defav = 0;  /* seen (...) = @_ */
            bool reuse = 0;  /* reuse an existing padrange op */

            /* look for a pushmark -> gv[_] -> rv2av */

            {
                OP *rv2av, *q;
                p = OpNEXT(o);
                if (   IS_TYPE(p, GV)
                    && cGVOPx_gv(p) == PL_defgv
                    && (rv2av = OpNEXT(p))
                    && IS_TYPE(rv2av, RV2AV)
                    && !(rv2av->op_flags & OPf_REF)
                    && !(rv2av->op_private & (OPpLVAL_INTRO|OPpMAYBE_LVSUB))
                    && OpWANT_LIST(rv2av)
                ) {
                    q = OpNEXT(rv2av);
                    if (IS_NULL_OP(q))
                        q = OpNEXT(q);
                    if (IS_TYPE(q, PUSHMARK)) {
                        defav = 1;
                        p = q;
                    }
                }
            }
            if (!defav) {
                p = o;
            }

            /* scan for PAD ops */

            for (p = OpNEXT(p); p; p = OpNEXT(p)) {
                if (IS_NULL_OP(p))
                    continue;

                if ((  ISNT_TYPE(p, PADSV)
                    && ISNT_TYPE(p, PADAV)
                    && ISNT_TYPE(p, PADHV)
                    )
                      /* any private flag other than INTRO? e.g. STATE */
                   || (p->op_private & ~OPpLVAL_INTRO)
                )
                    break;

                /* let $a[N] potentially be optimised into AELEMFAST_LEX
                 * instead */
                if (   IS_TYPE(p, PADAV)
                    && OP_TYPE_IS(OpNEXT(p), OP_CONST)
                    && OP_TYPE_IS(OpNEXT(OpNEXT(p)), OP_AELEM))
                    break;

                /* for 1st padop, note what type it is and the range
                 * start; for the others, check that it's the same type
                 * and that the targs are contiguous */
                if (count == 0) {
                    intro = (p->op_private & OPpLVAL_INTRO);
                    base = p->op_targ;
                    gvoid = OP_GIMME_VOID(p);
                }
                else {
                    if ((p->op_private & OPpLVAL_INTRO) != intro)
                        break;
                    /* Note that you'd normally  expect targs to be
                     * contiguous in my($a,$b,$c), but that's not the case
                     * when external modules start doing things, e.g.
                     * Function::Parameters */
                    if (p->op_targ != base + count)
                        break;
                    assert(p->op_targ == base + count);
                    /* Either all the padops or none of the padops should
                       be in void context.  Since we only do the optimisa-
                       tion for av/hv when the aggregate itself is pushed
                       on to the stack (one item), there is no need to dis-
                       tinguish list from scalar context.  */
                    if (gvoid != OP_GIMME_VOID(p))
                        break;
                }

                /* for AV, HV, only when we're not flattening */
                if (   ISNT_TYPE(p, PADSV)
                    && !gvoid
                    && !(p->op_flags & OPf_REF)
                )
                    break;

                if (count >= OPpPADRANGE_COUNTMASK)
                    break;

                /* there's a biggest base we can fit into a
                 * SAVEt_CLEARPADRANGE in pp_padrange.
                 * (The sizeof() stuff will be constant-folded, and is
                 * intended to avoid getting "comparison is always false"
                 * compiler warnings. See the comments above
                 * MEM_WRAP_CHECK for more explanation on why we do this
                 * in a weird way to avoid compiler warnings.)
                 */
                if (   intro
                    && (8*sizeof(base) >
                        8*sizeof(UV)-OPpPADRANGE_COUNTSHIFT-SAVE_TIGHT_SHIFT
                        ? (unsigned long)base
                        : (UV_MAX >> (OPpPADRANGE_COUNTSHIFT+SAVE_TIGHT_SHIFT))
                    ) > (UV_MAX >> (OPpPADRANGE_COUNTSHIFT+SAVE_TIGHT_SHIFT))
                )
                    break;

                /* Success! We've got another valid pad op to optimise away */
                count++;
                followop = OpNEXT(p);
            }

            if (count < 1 || (count == 1 && !defav))
                break;

            /* pp_padrange in specifically compile-time void context
             * skips pushing a mark and lexicals; in all other contexts
             * (including unknown till runtime) it pushes a mark and the
             * lexicals. We must be very careful then, that the ops we
             * optimise away would have exactly the same effect as the
             * padrange.
             * In particular in void context, we can only optimise to
             * a padrange if we see the complete sequence
             *     pushmark, pad*v, ...., list
             * which has the net effect of leaving the markstack as it
             * was.  Not pushing onto the stack (whereas padsv does touch
             * the stack) makes no difference in void context.
             */
            assert(followop);
            if (gvoid) {
                if (IS_TYPE(followop, LIST)
                    && OP_GIMME_VOID(followop))
                {
                    followop = OpNEXT(followop); /* skip OP_LIST */

                    /* consolidate two successive my(...);'s */

                    if (   OP_TYPE_IS(oldoldop, OP_PADRANGE)
                        && OpWANT_VOID(oldoldop)
                        && (oldoldop->op_private & OPpLVAL_INTRO) == intro
                        && !OpSPECIAL(oldoldop)
                    ) {
                        U8 old_count;
                        assert(OpNEXT(oldoldop) == oldop);
                        assert(   IS_TYPE(oldop, NEXTSTATE)
                               || IS_TYPE(oldop, DBSTATE));
                        assert(OpNEXT(oldop) == o);

                        old_count
                            = (oldoldop->op_private & OPpPADRANGE_COUNTMASK);

                       /* Do not assume pad offsets for $c and $d are con-
                          tiguous in
                            my ($a,$b,$c);
                            my ($d,$e,$f);
                        */
                        if (  oldoldop->op_targ + old_count == base
                           && old_count < OPpPADRANGE_COUNTMASK - count) {
                            base = oldoldop->op_targ;
                            count += old_count;
                            reuse = 1;
                        }
                    }

                    /* if there's any immediately following singleton
                     * my var's; then swallow them and the associated
                     * nextstates; i.e.
                     *    my ($a,$b); my $c; my $d;
                     * is treated as
                     *    my ($a,$b,$c,$d);
                     */

                    while (((p = OpNEXT(followop)))
                            && OP_IS_PADVAR(p->op_type)
                            && OpWANT_VOID(p)
                            && (p->op_private & OPpLVAL_INTRO) == intro
                            && !(p->op_private & ~OPpLVAL_INTRO)
                            && OpNEXT(p)
                            && OP_IS_COP(OpNEXT(p)->op_type)
                            && count < OPpPADRANGE_COUNTMASK
                            && base + count == p->op_targ
                    ) {
                        count++;
                        followop = OpNEXT(p);
                    }
                }
                else
                    break;
            }

            if (reuse) {
                assert(IS_TYPE(oldoldop, PADRANGE));
                OpNEXT(oldoldop) = followop;
                oldoldop->op_private = (intro | count);
                o = oldoldop;
                oldop = NULL;
                oldoldop = NULL;
                /*DEBUG_kv(Perl_deb(aTHX_ "rpeep: o=0x%p = oldoldop (padrange)\n", o));*/
            }
            else {
                /* Convert the pushmark into a padrange.
                 * To make Deparse easier, we guarantee that a padrange was
                 * *always* formerly a pushmark */
                assert(IS_TYPE(o, PUSHMARK));
                OpNEXT(o) = followop;
                OpTYPE_set(o, OP_PADRANGE);
                o->op_targ = base;
                /* bit 7: INTRO; bit 6..0: count */
                o->op_private = (intro | count);
                o->op_flags = ((o->op_flags & ~(OPf_WANT|OPf_SPECIAL))
                              | gvoid * OPf_WANT_VOID
                              | (defav ? OPf_SPECIAL : 0));
            }
            break;
        }

	case OP_RV2AV:
            if (OpWANT_SCALAR(o))
                S_check_for_bool_cxt(o, 1, OPpTRUEBOOL, 0);
            break;

	case OP_RV2HV:
	case OP_PADHV:
            /*'keys %h' in void or scalar context: skip the OP_KEYS
             * and perform the functionality directly in the RV2HV/PADHV
             * op
             */
            if (o->op_flags & OPf_REF) {
                OP *k = o->op_next;
                U8 want = (k->op_flags & OPf_WANT);
                if (   k
                    && k->op_type == OP_KEYS
                    && (   want == OPf_WANT_VOID
                        || want == OPf_WANT_SCALAR)
                    && !(k->op_private & OPpMAYBE_LVSUB)
                    && !(k->op_flags & OPf_MOD)
                ) {
                    o->op_next     = k->op_next;
                    o->op_flags   &= ~(OPf_REF|OPf_WANT);
                    o->op_flags   |= want;
#if OPpPADHV_ISKEYS != OPpRV2HV_ISKEYS
                    o->op_private |= (o->op_type == OP_PADHV ?
                                      OPpPADHV_ISKEYS : OPpRV2HV_ISKEYS);
#else
                    o->op_private |= OPpRV2HV_ISKEYS;
#endif
                    /* for keys(%lex), hold onto the OP_KEYS's targ
                     * since padhv doesn't have its own targ to return
                     * an int with */
                    if (!(o->op_type ==OP_PADHV && want == OPf_WANT_SCALAR))
                        op_null(k);
                }
            }

            /* see if %h is used in boolean context */
            if (OpWANT_SCALAR(o))
                S_check_for_bool_cxt(o, 1, OPpTRUEBOOL, OPpMAYBE_TRUEBOOL);


            if (o->op_type != OP_PADHV)
                break;
            /* FALLTHROUGH */
	case OP_PADAV:
            if (IS_TYPE(o, PADAV) && OpWANT_SCALAR(o))
                S_check_for_bool_cxt(o, 1, OPpTRUEBOOL, 0);
            /* FALLTHROUGH */
	case OP_PADSV:
            /* Skip over state($x) in void context.  */
            if (oldop && o->op_private == (OPpPAD_STATE|OPpLVAL_INTRO)
                && OpWANT_VOID(o))
            {
                OpNEXT(oldop) = OpNEXT(o);
                /*DEBUG_kv(Perl_deb(aTHX_ "rpeep: o=0x%p oldop->op_next=0x%p (Skip over state($x) in void context)\n", o, oldop->op_next));*/
                goto redo_nextstate;
            }
            if (ISNT_TYPE(o, PADAV))
                break;
            /* FALLTHROUGH */
	case OP_GV:
	    if (IS_TYPE(o, PADAV) || IS_TYPE(OpNEXT(o), RV2AV)) {
		OP* const pop = (IS_TYPE(o, PADAV))
                                 ? OpNEXT(o) : OpNEXT(OpNEXT(o));
		IV i;
		if (OP_TYPE_IS(pop, OP_CONST) &&
		    ((PL_op = OpNEXT(pop))) &&
		    IS_TYPE(OpNEXT(pop), AELEM) &&
		    !(OpNEXT(pop)->op_private &
		      (OPpLVAL_INTRO|OPpLVAL_DEFER|OPpDEREF|OPpMAYBE_LVSUB)) &&
		    (i = SvIV(((SVOP*)pop)->op_sv)) >= -128 && i <= 127)
		{
		    GV *gv;
		    if (cSVOPx(pop)->op_private & OPpCONST_STRICT)
			no_bareword_allowed(pop);
		    if (IS_TYPE(o, GV))
			op_null(OpNEXT(o));
		    op_null(OpNEXT(pop));
		    op_null(pop);
		    o->op_flags |= OpNEXT(pop)->op_flags & OPf_MOD;
		    OpNEXT(o) = OpNEXT(OpNEXT(pop));
		    o->op_private = (U8)i;
		    if (IS_TYPE(o, GV)) {
			gv = cGVOPo_gv;
			(void)GvAVn(gv);
			o->op_type = OP_AELEMFAST;
                        o->op_ppaddr = PL_ppaddr[OP_AELEMFAST];
		    }
		    else {
                        SV* av = pad_findmy_real(o->op_targ, PL_compcv);
                        if (AvSHAPED(av)) {
#ifndef AELEMSIZE_RT_NEGATIVE
                            if (i < 0) {
                                IV ix = AvFILLp(av)+1+i;
                                if (ix <= 255) {
                                    o->op_private = (U8)ix;
                                    DEBUG_k(Perl_deb(aTHX_ "aelemfast_lex_u %s[->%" IVdf "]\n",
                                                     PAD_COMPNAME_PV(o->op_targ), ix));
                                }
                                else
                                    goto lex;
                            }
#endif
                            o->op_type = OP_AELEMFAST_LEX_U;
                            o->op_ppaddr = PL_ppaddr[OP_AELEMFAST_LEX_U];
                            DEBUG_k(Perl_deb(aTHX_ "rpeep: aelemfast %s => aelemfast_lex_u\n",
                                             PAD_COMPNAME_PV(o->op_targ)));
                        } else {
                          lex:
                            DEBUG_k(Perl_deb(aTHX_ "rpeep: aelemfast %s => aelemfast_lex\n",
                                             PAD_COMPNAME_PV(o->op_targ)));
                            o->op_type = OP_AELEMFAST_LEX;
                            o->op_ppaddr = PL_ppaddr[OP_AELEMFAST];
                        }
                    }
		} else {
                    o->op_opt = 0;
                }
		if (ISNT_TYPE(o, GV))
		    break;
	    }

	    /* Remove $foo from the op_next chain in void context.  */
	    if (oldop
	     && (IS_RV2ANY_OP(OpNEXT(o)))
             && OpWANT_VOID(OpNEXT(o))
	     && !(OpNEXT(o)->op_private & OPpLVAL_INTRO))
	    {
		OpNEXT(oldop) = OpNEXT(OpNEXT(o));
		/* Reprocess the previous op if it is a nextstate, to
		   allow double-nextstate optimisation.  */
	      redo_nextstate:
		if (IS_TYPE(oldop, NEXTSTATE)) {
		    oldop->op_opt = 0;
		    o = oldop;
		    oldop = oldoldop;
		    oldoldop = NULL;
		    goto redo;
		}
		o = OpNEXT(oldop);
                goto redo;
	    }
	    else if (IS_TYPE(OpNEXT(o), RV2SV)) {
		if (!OpDEREF(OpNEXT(o))) {
		    op_null(OpNEXT(o));
		    o->op_private |= OpNEXT(o)->op_private & (OPpLVAL_INTRO
							       | OPpOUR_INTRO);
		    OpNEXT(o) = OpNEXT(OpNEXT(o));
                    OpTYPE_set(o, OP_GVSV);
		}
	    }
	    else if (IS_TYPE(OpNEXT(o), READLINE)
                  && IS_TYPE(OpNEXT(OpNEXT(o)), CONCAT)
                  && OpSTACKED(OpNEXT(OpNEXT(o))))
	    {
		/* Turn "$a .= <FH>" into an OP_RCATLINE. AMS 20010917 */
                OpTYPE_set(o, OP_RCATLINE);
		o->op_flags |= OPf_STACKED;
		op_null(OpNEXT(OpNEXT(o)));
		op_null(OpNEXT(o));
	    }

	    break;
        
        case OP_NOT:
            break;

        /* missing out on LOGOP OpOTHER branches here:
           {i_,s_}bit_{and,or,dor} {and,or,dor}assign
           regcomp substconst range once
           grepwhile mapwhile entergiven enterwhen entertry
         */
        case OP_ITER:
        case OP_ITER_ARY:
        case OP_ITER_LAZYIV:
        case OP_AND:
        case OP_OR:
        case OP_DOR:
	    while (IS_NULL_OP(OpOTHER(o)))
		OpOTHER(o) = OpNEXT(OpOTHER(o));
	    while (OpNEXT(o) && (   o->op_type == OpNEXT(o)->op_type
				  || IS_NULL_OP(OpNEXT(o))))
		OpNEXT(o) = OpNEXT(OpNEXT(o));

	    /* If we're an OR and our next is an AND in void context, we'll
	       follow its op_other on short circuit, same for reverse.
	       We can't do this with OP_DOR since if it's true, its return
	       value is the underlying value which must be evaluated
	       by the next op. */
	    if (OpNEXT(o) &&
	        (   (IS_AND_OP(o) && IS_OR_OP(OpNEXT(o)))
	         || (IS_OR_OP(o)  && IS_AND_OP(OpNEXT(o)))
	        )
	        && OpWANT_VOID(o)
	    ) {
	        OpNEXT(o) = OpOTHER(OpNEXT(o));
	    }
	    DEFER(OpOTHER(o));
          
	    o->op_opt = 1;
	    break;
	
	case OP_GREPWHILE:
            if (OpWANT_SCALAR(o))
                S_check_for_bool_cxt(o, 1, OPpTRUEBOOL, 0);
            /* FALLTHROUGH */
	case OP_COND_EXPR:
	case OP_MAPWHILE:
	case OP_ANDASSIGN:
	case OP_ORASSIGN:
	case OP_DORASSIGN:
	case OP_RANGE:
	case OP_ONCE:
	    while (IS_NULL_OP(OpOTHER(o)))
		OpOTHER(o) = OpNEXT(OpOTHER(o));
	    DEFER(OpOTHER(o));
	    break;

	case OP_ENTERLOOP:
	case OP_ENTERITER:
	    while (IS_NULL_OP(cLOOPo->op_redoop))
		cLOOPo->op_redoop = OpNEXT(cLOOPo->op_redoop);
	    while (IS_NULL_OP(cLOOPo->op_nextop))
		cLOOPo->op_nextop = OpNEXT(cLOOPo->op_nextop);
	    while (IS_NULL_OP(cLOOPo->op_lastop))
		cLOOPo->op_lastop = OpNEXT(cLOOPo->op_lastop);
	    /* a while(1) loop doesn't have an op_next that escapes the
	     * loop, so we have to explicitly follow the op_lastop to
	     * process the rest of the code */
	    DEFER(cLOOPo->op_lastop);
	    break;

        case OP_ENTERTRY:
	    assert(IS_TYPE(OpOTHER(o), LEAVETRY));
	    DEFER(OpOTHER(o));
	    break;

	case OP_SUBST:
            if (OpWANT_SCALAR(o))
                S_check_for_bool_cxt(o, 1, OPpTRUEBOOL, 0);
	    assert(!(cPMOPo->op_pmflags & PMf_ONCE));
	    while (OP_TYPE_IS(cPMOPo->op_pmstashstartu.op_pmreplstart, OP_NULL))
		cPMOPo->op_pmstashstartu.op_pmreplstart
		    = OpNEXT(cPMOPo->op_pmstashstartu.op_pmreplstart);
	    DEFER(cPMOPo->op_pmstashstartu.op_pmreplstart);
	    break;

	case OP_SORT: {
	    OP *oright;

	    if (OpSPECIAL(o)) {
                /* first arg is a code block */
                OP * const nullop = OpSIBLING(OpFIRST(o));
                OP * kid          = OpFIRST(nullop);

                assert(IS_NULL_OP(nullop));
		assert(IS_TYPE(kid, SCOPE)
                       || OP_TYPE_WAS_NN(kid, OP_LEAVE));
                /* since OP_SORT doesn't have a handy op_other-style
                 * field that can point directly to the start of the code
                 * block, store it in the otherwise-unused op_next field
                 * of the top-level OP_NULL. This will be quicker at
                 * run-time, and it will also allow us to remove leading
                 * OP_NULLs by just messing with op_nexts without
                 * altering the basic op_first/op_sibling layout. */
                kid = OpFIRST(kid);
                assert(
                       OP_TYPE_IS_OR_WAS_NN(kid, OP_NEXTSTATE)
                    || OP_TYPE_IS_OR_WAS_NN(kid, OP_DBSTATE)
                    || IS_TYPE(kid, STUB)
                    || IS_TYPE(kid, ENTER)
                    || (PL_parser && PL_parser->error_count));
                OpNEXT(nullop) = OpNEXT(kid);
                DEFER(OpNEXT(nullop));
	    }

	    /* check that RHS of sort is a single plain array */
	    oright = OpFIRST(o);
	    if (!oright || ISNT_TYPE(oright, PUSHMARK))
		break;

	    if (o->op_private & OPpSORT_INPLACE)
		break;

	    /* reverse sort ... can be optimised.  */
	    if (!OpHAS_SIBLING(cUNOPo)) {
		/* Nothing follows us on the list. */
		OP * const reverse = OpNEXT(o);

		if (IS_TYPE(reverse, REVERSE) &&
		    OpWANT_LIST(reverse)) {
		    OP * const pushmark = OpFIRST(reverse);
		    if (OP_TYPE_IS(pushmark, OP_PUSHMARK)
			&& OpSIBLING(cUNOPx(pushmark)) == o) {
			/* reverse -> pushmark -> sort */
			o->op_private |= OPpSORT_REVERSE;
			op_null(reverse);
			OpNEXT(pushmark) = OpNEXT(oright);
			op_null(oright);
		    }
		}
	    }

	    break;
	}

	case OP_REVERSE: {
	    OP *ourmark, *theirmark, *ourlast, *iter, *expushmark, *rv2av;
	    OP *gvop = NULL;
	    LISTOP *enter, *exlist;

	    if (o->op_private & OPpSORT_INPLACE)
		break;

	    enter = (LISTOP *) OpNEXT(o);
	    if (!enter)
		break;
	    if (IS_NULL_OP(enter)) {
		enter = (LISTOP *) OpNEXT(enter);
		if (!enter)
		    break;
	    }
	    /* for $a (...) will have OP_GV then OP_RV2GV here.
	       for (...) just has an OP_GV.  */
	    if (IS_TYPE(enter, GV)) {
		gvop = (OP *) enter;
		enter = (LISTOP *) OpNEXT(enter);
		if (!enter)
		    break;
		if (IS_TYPE(enter, RV2GV)) {
		  enter = (LISTOP *) OpNEXT(enter);
		  if (!enter)
		    break;
		}
	    }

	    if (ISNT_TYPE(enter, ENTERITER))
		break;

	    iter = OpNEXT(enter);
	    if (!iter || !OP_IS_ITER(iter->op_type))
		break;
	    
	    expushmark = OpFIRST(enter);
	    if (NO_OP_TYPE_OR_WASNT(expushmark, OP_PUSHMARK))
		break;

	    exlist = (LISTOP *) OpSIBLING(expushmark);
	    if (NO_OP_TYPE_OR_WASNT(exlist, OP_LIST))
		break;

	    if (OpLAST(exlist) != o) {
		/* Mmm. Was expecting to point back to this op.  */
		break;
	    }
	    theirmark = OpFIRST(exlist);
	    if (NO_OP_TYPE_OR_WASNT(theirmark, OP_PUSHMARK))
		break;

	    if (OpSIBLING(theirmark) != o) {
		/* There's something between the mark and the reverse, eg
		   for (1, reverse (...))
		   so no go.  */
		break;
	    }

	    ourmark = OpFIRST(o);
	    if (NO_OP_TYPE_OR_WASNT(ourmark, OP_PUSHMARK))
		break;

	    ourlast = OpLAST(o);
	    if (!ourlast || OpNEXT(ourlast) != o)
		break;

	    rv2av = OpSIBLING(ourmark);
	    if (OP_TYPE_IS(rv2av, OP_RV2AV) && !OpHAS_SIBLING(rv2av)
		&& rv2av->op_flags == (OPf_WANT_LIST | OPf_KIDS)) {
		/* We're just reversing a single array.  */
		rv2av->op_flags = OPf_WANT_SCALAR | OPf_KIDS | OPf_REF;
		enter->op_flags |= OPf_STACKED;
	    }

	    /* We don't have control over who points to theirmark, so sacrifice
	       ours.  */
	    OpNEXT(theirmark) = OpNEXT(ourmark);
	    theirmark->op_flags = ourmark->op_flags;
	    OpNEXT(ourlast) = gvop ? gvop : (OP *) enter;
	    op_null(ourmark);
	    op_null(o);
	    enter->op_private |= OPpITER_REVERSED;
	    iter->op_private |= OPpITER_REVERSED;

            oldoldop = NULL;
            oldop    = ourlast;
            o        = OpNEXT(oldop);
            goto redo;
            NOT_REACHED; /* NOTREACHED */
	    break;
	}

	case OP_QR:
	case OP_MATCH:
	    if (!(cPMOPo->op_pmflags & PMf_ONCE)) {
		assert (!cPMOPo->op_pmstashstartu.op_pmreplstart);
	    }
	    break;

	case OP_RUNCV:
	    if (!(o->op_private & OPpOFFBYONE) && !CvCLONE(PL_compcv)
	     && (!CvANON(PL_compcv) || (!PL_cv_has_eval && !PL_perldb)))
	    {
		SV *sv;
		if (CvEVAL(PL_compcv)) sv = UNDEF;
		else {
		    sv = newRV((SV *)PL_compcv);
		    sv_rvweaken(sv);
		    SvREADONLY_on(sv);
		}
                OpTYPE_set(o, OP_CONST);
		o->op_flags |= OPf_SPECIAL;
		cSVOPo->op_sv = sv;
	    }
	    break;

	case OP_SASSIGN:
	    if (OP_GIMME_VOID(o)
                || (IS_TYPE(OpNEXT(o), LINESEQ)
                    && (IS_TYPE(OpNEXT(OpNEXT(o)), LEAVESUB)
                        || (IS_TYPE(OpNEXT(OpNEXT(o)), RETURN)
                            && !CvLVALUE(PL_compcv)))))
	    {
		OP *right = OpFIRST(o);
		if (right) {
                    /*   sassign
                    *      RIGHT
                    *      substr
                    *         pushmark
                    *         arg1
                    *         arg2
                    *         ...
                    * becomes
                    *
                    *  ex-sassign
                    *     substr
                    *        pushmark
                    *        RIGHT
                    *        arg1
                    *        arg2
                    *        ...
                    */
		    OP *left = OpSIBLING(right);
		    if (IS_TYPE(left, SUBSTR)
			 && (left->op_private & 7) < 4) {
			op_null(o);
                        /* cut out right */
                        op_sibling_splice(o, NULL, 1, NULL);
                        /* and insert it as second child of OP_SUBSTR */
                        op_sibling_splice(left, OpFIRST(left), 0, right);
			left->op_private |= OPpSUBSTR_REPL_FIRST;
			left->op_flags =
			    (o->op_flags & ~OPf_WANT) | OPf_WANT_VOID;
		    }
		}
	    }
	    break;

	case OP_AASSIGN: {
            int l, r, lr, lscalars, rscalars;

            /* handle common vars detection, e.g. ($a,$b) = ($b,$a).
               Note that we do this now rather than in newASSIGNOP(),
               since only by now are aliased lexicals flagged as such

               See the essay "Common vars in list assignment" above for
               the full details of the rationale behind all the conditions
               below.

               PL_generation sorcery:
               To detect whether there are common vars, the global var
               PL_generation is incremented for each assign op we scan.
               Then we run through all the lexical variables on the LHS,
               of the assignment, setting a spare slot in each of them to
               PL_generation.  Then we scan the RHS, and if any lexicals
               already have that value, we know we've got commonality.
               Also, if the generation number is already set to
               PERL_INT_MAX, then the variable is involved in aliasing, so
               we also have potential commonality in that case.
             */

            PL_generation++;
            /* scan LHS */
            lscalars = 0;
            l = S_aassign_scan(aTHX_ OpLAST(o),  FALSE, 1, &lscalars);
            /* scan RHS */
            rscalars = 0;
            r = S_aassign_scan(aTHX_ OpFIRST(o), TRUE, 1, &rscalars);
            lr = (l|r);


            /* After looking for things which are *always* safe, this main
             * if/else chain selects primarily based on the type of the
             * LHS, gradually working its way down from the more dangerous
             * to the more restrictive and thus safer cases */

            if (   !l                      /* () = ....; */
                || !r                      /* .... = (); */
                || !(l & ~AAS_SAFE_SCALAR) /* (undef, pos()) = ...; */
                || !(r & ~AAS_SAFE_SCALAR) /* ... = (1,2,length,undef); */
                || (lscalars < 2)          /* ($x, undef) = ... */
            ) {
                NOOP; /* always safe */
            }
            else if (l & AAS_DANGEROUS) {
                /* always dangerous */
                o->op_private |= OPpASSIGN_COMMON_SCALAR;
                o->op_private |= OPpASSIGN_COMMON_AGG;
            }
            else if (l & (AAS_PKG_SCALAR|AAS_PKG_AGG)) {
                /* package vars are always dangerous - too many
                 * aliasing possibilities */
                if (l & AAS_PKG_SCALAR)
                    o->op_private |= OPpASSIGN_COMMON_SCALAR;
                if (l & AAS_PKG_AGG)
                    o->op_private |= OPpASSIGN_COMMON_AGG;
            }
            else if (l & ( AAS_MY_SCALAR|AAS_MY_AGG
                          |AAS_LEX_SCALAR|AAS_LEX_AGG))
            {
                /* LHS contains only lexicals and safe ops */

                if (l & (AAS_MY_AGG|AAS_LEX_AGG))
                    o->op_private |= OPpASSIGN_COMMON_AGG;

                if (l & (AAS_MY_SCALAR|AAS_LEX_SCALAR)) {
                    if (lr & AAS_LEX_SCALAR_COMM)
                        o->op_private |= OPpASSIGN_COMMON_SCALAR;
                    else if (   !(l & AAS_LEX_SCALAR)
                             && (r & AAS_DEFAV))
                    {
                        /* falsely mark
                         *    my (...) = @_
                         * as scalar-safe for performance reasons.
                         * (it will still have been marked _AGG if necessary */
                        NOOP;
                    }
                    else if (r  & (AAS_PKG_SCALAR|AAS_PKG_AGG|AAS_DANGEROUS))
                        /* if there are only lexicals on the LHS and no
                         * common ones on the RHS, then we assume that the
                         * only way those lexicals could also get
                         * on the RHS is via some sort of dereffing or
                         * closure, e.g.
                         *    $r = \$lex;
                         *    ($lex, $x) = (1, $$r)
                         * and in this case we assume the var must have
                         *  a bumped ref count. So if its ref count is 1,
                         *  it must only be on the LHS.
                         */
                        o->op_private |= OPpASSIGN_COMMON_RC1;
                }
            }

            /* ... = ($x)
             * may have to handle aggregate on LHS, but we can't
             * have common scalars. */
            if (rscalars < 2)
                o->op_private &=
                        ~(OPpASSIGN_COMMON_SCALAR|OPpASSIGN_COMMON_RC1);

            if (OpWANT_SCALAR(o))
                S_check_for_bool_cxt(o, 1, OPpASSIGN_TRUEBOOL, 0);
	    break;
        }

        case OP_REF:
            /* see if ref() is used in boolean context */
            if (OpWANT_SCALAR(o))
                S_check_for_bool_cxt(o, 1, OPpTRUEBOOL, OPpMAYBE_TRUEBOOL);
            break;

        case OP_LENGTH:
            /* see if the op is used in known boolean context */
            if (OpWANT_SCALAR(o))
                /* but not if OA_TARGLEX optimisation is enabled */
                /* && !(o->op_private & OPpTARGET_MY)) */
                S_check_for_bool_cxt(o, 1, OPpTRUEBOOL,
                                     OPpLENGTH_MAYBE_TRUEBOOL);
            break;

        case OP_BLESS:
            if (!OpNEXT(o) && IS_CONST_OP(OpLAST(o)) &&
                PL_compcv && !CvCLONE(PL_compcv))
            {   /* Type inference:
                 * If this is the last op of the body,
                 * set the type of the containing sub,
                 * as sub foo :type { bless{},"type" }
                 * Else TODO the type of the assigned variable.
                 */
                OP* b = OpLAST(o);
                SV* name = cSVOPx_sv(b);
                CvTYPED_on(PL_compcv);
                CvTYPE_set(PL_compcv, gv_stashsv(name, SvUTF8(name)|GV_NO_SVGMAGIC));
            }
            break;

        case OP_POS:
            /* see if the op is used in known boolean context */
            if (OpWANT_SCALAR(o))
                S_check_for_bool_cxt(o, 1, OPpTRUEBOOL, 0);
            break;

	case OP_CUSTOM: {
	    Perl_cpeep_t cpeep = 
		XopENTRYCUSTOM(o, xop_peep);
	    if (cpeep)
		cpeep(aTHX_ o, oldop);
	    break;
	}
	    
	}
        /* did we just null the current op? If so, re-process it to handle
         * eliding "empty" ops from the chain */
        if (IS_NULL_OP(o) && oldop && OpNEXT(oldop) == o) {
            o->op_opt = 0;
            o = oldop;
        }
        else {
            oldoldop = oldop;
            oldop = o;
        }
    }
    LEAVE;
}

/*
=for apidoc peep
=cut
*/
void
Perl_peep(pTHX_ OP *o)
{
    CALL_RPEEP(o);
}

/*
=head1 Custom Operators

=for apidoc Ao||custom_op_xop
Return the XOP structure for a given custom op.  This macro should be
considered internal to C<OP_NAME> and the other access macros: use them instead.
This macro does calls the function custom_op_get_field(). 
Prior to 5.19.6, this was implemented as a function.

=cut
*/

XOPRETANY
Perl_custom_op_get_field(pTHX_ const OP *o, const xop_flags_enum field)
{
    SV *keysv;
    HE *he = NULL;
    XOP *xop;

    static const XOP xop_null = { 0, 0, 0, 0, 0, 0 };

    PERL_ARGS_ASSERT_CUSTOM_OP_GET_FIELD;
    assert(IS_TYPE(o, CUSTOM));

    /* This is wrong. It assumes a function pointer can be cast to IV,
     * which isn't guaranteed, but this is what the old custom OP code
     * did. In principle it should be safer to Copy the bytes of the
     * pointer into a PV: since the new interface is hidden behind
     * functions, this can be changed later if necessary.  */
    /* Change custom_op_xop if this ever happens */
    keysv = sv_2mortal(newSViv(PTR2IV(o->op_ppaddr)));

    if (PL_custom_ops)
	he = hv_fetch_ent(PL_custom_ops, keysv, 0, 0);

    /* assume noone will have just registered a desc */
    if (!he && PL_custom_op_names &&
	(he = hv_fetch_ent(PL_custom_op_names, keysv, 0, 0))
    ) {
	const char *pv;
	STRLEN l;

	/* XXX does all this need to be shared mem? */
	Newxz(xop, 1, XOP);
	pv = SvPV(HeVAL(he), l);
	XopENTRY_set(xop, xop_name, savepvn(pv, l));
	if (PL_custom_op_descs &&
	    (he = hv_fetch_ent(PL_custom_op_descs, keysv, 0, 0))
	) {
	    pv = SvPV(HeVAL(he), l);
	    XopENTRY_set(xop, xop_desc, savepvn(pv, l));
	}
	Perl_custom_op_register(aTHX_ o->op_ppaddr, xop);
    }
    else {
	if (!he)
	    xop = (XOP *)&xop_null;
	else
	    xop = INT2PTR(XOP *, SvIV(HeVAL(he)));
    }
    {
	XOPRETANY any;
	if(field == XOPe_xop_ptr) {
	    any.xop_ptr = xop;
	} else {
	    const U32 flags = XopFLAGS(xop);
	    if(flags & field) {
		switch(field) {
		case XOPe_xop_name:
		    any.xop_name = xop->xop_name;
		    break;
		case XOPe_xop_desc:
		    any.xop_desc = xop->xop_desc;
		    break;
		case XOPe_xop_class:
		    any.xop_class = xop->xop_class;
		    break;
		case XOPe_xop_peep:
		    any.xop_peep = xop->xop_peep;
		    break;
		default:
		    NOT_REACHED; /* NOTREACHED */
		    break;
		}
	    } else {
		switch(field) {
		case XOPe_xop_name:
		    any.xop_name = XOPd_xop_name;
		    break;
		case XOPe_xop_desc:
		    any.xop_desc = XOPd_xop_desc;
		    break;
		case XOPe_xop_class:
		    any.xop_class = XOPd_xop_class;
		    break;
		case XOPe_xop_peep:
		    any.xop_peep = XOPd_xop_peep;
		    break;
		default:
		    NOT_REACHED; /* NOTREACHED */
		    break;
		}
	    }
	}
        /* On some platforms (HP-UX, IA64) gcc emits a warning for this function:
         * op.c: In function 'Perl_custom_op_get_field':
         * op.c:...: warning: 'any.xop_name' may be used uninitialized in this function [-Wmaybe-uninitialized]
         * This is because on those platforms (with -DEBUGGING) NOT_REACHED
         * expands to assert(0), which expands to ((0) ? (void)0 :
         * __assert(...)), and gcc doesn't know that __assert can never return. */
	return any;
    }
}

/*
=for apidoc Ao|void	|custom_op_register
Register a custom op.  See L<perlguts/"Custom Operators">.

=cut
*/
void
Perl_custom_op_register(pTHX_ Perl_ppaddr_t ppaddr, const XOP *xop)
{
    SV *keysv;

    PERL_ARGS_ASSERT_CUSTOM_OP_REGISTER;

    /* see the comment in custom_op_xop */
    keysv = sv_2mortal(newSViv(PTR2IV(ppaddr)));

    if (!PL_custom_ops)
	PL_custom_ops = newHV();

    if (!hv_store_ent(PL_custom_ops, keysv, newSViv(PTR2IV(xop)), 0))
	Perl_croak(aTHX_ "panic: can't register custom OP %s", xop->xop_name);

    PL_maxo++;
}

/*
=for apidoc core_prototype

This function assigns the prototype of the named core function to C<sv>, or
to a new mortal SV if C<sv> is C<NULL>.  It returns the modified C<sv>, or
C<NULL> if the core function has no prototype.  C<code> is a code as returned
by C<keyword()>.  It must not be equal to 0.

=cut
*/

SV *
Perl_core_prototype(pTHX_ SV *sv, const char *name, const int code,
                          int * const opnum)
{
    int i = 0, n = 0, seen_question = 0, defgv = 0;
    I32 oa;
#define MAX_ARGS_OP ((sizeof(I32) - 1) * 2)
    char str[ MAX_ARGS_OP * 2 + 2 ]; /* One ';', one '\0' */
    bool nullret = FALSE;

    PERL_ARGS_ASSERT_CORE_PROTOTYPE;

    assert (code);

    if (!sv) sv = sv_newmortal();

#define retsetpvs(x,y) sv_setpvs(sv, x); if (opnum) *opnum=(y); return sv

    switch (code < 0 ? -code : code) {
    case KEY_and   : case KEY_chop: case KEY_chomp:
    case KEY_cmp   : case KEY_defined: case KEY_delete: case KEY_exec  :
    case KEY_exists: case KEY_eq     : case KEY_ge    : case KEY_goto  :
    case KEY_grep  : case KEY_gt     : case KEY_last  : case KEY_le    :
    case KEY_lt    : case KEY_map    : case KEY_ne    : case KEY_next  :
    case KEY_or    : case KEY_print  : case KEY_printf: case KEY_qr    :
    case KEY_redo  : case KEY_require: case KEY_return: case KEY_say   :
    case KEY_select: case KEY_sort   : case KEY_split : case KEY_system:
    case KEY_x     : case KEY_xor    :
	if (!opnum) return NULL; nullret = TRUE; goto findopnum;
    case KEY_glob:    retsetpvs("_;", OP_GLOB);
    case KEY_keys:    retsetpvs("\\[%@]", OP_KEYS);
    case KEY_values:  retsetpvs("\\[%@]", OP_VALUES);
    case KEY_each:    retsetpvs("\\[%@]", OP_EACH);
    case KEY_pos:     retsetpvs(";\\[$*]", OP_POS);
    case KEY_dump:    retsetpvs(";\\[$*]", OP_DUMP);
    case KEY_class: case KEY_role: case KEY_method: case KEY_multi:
        retsetpvs("$&", 0);
    case KEY_has:
        retsetpvs("$", 0);
    case KEY___FILE__: case KEY___LINE__: case KEY___PACKAGE__:
	retsetpvs("", 0);
    case KEY_evalbytes:
	name = "entereval"; break;
    case KEY_readpipe:
	name = "backtick";
    }

#undef retsetpvs

  findopnum:
    while (i < MAXO) {	/* The slow way. */
	if (strEQ(name, PL_op_name[i])
	    || strEQ(name, PL_op_desc[i]))
	{
	    if (nullret) { assert(opnum); *opnum = i; return NULL; }
	    goto found;
	}
	i++;
    }
    return NULL;
  found:
    defgv = PL_opargs[i] & OA_DEFGV;
    oa = PL_opargs[i] >> OASHIFT;
    while (oa) {
	if (oa & OA_OPTIONAL && !seen_question &&
            (!defgv || (oa & (OA_OPTIONAL - 1)) == OA_FILEREF
                    || i  == OP_STUDY)
            ) {
	    seen_question = 1;
	    str[n++] = ';';
	}
	if ((oa & (OA_OPTIONAL - 1)) >= OA_AVREF
	    && (oa & (OA_OPTIONAL - 1)) <= OA_SCALARREF
	    /* But globs are already references (kinda) */
	    && (oa & (OA_OPTIONAL - 1)) != OA_FILEREF
	) {
	    str[n++] = '\\';
	}
	if ((oa & (OA_OPTIONAL - 1)) == OA_SCALARREF
	 && !scalar_mod_type(NULL, i)) {
	    str[n++] = '[';
	    str[n++] = '$';
	    str[n++] = '@';
	    str[n++] = '%';
	    if (i == OP_LOCK || i == OP_STUDY || i == OP_UNDEF)
                str[n++] = '&';
	    str[n++] = '*';
	    str[n++] = ']';
	}
	else str[n++] = ("?$@@%&*$")[oa & (OA_OPTIONAL - 1)];
	if (oa & OA_OPTIONAL && defgv && str[n-1] == '$') {
	    str[n-1] = '_'; defgv = 0;
	}
	oa = oa >> 4;
    }
    if (code == -KEY_not || code == -KEY_getprotobynumber) str[n++] = ';';
    str[n++] = '\0';
    sv_setpvn(sv, str, n - 1);
    if (opnum) *opnum = i;
    return sv;
}

/*
=for apidoc coresub_op

Provide the coreargs arguments for &CORE::* subroutines, usually with
matching ops. coreargssv is either the opnum (as UV) or the name (as
PV) of no such op exists.
code is the result of C<keyword()>, and maybe negative.
See F<gv.c>: C<S_maybe_add_coresub()>.

=cut
*/
OP *
Perl_coresub_op(pTHX_ SV * const coreargssv, const int code,
                      const int opnum)
{
    OP * const argop = newSVOP(OP_COREARGS,0,coreargssv);
    OP *o;

    PERL_ARGS_ASSERT_CORESUB_OP;

    switch (opnum) {
    case 0:
        /* TODO: CLASS,ROLE,METHOD,MULTI,HAS */
	return op_append_elem(OP_LINESEQ, argop,
	               newSLICEOP(0, newSVOP(OP_CONST, 0, newSViv(-code % 3)),
	                          newOP(OP_CALLER,0)));
    case OP_EACH:
    case OP_KEYS:
    case OP_VALUES:
	o = newUNOP(OP_AVHVSWITCH,0,argop);
	o->op_private = opnum-OP_EACH;
	return o;
    case OP_SELECT: /* which represents OP_SSELECT as well */
	if (code)
	    return newCONDOP(
	                 0,
	                 newBINOP(OP_GT, 0,
	                          newAVREF(newGVOP(OP_GV, 0, PL_defgv)),
	                          newSVOP(OP_CONST, 0, newSVuv(1))
	                         ),
	                 coresub_op(newSVuv((UV)OP_SSELECT), 0,
	                            OP_SSELECT),
	                 coresub_op(coreargssv, 0, OP_SELECT)
	           );
	/* FALLTHROUGH */
    default:
	switch (PL_opargs[opnum] & OA_CLASS_MASK) {
	case OA_BASEOP:
	    return op_append_elem(
	                OP_LINESEQ, argop,
	                newOP(opnum,
	                      opnum == OP_WANTARRAY || opnum == OP_RUNCV
	                        ? OPpOFFBYONE << 8 : 0)
	           );
	case OA_BASEOP_OR_UNOP:
	    if (opnum == OP_ENTEREVAL) {
		o = newUNOP(OP_ENTEREVAL,OPpEVAL_COPHH<<8,argop);
		if (code == -KEY_evalbytes) o->op_private |= OPpEVAL_BYTES;
	    }
	    else o = newUNOP(opnum,0,argop);
	    if (opnum == OP_CALLER) o->op_private |= OPpOFFBYONE;
	    else {
	  onearg:
	      if (is_handle_constructor(o, 1))
		argop->op_private |= OPpCOREARGS_DEREF1;
	      if (scalar_mod_type(NULL, opnum))
		argop->op_private |= OPpCOREARGS_SCALARMOD;
	    }
	    return o;
	default:
	    o = op_convert_list(opnum,OPf_SPECIAL*(opnum == OP_GLOB),argop);
	    if (is_handle_constructor(o, 2))
		argop->op_private |= OPpCOREARGS_DEREF2;
	    if (opnum == OP_SUBSTR) {
		o->op_private |= OPpMAYBE_LVSUB;
		return o;
	    }
	    else goto onearg;
	}
    }
}

/*
=for apidoc report_redefined_cv

If a CV is overwritten, warn by whom
when use warnings 'redefine' is in effect.
=cut
*/
void
Perl_report_redefined_cv(pTHX_ const SV *name, const CV *old_cv,
                         SV * const *new_const_svp)
{
    const char *hvname;
    bool is_const = !!CvCONST(old_cv);
    SV *old_const_sv = is_const ? cv_const_sv(old_cv) : NULL;

    PERL_ARGS_ASSERT_REPORT_REDEFINED_CV;

    if (is_const && new_const_svp && old_const_sv == *new_const_svp)
	return;
	/* They are 2 constant subroutines generated from
	   the same constant. This probably means that
	   they are really the "same" proxy subroutine
	   instantiated in 2 places. Most likely this is
	   when a constant is exported twice.  Don't warn.
	*/
    if (
	(ckWARN(WARN_REDEFINE)
	 && !(
		CvGV(old_cv) && GvSTASH(CvGV(old_cv))
	     && HvNAMELEN(GvSTASH(CvGV(old_cv))) == 7
	     && (hvname = HvNAME(GvSTASH(CvGV(old_cv))),
		 memEQc(hvname, "autouse"))
	     )
	)
     || (is_const
	 && ckWARN_d(WARN_REDEFINE)
	 && (!new_const_svp || sv_cmp(old_const_sv, *new_const_svp))
	)
      ) {
        /* which module/srcline caused this forced require/do/eval redefinition */
        if (cxstack_ix >= 0) {
            const COP * const cop = cxstack[cxstack_ix].blk_oldcop;

            if (cop) {
                const COP * const ccop = closest_cop(cop, OpSIBLING(cop), PL_op, FALSE);
                const char *file = ccop ? OutCopFILE(ccop) : NULL;
                long line;
                if (!file || !*file) goto no_caller;
                line = (long)CopLINE(ccop);
                if (!line) goto no_caller;
                Perl_warner(aTHX_ packWARN(WARN_REDEFINE),
                            is_const
			    ? "Constant subroutine %" SVf " redefined, called by %s:%ld"
			    : "Subroutine %" SVf " redefined, called by %s:%ld",
                            SVfARG(name), file, line);
            } else {
                goto no_caller;
            }

        } else {
        no_caller:
            Perl_warner(aTHX_ packWARN(WARN_REDEFINE),
                        is_const
                          ? "Constant subroutine %" SVf " redefined"
                          : "Subroutine %" SVf " redefined",
                        SVfARG(name));
        }
    }
}

/*
=head1 Hook manipulation

These functions provide convenient and thread-safe means of manipulating
hook variables.

=cut
*/

/*
=for apidoc Am|void  |wrap_op_checker  |Optype opcode  \
			|Perl_check_t new_checker|Perl_check_t *old_checker_p

Puts a C function into the chain of check functions for a specified op
type.  This is the preferred way to manipulate the L</PL_check> array.
C<opcode> specifies which type of op is to be affected.  C<new_checker>
is a pointer to the C function that is to be added to that opcode's
check chain, and C<old_checker_p> points to the storage location where a
pointer to the next function in the chain will be stored.  The value of
C<new_checker> is written into the L</PL_check> array, while the value
previously stored there is written to C<*old_checker_p>.

L</PL_check> is global to an entire process, and a module wishing to
hook op checking may find itself invoked more than once per process,
typically in different threads.  To handle that situation, this function
is idempotent.  The location C<*old_checker_p> must initially (once
per process) contain a null pointer.  A C variable of static duration
(declared at file scope, typically also marked C<static> to give
it internal linkage) will be implicitly initialised appropriately,
if it does not have an explicit initialiser.  This function will only
actually modify the check chain if it finds C<*old_checker_p> to be null.
This function is also thread safe on the small scale.  It uses appropriate
locking to avoid race conditions in accessing L</PL_check>.

When this function is called, the function referenced by C<new_checker>
must be ready to be called, except for C<*old_checker_p> being unfilled.
In a threading situation, C<new_checker> may be called immediately,
even before this function has returned.  C<*old_checker_p> will always
be appropriately set before C<new_checker> is called.  If C<new_checker>
decides not to do anything special with an op that it is given (which
is the usual case for most uses of op check hooking), it must chain the
check function referenced by C<*old_checker_p>.

Taken all together, XS code to hook an op checker should typically look
something like this:

    static Perl_check_t nxck_frob;
    static OP *myck_frob(pTHX_ OP *op) {
	...
	op = nxck_frob(aTHX_ op);
	...
	return op;
    }
    BOOT:
	wrap_op_checker(OP_FROB, myck_frob, &nxck_frob);

If you want to influence compilation of calls to a specific subroutine,
then use L</cv_set_call_checker_flags> rather than hooking checking of
all C<entersub> ops.

=cut
*/

void
Perl_wrap_op_checker(pTHX_ Optype opcode,
    Perl_check_t new_checker, Perl_check_t *old_checker_p)
{
    dVAR;

    PERL_UNUSED_CONTEXT;
    PERL_ARGS_ASSERT_WRAP_OP_CHECKER;
    if (*old_checker_p) return;
    OP_CHECK_MUTEX_LOCK;
    if (!*old_checker_p) {
	*old_checker_p = PL_check[opcode];
	PL_check[opcode] = new_checker;
    }
    OP_CHECK_MUTEX_UNLOCK;
}

#include "XSUB.h"

/*
=for apidoc const_sv_xsub

Efficient sub that returns a constant scalar value.

=cut
*/
static void
S_const_sv_xsub(pTHX_ CV* cv)
{
    dXSARGS;
    SV * const sv = MUTABLE_SV(XSANY.any_ptr);
    PERL_ARGS_ASSERT_CONST_SV_XSUB;
    PERL_UNUSED_ARG(items);
    if (!sv) {
	XSRETURN(0);
    }
    EXTEND_NNEG(sp, 1);
    ST(0) = sv;
    XSRETURN(1);
}

/*
=for apidoc const_av_xsub

Efficient sub that returns a constant array value.

=cut
*/
static void
S_const_av_xsub(pTHX_ CV* cv)
{
    dXSARGS;
    AV * const av = MUTABLE_AV(XSANY.any_ptr);
    PERL_ARGS_ASSERT_CONST_AV_XSUB;
    SP -= items;
    assert(av);
#ifndef DEBUGGING
    if (!av) {
	XSRETURN(0);
    }
#endif
    if (SvRMAGICAL(av))
	Perl_croak(aTHX_ "Magical list constants are not supported");
    if (GIMME_V != G_ARRAY) {
	EXTEND_NNEG(SP, 1);
	ST(0) = sv_2mortal(newSViv((IV)AvFILLp(av)+1));
	XSRETURN(1);
    }
    EXTEND(SP, AvFILLp(av)+1);
    Copy(AvARRAY(av), &ST(0), AvFILLp(av)+1, SV *);
    XSRETURN(AvFILLp(av)+1);
}

/*
=for apidoc Mu_sv_xsub

XS template to return an object scalar value from it's compile-time
field offset.

=cut
*/
static void
S_Mu_sv_xsub(pTHX_ CV* cv)
{
    dXSARGS;
    const U32 ix = XSANY.any_u32;
    SV* self = ST(0);
    PERL_ARGS_ASSERT_MU_SV_XSUB;
    if (items != 1 || !SvROK(self)) {
        croak_xs_usage(cv, "object");
    } else
        self = SvRV(self);
    /* if (CvLVALUE(cv) && (PL_op->op_private & OPpLVAL_INTRO)) */
    assert(AvARRAY(self));
    assert((U32)AvFILLp(self) >= ix);
    ST(0) = AvARRAY(self)[ix];
    XSRETURN(1);
}

/*
=for apidoc Mu_av_xsub

XS template to set or return object array values from it's
compile-time field offset.

    class MY {
      has @a;
    }
    my $c = new MY;
    $c->a = (0..2); # (0,1,2)
    print scalar $c->a; # 3
    $c->a = 1;     # (1)
    $c->a = 0..2;  # (0,1,2)
    $c->a = 1,2;   # (1,2)

=cut
*/
static void
S_Mu_av_xsub(pTHX_ CV* cv)
{
    dXSARGS;
    const U32 ix = XSANY.any_u32;
    SV* const self = ST(0);
    AV* av;
    U8 gimme = GIMME_V;
    PERL_ARGS_ASSERT_MU_AV_XSUB;
    if (items != 1 || !SvROK(self)) {
        croak_xs_usage(cv, "object");
    }
    av = (AV*)AvARRAY(SvRV(self))[ix];
    /* setters are usually G_SCALAR */
    if (CvLVALUE(cv) && (PL_op->op_private & OPpLVAL_INTRO)) {
        ST(0) = (SV*)av; /* set the av or hv */
        XSRETURN(1);
    }
    else if (gimme != G_ARRAY) {
        if (SvTYPE(av) == SVt_PVAV) /* scalar @a */
            ST(0) = sv_2mortal(newSViv((IV)AvFILLp(av)+1));
        else if (SvTYPE(av) == SVt_PVHV) /* scalar %a*/
            ST(0) = sv_2mortal(newSViv((IV)HvKEYS((HV*)av)));
        else
            Perl_croak(aTHX_ "Invalid object field type %x", SvTYPE(av));
	XSRETURN(1);
    }
    if (SvTYPE(av) == SVt_PVAV) {
        const SSize_t fill = AvFILL(av); /* last elem */
        if (fill >= 0) {
            EXTEND(SP, fill);
            Copy(AvARRAY(av), &ST(0), fill+1, SV *);
        }
        XSRETURN(fill+1);
    } else if (SvTYPE(av) == SVt_PVHV) { /* %a as list */
        HV* const hv = (HV* const)av;
        HE *he;
        const U32 keys = HvKEYS(hv);
        U32 i = 0;
        if (keys > 0) {
#if LONGSIZE > 2
            EXTEND_NNEG(SP, keys*2);
#else
            EXTEND(SP, keys*2);
#endif
            (void)hv_iterinit(hv);
            while ((he = hv_iternext(hv))) {
                ST(i++) = newSVhek(HeKEY_hek(he));
                ST(i++) = HeVAL(he);
            }
            XSRETURN(i-1);
        }
        XSRETURN(0);
    } else {
        Perl_croak(aTHX_ "Invalid object field type %x", SvTYPE(av));
    }
}

/*
=for apidoc class_isamagic

Set closed ISA magic to the array in pkg, either @ISA or @DOES.

=cut
*/
static void
S_class_isamagic(pTHX_ OP* o, SV* pkg, const char* what, int len)
{
    GV *gv; AV *av; SV *name;
    PERL_ARGS_ASSERT_CLASS_ISAMAGIC;

    av = (AV*)cSVOPx_sv(OpFIRST(o));
    name = newSVpvn_flags(SvPVX(pkg), SvCUR(pkg), SVs_TEMP|SvUTF8(pkg));
    sv_catpvn_nomg(name, what, len);
    gv = gv_fetchsv(name, GV_ADD, SVt_PVAV);
    SvREFCNT_dec(GvAV(gv));
    GvAV(gv) = av;
    SvREADONLY_off(av);
    sv_magic(MUTABLE_SV(av), MUTABLE_SV(gv), PERL_MAGIC_isa, NULL, 0);
    AvSHAPED_on(av);
    SvREADONLY_on(av);
 }

/*
=for apidoc class_role

Extend a parsed package block to a class or role,
and add its ISA and DOES arrays. They are closed by default.

:native is parsed as repr(CStruct). This needs a HvAUX flag as well.

Warn on existing packages.

=cut
*/
void
Perl_class_role(pTHX_ OP* o)
{
    bool is_role;
    SV *name; HV* stash;
    PERL_ARGS_ASSERT_CLASS_ROLE;

    if (IS_TYPE(o, LIST))
        o = OpSIBLING(OpFIRST(o));
    is_role = OpSPECIAL(o);
    name = cSVOPo->op_sv;

    if ((stash = gv_stashsv(name, 0)))
        /* diag_listed_as: package %s redefined as class */
        Perl_ck_warner(aTHX_ packWARN(WARN_REDEFINE),
                       "%s %" SVf " redefined as %s",
                       HvCLASS(stash) ? HvROLE(stash) ? "role"
                                                      : "class"
                                      : "package",
                       SVfARG(name), is_role ? "role" : "class");
    /* get the isa and does AV from the op, not some parser SVs, as
       the full class block was parsed with this, and there might be some
       s/// in some method.
       toke sets the CONST name to SPECIAL on a native repr.
       LIST-PUSHMARK - NAME - RV2AV-ISA_AV - RV2AV-DOES_AV */
    if (OpSIBLING(o)) {
        o = OpSIBLING(o);
        if (IS_TYPE(o, RV2AV)) {
            /* Mu is now implemented in universal.c as XS */
            /*Perl_load_module(aTHX_ PERL_LOADMOD_NOIMPORT,
              newSVpvs("Mu"), NULL);*/
            class_isamagic(o, name, "::ISA", 5);
        }
        o = OpSIBLING(o);
        if (IS_TYPE(o, RV2AV)) {
            class_isamagic(o, name, "::DOES", 6);
        }
    }
    /*package(pop);*/ /* free's o */
    SAVEGENERICSV(PL_curstash);
    save_item(PL_curstname);
    PL_curstash = (HV *)SvREFCNT_inc(gv_stashsv(name, GV_ADD));
    sv_setsv(PL_curstname, name);
    PL_hints |= HINT_BLOCK_SCOPE;
    PL_parser->copline = NOLINE;
    
    HvCLASS_on(PL_curstash);
    if (is_role)
        HvROLE_on(PL_curstash);
}

/*
=for apidoc do_method_finalize

A field may start as lexical or access call in the class block and
method pad, and needs to be converted to oelemfast ops, which are
basically aelemfast_lex_u (lexical typed self, const ix < 256).

  PADxV targ     -> OELEMFAST(self)[targ]

  $field         -> $self->field[i] (same as above)
  $self->{field} ->     -"- (do not use)
  $self->field   ->     -"-

  exists $self->field    -> compile-time const if exists
  exists $self->{field}  -> compile-time const (do not use)
  exists $self->{$field} -> exists oelem

If the field is computed, convert to a new 'oelem' op, which does the
field lookup at run-time.

=cut
*/
static void
S_do_method_finalize(pTHX_ const HV *klass, const CV* cv,
                     OP *o, const PADOFFSET self)
{
    PADNAME *pn;
    PADNAMELIST *pnl = PadlistNAMES(CvPADLIST(cv));
    PERL_ARGS_ASSERT_DO_METHOD_FINALIZE;
    if (IS_TYPE(o, PADSV)) { /* $field -> $self->field[i] */
        /* check if it's a field, or a my var. self is the first my var */
        pn = PadnamelistARRAY(pnl)[o->op_targ];
        if (o->op_targ > self && pn && PadnameOUTER(pn)) {
            I32 klen = PadnameUTF8(pn) ? -(PadnameLEN(pn)-1) : PadnameLEN(pn)-1;
            int ix = field_search(klass, PadnamePV(pn)+1, klen, NULL);
            if (ix >= 0) {
                if (LIKELY(ix < 256)) {
                    o->op_private = (U8)ix;
                    DEBUG_k(Perl_deb(aTHX_
                        "method_finalize %" SVf ": padsv %s %d => oelemfast %d[%d]\n",
                                     SVfARG(cv_name((CV*)cv, NULL, CV_NAME_NOMAIN)),
                        PadnamePV(pn), (int)o->op_targ, (int)self, (int)o->op_private));
                    o->op_targ = self;
                    OpTYPE_set(o, OP_OELEMFAST);
                }
                else { /* padsv -> oelem self,fieldname */
                    OP *field = newSVOP(OP_CONST, 0,
                                        newSVpvn_flags(PadnamePV(pn)+1, PadnameLEN(pn)-1,
                                                 PadnameUTF8(pn) ? SVf_UTF8 : 0));
                    I32 flags = o->op_flags & OPf_MOD;
                    OP* obj = newBINOP(OP_OELEM, flags, o, field);
                    OP* prevsib  = S_op_prev_nn(o);
                    OP* prevnext = S_op_prevstart_nn(CvSTART(cv), o);
                    if (o->op_private & OPpMAYBE_LVSUB)
                        obj->op_private |= OPpMAYBE_LVSUB;
                    o->op_targ = self;
                    DEBUG_k(Perl_deb(aTHX_
                        "method_finalize %" SVf ": padsv %s %d %d => oelem->{%s}\n",
                        SVfARG(cv_name((CV*)cv, NULL, CV_NAME_NOMAIN)),
                        PadnamePV(pn), (int)o->op_targ, (int)ix, PadnamePV(pn)));
                    if (OpHAS_SIBLING(prevsib))
                        OpMORESIB_set(prevsib, obj);
                    else
                        OpFIRST(prevsib) = obj;
                    OpNEXT(prevnext) = o;
                    OpNEXT(obj) = OpNEXT(o);
                    OpNEXT(o) = field;
                    OpNEXT(field) = obj;
                }
            }
        }
#if DEBUGGING
        else if (o->op_targ == self) {
            pn = PadnamelistARRAY(pnl)[o->op_targ];
            assert(strEQc(PadnamePV(pn), "$self"));
            DEBUG_k(Perl_deb(aTHX_ "method_finalize: self %d\n", (int)o->op_targ));
        }
#endif
    }
    /* Disabled old hashref syntax for fields. Only direct lexical inside
       or method outside.*/
#if 0
    /* Check hashref $self->{field}.
       Easier to this in S_maybe_multideref if PL_parser->in_class, but here
       we are sure it's inside the class method. */
    else if (IS_TYPE(o, MULTIDEREF)) {

#ifdef USE_ITHREADS
#  define ITEM_SV(item) (PL_comppad ? \
    *av_fetch(PL_comppad, (item)->pad_offset, FALSE) : NULL)
#else
#  define ITEM_SV(item) UNOP_AUX_item_sv(item)
#endif
        UNOP_AUX_item *items = cUNOP_AUXx(o)->op_aux;
        UV actions = items->uv;
        const UV mderef_flags = /* $self->{field} */
            MDEREF_HV_padsv_vivify_rv2hv_helem |
            MDEREF_INDEX_const |
            MDEREF_FLAG_last;
        /* if first and only arg is $self */
        if (actions == mderef_flags
            && (++items)->pad_offset == self)
        {
            SV* key = ITEM_SV(++items);
            I32 klen = SvUTF8(key) ? -SvCUR(key) : SvCUR(key);
            int ix = field_search(klass, SvPVX(key), klen, NULL);
            if (ix != -1) {
                assert(ix < 256);   /* TODO aelem_u or oelem */
                o->op_private = (U8)ix; /* field offset */
                DEBUG_k(Perl_deb(aTHX_
                    "method_finalize: $self->{%s} => $self %d[%d]\n",
                    SvPVX(key), (int)self, (int)ix));
                o->op_targ = self;
                PerlMemShared_free(cUNOP_AUXo->op_aux - 1);
                OpTYPE_set(o, OP_OELEMFAST);
            }
        }
    }
#endif
    /* optimize typed accessor calls $self->field -> $self->[i] */
    else if (IS_TYPE(o, ENTERSUB) && IS_TYPE(OpFIRST(o), PUSHMARK)) {
        OP *f = OpFIRST(o);
        OP *arg = OpNEXT(f);
        /* first and only arg is typed $self */
        if (IS_TYPE(arg, PADSV) &&
            arg->op_targ == self && /* $self is always the first inside the method */
            IS_TYPE(OpNEXT(arg), METHOD_NAMED))
        {
            SV* const meth = cMETHOPx_meth(OpNEXT(arg));
            pn = PadnamelistARRAY(pnl)[arg->op_targ];
            if (meth && SvPOK(meth) && pn && PadnameTYPE(pn) &&
                PadnameLEN(pn) == 5 && strEQc(PadnamePV(pn), "$self"))
            {
                const I32 klen = SvUTF8(meth) ? -SvCUR(meth) : SvCUR(meth);
                PADOFFSET po;
                const int ix = field_search(klass, SvPVX(meth), klen, &po);
                if (ix != -1) {
                    HV *type;
                    if (LIKELY(ix < 256)) {
                        f->op_private = (U8)ix; /* field offset */
                        DEBUG_k(Perl_deb(aTHX_
                            "method_finalize %" SVf ": $self->%s => oelemfast %d[%d]\n",
                            SVfARG(cv_name((CV*)cv, NULL, CV_NAME_NOMAIN)),
                            SvPVX(meth), (int)self, (int)ix));
                        f->op_targ = self;
                        OpTYPE_set(f, OP_OELEMFAST); /* PUSHMARK is the bb leader,
                                                        not ENTERSUB. Some next might point
                                                        to it */
                        OpMORESIB_set(f, OpSIBLING(o));
                        OpNEXT(f) = OpNEXT(o);
                        OpFLAGS(o) &= ~(OPf_KIDS|OPf_REF|OPf_STACKED);

                        /* has TYPE */
                        pn = PAD_COMPNAME(po);
                        type = PadnameTYPE(pn);
                        if (type)
                            OpRETTYPE_set(o, stash_to_coretype(type));

                        /*op_free(o);*/ /* need the pad still */
                        op_free(OpNEXT(arg));
                        op_free(arg);
                        /*finalize_op(o);*/
                    }
#if 0
                    /* the XS method is easier and faster */
                    else {
                        OP *field = newSVOP(OP_CONST, 0,
                                        newSVpvn_flags(SvPVX(meth), SvCUR(meth),
                                                       SvUTF8(meth)));
                        I32 flags = o->op_flags & OPf_MOD;
                        OP* obj = newBINOP(OP_OELEM, flags, arg, field);
                        OP* prev = S_op_prev_nn(o);
                        OP* prevnext = S_op_prevstart_nn(CvSTART(cv), o);
                        arg->op_targ = self;
                        if (o->op_private & OPpMAYBE_LVSUB)
                            obj->op_private |= OPpMAYBE_LVSUB;
                        DEBUG_k(Perl_deb(aTHX_
                            "method_finalize %" SVf ": $self->%s => oelem->{%s}\n",
                            SVfARG(cv_name((CV*)cv, NULL, CV_NAME_NOMAIN)),
                            SvPVX(meth), PadnamePV(pn)));
                        OpMORESIB_set(prev, obj);
                        OpNEXT(prevnext) = arg;
                        OpNEXT(arg) = field;
                        OpNEXT(field) = obj;
                        OpNEXT(obj) = OpNEXT(OpNEXT(arg));

                        OpFLAGS(o) &= ~(OPf_KIDS|OPf_REF|OPf_STACKED);

                        pn = PAD_COMPNAME(po);
                        type = PadnameTYPE(pn);
                        if (type)
                            OpRETTYPE_set(obj, stash_to_coretype(type));

                        op_free(o);
                        op_free(OpNEXT(arg));
                    }
#endif
                } else {
                    DEBUG_kv(Perl_deb(aTHX_
                        "method_finalize: $self->%s not a field\n", SvPVX(meth)));
                }
            }
        }
    }
    else if (OpKIDS(o)) {
	OP *kid;
	for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid)) {
            if (IS_PADxV_OP(kid) || OpKIDS(kid))
                S_do_method_finalize(aTHX_ klass, cv, kid, self);
        }
    }
}

/*
=for apidoc method_finalize

Resolve internal lexicals or field helem's or field accessors 
to fields in the class method or sub.

Field helem's might get deleted, as they don't work outside of classes.
Only subs and methods inside the class are processed, not outside!
=cut
*/
static void
S_method_finalize(pTHX_ const HV* klass, const CV* cv)
{
    OP *o;
    PADOFFSET self = 1;
    PERL_ARGS_ASSERT_METHOD_FINALIZE;

    if (CvHASSIG(cv)) {
        UNOP_AUX *o = CvSIGOP((SV*)cv);
        /* padoffset of $self, the first padrange in the signature. Always 1. */
        UNOP_AUX_item *items = cUNOP_AUXo->op_aux;
        if ((items[1].uv & SIGNATURE_ACTION_MASK) == SIGNATURE_padintro)
            self = items[2].uv >> OPpPADRANGE_COUNTSHIFT;
    }
    if ((o = CvROOT(cv)) && CvMETHOD(cv) && HvFIELDS_get(klass)) {
        S_do_method_finalize(aTHX_ klass, cv, o, self);
    }
}

static bool
S_role_field_fixup(pTHX_ OP* o, CV* cv, U16 ix, U16 nix, bool doit)
{
    bool fixedup = FALSE;
    if (IS_TYPE(o, OELEMFAST) && o->op_private == (U8)ix) {
        DEBUG_k(Perl_deb(aTHX_ "role_field_fixup %" SVf ": %d => %d %s\n",
                         SVfARG(cv_name(cv,NULL,CV_NAME_NOMAIN)),
                         (int)ix, (int)nix, !doit ? "CHECK" : "DONE"));
        if (doit) {
            o->op_private = (U8)nix;
        }
        fixedup = TRUE;
    }
    if (OpKIDS(o)) {
	OP *kid;
	for (kid = OpFIRST(o); kid; kid = OpSIBLING(kid)) {
            if (IS_TYPE(kid, OELEMFAST) || OpKIDS(kid))
                fixedup |= S_role_field_fixup(aTHX_ kid, cv, ix, nix, doit);
        }
    }
    return fixedup;
}

/*
=for apidoc add_isa_fields

Copy all not-existing fields from parent classes or roles to the class of
C<name>. Duplicates are fatal with roles, ignored with classes.

=cut
*/
static void
S_add_isa_fields(pTHX_ HV* klass, AV* isa)
{
    const char * const klassname = HvNAME(klass);
#ifdef OLD_FIELDS_GV
    STRLEN len = HvNAMELEN(klass);
    SV *name = newSVpvn_flags(klassname, len, HvNAMEUTF8(klass)|SVs_TEMP);
    GV *fsym;
#else
    char padsize;
#endif
    SSize_t i;
    PERL_ARGS_ASSERT_ADD_ISA_FIELDS;

#ifdef OLD_FIELDS_GV
    sv_catpvs(name, "::FIELDS");
    fsym = gv_fetchsv(name, 0, SVt_PVAV); /* might be empty */
    SvCUR_set(name, len);
    SvPVX(name)[len] = '\0';
#endif

    for (i=0; i<=AvFILL(isa); i++) {
        SV *tmpnam;
        SV** svp = av_fetch(isa, i, FALSE);
        HV *curclass;
#ifdef OLD_FIELDS_GV
        GV *sym;
        AV *f;
        SSize_t j;
#else
        STRLEN l;
        char *fields;
#endif
        if (!svp)
            continue;
        if (SvPOK(*svp))
            tmpnam = newSVpvn_flags(SvPVX(*svp), SvCUR(*svp), SvUTF8(*svp));
        else if (SvTYPE(*svp) == SVt_PVHV)
            tmpnam = newSVpvn_flags(HvNAME(*svp), HvNAMELEN(*svp), HvNAMEUTF8(*svp));
        else
            continue;
        assert(klassname);
        if (strEQ(SvPVX(tmpnam), klassname))
            continue;
        if (strEQc(SvPVX(tmpnam), "Mu"))
            continue;

        curclass = gv_stashsv(tmpnam, 0);
#ifdef OLD_FIELDS_GV
        sv_catpvs(tmpnam, "::FIELDS");
        sym = gv_fetchsv(tmpnam, 0, SVt_PVAV);
        if (!sym || !GvAV(sym)) {
            SvREFCNT_dec(tmpnam);
            continue;
        }
        SvCUR_set(tmpnam, SvCUR(*svp));
        SvPVX(tmpnam)[SvCUR(*svp)] = '\0';

        f = GvAV(sym);
        for (j=0; j<=AvFILL(f); j++) {
            SV* padix = AvARRAY(f)[j];
            PADOFFSET po = (PADOFFSET)SvIVX(padix);
#else
        fields = HvFIELDS_get(curclass);
        if (!fields) /* nothing to copy */
            continue;
# ifdef FIELDS_DYNAMIC_PADSIZE
        padsize = *fields;
        fields++;
# else
        padsize = sizeof(PADOFFSET);
# endif
        l = strlen(fields);
        for (; *fields; l=strlen(fields), fields += l+padsize+1 ) {
            PADOFFSET po = fields_padoffset(fields, l+1, padsize);
#endif
            const PADNAME *pn = PAD_COMPNAME(po);
            char *key;
            I32 klen;
            if (!pn)
                continue;
            key = PadnamePV(pn);
            klen = PadnameLEN(pn);
            klen = PadnameUTF8(pn) ? -(klen-1) : klen-1;
            /* check for duplicate */
            if (field_search(klass, key+1, klen, NULL) >= 0) {
                /* fatal with roles, valid and ignored for classes */
                if (HvROLE(curclass))
                    Perl_croak(aTHX_
                        "Field %s from %s already exists in %s during role composition",
                        key, SvPVX(tmpnam), klassname);
                DEBUG_kv(Perl_deb(aTHX_ "add_isa_fields: exists %s from %s in %s [%d]\n",
                                  key, SvPVX(tmpnam), klassname, (int)po));
                continue;
            }

            /* use the upper padix, not a new one. */
            /*new_po = allocmy(key, klen, 0);*/
#ifdef OLD_FIELDS_GV
            if (!fsym) {
                sv_catpvs(name, "::FIELDS");
                fsym = gv_fetchsv(name, GV_ADD, SVt_PVAV);
                av_extend(GvAVn(fsym), 0);
                SvCUR_set(name, len);
                SvPVX(name)[len] = '\0';
            }
#endif
            DEBUG_k(Perl_deb(aTHX_ "add_isa_fields: add %s from %s to %s [%d]\n",
                             key, SvPVX(tmpnam), klassname, (int)po));
            field_pad_add(klass, key+1, klen, po);
        }
        SvREFCNT_dec(tmpnam);
    }
}

static bool
S_check_role_field_fixup(pTHX_ HV* klass, HV* newclass, CV* cv, bool doit)
{
   U16 num = numfields(klass);
   int i;
   bool need_copy = FALSE;
   /* TODO: better iterate once manually, than twice via methods */
   for (i=0; i<num; i++) {
       PADOFFSET po = field_index(klass, i);
       PADNAME *pn = PAD_COMPNAME(po);
       if (!pn || !PadnameLEN(pn))
           continue;
       else {
           I32 klen = PadnameUTF8(pn) ? -(PadnameLEN(pn)-1) : PadnameLEN(pn)-1;
           int nix = field_search(newclass, PadnamePV(pn)+1, klen, NULL);
           if (nix != -1 && i != (U16)nix) {
               bool result = S_role_field_fixup(aTHX_ CvROOT(cv), cv,
                                                (U16)i, (U16)nix, doit);
               /*DEBUG_k(Perl_deb(aTHX_ "check_role_field_fixup %" SVf ": (%d => %d) => %s\n",
                                SVfARG(cv_name(cv,NULL,CV_NAME_NOMAIN)),
                                i, (int)nix, result ? "TRUE" : "FALSE"));*/
               need_copy |= result;
           }
       }
   }
   return need_copy;
}

/*
=for apidoc add_does_methods

Copy all not-existing methods from the parent roles to the class/role.
Fixup changed oelemfast indices.

Duplicates are fatal:
"Method %s from %s already exists in %s during role composition"

=cut
*/
static void
S_add_does_methods(pTHX_ HV* klass, AV* does)
{
    const char *klassname = HvNAME(klass);
    STRLEN len = HvNAMELEN(klass);
    SV *name = newSVpvn_flags(klassname, len, HvNAMEUTF8(klass)|SVs_TEMP);
    SSize_t i;
    bool need_copy = TRUE;
    PERL_ARGS_ASSERT_ADD_DOES_METHODS;

    for (i=0; i<=AvFILL(does); i++) {
        SV **classp = av_fetch(does, i, FALSE);
        HV *curclass;
        HE *entry;

        if (!classp) continue;
        if (SvPOK(*classp))
            curclass = gv_stashsv(*classp, 0);
        else if (SvTYPE(*classp) == SVt_PVHV)
            curclass = MUTABLE_HV(*classp);
        else
            continue;

        (void)hv_iterinit(curclass);
        HvAUX(curclass)->xhv_aux_flags |= HvAUXf_SCAN_STASH;
        while ((entry = hv_iternext(curclass))) {
            GV *gv = MUTABLE_GV(HeVAL(entry));
            CV *cv;

            if (isGV(gv) && (cv = GvCV(gv))) {
                GV *sym;
                /*CV *ncv;*/
                sv_catpvs(name, "::");
                sv_catpvn_flags(name, HeKEY(entry), HeKLEN(entry), HeUTF8(entry));
                sym = gv_fetchsv(name, 0, SVt_PVCV);
                /* Note that we already copied the fields. */
                if (sym && GvCV(sym)) {
                    /*ncv = GvCV(sym);*/
                    if (CvMETHOD(cv) && !CvMULTI(cv)) {
                        DEBUG_kv(Perl_deb(aTHX_ "add_does_methods: exists method %s::%s\n",
                                          klassname, HeKEY(entry)));
                        SvCUR_set(name, len);
                        continue;
                    } else {
                        /* perl6: Method '%s' must be resolved by class %s because it
                           exists in multiple roles (%s, %s) */
                        Perl_croak(aTHX_
                            "Method %s from role %s already exists in %s %s during role composition",
                            HeKEY(entry), GvNAME(gv), HvPKGTYPE_NN(klass), klassname);
                    }
                }
                /* ignore default field accessors, they are created later */
                if (CvISXSUB(cv) &&
                    field_search(klass, HeKEY(entry), HeKLEN_UTF8(entry), NULL) >= 0) {
                    DEBUG_kv(Perl_deb(aTHX_ "add_does_methods: ignore field accessor %s::%s\n",
                                      klassname, HeKEY(entry)));
                    SvCUR_set(name, len);
                    continue;
                }
                /* We also might have class methods without a GV, but
                   I believe we already vivified them to fat GVs */

                if (UNLIKELY(CvISXSUB(cv))) {
                    if (CvXSUB(cv) == S_Mu_sv_xsub ||
                        CvXSUB(cv) == S_Mu_av_xsub) {
                        DEBUG_kv(Perl_deb(aTHX_
                            "add_does_methods: ignore other field XS accessor\n"));
                    }
                    need_copy = FALSE; /* GV alias */
                }
                else if (CvCONST(cv)) {
                    need_copy = FALSE; /* GV alias */
                    DEBUG_kv(Perl_deb(aTHX_
                        "add_does_methods: CvCONST NYI\n"));
                }
                else if (CvMULTI(cv)) {
                    DEBUG_kv(Perl_deb(aTHX_
                        "add_does_methods: CvMULTI NYI\n"));
                }
                /* compare field indices. might need to create a new method
                   with adjusted indices. #311 */
                if (need_copy) {
                    need_copy = S_check_role_field_fixup(aTHX_ curclass, klass, cv, FALSE);
                }
                if (!need_copy) { /* GV alias */
                    DEBUG_k(Perl_deb(aTHX_ "add_does_methods: alias %s::%s to %s %s\n",
                                 HvNAME(curclass), HeKEY(entry), HvPKGTYPE_NN(klass),
                                 klassname));
                    sym = gv_fetchsv_nomg(name, GV_ADD, SVt_PVCV);
                    SvSetMagicSV((SV*)sym, (SV*)gv); /* glob_assign_glob */
                } else {
                    /* CV copy */
#if 1
                    Perl_die(aTHX_ "panic: cannot yet adjust field indices when composing role "
                               "%s::%s into %s %s [cperl #311]\n",
                               HvNAME(curclass), HeKEY(entry), HvPKGTYPE_NN(klass), klassname);
#else                
                    CV* ncv = MUTABLE_CV(newSV_type(SvTYPE(cv)));
                    DEBUG_k(Perl_deb(aTHX_ "add_does_methods: copy %s::%s to %s %s\n",
                                 HvNAME(curclass), HeKEY(entry), HvPKGTYPE_NN(klass),
                                 klassname));
                    CvGV_set(ncv, sym);
                    CvSTASH_set(ncv, klass);
                    OP_REFCNT_LOCK;
                    /* TODO: either clone the optree or pessimize oelemfast */
                    CvROOT(ncv)	     = OpREFCNT_inc(CvROOT(cv));
                    if (CvHASSIG(cv))
                        CvSIGOP(ncv) = CvSIGOP(cv);
                    OP_REFCNT_UNLOCK;
                    CvSTART(ncv)     = CvSTART(cv);
                    CvOUTSIDE(ncv)   = CvOUTSIDE(cv); /* ? */
                    CvOUTSIDE_SEQ(ncv) = CvOUTSIDE_SEQ(cv);
                    CvFILE(ncv)   = CvFILE(cv); /* ? */
                    if (SvPOK(cv)) {
                        SV* const sv = MUTABLE_SV(ncv);
                        sv_setpvn(sv, SvPVX_const(cv), SvCUR(cv));
                        if (SvUTF8(cv) && !SvUTF8(sv)) {
                            if (SvIsCOW(sv)) sv_uncow(sv, 0);
                            SvUTF8_on(sv);
                        }
                    }
                    SvFLAGS(ncv) = SvFLAGS(cv);
                    CvFLAGS(ncv) = CvFLAGS(cv);
                    if (SvMAGIC(cv))
                        mg_copy((SV *)cv, (SV *)ncv, 0, 0);

                    if (CvPADLIST(cv)) {
                        CvPADLIST(ncv) = CvPADLIST(cv);
                        /*ncv = S_cv_clone_pad(aTHX_ cv, ncv, CvOUTSIDE(cv), NULL, FALSE);*/
                    }
                    if (!S_check_role_field_fixup(aTHX_ curclass, klass, ncv, TRUE))
                        assert(!"check_role_field_fixup with copied ncv");
                    mro_method_changed_in(klass);
                    DEBUG_kv(sv_dump((SV*)ncv));
#endif
                }
            }
            SvCUR_set(name, len);
        }
    }
}

/*
=for apidoc class_role_finalize

Create the field accessors and resolve internal lexicals to fields in
all methods.
Apply fields optimizations and type checks.
Close the class/role.

Note that we need to undo the stash restricted'ness during
destruction.

=cut
*/
void
Perl_class_role_finalize(pTHX_ OP* o)
{
    SV *name;
    GV* sym; HV* stash;
    CV *savecv, *cv;
    AV *isa = NULL;
    AV *does = NULL;
    const char *const file = CopFILE(PL_curcop);
#ifdef OLD_FIELDS_GV
    AV *fields = NULL;
#else
    char *fields;
    char padsize;
#endif
    STRLEN len;
    /*PADOFFSET floor = 1;*/
    U32 i;
    bool is_utf8;
    PERL_ARGS_ASSERT_CLASS_ROLE_FINALIZE;

    if (IS_TYPE(o, LIST))
        o = OpSIBLING(OpFIRST(o));
    name = cSVOPo->op_sv;
    stash = gv_stashsv(name, 0);
    len = SvCUR(name);
    is_utf8 = cBOOL(SvUTF8(name));
    /*SvREADONLY_off(stash);*/
    SvREADONLY_off(name);

    sv_catpvs(name, "::DOES");
    sym = gv_fetchsv(name, 0, SVt_PVAV);
    if (sym && GvAV(sym)) {
        does = GvAV(sym);
        if (AvARRAY(does) && AvFILL(does) >= 0) {
            S_add_isa_fields(aTHX_ stash, does);
            S_add_does_methods(aTHX_ stash, does);
        }
        SvREADONLY_on(does);
    }
    SvCUR_set(name, len);

    sv_catpvs(name, "::ISA");
    sym = gv_fetchsv(name, 0, SVt_PVAV);
    if (sym && GvAV(sym)) {
        isa = GvAV(sym);
        if (AvARRAY(isa) && AvFILL(isa) > 0) { /* skip Mu only */
            S_add_isa_fields(aTHX_ stash, isa);
        }
        SvREADONLY_on(isa);
    }
    SvCUR_set(name, len);

#ifdef OLD_FIELDS_GV
    sv_catpvs(name, "::FIELDS");
    sym = gv_fetchsv(name, 0, SVt_PVAV);
    SvCUR_set(name, len);
    SvPVX(name)[len] = '\0';
    if (!sym || !GvAV(sym) || AvFILLp(GvAV(sym)) < 0) { /* no fields */
        SvREADONLY_on(stash);
        PL_parser->in_class = FALSE;
        return;
    }
    fields = GvAV(sym);
#else
    fields = HvFIELDS_get(stash);
    if (!fields) {
        SvREADONLY_on(stash);
        PL_parser->in_class = FALSE;
        return;
    }
# ifdef FIELDS_DYNAMIC_PADSIZE
    padsize = *fields;
    fields++;
# else
    padsize = sizeof(PADOFFSET);
# endif
#endif

    /* create the field accessor methods */
    /*ENTER;*/
    savecv = PL_compcv;
    DEBUG_Xv(padlist_dump(CvPADLIST(PL_compcv)));
#ifdef OLD_FIELDS_GV
    assert(AvFILLp(fields) < MAX_NUMFIELDS);
    for (i=0; i<=(U32)AvFILLp(fields); i++) {
        SV* ix = AvARRAY(fields)[i];
        PADOFFSET po = (PADOFFSET)SvIVX(ix);
#else
    for (i=0; *fields; i++) {
        STRLEN l = strlen(fields);
        PADOFFSET po = fields_padoffset(fields, l+1, padsize);
#endif
        PADNAME *pn = PAD_COMPNAME(po);
        char *reftype;
        char *key;
        SV *sv;
        /*OP *body;*/
        U32 klen;
        U32 utf8;
        bool lval;

        if (!pn)
            continue;
        reftype = PadnamePV(pn);
        key = reftype + 1; /* skip the $ */
        sv = pad_findmy_real(po, savecv);
        klen = PadnameLEN(pn) - 1;
        utf8 = is_utf8 ? SVf_UTF8
                       : PadnameUTF8(pn) ? SVf_UTF8 : 0;
        lval = !PadnameCONST(pn);

#ifndef OLD_FIELDS_GV
        fields += l+padsize+1;
#endif
        /* fixup the pad field for Mu->new */
        SvFLAGS(sv) &= ~(SVs_PADTMP|SVs_PADSTALE);
        /* Or maybe install the accessor as XS, with XSANY for the field ix.
           Mouse does it with a template and magic. They support write-only,
           exists and clear, we only read and read-write.

           TODO: exists $obj->field
         */
        sv_catpvs(name, "::");
        sv_catpvn_flags(name, key, klen, utf8);
        sym = gv_fetchsv(name, 0, SVt_PVCV);
        if (sym && GvCV(sym)) {
            SvCUR_set(name, len);
            SvPVX(name)[len] = '\0';
            continue; /* Already exists. This is a valid accessor override. */
        }
#if 1
        cv = newXS_len_flags(SvPVX(name), SvCUR(name),
                             *reftype == '$' ? S_Mu_sv_xsub : S_Mu_av_xsub,
                             file ? file : "",
                             "" /* proto */, NULL /*&const_sv*/,
                             XS_DYNAMIC_FILENAME | utf8);
        CvXSUBANY(cv).any_u32 = i;
        SvCUR_set(name, len);
        SvPVX(name)[len] = '\0';
        CvMETHOD_on(cv);
        CvPURE_on(cv);
        if (lval)
            CvLVALUE_on(cv);
        DEBUG_k(Perl_deb(aTHX_ "add class accessor method %*s->%s()%s%s%s { $self->[%d] }\n",
                         (int)len, SvPVX(name), key, lval ? " :lvalue" : "",
                         PadnameTYPE(pn) ? " :" : "",
                         PadnameTYPE(pn) ? HvNAME(PadnameTYPE(pn)) : "",
                         (int)i));
        /* Cannot type a XS yet. no padlist[0], only sigop or hscxt */
        if (PadnameTYPE(pn)) {
            CvTYPED_on(cv);
            /* XXX NYI XS typecheck. Clashes with implicit context &sp? */
            CvHSCXT(cv) = PadnameTYPE(pn);
            /*PAD_COMPNAME(0) = pn;*/
        }
#else
        /* TODO: scope fixup */
        SvCUR_set(name, len);
        SvPVX(name)[len] = '\0';
        DEBUG_k(Perl_deb(aTHX_ "add class accessor method %*s->%s()%s%s%s { $self->[%d] }\n",
                         (int)len, SvPVX(name), key, lval ? " :lvalue" : "",
                         PadnameTYPE(pn) ? " :" : "",
                         PadnameTYPE(pn) ? HvNAME(PadnameTYPE(pn)) : "",
                         (int)i));
        start_subparse(0, CVf_METHOD | (lval ? CVf_LVALUE : 0));
        po = pad_add_name_pvn("$self", 5, padadd_NO_DUP_CHECK, PadnameTYPE(pn), NULL);
        assert(po == 1);
        body = newOP(OP_OELEMFAST, i<<8);
        body->op_targ = po; /* self */
        {
            UNOP_AUX_item *items = (UNOP_AUX_item*)PerlMemShared_malloc
                (sizeof(UNOP_AUX_item) * 5);
            OP *op;
            items[0].uv = 3;
            items[1].uv = 1 << 16;
            items[2].uv = 0x10c2; /* padrange + arg + end */
            items[3].uv = (po << OPpPADRANGE_COUNTSHIFT) | 1; /* 0x81 */
            op = newUNOP_AUX(OP_SIGNATURE, 0, NULL, items+1);
            body = op_append_list(OP_LINESEQ, op, body);
        }
        cv = newSUB(floor,
                    newSVOP(OP_CONST, 0, newSVpvn_flags(key, klen, PadnameUTF8(pn))),
                    NULL, body);
        CvSTASH_set(cv, stash);
        CvHASSIG_on(cv);
        CvSIGOP(cv) = (UNOP_AUX*)CvSTART(cv);
        if (PadnameTYPE(pn)) {
            CvTYPED_on(cv);
            CvTYPE_set(cv, PadnameTYPE(pn));
        }
        DEBUG_Xv(padlist_dump(CvPADLIST(cv)));
#endif
    }
    PL_compcv = savecv;
    /*LEAVE;*/

    /* walk and finalize the subs and methods, i.e. fixup field accessors */
    for (i=0; i <= HvMAX(stash); i++) {
        const HE *entry;
	for (entry = HvARRAY(stash)[i]; entry; entry = HeNEXT(entry)) {
	    GV *gv = (GV*)HeVAL(entry);
            CV *cv;
            if (SvROK(gv) && SvTYPE(SvRV(gv)) == SVt_PVCV)
                (void)CvGV(SvRV(gv)); /* unfake a fake GV */
	    if (SvTYPE(gv) != SVt_PVGV || !GvGP(gv))
		continue;
	    if ((cv = GvCVu(gv)) && !CvISXSUB(cv))
                method_finalize(stash, cv);
            /* skip nested classes
	    if (HeKEY(entry)[HeKLEN(entry)-1] == ':') {
		const HV * const hv = GvHV(gv);
		if (hv && (hv != PL_defstash))
                    class_role_finalize(newSVOP(OP_CONST,0,HvNAME(hv)));
	    }
            */
        }
    }
    DEBUG_Xv(pnl_dump(PL_comppad_name));
    SvREADONLY_on(stash);
    PL_parser->in_class = FALSE;
}

/*
=for apidoc method_field_type

Try to detect if the method_named call is a method call on an object class field.
$self, the object target needs to be typed to a class.

Returns the field type:
   1 - scalar
   2 - array
   3 - hash
or 0 if none.
=cut
*/
int
Perl_method_field_type(pTHX_ OP* o)
{
    PERL_ARGS_ASSERT_METHOD_FIELD_TYPE;
    assert(IS_TYPE(o, ENTERSUB));
    /* TODO: there might be a nullified list before */
    if (OP_TYPE_IS(OpFIRST(o), OP_PUSHMARK)) {
        OP *arg = OpSIBLING(OpFIRST(o));
        /* first and only arg is typed $self */
        if (OP_TYPE_IS(arg, OP_PADSV) &&
            arg->op_targ &&
            (o = OpSIBLING(arg)) &&
            IS_TYPE(o, METHOD_NAMED))
        {
            SV* const meth  = cMETHOPx_meth(o);
            HV* const klass = PAD_COMPNAME_TYPE(arg->op_targ);
            if (meth && SvPOK(meth) && klass && HvCLASS(klass)) {
                const I32 klen = SvUTF8(meth) ? -SvCUR(meth) : SvCUR(meth);
                const PADOFFSET pad = field_pad(klass, SvPVX(meth), klen);
                OpRETTYPE_set(arg, type_Object);
                if (pad != NOT_IN_PAD &&
                    pad <= PadnamelistMAXNAMED(PL_comppad_name) &&
                    PAD_COMPNAME(pad))
                {
                    const char c = *PAD_COMPNAME_PV(pad);
                    if (c == '$')
                        return METHOD_FIELD_SCALAR;
                    else if (c == '@')
                        return METHOD_FIELD_ARRAY;
                    else if (c == '%')
                        return METHOD_FIELD_HASH;
                }
            }
        }
    }
    return METHOD_FIELD_NONE;
}

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
