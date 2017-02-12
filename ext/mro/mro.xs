#define PERL_NO_GET_CONTEXT
#define PERL_CORE

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

static AV*
S_mro_get_linear_isa_dfs(pTHX_ HV* stash, U32 level);

static const struct mro_alg dfs_alg =
    {S_mro_get_linear_isa_dfs, "dfs", 3, 0, 0};


/*
=for apidoc mro_get_linear_isa_dfs

Returns the old Depth-First Search linearization of C<@ISA> the given
stash.  The return value is a read-only AV*.  C<level> should be 0 (it
is used internally in this function's recursion).

You are responsible for C<SvREFCNT_inc()> on the return value if you
plan to store it anywhere semi-permanently (otherwise it might be
deleted out from under you the next time the cache is invalidated).

=cut
*/
static AV*
S_mro_get_linear_isa_dfs(pTHX_ HV *stash, U32 level)
{
    AV* retval;
    GV** gvp;
    GV* gv;
    AV* av;
    const HEK* stashhek;
    struct mro_meta* meta;
    SV *our_name;
    HV *stored = NULL;

    assert(HvAUX(stash));
    stashhek = HvAUX(stash)->xhv_name_u.xhvnameu_name && HvENAME_HEK_NN(stash)
        ? HvENAME_HEK_NN(stash)
        : HvNAME_HEK(stash);

    if (!stashhek)
      Perl_croak(aTHX_ "Can't linearize anonymous symbol table");

    if (level > 100)
        Perl_croak(aTHX_
		  "Recursive inheritance detected in package '%" HEKf "'",
		   HEKfARG(stashhek));

    meta = HvMROMETA(stash);

    /* return cache if valid */
    if ((retval = MUTABLE_AV(MRO_GET_PRIVATE_DATA(meta, &dfs_alg)))) {
        return retval;
    }

    /* not in cache, make a new one */

    retval = MUTABLE_AV(sv_2mortal(MUTABLE_SV(newAV())));
    /* We use this later in this function, but don't need a reference to it
       beyond the end of this function, so reference count is fine.  */
    our_name = newSVhek(stashhek);
    av_push(retval, our_name); /* add ourselves at the top */

    /* fetch our @ISA */
    gvp = (GV**)hv_fetchs_ifexists(stash, "ISA", FALSE);
    av = (gvp && (gv = *gvp) && isGV_with_GP(gv)) ? GvAV(gv) : NULL;

    /* "stored" is used to keep track of all of the classnames we have added to
       the MRO so far, so we can do a quick exists check and avoid adding
       duplicate classnames to the MRO as we go.
       It's then retained to be re-used as a fast lookup for ->isa(), by adding
       our own name and "UNIVERSAL" to it.  */

    if (av && AvFILLp(av) >= 0) {

        SV **svp = AvARRAY(av);
        SSize_t items = AvFILLp(av) + 1;

        /* foreach(@ISA) */
        while (items--) {
            SV* const sv = *svp ? *svp : &PL_sv_undef;
            HV* const basestash = gv_stashsv(sv, 0);
	    SV *const *subrv_p;
	    SSize_t subrv_items;
	    svp++;

            if (!basestash) {
                /* if no stash exists for this @ISA member,
                   simply add it to the MRO and move on */
		subrv_p = &sv;
		subrv_items = 1;
            }
            else {
                /* otherwise, recurse into ourselves for the MRO
                   of this @ISA member, and append their MRO to ours.
		   The recursive call could throw an exception, which
		   has memory management implications here, hence the use of
		   the mortal.  */
		const AV *const subrv
		    = S_mro_get_linear_isa_dfs(aTHX_ basestash, level + 1);

		subrv_p = AvARRAY(subrv);
		subrv_items = AvFILLp(subrv) + 1;
	    }
	    if (stored) {
		while (subrv_items--) {
		    SV *const subsv = *subrv_p++;
		    /* LVALUE fetch will create a new undefined SV if necessary
		     */
		    HE *const he = hv_fetch_ent(stored, subsv, 1, 0);
		    assert(he);
		    if (HeVAL(he) != &PL_sv_undef) {
			/* It was newly created.  Steal it for our new SV, and
			   replace it in the hash with the "real" thing.  */
			SV *const val = HeVAL(he);
			HEK *const key = HeKEY_hek(he);

			HeVAL(he) = &PL_sv_undef;
			Perl_sv_sethek(aTHX_ val, key);
			av_push(retval, val);
		    }
		}
            } else {
		/* We are the first (or only) parent. We can short cut the
		   complexity above, because our @ISA is simply us prepended
		   to our parent's @ISA, and our ->isa cache is simply our
		   parent's, with our name added.  */
		/* newSVsv() is slow. This code is only faster if we can avoid
		   it by ensuring that SVs in the arrays are shared hash key
		   scalar SVs, because we can "copy" them very efficiently.
		   Although to be fair, we can't *ensure* this, as a reference
		   to the internal array is returned by mro::get_linear_isa(),
		   so we'll have to be defensive just in case someone faffed
		   with it.  */
		if (basestash) {
		    SV **svp;
		    stored = MUTABLE_HV(sv_2mortal((SV*)newHVhv(HvMROMETA(basestash)->isa)));
		    av_extend(retval, subrv_items);
		    AvFILLp(retval) = subrv_items;
		    svp = AvARRAY(retval);
		    while (subrv_items--) {
			SV *const val = *subrv_p++;
			*++svp = SvIsCOW_shared_hash(val)
			    ? newSVhek(SvSHARED_HEK_FROM_PV(SvPVX(val)))
			    : newSVsv(val);
		    }
		} else {
		    /* They have no stash.  So create ourselves an ->isa cache
		       as if we'd copied it from what theirs should be.  */
		    stored = MUTABLE_HV(sv_2mortal(MUTABLE_SV(newHV())));
		    (void)hv_stores(stored, "UNIVERSAL", &PL_sv_undef);
		    av_push(retval,
			    newSVhek(HeKEY_hek(hv_store_ent(stored, sv,
							    &PL_sv_undef, 0))));
		}
	    }
        }
    } else {
	/* We have no parents.  */
	stored = MUTABLE_HV(sv_2mortal(MUTABLE_SV(newHV())));
	(void)hv_stores(stored, "UNIVERSAL", &PL_sv_undef);
    }

    (void)hv_store_ent(stored, our_name, &PL_sv_undef, 0);

    SvREFCNT_inc_simple_void_NN(stored);
    SvTEMP_off(stored);
    SvREADONLY_on(stored);

    meta->isa = stored;

    /* now that we're past the exception dangers, grab our own reference to
       the AV we're about to use for the result. The reference owned by the
       mortals' stack will be released soon, so everything will balance.  */
    SvREFCNT_inc_simple_void_NN(retval);
    SvTEMP_off(retval);

    /* we don't want anyone modifying the cache entry but us,
       and we do so by replacing it completely */
    SvREADONLY_on(retval);

    return MUTABLE_AV(mro_set_private_data(meta, &dfs_alg,
                                           MUTABLE_SV(retval)));
}

