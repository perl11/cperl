/* vim: ts=8 sw=4 expandtab:
 * ************************************************************************
 * This file is part of the Devel::NYTProf package.
 * Copyright 2008 Adam J. Kaplan, The New York Times Company.
 * Copyright 2008 Tim Bunce, Ireland.
 * Released under the same terms as Perl 5.8
 * See http://metacpan.org/release/Devel-NYTProf/
 *
 * Contributors:
 * Adam Kaplan, akaplan at nytimes.com
 * Tim Bunce, http://www.tim.bunce.name and http://blog.timbunce.org
 * Steve Peters, steve at fisharerojo.org
 * Forked version by Reini Urban for cperl core
 *
 * ************************************************************************
 */

/* cperl optims */
#ifndef strEQc
#define strEQc(s,c) memEQ(s, ("" c ""), sizeof(c))
#define strNEc(s,c) memNE(s, ("" c ""), sizeof(c))
#define memNEc(s,c) memNE(s, ("" c ""), sizeof(c)-1)
#endif
