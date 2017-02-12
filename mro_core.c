/*    mro_core.c
 *
 *    Copyright (c) 2007 Brandon L Black
 *    Copyright (c) 2007, 2008, 2009, 2010, 2011 Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 *    This was 'mro.c', but changed because there is another mro.c in /ext, and
 *    the os390 loader can't cope with this situation (which involves the two
 *    files calling functions defined in the other)
 */

/*
 * 'Which order shall we go in?' said Frodo.  'Eldest first, or quickest first?
 *  You'll be last either way, Master Peregrin.'
 *
 *     [p.101 of _The Lord of the Rings_, I/iii: "A Conspiracy Unmasked"]
 */

/*
=head1 MRO Functions
These functions are related to the method resolution order of perl classes.

Implemented are the old dfs, and the new c3 methods, but via the L<perlmroapi>
you can add arbitrary methods as extension.

=cut
*/

#include "EXTERN.h"
#define PERL_IN_MRO_C
#include "perl.h"

static const struct mro_alg c3_alg =
    {S_mro_get_linear_isa_c3, "c3", 2, 0, 0};

SV *
Perl_mro_get_private_data(pTHX_ struct mro_meta *const smeta,
			  const struct mro_alg *const which)
{
    SV **data;
    PERL_ARGS_ASSERT_MRO_GET_PRIVATE_DATA;

    data = (SV **)hv_common(smeta->mro_linear_all, NULL,
                            which->name, which->length, which->kflags,
                            HV_FETCH_JUST_SV, NULL, which->hash);
    if (!data)
	return NULL;

    /* If we've been asked to look up the private data for the current MRO, then
       cache it.  */
    if (smeta->mro_which == which)
	smeta->mro_linear_current = *data;

    return *data;
}

SV *
Perl_mro_set_private_data(pTHX_ struct mro_meta *const smeta,
			  const struct mro_alg *const which, SV *const data)
{
    PERL_ARGS_ASSERT_MRO_SET_PRIVATE_DATA;

    if (!smeta->mro_linear_all) {
	if (smeta->mro_which == which) {
	    /* If all we need to store is the current MRO's data, then don't use
	       memory on a hash with 1 element - store it direct, and signal
	       this by leaving the would-be-hash NULL.  */
	    smeta->mro_linear_current = data;
	    return data;
	} else {
	    HV *const hv = newHV();
	    /* Start with 2 buckets. It's unlikely we'll need more. */
	    HvMAX(hv) = 1;
	    smeta->mro_linear_all = hv;

	    if (smeta->mro_linear_current) {
		/* If we were storing something directly, put it in the hash
		   before we lose it. */
		mro_set_private_data(smeta, smeta->mro_which,
                                     smeta->mro_linear_current);
	    }
	}
    }

    /* We get here if we're storing more than one linearisation for this stash,
       or the linearisation we are storing is not that if its current MRO.  */

    if (smeta->mro_which == which) {
	/* If we've been asked to store the private data for the current MRO,
	   then cache it.  */
	smeta->mro_linear_current = data;
    }

    if (!hv_common(smeta->mro_linear_all, NULL,
                   which->name, which->length, which->kflags,
                   HV_FETCH_ISSTORE, data, which->hash)) {
	Perl_croak(aTHX_ "panic: hv_store() failed in set_mro_private_data() "
		   "for '%.*s' %d", (int) which->length, which->name,
		   which->kflags);
    }

    return data;
}

const struct mro_alg *
Perl_mro_get_from_name(pTHX_ SV *name) {
    SV **data;

    PERL_ARGS_ASSERT_MRO_GET_FROM_NAME;

    data = (SV **)hv_common(PL_registered_mros, name, NULL, 0, 0,
                            HV_FETCH_JUST_SV, NULL, 0);
    if (!data)
	return NULL;
    assert(SvTYPE(*data) == SVt_IV);
    assert(SvIOK(*data));
    return INT2PTR(const struct mro_alg *, SvUVX(*data));
}

/*
=for apidoc mro_register
Registers a custom mro plugin.  See L<perlmroapi> for details.

=cut
*/

void
Perl_mro_register(pTHX_ const struct mro_alg *mro) {
    SV *wrapper = newSVuv(PTR2UV(mro));

    PERL_ARGS_ASSERT_MRO_REGISTER;


    if (!Perl_hv_common(aTHX_ PL_registered_mros, NULL,
			mro->name, mro->length, mro->kflags,
			HV_FETCH_ISSTORE, wrapper, mro->hash)) {
	SvREFCNT_dec_NN(wrapper);
	Perl_croak(aTHX_ "panic: hv_store() failed in mro_register() "
		   "for '%.*s' %d", (int) mro->length, mro->name, mro->kflags);
    }
}

struct mro_meta*
Perl_mro_meta_init(pTHX_ HV* stash)
{
    struct mro_meta* newmeta;

    PERL_ARGS_ASSERT_MRO_META_INIT;
    PERL_UNUSED_CONTEXT;
    assert(HvAUX(stash));
    assert(!(HvAUX(stash)->xhv_mro_meta));
    Newxz(newmeta, 1, struct mro_meta);
    HvAUX(stash)->xhv_mro_meta = newmeta;
    newmeta->cache_gen = 1;
    newmeta->pkg_gen = 1;
    newmeta->mro_which = &c3_alg;

    return newmeta;
}

#if defined(USE_ITHREADS)

/* for sv_dup on new threads */
struct mro_meta*
Perl_mro_meta_dup(pTHX_ struct mro_meta* smeta, CLONE_PARAMS* param)
{
    struct mro_meta* newmeta;

    PERL_ARGS_ASSERT_MRO_META_DUP;

    Newx(newmeta, 1, struct mro_meta);
    Copy(smeta, newmeta, 1, struct mro_meta);

    if (newmeta->mro_linear_all) {
	newmeta->mro_linear_all
	    = MUTABLE_HV(sv_dup_inc((const SV *)newmeta->mro_linear_all, param));
	/* This is just acting as a shortcut pointer, and will be automatically
	   updated on the first get.  */
	newmeta->mro_linear_current = NULL;
    } else if (newmeta->mro_linear_current) {
	/* Only the current MRO is stored, so this owns the data.  */
	newmeta->mro_linear_current
	    = sv_dup_inc((const SV *)newmeta->mro_linear_current, param);
    }

    if (newmeta->mro_nextmethod)
	newmeta->mro_nextmethod
	    = MUTABLE_HV(sv_dup_inc((const SV *)newmeta->mro_nextmethod, param));
    if (newmeta->isa)
	newmeta->isa
	    = MUTABLE_HV(sv_dup_inc((const SV *)newmeta->isa, param));

    newmeta->super = NULL;

    /* clear the destructor cache */
    newmeta->destroy = NULL;
    newmeta->destroy_gen = 0;

    return newmeta;
}

#endif /* USE_ITHREADS */