/* These two are static helpers for next::method and friends,
   and re-implement a bunch of the code from pp_caller() in
   a more efficient manner for this particular usage.
*/

static I32
__dopoptosub_at(const PERL_CONTEXT *cxstk, I32 startingblock) {
    I32 i;
    for (i = startingblock; i >= 0; i--) {
        if (CxTYPE((PERL_CONTEXT*)(&cxstk[i])) == CXt_SUB) return i;
    }
    return i;
}

MODULE = mro		PACKAGE = mro		PREFIX = mro_

void
mro_get_linear_isa(...)
  PROTOTYPE: $;$
  PREINIT:
    AV* RETVAL;
    HV* class_stash;
    SV* classname;
  PPCODE:
    if (items < 1 || items > 2)
	croak_xs_usage(cv, "classname [, type ]");
    classname = ST(0);
    class_stash = gv_stashsv(classname, 0);
    if (!class_stash) {
        /* No stash exists yet, give them just the classname */
        AV* isalin = newAV();
        av_push(isalin, newSVsv(classname));
        ST(0) = sv_2mortal(newRV_noinc(MUTABLE_SV(isalin)));
        XSRETURN(1);
    }
    else if (items > 1) {
	const struct mro_alg *const algo = mro_get_from_name(ST(1));
	if (!algo)
	    Perl_croak(aTHX_ "Invalid mro name: '%" SVf "'", ST(1));
	RETVAL = algo->resolve(aTHX_ class_stash, 0);
    }
    else {
        RETVAL = mro_get_linear_isa(class_stash);
    }
    ST(0) = newRV_inc(MUTABLE_SV(RETVAL));
    sv_2mortal(ST(0));
    XSRETURN(1);

