/* -*- dtrace-script -*-
 * Written by Alan Burlinson -- taken from his blog post
 * at C<http://bleaklow.com/2005/09/09/dtrace_and_perl.html>,
 * archived at L<https://web.archive.org/web/20130513220122/http://bleaklow.com/2005/09/09/dtrace_and_perl.html>
 * with the perl5 patch at L<http://rich.phekda.org/perl-dtrace/perl-5.8.8-dtrace-20070720.patch>
 */

provider perl {
    probe sub__entry(const char *, const char *, int, const char *);
    probe sub__return(const char *, const char *, int, const char *);

    probe phase__change(const char *, const char *);

    probe op__entry(const char *);

    probe load__entry(const char *);
    probe load__return(const char *);

    /* int mode: gv_init/gv_add/gv_fetch/gv_fetchmethod */
    probe glob__entry(int, const char *);
    probe glob__return(int, const char *);

    /* int mode: fetch/store/exists/delete */
    probe hash__entry(int, const char *);
    probe hash__return(int, const char *);
};

/*
 * ex: set ts=8 sts=4 sw=4 et:
 */