/*
=for apidoc mro_get_linear_isa_c3

Returns the C3 linearization of C<@ISA> the given stash.  The return
value is a read-only AV*.  C<level> should be 0 (it is used internally
in this function's recursion).

You are responsible for C<SvREFCNT_inc()> on the return value if you
plan to store it anywhere semi-permanently (otherwise it might be
deleted out from under you the next time the cache is invalidated).

=cut
*/

static AV*
S_mro_get_linear_isa_c3(pTHX_ HV* stash, U32 level)
{
    AV* retval;
    GV** gvp;
    GV* gv;
    AV* isa;
    const HEK* stashhek;
    struct mro_meta* meta;

    PERL_ARGS_ASSERT_MRO_GET_LINEAR_ISA_C3;
    assert(HvAUX(stash));

    stashhek = HvENAME_HEK(stash);
    if (!stashhek)
        stashhek = HvNAME_HEK(stash);
    if (!stashhek)
        /* TODO: fix this severe limitation */
        Perl_croak(aTHX_ "Can't linearize anonymous symbol table");

    if (level > 100)
        Perl_croak(aTHX_ "Recursive inheritance detected in package '%" HEKf
                         "'",
                          HEKfARG(stashhek));

    meta = HvMROMETA(stash);

    /* return cache if valid */
    if ((retval = MUTABLE_AV(MRO_GET_PRIVATE_DATA(meta, &c3_alg)))) {
        return retval;
    }

    /* not in cache, make a new one */
    gvp = (GV**)hv_fetchs_ifexists(stash, "ISA", FALSE);
    isa = (gvp && (gv = *gvp) && isGV_with_GP(gv)) ? GvAV(gv) : NULL;

    /* For a better idea how the rest of this works, see the much clearer
       pure perl version in Algorithm::C3 0.01:
       http://search.cpan.org/src/STEVAN/Algorithm-C3-0.01/lib/Algorithm/C3.pm
       (later versions go about it differently than this code for speed reasons)
    */

    if (isa && AvFILLp(isa) >= 0) {
        SV** seqs_ptr;
        SSize_t seqs_items;
        HV *tails;
        AV *const seqs = MUTABLE_AV(sv_2mortal(MUTABLE_SV(newAV())));
        I32* heads;

        /* This builds @seqs, which is an array of arrays.
           The members of @seqs are the MROs of
           the members of @ISA, followed by @ISA itself.
        */
        SSize_t items = AvFILLp(isa) + 1;
        SV** isa_ptr = AvARRAY(isa);
        while (items--) {
            /* Change deleted ISA elems into "main".
               !*isa_ptr deletion can happen with $#ISA++.
               Normal deletion changes the isaelem to an empty PVMG.
               The stash of those will always be main. */
            SV* isa_item = *isa_ptr ? *isa_ptr : &PL_sv_undef;
            HV* isa_item_stash = gv_stashsv(isa_item, 0);
            if (UNLIKELY((isa_item == &PL_sv_undef) ||
                         (SvFLAGS(isa_item) == SVt_PVMG && /* missing SVs_SMG */
                          isa_item_stash &&
                          !SvPVX(isa_item)))) { /* a deleted elem */
                SvREFCNT_dec_NN(isa_item);
                /* *isa_ptr = &PL_sv_undef; */
                isa_item_stash = NULL;
                *isa_ptr = newSVpvs("main");
                isa_item = *isa_ptr;
            }
            isa_ptr++;
            if (!isa_item_stash) {
                /* if no stash, make a temporary fake MRO
                   containing just itself */
                AV* const isa_lin = newAV();
                av_push(isa_lin, newSVsv(isa_item));
                av_push(seqs, MUTABLE_SV(isa_lin));
            }
            else {
                /* recursion */
                AV* const isa_lin
		  = S_mro_get_linear_isa_c3(aTHX_ isa_item_stash, level + 1);

		if (items == 0 && AvFILLp(seqs) == -1) {
		    /* Only one parent class. For this case, the C3
		       linearisation is this class followed by the parent's
		       linearisation, so don't bother with the expensive
		       calculation.  */
		    SV **svp;
		    SV *const *subrv_p = AvARRAY(isa_lin);
		    SSize_t subrv_items = AvFILLp(isa_lin) + 1;

		    /* Hijack the allocated but unused array seqs to be the
		       return value. It's currently mortalised.  */
		    retval = seqs;

		    av_extend(retval, subrv_items);
		    AvFILLp(retval) = subrv_items;
		    svp = AvARRAY(retval);

		    /* First entry is this class.  We happen to make a shared
		       hash key scalar because it's the cheapest and fastest
		       way to do it.  */
		    *svp++ = newSVhek(stashhek);

		    while (subrv_items--) {
			/* These values are unlikely to be shared hash key
			   scalars, so no point in adding code to optimising
			   for a case that is unlikely to be true.
			   (Or prove me wrong and do it.)  */
			SV *const val = *subrv_p++;
                        if (LIKELY(val != &PL_sv_undef)) {
                            if (SvIsCOW_shared_hash(val))
                                *svp++ = SvREFCNT_inc_simple_NN(val);
                            else
                                *svp++ = newSVsv(val);
                        }
		    }

		    SvREFCNT_inc(retval);
		    goto done;
		}
                av_push(seqs, SvREFCNT_inc_simple_NN(MUTABLE_SV(isa_lin)));
            }
        }
        av_push(seqs, SvREFCNT_inc_simple_NN(MUTABLE_SV(isa)));
	tails = MUTABLE_HV(sv_2mortal(MUTABLE_SV(newHV())));

        /* This builds "heads", which as an array of integer array
           indices, one per seq, which point at the virtual "head"
           of the seq (initially zero) */
        Newxz(heads, AvFILLp(seqs)+1, I32);

        /* This builds %tails, which has one key for every class
           mentioned in the tail of any sequence in @seqs (tail meaning
           everything after the first class, the "head").  The value
           is how many times this key appears in the tails of @seqs. */
        seqs_ptr = AvARRAY(seqs);
        seqs_items = AvFILLp(seqs) + 1;
        while (seqs_items--) {
            AV *const seq = MUTABLE_AV(*seqs_ptr++);
            SSize_t seq_items = AvFILLp(seq);
            if (seq_items > 0) {
                SV** seq_ptr = AvARRAY(seq) + 1;
                while (seq_items--) {
                    SV* const seqitem = *seq_ptr++;
		    /* LVALUE fetch will create a new undefined SV if necessary */
                    HE* const he = hv_fetch_ent(tails, seqitem, 1, 0);
                    if (he) {
                        SV* const val = HeVAL(he);
                        /* For 5.8.0 and later, sv_inc() will increment undef to
			   an IV of 1, which is what we want for a newly created
			   entry.  However, for 5.6.x it will become an NV of
			   1.0, which confuses the SvIVX() checks above.  */
			if (SvIOK(val)) {
			    SvIV_set(val, SvIVX(val) + 1);
			} else {
			    sv_setiv(val, 1);
			}
                    }
                }
            }
        }

        /* Initialize retval to build the return value in */
        retval = newAV();
        av_push(retval, newSVhek(stashhek)); /* us first */

        /* This loop won't terminate until we either finish building
           the MRO, or get an exception. */
        while (1) {
            SV* cand = NULL;
            SV* winner = NULL;
            SSize_t s;

            /* "foreach $seq (@seqs)" */
            SV** const avptr = AvARRAY(seqs);
            for (s = 0; s <= AvFILLp(seqs); s++) {
                SV** svp;
                AV * const seq = MUTABLE_AV(avptr[s]);
		SV* seqhead;
                if (!seq)
                    continue; /* skip empty seqs */
                svp = av_fetch(seq, heads[s], 0);
                seqhead = *svp; /* seqhead = head of this seq */
                if (!winner) {
		    HE* tail_entry;
		    SV* val;
                    /* If we haven't found a winner for this round yet,
                       and this seqhead is not in tails (or the count
                       for it in tails has dropped to zero), then this
                       seqhead is our new winner, and is added to the
                       final MRO immediately */
                    cand = seqhead;
                    if ((tail_entry = hv_fetch_ent(tails, cand, 0, 0))
                       && (val = HeVAL(tail_entry))
                       && (SvIVX(val) > 0))
                           continue;
                    winner = newSVsv(cand);
                    av_push(retval, winner);
                    /* note however that even when we find a winner,
                       we continue looping over @seqs to do housekeeping */
                }
                if (!sv_cmp(seqhead, winner)) {
                    /* Once we have a winner (including the iteration
                       where we first found him), inc the head ptr
                       for any seq which had the winner as a head,
                       NULL out any seq which is now empty,
                       and adjust tails for consistency */

                    const int new_head = ++heads[s];
                    if (new_head > AvFILLp(seq)) {
                        SvREFCNT_dec(avptr[s]);
                        avptr[s] = NULL;
                    }
                    else {
			HE* tail_entry;
			SV* val;
                        /* Because we know this new seqhead used to be
                           a tail, we can assume it is in tails and has
                           a positive value, which we need to dec */
                        svp = av_fetch(seq, new_head, 0);
                        seqhead = *svp;
                        tail_entry = hv_fetch_ent(tails, seqhead, 0, 0);
                        val = HeVAL(tail_entry);
                        sv_dec(val);
                    }
                }
            }

            /* if we found no candidates, we are done building the MRO.
               !cand means no seqs have any entries left to check */
            if (!cand) {
                Safefree(heads);
                break;
            }

            /* If we had candidates, but nobody won, then the @ISA
               hierarchy is not C3-incompatible */
            if (!winner) {
                SV *errmsg;
                SSize_t i;

                errmsg = newSVpvf
                  (
                   "Inconsistent hierarchy during C3 merge of class '%" HEKf "':\n\t"
                   "current merge results [\n",
                   HEKfARG(stashhek));
                for (i = 0; i <= av_tindex(retval); i++) {
                    SV **elem = av_fetch(retval, i, 0);
                    sv_catpvf(errmsg, "\t\t%" SVf ",\n", SVfARG(*elem));
                }
                sv_catpvf(errmsg,
                    "\t]\n\tmerging failed on '%" SVf "'", SVfARG(cand));

                /* we have to do some cleanup before we croak */

                SvREFCNT_dec(retval);
                Safefree(heads);

                Perl_croak(aTHX_ "%" SVf, SVfARG(errmsg));
            }
        }
    }
    else { /* @ISA was undefined or empty */
        /* build a retval containing only ourselves */
        retval = newAV();
        av_push(retval, newSVhek(stashhek));
    }

 done:
    /* we don't want anyone modifying the cache entry but us,
       and we do so by replacing it completely */
    SvREADONLY_on(retval);

    return MUTABLE_AV(mro_set_private_data(meta, &c3_alg,
                          MUTABLE_SV(retval)));
}