void
mro_set_mro(...)
  PROTOTYPE: $$
  PREINIT:
    SV* classname;
    HV* class_stash;
    struct mro_meta* meta;
  PPCODE:
    if (items != 2)
	croak_xs_usage(cv, "classname, type");
    classname = ST(0);
    class_stash = gv_stashsv(classname, GV_ADD);
    if (!class_stash)
        Perl_croak(aTHX_ "Cannot create class: '%" SVf "'!", SVfARG(classname));
    meta = HvMROMETA(class_stash);
    mro_set_mro(meta, ST(1));
    XSRETURN_EMPTY;

void
mro_get_mro(...)
  PROTOTYPE: $
  PREINIT:
    SV* classname;
    HV* class_stash;
  PPCODE:
    if (items != 1)
	croak_xs_usage(cv, "classname");
    classname = ST(0);
    class_stash = gv_stashsv(classname, 0);
    if (class_stash) {
        const struct mro_alg *const meta = HvMROMETA(class_stash)->mro_which;
 	ST(0) = newSVpvn_flags(meta->name, meta->length,
		    SVs_TEMP | ((meta->kflags & HVhek_UTF8) ? SVf_UTF8 : 0));
    } else {
        ST(0) = newSVpvn_flags("c3", 2, SVs_TEMP);
    }
    XSRETURN(1);

void
mro_get_isarev(...)
  PROTOTYPE: $
  PREINIT:
    SV* classname;
    HE* he;
    HV* isarev;
    AV* ret_array;
  PPCODE:
    if (items != 1)
	croak_xs_usage(cv, "classname");
    classname = ST(0);
    he = hv_fetch_ent(PL_isarev, classname, 0, 0);
    isarev = he ? MUTABLE_HV(HeVAL(he)) : NULL;
    ret_array = newAV();
    if (isarev) {
        HE* iter;
        hv_iterinit(isarev);
        while ((iter = hv_iternext(isarev)))
            av_push(ret_array, newSVsv(hv_iterkeysv(iter)));
    }
    mXPUSHs(newRV_noinc(MUTABLE_SV(ret_array)));
    PUTBACK;

void
mro_is_universal(...)
  PROTOTYPE: $
  PREINIT:
    SV* classname;
    HV* isarev;
    char* classname_pv;
    STRLEN classname_len;
    HE* he;
  PPCODE:
    if (items != 1)
	croak_xs_usage(cv, "classname");
    classname = ST(0);
    classname_pv = SvPV(classname, classname_len);
    he = hv_fetch_ent(PL_isarev, classname, 0, 0);
    isarev = he ? MUTABLE_HV(HeVAL(he)) : NULL;
    if ((classname_len == 9 && strEQc(classname_pv, "UNIVERSAL"))
        || (isarev && hv_exists(isarev, "UNIVERSAL", 9)))
        XSRETURN_YES;
    else
        XSRETURN_NO;


void
mro_invalidate_all_method_caches(...)
  PROTOTYPE: 
  PPCODE:
    if (items != 0)
	croak_xs_usage(cv, "");

    PL_sub_generation++;

    XSRETURN_EMPTY;

void
mro_get_pkg_gen(...)
  PROTOTYPE: $
  PREINIT:
    HV* class_stash;
  PPCODE:
    if (items != 1)
	croak_xs_usage(cv, "classname");
    class_stash = gv_stashsv(ST(0), 0);
    mXPUSHi(class_stash ? HvMROMETA(class_stash)->pkg_gen : 0);
    PUTBACK;

