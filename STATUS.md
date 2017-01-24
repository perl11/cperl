# cperl status

[![Build Status](https://travis-ci.org/perl11/cperl.svg?branch=master)](https://travis-ci.org/perl11/cperl) [![Coverity Status](https://scan.coverity.com/projects/6933/badge.svg)](https://scan.coverity.com/projects/perl11-cperl) [perl11.org/cperl/STATUS.html](perl11.org/cperl/STATUS.html)

The name **cperl** stands for **a perl with classes, types, compiler
support, continuation of perl5 development or just a company-friendly
perl**.

cperl started Feb. 2015 when `:const` was added, parrot was killed and
it became clear that optimizing for fun is better than waiting for
someone else to allow it.

Currently it is about 20% faster than perl5 overall, >2x faster
then 5.14 and uses the least amount of memory measured since 5.6,
i.e. less than 5.10 and 5.6.2, which were the previous leaders. While
perl5.22 uses the most memory yet measured. cperl 5.24 is about 2x faster
than 5.22. Function calls with signatures are 2x faster, normal functions with a
`my(..) = @_;` prolog are automatically promoted to signatures.

But not all of the wanted features are merged.  The plan is to support
most perl5-compatible perl6 features (*"do not break CPAN"*), improve
performance and memory usage, re-establish compiler (`B::C`) support,
re-establish perl5 core development which essentially stopped 2002,
use perl6-like development policies, and better security fixes and
maintenance than the upstream p5p perl5. See [README.cperl](perlcperl.html).

There's no class keyword yet as this needs proper field and method
handling, multi-dispatch, aggregate type handling and class
finalization, which is not yet finished. But classes are user-facing
types, and type-support is builtin.

Tested and developed on linux and darwin 64bit. darwin 32bit fails
on two unrelated core tests (issignaling setpayloadsig + chmod linked in).
Windows is smoked with MSVC 10 and 12 for 32 and 64bit.

The current stable release is
  [5.24.2c](https://github.com/perl11/cperl/releases/tag/cperl-5.24.2) - [perl5242cdelta](perl5242cdelta.html),
the latest development release [5.25.2c](https://github.com/perl11/cperl/releases/tag/cperl-5.25.2) - [perl5252cdelta](perl5252cdelta.html).
We also have [5.22.4c](https://github.com/perl11/cperl/releases/tag/cperl-5.22.4), [perl5224cdelta](perl5224cdelta.html).

All tests pass. CPAN works.
Some fixes in my `rurban/distroprefs` repo for certain CPAN modules are needed.

Since 5.24.1c with some modernized core modules some signatures are
pretty strictly typed to catch wrong usages and enforce better code.
See the `Test::More::skip()` [FAQ](https://github.com/perl11/cperl/issues/153#issuecomment-224515895) or below.
Patches are needed for `Module::Build`, `IO::Socket::SSL` and `Net::SSLeay`.
`bigint`, `bignum` and `bigrat` are now also stricly typed, you shouldn't mess with
sloppy types there neither. See below for *Known Problems*.

This is still much less than with a typical major perl5 release, and
the patches are all provided in my
[rurban/distroprefs](https://github.com/rurban/distroprefs/), so the
upgrade is seemless.  E.g. Test2 (the new Test::Simple) broke >15
modules without any patches.

v5.24.0c, v5.24.1c and v5.24.2c have [about 24 fixes](perldelta.html#Known-Problems-fixed-elsewhere), for problems which are not fixed in perl-5.24.1.
Ditto cperl-5.22.4c has about 20 fixes which are not in the latest perl-5.22.3.

![Memory usage: perl -e0](cperl-m0.png)

![Memory usage: with Config_heavy](cperl-p0.png)

![Memory usage with unicode s///i](cperl-p1.png)

![Benchmarks](cperl-bench.png)
For all versions see [bench-all/](bench-all/index.html)

# In the stable master branch are the following major features

* coretypes (Int, UInt, Num, Str. lowercase native types accepted)
* types in signatures as designed and also as attribute.
* signatures are 2x faster, not 2x slower as with 5.24 or almost as slow
  as without as with 5.26.
* function return types declarations as attribute
* many more builtin function attributes
* shaped arrays with compile-time checks and optims
* static loop optims, eliminated run-time bounds checks
* fast arithmetic overflow
* convert static method to subs
* Config as XS
* strict, attributes, DynaLoader, XSLoader as builtin packages, rewritten in C.
  Security fixes for DynaLoader.
* changed default hash function to the fastest FNV1A *(as in the stableperl fork)*
* changed the hash collision strategy from randomize to the usual move-to-front
* changed the default hash fill rate from 100% to 90%. It's tunable via ccflags and
  still fast.
* cperl has besides java the only secure hash table implementation of all popular
  dynamic scripting languages or static languages with internal hash table support.
  other secure hash tables are only found in glibc, bsd or unix kernels or various
  public services.
* seperate XS and PP XS calls dynamically with a new enterxssub op
* -DI and -Dk
* add some unicode ops
* improved build system (make -s, faster, CC vs LD confusion)
* hash keys keep the tainted info. see [perlsec](http://perldoc.perl.org/perlsec.html#Taint-mode)
  There are no known taint loopholes anymore.
* fixes ops and modules using lexical `$_`. The lexical topic feature is supported.
* fixed the encoding pragma, it is undeprecated.
* readonly packages can be cloned with threads.
* security and overlarge data fixes for Storable, YAML not yet.
* include B-C, Cpanel::JSON::XS, YAML::XS, Devel::NYTProf, Term::ReadKey
* improved redefined warnings.
* cperl specific toolchain modules, with support for cperl-only module.
  versions with a 'c' suffix, and 10x faster JSON and YAML usage. (esp. with cpan).
* many typed and modernized core modules, where signatures and types make
  sense and cause not much trouble.
* many security fixes for Unicode symbols. no mixed scripts, normalized, no \0.
* handle method calls on protected stashes.
* disallow silent overflows of hash and array indices or string/name lengths.
  New "Too many elements" error and many new "overlarge" or "too large" panics.
* harmonize overlarge (>2GB) data, max. I64/I32 string and array lengths,
  and U32 hash keys. You can properly access all elements, unlike with perl5.
  Do not silently wrap around indices or counts, do not silently truncate
  overlarge data as in perl5 upstream.
* special handling for security warnings: protect against hash flood DoS. Warn on
  all known public attacks, as metasploit bind/reverse shells or the Storable attack
  with the new `warn_security` API.
  Since v5.25.1c such security warnings are logged at STDERR/syslog with the
  remote user/IP.
* Support clang LTO "link time optimizations", using proper linkage attributes.
  -fsanitize=cfi instead of -fstack-protector not yet.
* Reproducible builds are default since v5.25.2c
* Unicode *Moderately Restrictive Level* security profile for identifiers.
  cperl is the only known unicode-enabled language following any
  recommended security practice. python 3 does normalization but not any
  restriction level. perl5+6, ruby, php, javascript, java, c#, python, julia,
  haskell, lua, swift ... allow all insecure confusable characters and arbitrary
  mixed scripts in identifiers.
* undeprecate qw-as-parens with for. 'for qw(a b c) { print }' works again.
* constant fold unpack in scalar context
* range works with unicode characters
* UNITCHECK global phase introspection

Most of them only would have a chance to be merged upstream if a p5p
committer would have written it.

But some features revert decisions p5p already made. See
[README.cperl](perlcperl.html).  When in doubt I went with the
decisions and policies perl5 made before 2001, before p5p went
downwards. It is very unlikely that p5p will revert their own design
mistakes. It never happened so far.

# Installation

## From source

Download the latest .tar.gz or .tar.bz2 from [github.com/perl11/cperl/releases/](https://github.com/perl11/cperl/releases/)

    tar xfz cperl-5.VER
    cd cperl-5.VER
    ./Configure -sde
    make -s -j4 test
    sudo make install

## rpm

add this file to `/etc/yum.repos.d/perl11.repo`, with either `el6` or `el7`.
`el6` for Centos6 and older Fedora and RHEL, `el7` for Centos7 and newer variants.

    [perl11]
    name=perl11
    baseurl=http://perl11.org/rpm/el7/$basearch
    enabled=1
    gpgkey==http://perl11.org/rpm/RPM-GPG-KEY-rurban
    gpgcheck=1

run as root: `yum update; yum install cperl`

## debian

add this file to `/etc/apt/sources.list.d/perl11.list`

    deb http://perl11.org/deb/ sid main

run as root:

    apt update
    wget http://perl11.org/deb/rurban.gpg.key
    apt-key add rurban.gpg.key
    apt install cperl

## osx

download the pkg installer from [http://perl11.org/osx/](http://perl11.org/osx/)

## windows

download the self-extracting zip from [http://perl11.org/win/](http://perl11.org/win/)
and install it into drive and directory `C:\cperl`.


# Known bugs

See the github issues: [github.com/perl11/cperl/issues](https://github.com/perl11/cperl/issues)

The perl debugger is unstable with signatures and tailcalls (AUTOLOAD).

The following CPAN modules have no patches for 5.24.0c yet:

* autovivification (mderef rpeep changes)
* TryCatch
* Catalyst::Runtime

Time::Tiny, Date::Tiny, DateTime::Tiny feature DateTime::locale broken since 5.22.
unrelated to cperl, -f force install.

# FAQ

## Test::More::skip errors

**skip** has the historical problem of mixed up arguments of `$why`
and `$count`, so those arguments are now stricter typed to catch all
wrong arguments. At compile-time.

When you use one or two args for `Test::More::skip()`, they need to
properly typed.

I.e.

**Mandatory:**

    skip $why, 1               => skip "$why", 1

    plan tests => 1;
    SKIP: { skip }             => SKIP: { skip "", 1; }

**Recommended:**

    skip "why", scalar(@skips) => skip "why", int(@skips)

    skip "why", 2*$skips       => skip "why", int(2*$skips)

**Rationale**:

`skip()` is a special case that the two args are very often mixed
up. This error had previously to be detected at run-time with a
fragile \d regex check. And in most cases this problem was never
fixed, e.g. in `Module::Build`.

Only with checking for strict types I could detect and fix all of the
wrong usages, get rid of the unneeded run-time check, the code is
better, all errors are detected at compile time, and not covered at
run-time and with the new strict types the code is much more readable,
what is the `str $why` and what the `UInt $count` argument.

**When the `$count` can be optional**

The Test::More docs state the following:
*It's important that $how_many accurately reflects the number of tests
in the SKIP block so the # of tests run will match up with your plan.
If your plan is no_plan $how_many is optional and will default to 1.*

I.e. Only with plan tests => 'no_plan' a bare skip is allowed.

`$count` can never be a NV, thus `:Numeric` (which would allow
`2*$skip`) is wrong. It needs to be `:UInt`. The used range op
(`pp_flip`) would die at run-time with a overflowed number. `die
"Range iterator outside integer range"`. `$count := -1` will lead to
test timeouts.

Note that cperl doesn't yet check `UInt` types at run-time for
negative values. This might change in later versions with the `use
types` pragma.  For now the `$count` type is relaxed to `:Numeric` to
permit simple arithmetic.

`scalar(@array)` for array or hash length is also bad code, it needs
to be replaced with `int(@array)`.  Such a length can never be a NV or
PV, it is always a UInt. Using `int()` is clearer and better, at least
for cperl.

This is also the answer to the question why `scalar(@array)` is
considered bad, and why counts and lengths cannot overflow.

# Branch overview

## Older bugfixes for perl5 upstream

* [merge-upstream](http://github.com/perl11/cperl/commits/merge-upstream)

This could have been easily taken up upstream, was already perlbug'ed and
published, and did not violate any of the p5p commit policies and
previous decisions.  From those 47 patches 2 were taken, some
were rejected and 2 were butchered, i.e. rewritten in a worse way.

## Almost ready branches, only minor tests are failing

Those branches could have theoretically been merged upstream, but the chances
are limited. So they are based on master.

* [bugfix/gh8-cowrefcnt](https://github.com/perl11/cperl/issues/8)

  [code](http://github.com/perl11/cperl/commits/bugfix/gh8-cowrefcnt)

  works for the compiler, but does not do COW yet, i.e. slower for
  uncompiled perls, faster for compiled.

* [feature/CM-367-cperl-warnings-xs-carp](http://github.com/perl11/cperl/commits/feature/CM-367-cperl-warnings-xs-carp)
* [feature/CM-367-cperl-carp-builtin](http://github.com/perl11/cperl/commits/feature/CM-367-cperl-carp-builtin)
* [feature/gh9-warnings-xs](https://github.com/perl11/cperl/issues/9)

  [code](http://github.com/perl11/cperl/commits/feature/gh9-warnings-xs)

  much faster and much less memory, but 3 minor scope test fails.

* [feature/gh6-no-miniperl](https://github.com/perl11/cperl/issues/6)

  [code](http://github.com/perl11/cperl/commits/feature/gh6-no-miniperl)

  Need to fix some Makefile deps and break cross-references

* [feature/CM-626-cperl-use-dots](http://github.com/perl11/cperl/commits/feature/CM-626-cperl-use-dots)

  works, but unsure if good enough. `.` instead of `->` works only for
  a few method calls and clashes with string concat. A disruptive
  design decision, which probably cannot be backported. Chip has a
  perl6-like patch which changes `.` to `~` for string concat also,
  but this doesn't accept valid perl5 syntax then. A blocker.

* [feature/gh102-smallhash](https://github.com/perl11/cperl/issues/102)

  [code](http://github.com/perl11/cperl/commits/feature/gh102-smallhash)

  optimize the speed for small hashes.

* [feature/gh176-unexec](https://github.com/perl11/cperl/issues/176)

  [code](http://github.com/perl11/cperl/commits/feature/gh176-unexec)

  compile/dump to native code via emacs unexec, on most platforms.

* [feature/gh141-smallstring](https://github.com/perl11/cperl/issues/141)

  [code](http://github.com/perl11/cperl/commits/feature/gh141-smallstring)

  optimize space for small strings.

and various [hash tables refactorings]((https://github.com/perl11/cperl/issues/24):

feature/gh24-base-hash feature/gh24-he-array feature/gh24-oldnew-hash-table
featurex/gh24-array_he featurex/gh24-hash-loop featurex/gh24-hash-loop+utf8
featurex/gh24-hash-utf8

## A bit more work is needed for

These are major new features, and have no chance to be merged upstream.
They also revert some wrong decisions p5p already made.

* [feature/gh14-native-types](https://github.com/perl11/cperl/issues/14)

  [code](http://github.com/perl11/cperl/commits/feature/gh14-native-types)

  int, uint, num, str. unboxed data on the stack and pads. some minor
  compiler fixes needed, esp. for typed pads. boxed or unboxed, that's
  the question.

* [feature/gh23-inline-subs](https://github.com/perl11/cperl/issues/23)

  [code](http://github.com/perl11/cperl/commits/feature/gh23-inline-subs)

  some compiler fixes needed

* [feature/CM-712-cperl-types-proto](http://github.com/perl11/cperl/commits/feature/CM-712-cperl-types-proto)

  constant fold everything, not only with empty `()` protos

* [feature/gh24-new-hash-table](https://github.com/perl11/cperl/issues/24)

  [code](http://github.com/perl11/cperl/commits/feature/gh24-new-hash-table)

  lots of small attempts, but still too hairy. needs a complete hash table rewrite.

* [feature/gh16-multi](https://github.com/perl11/cperl/issues/16)

  [code](http://github.com/perl11/cperl/commits/feature/gh16-multi)

  class, method and multi keywords but no dispatch, subtyping and type checks yet.
  in work.

* various more hash tables:

[featurex/gh24-one-word-ahe](http://github.com/perl11/cperl/commits/featurex/gh24-one-word-ahe)
[featurex/gh24-open-hash](http://github.com/perl11/cperl/commits/featurex/gh24-open-hash)

## Soon

* user facing classes, multiple dispatch (fast for binary, slow for mega)

* builtin macros

* builtin ffi

2016-12-16 rurban