/*
=for apidoc mro_get_linear_isa

Returns the mro linearisation for the given stash.  By default, this
will be whatever C<mro_get_linear_isa_c3> returns unless the other MRO
(dfs) is in effect for the stash.  The return value is a read-only
AV*.

You are responsible for C<SvREFCNT_inc()> on the return value if you
plan to store it anywhere semi-permanently (otherwise it might be
deleted out from under you the next time the cache is invalidated).

=cut
*/
AV*
Perl_mro_get_linear_isa(pTHX_ HV *stash)
{
    struct mro_meta* meta;
    AV *isa;

    PERL_ARGS_ASSERT_MRO_GET_LINEAR_ISA;
    if (!SvOOK(stash))
        Perl_croak(aTHX_ "Can't linearize anonymous symbol table");

    meta = HvMROMETA(stash);
    if (!meta->mro_which)
        Perl_croak(aTHX_ "panic: invalid MRO!");
    isa = meta->mro_which->resolve(aTHX_ stash, 0);

    if (meta->mro_which != &c3_alg) { /* skip for the default, for speed */
	SV * const namesv =
	    (HvENAME(stash)||HvNAME(stash))
	      ? newSVhek(HvENAME_HEK(stash)
			  ? HvENAME_HEK(stash)
			  : HvNAME_HEK(stash))
	      : NULL;

	if (namesv && (AvFILLp(isa) == -1 || !sv_eq(*AvARRAY(isa), namesv)))
	{
	    AV * const old = isa;
	    SV **svp;
	    SV **ovp = AvARRAY(old);
	    SV * const * const oend = ovp + AvFILLp(old) + 1;
	    isa = (AV *)sv_2mortal((SV *)newAV());
	    av_extend(isa, AvFILLp(isa) = AvFILLp(old)+1);
	    *AvARRAY(isa) = namesv;
	    svp = AvARRAY(isa)+1;
	    while (ovp < oend) *svp++ = SvREFCNT_inc(*ovp++);
	}
	else SvREFCNT_dec(namesv);
    }

    if (!meta->isa) {
        HV *const isa_hash = newHV();
        /* Linearisation didn't build it for us, */
        SV *const *svp = AvARRAY(isa);
        SV *const *const svp_end = svp + AvFILLp(isa);
        const HEK *canon_name = HvENAME_HEK(stash);
        if (!canon_name) canon_name = HvNAME_HEK(stash);
        /* so add empty isa_hash entries for all isa keys */
        while (svp <= svp_end) {
            (void) hv_store_ent(isa_hash, *svp++, UNDEF, 0);
        }
        (void)hv_common(isa_hash, NULL, HEK_KEY(canon_name),
                        HEK_LEN(canon_name), HEK_FLAGS(canon_name),
                        HV_FETCH_ISSTORE, UNDEF,
                        HEK_HASH(canon_name));
        (void)hv_stores(isa_hash, "UNIVERSAL", UNDEF);
        SvREADONLY_on(isa_hash);
        meta->isa = isa_hash;
    }

    return isa;
}