void
mro__nextcan(...)
  PREINIT:
    SV* self = ST(0);
    const I32 throw_nomethod = SvIVX(ST(1));
    I32 cxix = cxstack_ix;
    const PERL_CONTEXT *ccstack = cxstack;
    const PERL_SI *top_si = PL_curstackinfo;
    HV* selfstash;
    SV *stashname;
    const char *fq_subname = NULL;
    const char *subname = NULL;
    bool subname_utf8 = 0;
    STRLEN stashname_len;
    STRLEN subname_len = 0;
    SV* sv = NULL;
    GV** gvp;
    AV* linear_av;
    SV** linear_svp;
    const char *hvname;
    SSize_t entries;
    struct mro_meta* selfmeta;
    HV* nmcache;
    I32 i;
  PPCODE:
    PERL_UNUSED_ARG(cv);

    if (sv_isobject(self))
        selfstash = SvSTASH(SvRV(self));
    else
        selfstash = gv_stashsv(self, GV_ADD);

    assert(selfstash);

    hvname = HvNAME_get(selfstash);
    if (!hvname)
        Perl_croak(aTHX_ "Can't use anonymous symbol table for method lookup");

    /* This block finds the contextually-enclosing fully-qualified subname,
       much like looking at (caller($i))[3] until you find a real sub that
       isn't ANON, etc (also skips over pureperl next::method, etc) */
    for(i = 0; i < 2; i++) {
        cxix = __dopoptosub_at(ccstack, cxix);
        for (;;) {
	    GV* cvgv;
	    STRLEN fq_subname_len = 0;

            /* we may be in a higher stacklevel, so dig down deeper */
            while (cxix < 0) {
                if (top_si->si_type == PERLSI_MAIN)
                    Perl_croak(aTHX_
                      "next::method/next::can/maybe::next::method must be used in method context");
                top_si = top_si->si_prev;
                ccstack = top_si->si_cxstack;
                cxix = __dopoptosub_at(ccstack, top_si->si_cxix);
            }

            if (CxTYPE((PERL_CONTEXT*)(&ccstack[cxix])) != CXt_SUB
                || (PL_DBsub && GvCV(PL_DBsub)
                    && ccstack[cxix].blk_sub.cv == GvCV(PL_DBsub))) {
                cxix = __dopoptosub_at(ccstack, cxix - 1);
                continue;
            }

            {
                const I32 dbcxix = __dopoptosub_at(ccstack, cxix - 1);
                if (PL_DBsub
                    && GvCV(PL_DBsub)
                    && dbcxix >= 0
                    && ccstack[dbcxix].blk_sub.cv == GvCV(PL_DBsub))
                {
                    if (CxTYPE((PERL_CONTEXT*)(&ccstack[dbcxix])) != CXt_SUB) {
                        cxix = dbcxix;
                        continue;
                    }
                }
            }

            cvgv = CvGV(ccstack[cxix].blk_sub.cv);

            if (!isGV(cvgv)) {
                cxix = __dopoptosub_at(ccstack, cxix - 1);
                continue;
            }

            /* we found a real sub here */
            sv = sv_newmortal();

            gv_efullname3(sv, cvgv, NULL);

	    if (SvPOK(sv)) {
		fq_subname = SvPVX(sv);
		fq_subname_len = SvCUR(sv);

                subname_utf8 = SvUTF8(sv) ? 1 : 0;
		subname = strrchr(fq_subname, ':');
	    } else {
		subname = NULL;
	    }

            if (!subname)
                Perl_croak(aTHX_
              "next::method/next::can/maybe::next::method cannot find enclosing method");

            subname++;
            subname_len = fq_subname_len - (subname - fq_subname);
            if (subname_len == 8 && strEQc(subname, "__ANON__")) {
                cxix = __dopoptosub_at(ccstack, cxix - 1);
                continue;
            }
            break;
        }
        cxix--;
    }

    /* If we made it to here, we found our context */

    /* Initialize the next::method cache for this stash
       if necessary */
    selfmeta = HvMROMETA(selfstash);
    if (!(nmcache = selfmeta->mro_nextmethod)) {
        nmcache = selfmeta->mro_nextmethod = newHV();
    }
    else { /* Use the cached coderef if it exists */
	HE* cache_entry = hv_fetch_ent(nmcache, sv, 0, 0);
	if (cache_entry) {
	    SV* const val = HeVAL(cache_entry);
	    if (val == &PL_sv_undef) {
		if (throw_nomethod)
		    Perl_croak(aTHX_
                       "No next::method '%" SVf "' found for %" HEKf,
                        SVfARG(newSVpvn_flags(subname, subname_len,
                                SVs_TEMP | ( subname_utf8 ? SVf_UTF8 : 0 ) )),
                        HEKfARG( HvNAME_HEK(selfstash) ));
                XSRETURN_EMPTY;
	    }
	    mXPUSHs(newRV_inc(val));
            XSRETURN(1);
	}
    }

    /* beyond here is just for cache misses, so perf isn't as critical */

    stashname_len = subname - fq_subname - 2;
    stashname = newSVpvn_flags(fq_subname, stashname_len,
                               SVs_TEMP | (subname_utf8 ? SVf_UTF8 : 0));

    /* has ourselves at the top of the list */
    linear_av = mro_get_linear_isa(selfstash);

    linear_svp = AvARRAY(linear_av);
    entries = AvFILLp(linear_av) + 1;

    /* Walk down our MRO, skipping everything up
       to the contextually enclosing class */
    while (entries--) {
        SV * const linear_sv = *linear_svp++;
        assert(linear_sv);
        if (sv_eq(linear_sv, stashname))
            break;
    }

    /* Now search the remainder of the MRO for the
       same method name as the contextually enclosing
       method */
    if (entries > 0) {
        while (entries--) {
            SV * const linear_sv = *linear_svp++;
	    HV* curstash;
	    GV* candidate;
	    CV* cand_cv;

            assert(linear_sv);
            curstash = gv_stashsv(linear_sv, FALSE);

            if (!curstash) {
                if (ckWARN(WARN_SYNTAX))
                    Perl_warner(aTHX_ packWARN(WARN_SYNTAX),
                       "Can't locate package %" SVf " for @%" HEKf "::ISA",
                        (void*)linear_sv,
                        HEKfARG( HvNAME_HEK(selfstash) ));
                continue;
            }

            assert(curstash);

            gvp = (GV**)hv_fetch_ifexists(curstash, subname,
                            subname_utf8 ? -(I32)subname_len : (I32)subname_len, 0);
            if (!gvp) continue;

            candidate = *gvp;
            assert(candidate);

            if (SvTYPE(candidate) != SVt_PVGV)
                gv_init_pvn(candidate, curstash, subname, subname_len,
                                GV_ADDMULTI|(subname_utf8 ? SVf_UTF8 : 0));

            /* Notably, we only look for real entries, not method cache
               entries, because in C3 the method cache of a parent is not
               valid for the child */
            if (SvTYPE(candidate) == SVt_PVGV
                && (cand_cv = GvCV(candidate))
                && !GvCVGEN(candidate))
            {
                SvREFCNT_inc_simple_void_NN(MUTABLE_SV(cand_cv));
                (void)hv_store_ent(nmcache, sv, MUTABLE_SV(cand_cv), 0);
                mXPUSHs(newRV_inc(MUTABLE_SV(cand_cv)));
                XSRETURN(1);
            }
        }
    }

    (void)hv_store_ent(nmcache, sv, &PL_sv_undef, 0);
    if (throw_nomethod)
        Perl_croak(aTHX_ "No next::method '%" SVf "' found for %" HEKf,
                         SVfARG(newSVpvn_flags(subname, subname_len,
                                SVs_TEMP | ( subname_utf8 ? SVf_UTF8 : 0 ) )),
                        HEKfARG( HvNAME_HEK(selfstash) ));
    XSRETURN_EMPTY;

BOOT:
    mro_register(&dfs_alg);