/*
=for apidoc mro_isa_changed_in

Takes the necessary steps (cache invalidations, mostly) when the
C<@ISA> of the given package has changed.  Invoked by the C<setisa>
magic, should not need to invoke directly.

=cut
*/

/* Macro to avoid repeating the code five times. */
#define CLEAR_LINEAR(mEta)                                     \
    if (mEta->mro_linear_all) {                                 \
	SvREFCNT_dec(MUTABLE_SV(mEta->mro_linear_all));          \
	mEta->mro_linear_all = NULL;                              \
	/* This is just acting as a shortcut pointer.  */          \
	mEta->mro_linear_current = NULL;                            \
    } else if (mEta->mro_linear_current) {                           \
	/* Only the current MRO is stored, so this owns the data.  */ \
	SvREFCNT_dec(mEta->mro_linear_current);                        \
	mEta->mro_linear_current = NULL;                                \
    }

void
Perl_mro_isa_changed_in(pTHX_ HV* stash)
{
    HV* isarev;
    AV* linear_mro;
    HE* iter;
    SV** svp;
    SSize_t items;
    bool is_universal;
    struct mro_meta * meta;
    HV *isa = NULL;

    const HEK * const stashhek = HvENAME_HEK(stash);
    const char * const stashname = HvENAME_get(stash);
    const STRLEN stashname_len = HvENAMELEN_get(stash);

    PERL_ARGS_ASSERT_MRO_ISA_CHANGED_IN;

    if (!stashname)
        Perl_croak(aTHX_ "Can't call mro_isa_changed_in() on anonymous symbol table");


    /* wipe out the cached linearizations for this stash */
    meta = HvMROMETA(stash);
    CLEAR_LINEAR(meta);
    if (meta->isa) {
	/* Steal it for our own purposes. */
	isa = (HV *)sv_2mortal((SV *)meta->isa);
	meta->isa = NULL;
    }

    /* Inc the package generation, since our @ISA changed */
    meta->pkg_gen++;

    /* Wipe the global method cache if this package
       is UNIVERSAL or one of its parents */

    svp = hv_fetchhek(PL_isarev, stashhek, 0);
    isarev = svp ? MUTABLE_HV(*svp) : NULL;

    if ((stashname_len == 9 && strEQc(stashname, "UNIVERSAL"))
        || (isarev && hv_exists(isarev, "UNIVERSAL", 9))) {
        PL_sub_generation++;
        is_universal = TRUE;
    }
    else { /* Wipe the local method cache otherwise */
        meta->cache_gen++;
	is_universal = FALSE;
    }

    /* wipe next::method cache too */
    if (meta->mro_nextmethod) hv_clear(meta->mro_nextmethod);

    /* Changes to @ISA might turn overloading on */
    HvAMAGIC_on(stash);
    /* pessimise derefs for now. Will get recalculated by Gv_AMupdate() */
    HvAUX(stash)->xhv_aux_flags &= ~HvAUXf_NO_DEREF;

    /* DESTROY can be cached in meta. */
    meta->destroy_gen = 0;

    /* Iterate the isarev (classes that are our children),
       wiping out their linearization, method and isa caches
       and upating PL_isarev. */
    if (isarev) {
        HV *isa_hashes = NULL;

       /* We have to iterate through isarev twice to avoid a chicken and
        * egg problem: if A inherits from B and both are in isarev, A might
        * be processed before B and use B's previous linearisation.
        */

       /* First iteration: Wipe everything, but stash away the isa hashes
        * since we still need them for updating PL_isarev.
        */

        if (hv_iterinit(isarev)) {
            /* Only create the hash if we need it; i.e., if isarev has
               any elements. */
            isa_hashes = (HV *)sv_2mortal((SV *)newHV());
        }
        while ((iter = hv_iternext(isarev))) {
            HV* revstash = gv_stashsv(hv_iterkeysv(iter), 0);
            struct mro_meta* revmeta;

            if (!revstash) continue;
            revmeta = HvMROMETA(revstash);
	    CLEAR_LINEAR(revmeta);
            if (!is_universal)
                revmeta->cache_gen++;
            if (revmeta->mro_nextmethod)
                hv_clear(revmeta->mro_nextmethod);
	    if (!SvOBJECT(revstash)) SvSTASH(revstash) = NULL;

	    (void)
	      hv_store(
	       isa_hashes, (const char*)&revstash, sizeof(HV *),
	       revmeta->isa ? (SV *)revmeta->isa : UNDEF, 0
	      );
	    revmeta->isa = NULL;
        }

       /* Second pass: Update PL_isarev. We can just use isa_hashes to
        * avoid another round of stash lookups. */

       /* isarev might be deleted from PL_isarev during this loop, so hang
        * on to it. */
        SvREFCNT_inc_simple_void_NN(sv_2mortal((SV *)isarev));

        if (isa_hashes) {
            (void)hv_iterinit(isa_hashes);
            while ((iter = hv_iternext(isa_hashes))) {
                HV* const revstash = *(HV **)HEK_KEY(HeKEY_hek(iter));
                HV * const isa = (HV *)HeVAL(iter);
                const HEK *namehek;

                /* We're starting at the 2nd element, skipping revstash */
                linear_mro = mro_get_linear_isa(revstash);
                svp = AvARRAY(linear_mro) + 1;
                items = AvFILLp(linear_mro);

                namehek = HvENAME_HEK(revstash);
                if (!namehek) namehek = HvNAME_HEK(revstash);

                while (items--) {
                    SV* const sv = *svp++;
                    HV* mroisarev;

                    HE *he = hv_fetch_ent(PL_isarev, sv, TRUE, 0);

                    /* That fetch should not fail.  But if it had to create
                       a new SV for us, then will need to upgrade it to an
                       HV (which sv_upgrade() can now do for us). */

                    mroisarev = MUTABLE_HV(HeVAL(he));

                    SvUPGRADE(MUTABLE_SV(mroisarev), SVt_PVHV);

                    /* This hash only ever contains PL_sv_yes. Storing it
                       over itself is almost as cheap as calling hv_exists,
                       so on aggregate we expect to save time by not making
                       two calls to the common HV code for the case where
                       it doesn't exist.  */

                    (void)
                      hv_storehek(mroisarev, namehek, SV_YES);
                }

                if ((SV *)isa != UNDEF) {
                    assert(namehek);
                    mro_clean_isarev(
                     isa, HEK_KEY(namehek), HEK_LEN(namehek),
                     HvMROMETA(revstash)->isa, HEK_HASH(namehek),
                     HEK_UTF8(namehek)
                    );
                }
            }
        }
    }

    /* Now iterate our MRO (parents), adding ourselves and everything from
       our isarev to their isarev. */

    /* We're starting at the 2nd element, skipping ourselves here */
    linear_mro = mro_get_linear_isa(stash);
    svp = AvARRAY(linear_mro) + 1;
    items = AvFILLp(linear_mro);

    while (items--) {
        SV* const sv = *svp++;
        HV* mroisarev;

        HE *he = hv_fetch_ent(PL_isarev, sv, TRUE, 0);

	/* That fetch should not fail.  But if it had to create a new SV for
	   us, then will need to upgrade it to an HV (which sv_upgrade() can
	   now do for us. */

        mroisarev = MUTABLE_HV(HeVAL(he));

	SvUPGRADE(MUTABLE_SV(mroisarev), SVt_PVHV);

	/* This hash only ever contains PL_sv_yes. Storing it over itself is
	   almost as cheap as calling hv_exists, so on aggregate we expect to
	   save time by not making two calls to the common HV code for the
	   case where it doesn't exist.  */

	(void)hv_storehek(mroisarev, stashhek, SV_YES);
    }

    /* Delete our name from our former parents' isarevs. */
    if (isa && HvARRAY(isa))
        mro_clean_isarev(isa, stashname, stashname_len, meta->isa,
                         HEK_HASH(stashhek), HEK_UTF8(stashhek));
}

/* Deletes name from all the isarev entries listed in isa */
STATIC void
S_mro_clean_isarev(pTHX_ HV * const isa, const char * const name,
                         const STRLEN len, HV * const exceptions, U32 hash,
                         U32 flags)
{
    HE* iter;
    PERL_ARGS_ASSERT_MRO_CLEAN_ISAREV;

    /* Delete our name from our former parents' isarevs. */
    if (HvARRAY(isa) && hv_iterinit(isa)) {
        SV **svp;
        while ((iter = hv_iternext(isa))) {
            I32 klen;
            const char * const key = hv_iterkey(iter, &klen);
            if (exceptions && hv_exists(exceptions, key, HeKUTF8(iter) ? -klen : klen))
                continue;
            svp = hv_fetch(PL_isarev, key, HeKUTF8(iter) ? -klen : klen, 0);
            if (svp) {
                HV * const isarev = (HV *)*svp;
                if (UNLIKELY(len > I32_MAX))
                    Perl_croak(aTHX_ "panic: mro name too long (%" UVuf ")", (UV) len);
                (void)hv_common(isarev, NULL, name, len, flags,
                                G_DISCARD|HV_DELETE, NULL, hash);
                if (!HvARRAY(isarev) || !HvUSEDKEYS(isarev))
                    (void)hv_delete(PL_isarev, key,
                                    HeKUTF8(iter) ? -klen : klen, G_DISCARD);
            }
        }
    }
}

/*
=for apidoc mro_package_moved

Call this function to signal to a stash that it has been assigned to
another spot in the stash hierarchy.  C<stash> is the stash that has been
assigned.  C<oldstash> is the stash it replaces, if any.  C<gv> is the glob
that is actually being assigned to.

This can also be called with a null first argument to indicate that
C<oldstash> has been deleted.

This function invalidates isa caches on the old stash, on all subpackages
nested inside it, and on the subclasses of all those, including
non-existent packages that have corresponding entries in C<stash>.

It also sets the effective names (C<HvENAME>) on all the stashes as
appropriate.

If the C<gv> is present and is not in the symbol table, then this function
simply returns.  This checked will be skipped if C<flags & 1>.

=cut
*/
void
Perl_mro_package_moved(pTHX_ HV * const stash, HV * const oldstash,
                       const GV * const gv, U32 flags)
{
    SV *namesv;
    HEK **namep;
    I32 name_count;
    HV *stashes;
    HE* iter;

    PERL_ARGS_ASSERT_MRO_PACKAGE_MOVED;
    assert(stash || oldstash);

    /* Determine the name(s) of the location that stash was assigned to
     * or from which oldstash was removed.
     *
     * We cannot reliably use the name in oldstash, because it may have
     * been deleted from the location in the symbol table that its name
     * suggests, as in this case:
     *
     *   $globref = \*foo::bar::;
     *   Symbol::delete_package("foo");
     *   *$globref = \%baz::;
     *   *$globref = *frelp::;
     *      # calls mro_package_moved(%frelp::, %baz::, *$globref, NULL, 0)
     *
     * So we get it from the gv. But, since the gv may no longer be in the
     * symbol table, we check that first. The only reliable way to tell is
     * to see whether its stash has an effective name and whether the gv
     * resides in that stash under its name. That effective name may be
     * different from what gv_fullname4 would use.
     * If flags & 1, the caller has asked us to skip the check.
     */
    if (!(flags & 1)) {
	SV **svp;
	if (!GvSTASH(gv)
            || !HvENAME(GvSTASH(gv))
            || !(svp = hv_fetchhek_ifexists(GvSTASH(gv), GvNAME_HEK(gv), 0))
            || *svp != (SV *)gv)
            return;
    }
    assert(SvOOK(GvSTASH(gv)));
    assert(GvNAMELEN(gv));
    assert(GvNAME(gv)[GvNAMELEN(gv) - 1] == ':');
    assert(GvNAMELEN(gv) == 1 || GvNAME(gv)[GvNAMELEN(gv) - 2] == ':');
    name_count = HvAUX(GvSTASH(gv))->xhv_name_count;
    if (!name_count) {
	name_count = 1;
	namep = &HvAUX(GvSTASH(gv))->xhv_name_u.xhvnameu_name;
    }
    else {
	namep = HvAUX(GvSTASH(gv))->xhv_name_u.xhvnameu_names;
	if (name_count < 0) ++namep, name_count = -name_count - 1;
    }
    if (name_count == 1) {
	if (memEQs(HEK_KEY(*namep), HEK_LEN(*namep), "main")) {
	    namesv = GvNAMELEN(gv) == 1
		? newSVpvs_flags(":", SVs_TEMP)
		: newSVpvs_flags("",  SVs_TEMP);
	}
	else {
	    namesv = sv_2mortal(newSVhek(*namep));
	    if (GvNAMELEN(gv) == 1) sv_catpvs(namesv, ":");
	    else                    sv_catpvs(namesv, "::");
	}
	if (GvNAMELEN(gv) != 1) {
	    sv_catpvn_flags(
		namesv, GvNAME(gv), GvNAMELEN(gv) - 2,
	                                  /* skip trailing :: */
		GvNAMEUTF8(gv) ? SV_CATUTF8 : SV_CATBYTES);
        }
    }
    else {
	SV *aname;
	namesv = sv_2mortal((SV *)newAV());
	while (name_count--) {
	    if (memEQs(HEK_KEY(*namep), HEK_LEN(*namep), "main")) {
		aname = GvNAMELEN(gv) == 1
		         ? newSVpvs(":")
		         : newSVpvs("");
		namep++;
	    }
	    else {
		aname = newSVhek(*namep++);
		if (GvNAMELEN(gv) == 1) sv_catpvs(aname, ":");
		else                    sv_catpvs(aname, "::");
	    }
	    if (GvNAMELEN(gv) != 1) {
		sv_catpvn_flags(
		    aname, GvNAME(gv), GvNAMELEN(gv) - 2,
	                                  /* skip trailing :: */
		    GvNAMEUTF8(gv) ? SV_CATUTF8 : SV_CATBYTES
		);
            }
	    av_push((AV *)namesv, aname);
	}
    }

    /* Get a list of all the affected classes. */
    /* We cannot simply pass them all to mro_isa_changed_in to avoid
       the list, as that function assumes that only one package has
       changed. It does not work with:

          @foo::ISA = qw( B B::B );
          *B:: = delete $::{"A::"};

       as neither B nor B::B can be updated before the other, since they
       will reset caches on foo, which will see either B or B::B with the
       wrong name. The names must be set on *all* affected stashes before
       we do anything else. (And linearisations must be cleared, too.)
     */
    stashes = (HV *) sv_2mortal((SV *)newHV());
    mro_gather_and_rename(stashes, (HV *) sv_2mortal((SV *)newHV()),
                          stash, oldstash, namesv);

    /* Once the caches have been wiped on all the classes, call
       mro_isa_changed_in on each. */
    (void)hv_iterinit(stashes);
    while ((iter = hv_iternext(stashes))) {
	HV * const stash = *(HV **)HEK_KEY(HeKEY_hek(iter));
	if (HvENAME(stash)) {
	    /* We have to restore the original meta->isa (that
	       mro_gather_and_rename set aside for us) this way, in case
	       one class in this list is a superclass of a another class
	       that we have already encountered. In such a case, meta->isa
	       will have been overwritten without old entries being deleted
	       from PL_isarev. */
	    struct mro_meta * const meta = HvMROMETA(stash);
	    if (meta->isa != (HV *)HeVAL(iter)) {
		SvREFCNT_dec(meta->isa);
		meta->isa = HeVAL(iter) == SV_YES
		    ? NULL : (HV *)HeVAL(iter);
		HeVAL(iter) = NULL; /* We donated our reference count. */
	    }
	    mro_isa_changed_in(stash);
	}
    }
}

STATIC void
S_mro_gather_and_rename(pTHX_ HV * const stashes, HV * const seen_stashes,
                              HV *stash, HV *oldstash, SV *namesv)
{
    XPVHV* xhv;
    HE *entry;
    U32 riter = 0;
    SSize_t items = 0;
    const bool stash_had_name = stash && HvENAME(stash);
    bool fetched_isarev = FALSE;
    HV *seen = NULL;
    HV *isarev = NULL;
    SV **svp = NULL;

    PERL_ARGS_ASSERT_MRO_GATHER_AND_RENAME;

    /* We use the seen_stashes hash to keep track of which packages have
       been encountered so far. This must be separate from the main list of
       stashes, as we need to distinguish between stashes being assigned
       and stashes being replaced/deleted. (A nested stash can be on both
       sides of an assignment. We cannot simply skip iterating through a
       stash on the right if we have seen it on the left, as it will not
       get its ename assigned to it.)

       To avoid allocating extra SVs, instead of a bitfield we can make
       bizarre use of immortals:

        UNDEF:  seen on the left  (oldstash)
        SV_NO   :  seen on the right (stash)
        SV_YES  :  seen on both sides

     */

    if (oldstash) {
	/* Add to the big list. */
	struct mro_meta * meta;
        /* Hack. This stores a pointer, not the name */
	HE * const entry = (HE*)hv_common(seen_stashes, NULL, (const char *)&oldstash,
              sizeof(HV *), 0, HV_FETCH_LVALUE|HV_FETCH_EMPTY_HE, NULL, 0);
	if (HeVAL(entry) == UNDEF || HeVAL(entry) == SV_YES) {
	    oldstash = NULL;
	    goto check_stash;
	}
	HeVAL(entry) = HeVAL(entry) == SV_NO ? SV_YES : UNDEF;
	meta = HvMROMETA(oldstash);
        /* Hack. Again a pointer, not the name */
	(void)hv_store(stashes, (const char *)&oldstash, sizeof(HV *),
                       meta->isa ? SvREFCNT_inc_simple_NN((SV *)meta->isa)
                                 : SV_YES, 0);
	CLEAR_LINEAR(meta);

	/* Update the effective name. */
	if (HvENAME_get(oldstash)) {
	    const HEK * const enamehek = HvENAME_HEK(oldstash);
	    if (SvTYPE(namesv) == SVt_PVAV) {
		items = AvFILLp((AV *)namesv) + 1;
		svp = AvARRAY((AV *)namesv);
	    }
	    else {
		items = 1;
		svp = &namesv;
	    }
	    while (items--) {
                const U32 name_utf8 = SvUTF8(*svp);
		STRLEN len;
		const char *name = SvPVx_const(*svp, len);
		if (PL_stashcache) {
                    DEBUG_o(Perl_deb(aTHX_
                        "mro_gather_and_rename clearing PL_stashcache for '%" SVf "'\n",
                        SVfARG(*svp)));
                    if (UNLIKELY(len > I32_MAX))
                        Perl_croak(aTHX_ "panic: stash name too long (%" UVuf ")",
                                   (UV) len);
		   (void)hv_delete(PL_stashcache, name, name_utf8
                                   ? -(I32)len : (I32)len, G_DISCARD);
                }
                ++svp;
	        hv_ename_delete(oldstash, name, len, name_utf8);

		if (!fetched_isarev) {
		    /* If the name deletion caused a name change, then we
		     * are not going to call mro_isa_changed_in with this
		     * name (and not at all if it has become anonymous) so
		     * we need to delete old isarev entries here, both
		     * those in the superclasses and this class's own list
		     * of subclasses. We simply delete the latter from
		     * PL_isarev, since we still need it. hv_delete morti-
		     * fies it for us, so sv_2mortal is not necessary. */
		    if (HvENAME_HEK(oldstash) != enamehek) {
			if (meta->isa && HvARRAY(meta->isa))
			    mro_clean_isarev(meta->isa, name, len, 0, 0,
					     name_utf8 ? HVhek_UTF8 : 0);
                        if (UNLIKELY(len > I32_MAX))
                            Perl_croak(aTHX_ "panic: stash name too long (%" UVuf ")",
                                       (UV) len);
			isarev = (HV *)hv_delete(PL_isarev, name,
                                                 name_utf8 ? -(I32)len : (I32)len, 0);
			fetched_isarev = TRUE;
		    }
		}
	    }
	}
    }
   check_stash:
    if (stash) {
	if (SvTYPE(namesv) == SVt_PVAV) {
	    items = AvFILLp((AV *)namesv) + 1;
	    svp = AvARRAY((AV *)namesv);
	}
	else {
	    items = 1;
	    svp = &namesv;
	}
	while (items--) {
            const U32 name_utf8 = SvUTF8(*svp);
	    STRLEN len;
	    const char *name = SvPVx_const(*svp++, len);
            if (UNLIKELY(len > I32_MAX))
                Perl_croak(aTHX_ "panic: stash name too long (%" UVuf ")", (UV) len);
	    hv_ename_add(stash, name, len, name_utf8);
	}

       /* Add it to the big list if it needs mro_isa_changed_in called
	* on it. That happens if it was detached from the symbol table
	* (so it had no HvENAME) before being assigned to the spot
	* named by the 'name' variable, because its cached isa
	* linearisation is now stale (the effective name having
	* changed), and subclasses will then use that cache when
	* mro_package_moved calls mro_isa_changed_in. (See [perl
	* #77358].)
	*
	* If it did have a name, then its previous name is still used
	* in isa caches, and there is no need for mro_package_moved to
	* call mro_isa_changed_in.
	*/

        /* Hack. Again a pointer, not the name */
	entry = (HE *)hv_common(seen_stashes, NULL, (const char *)&stash,
              sizeof(HV *), 0, HV_FETCH_LVALUE|HV_FETCH_EMPTY_HE, NULL, 0);
	if (HeVAL(entry) == SV_YES || HeVAL(entry) == SV_NO)
	    stash = NULL;
	else {
	    HeVAL(entry) = HeVAL(entry) == UNDEF ? SV_YES : SV_NO;
	    if (!stash_had_name) {
		struct mro_meta * const meta = HvMROMETA(stash);
                /* Hack. Again a pointer, not the name */
		(void)hv_store(stashes, (const char *)&stash, sizeof(HV *),
                               meta->isa ? SvREFCNT_inc_simple_NN((SV *)meta->isa)
                                         : SV_YES, 0);
		CLEAR_LINEAR(meta);
	    }
	}
    }

    if (!stash && !oldstash)
	/* Both stashes have been encountered already. */
	return;

    /* Add all the subclasses to the big list. */
    if (!fetched_isarev) {
	/* If oldstash is not null, then we can use its HvENAME to look up
	   the isarev hash, since all its subclasses will be listed there.
	   It will always have an HvENAME. It the HvENAME was removed
	   above, then fetch_isarev will be true, and this code will not be
	   reached.

	   If oldstash is null, then this is an empty spot with no stash in
	   it, so subclasses could be listed in isarev hashes belonging to
	   any of the names, so we have to check all of them.
	 */
	assert(!oldstash || HvENAME(oldstash));
	if (oldstash) {
	    /* Extra variable to avoid a compiler warning */
	    const HEK * const hvename = HvENAME_HEK(oldstash);
	    fetched_isarev = TRUE;
	    svp = hv_fetchhek(PL_isarev, hvename, 0);
	    if (svp) isarev = MUTABLE_HV(*svp);
	}
	else if (SvTYPE(namesv) == SVt_PVAV) {
	    items = AvFILLp((AV *)namesv) + 1;
	    svp = AvARRAY((AV *)namesv);
	}
	else {
	    items = 1;
	    svp = &namesv;
	}
    }
    if ( isarev || !fetched_isarev ) {
        while (fetched_isarev || items--) {
            HE *iter;

            if (!fetched_isarev) {
                HE * const he = hv_fetch_ent(PL_isarev, *svp++, 0, 0);
                if (!he || !(isarev = MUTABLE_HV(HeVAL(he)))) continue;
            }

            (void)hv_iterinit(isarev);
            while ((iter = hv_iternext(isarev))) {
                HV* revstash = gv_stashsv(hv_iterkeysv(iter), 0);
                struct mro_meta * meta;

                if (!revstash) continue;
                meta = HvMROMETA(revstash);
                /* Hack. Again a pointer, not the name */
                (void)hv_store(stashes, (const char *)&revstash, sizeof(HV *),
                               meta->isa ? SvREFCNT_inc_simple_NN((SV *)meta->isa)
                               : SV_YES, 0);
                CLEAR_LINEAR(meta);
            }

            if (fetched_isarev) break;
        }
    }

    /* This is partly based on code in hv_iternext_flags. We are not call-
       ing that here, as we want to avoid resetting the hash iterator. */

    /* Skip the entire loop if the hash is empty.   */
    if (oldstash && HvUSEDKEYS(oldstash)) {
	xhv = (XPVHV*)SvANY(oldstash);
	seen = (HV *) sv_2mortal((SV *)newHV());

	/* Iterate through entries in the oldstash, adding them to the
	   list, meanwhile doing the equivalent of $seen{$key} = 1. */

	for (; riter <= xhv->xhv_max; riter++) {
	    entry = (HvARRAY(oldstash))[riter];

	    /* Iterate through the entries in this list */
	    for(; entry; entry = HeNEXT(entry)) {
		const char* key;
		I32 len;

		/* If this entry is not a glob, ignore it.
		   Try the next.  */
		if (!isGV(HeVAL(entry))) continue;

		key = hv_iterkey(entry, &len);
		if ((len > 1 && key[len-2] == ':' && key[len-1] == ':')
		 || (len == 1 && key[0] == ':')) {
		    HV * const oldsubstash = GvHV(HeVAL(entry));
		    SV ** const stashentry = stash
                        ? hv_fetch_ifexists(stash, key, HeUTF8(entry) ? -(I32)len : (I32)len, 0)
                        : NULL;
		    HV *substash = NULL;

		    /* Avoid main::main::main::... */
		    if (oldsubstash == oldstash) continue;

		    if ((    stashentry && *stashentry && isGV(*stashentry)
		         && (substash = GvHV(*stashentry)))
                        || (oldsubstash && HvENAME_get(oldsubstash)))
		    {
			/* Add :: and the key (minus the trailing ::)
			   to each name. */
			SV *subname;
			if (SvTYPE(namesv) == SVt_PVAV) {
			    SV *aname;
			    items = AvFILLp((AV *)namesv) + 1;
			    svp = AvARRAY((AV *)namesv);
			    subname = sv_2mortal((SV *)newAV());
			    while (items--) {
				aname = newSVsv(*svp++);
				if (len == 1)
				    sv_catpvs(aname, ":");
				else {
				    sv_catpvs(aname, "::");
				    sv_catpvn_flags(
					aname, key, len-2,
					HeUTF8(entry)
					   ? SV_CATUTF8 : SV_CATBYTES);
				}
				av_push((AV *)subname, aname);
			    }
			}
			else {
			    subname = sv_2mortal(newSVsv(namesv));
			    if (len == 1) sv_catpvs(subname, ":");
			    else {
				sv_catpvs(subname, "::");
				sv_catpvn_flags(
				   subname, key, len-2,
				   HeUTF8(entry) ? SV_CATUTF8 : SV_CATBYTES);
			    }
			}
			mro_gather_and_rename(stashes, seen_stashes,
                                              substash, oldsubstash, subname);
		    }

		    (void)hv_store(seen, key, HeUTF8(entry) ? -(I32)len : (I32)len,
                                   SV_YES, 0);
		}
	    }
	}
    }

    /* Skip the entire loop if the hash is empty.   */
    if (stash && HvUSEDKEYS(stash)) {
	xhv = (XPVHV*)SvANY(stash);

	/* Iterate through the new stash, skipping $seen{$key} items,
	   calling mro_gather_and_rename(stashes,seen,entry,NULL, ...). */
	for (riter=0; riter <= xhv->xhv_max; riter++) {
	    entry = (HvARRAY(stash))[riter];

	    /* Iterate through the entries in this list */
	    for(; entry; entry = HeNEXT(entry)) {
		const char* key;
		I32 len;

		/* If this entry is not a glob, ignore it.
		   Try the next. */
		if (!isGV(HeVAL(entry))) continue;

		key = hv_iterkey(entry, &len);
		if ((len > 1 && key[len-2] == ':' && key[len-1] == ':')
		 || (len == 1 && key[0] == ':')) {
		    HV *substash;

		    /* If this entry was seen when we iterated through the
		       oldstash, skip it. */
		    if (seen && hv_exists(seen, key, HeUTF8(entry)
                                          ? -(I32)len : (I32)len))
                        continue;

		    /* We get here only if this stash has no corresponding
		       entry in the stash being replaced. */

		    substash = GvHV(HeVAL(entry));
		    if (substash) {
			SV *subname;

			/* Avoid checking main::main::main::... */
			if (substash == stash) continue;

			/* Add :: and the key (minus the trailing ::)
			   to each name. */
			if (SvTYPE(namesv) == SVt_PVAV) {
			    SV *aname;
			    items = AvFILLp((AV *)namesv) + 1;
			    svp = AvARRAY((AV *)namesv);
			    subname = sv_2mortal((SV *)newAV());
			    while (items--) {
				aname = newSVsv(*svp++);
				if (len == 1)
				    sv_catpvs(aname, ":");
				else {
				    sv_catpvs(aname, "::");
				    sv_catpvn_flags(
					aname, key, len-2,
					HeUTF8(entry)
					   ? SV_CATUTF8 : SV_CATBYTES
				    );
				}
				av_push((AV *)subname, aname);
			    }
			}
			else {
			    subname = sv_2mortal(newSVsv(namesv));
			    if (len == 1) sv_catpvs(subname, ":");
			    else {
				sv_catpvs(subname, "::");
				sv_catpvn_flags(subname, key, len-2,
				   HeUTF8(entry) ? SV_CATUTF8 : SV_CATBYTES);
			    }
			}
			mro_gather_and_rename(stashes, seen_stashes,
                                              substash, NULL, subname);
		    }
		}
	    }
	}
    }
}

/*
=for apidoc mro_method_changed_in

Invalidates method caching on any child classes of the given stash, so
that they might notice the changes in this one.

Ideally, all instances of C<PL_sub_generation++> in perl source
outside of F<mro.c> should be replaced by calls to this.

Perl automatically handles most of the common ways a method might be
redefined.  However, there are a few ways you could change a method in
a stash without the cache code noticing, in which case you need to
call this method afterwards:

1) Directly manipulating the stash HV entries from XS code.

2) Assigning a reference to a readonly scalar constant into a stash
entry in order to create a constant subroutine (like F<constant.pm>
does).

This same method is available from pure perl via,
C<mro::method_changed_in(classname)>.

=cut
*/
void
Perl_mro_method_changed_in(pTHX_ HV *stash)
{
    const char * const stashname = HvENAME_get(stash);
    const I32 stashname_len = HvENAMELEN_get(stash);

    SV ** const svp = hv_fetchhek(PL_isarev, HvENAME_HEK(stash), 0);
    HV * const isarev = svp ? MUTABLE_HV(*svp) : NULL;

    PERL_ARGS_ASSERT_MRO_METHOD_CHANGED_IN;

    if (!stashname)
        Perl_croak(aTHX_ "Can't call mro_method_changed_in() on anonymous symbol table");

    /* Inc the package generation, since a local method changed */
    HvMROMETA(stash)->pkg_gen++;

    /* DESTROY can be cached in meta */
    HvMROMETA(stash)->destroy_gen = 0;

    /* If stash is UNIVERSAL, or one of UNIVERSAL's parents,
       invalidate all method caches globally */
    if ((stashname_len == 9 && strEQc(stashname, "UNIVERSAL"))
        || (isarev && hv_exists(isarev, "UNIVERSAL", 9))) {
        PL_sub_generation++;
        return;
    }

    /* else, invalidate the method caches of all child classes,
       but not itself */
    if (isarev) {
	HE* iter;

        (void)hv_iterinit(isarev);
        while ((iter = hv_iternext(isarev))) {
            HV* const revstash = gv_stashsv(hv_iterkeysv(iter), 0);
            struct mro_meta* mrometa;

            if (!revstash) continue;
            mrometa = HvMROMETA(revstash);
            mrometa->cache_gen++;
            if (mrometa->mro_nextmethod)
                hv_clear(mrometa->mro_nextmethod);
            mrometa->destroy_gen = 0;
        }
    }

    /* The method change may be due to *{$package . "::()"} = \&nil; in
       overload.pm. */
    HvAMAGIC_on(stash);
    /* pessimise derefs for now. Will get recalculated by Gv_AMupdate() */
    HvAUX(stash)->xhv_aux_flags &= ~HvAUXf_NO_DEREF;
}

void
Perl_mro_set_mro(pTHX_ struct mro_meta *const meta, SV *const name)
{
    const struct mro_alg *const which = mro_get_from_name(name);

    PERL_ARGS_ASSERT_MRO_SET_MRO;

    if (!which)
        Perl_croak(aTHX_ "Invalid mro name: '%" SVf "'", name);

    if (meta->mro_which != which) {
	if (meta->mro_linear_current && !meta->mro_linear_all) {
	    /* If we were storing something directly, put it in the hash before
	       we lose it. */
	    mro_set_private_data(meta, meta->mro_which,
                                 MUTABLE_SV(meta->mro_linear_current));
	}
	meta->mro_which = which;
	/* Scrub our cached pointer to the private data.  */
	meta->mro_linear_current = NULL;
        /* Only affects local method cache, not
           even child classes */
        meta->cache_gen++;
        if (meta->mro_nextmethod)
            hv_clear(meta->mro_nextmethod);
    }
}

#include "XSUB.h"

XS(XS_mro_method_changed_in);

void
Perl_boot_core_mro(pTHX)
{
    static const char file[] = __FILE__;
    mro_register(&c3_alg);
    newXSproto("mro::method_changed_in", XS_mro_method_changed_in, file, "$");
}

XS(XS_mro_method_changed_in)
{
    dXSARGS;
    SV* classname;
    HV* class_stash;

    if (items != 1)
	croak_xs_usage(cv, "classname");
    classname = ST(0);
    class_stash = gv_stashsv(classname, 0);
    if (!class_stash)
        Perl_croak(aTHX_ "No such class: '%" SVf "'!", SVfARG(classname));
    mro_method_changed_in(class_stash);
    XSRETURN_EMPTY;
}

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
