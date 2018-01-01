# cperl status

[![Build Status](https://travis-ci.org/perl11/cperl.svg?branch=master)](https://travis-ci.org/perl11/cperl) [![Coverity Status](https://scan.coverity.com/projects/6933/badge.svg)](https://scan.coverity.com/projects/perl11-cperl) [perl11.org/cperl/STATUS.html](perl11.org/cperl/STATUS.html) [![Donate](https://liberapay.com/assets/widgets/donate.svg)](https://liberapay.com/rurban/donate) [![Average time to resolve an issue](http://isitmaintained.com/badge/resolution/perl11/cperl.svg)](http://isitmaintained.com/project/perl11/cperl "Average time to resolve an issue") [![Percentage of issues still open](http://isitmaintained.com/badge/open/perl11/cperl.svg)](http://isitmaintained.com/project/perl11/cperl "Percentage of issues still open")

The name **cperl** stands for **a perl with classes, types, compiler
support, continuation of perl5 development** or just a **company-friendly
perl**.

cperl started Feb. 2015 when `:const` was added, parrot was killed and
it became clear that optimizing for fun is better than waiting for
someone else to allow it, and the ongoing destruction has to be
stopped, even if it will cause a massive blame game.

Currently it is about 20% faster than perl5 overall, >2x faster then
5.14 and uses the least amount of memory measured since 5.6, i.e. less
than 5.10 and 5.6.2, which were the previous leaders. While perl5.22
uses the most memory yet measured. cperl 5.24 and 5.26 is about 2x
faster than 5.22 in bigger real-world applications. Esp. function
calls with signatures are 2x faster, normal functions with a `my(..) =
@_;` prolog are automatically promoted to signatures.

But only a small number of needed features are yet merged.  The plan
was to support most perl5-compatible perl6 features (*"do not break
CPAN"*), improve performance and memory usage, re-establish compiler
(`B::C`) support, re-establish perl5 core development which
essentially stopped 2002, use perl6-like development policies, better
security fixes and maintenance than the upstream p5p perl5, and stop
the ongoing destruction going on in p5p. See [README.cperl](perlcperl.html).

Almost perl6-like classes, roles, methods, fields. classes are
user-facing types, and support for types, restricted stashes and fast
fields is builtin.

Tested and developed on linux and darwin 64bit. darwin 32bit fails
on two unrelated core tests (issignaling setpayloadsig + chmod linked in).
Windows is smoked with mingw, cygwin and MSVC 10 and 12 for 32 and 64bit.
The BSD's and Solaris are only tested before a release.

The current stable release is

* [5.26.1c](https://github.com/perl11/cperl/releases/tag/cperl-5.26.1) - [perl5261cdelta](perl5261cdelta.html).
  
the latest development release:

* [5.27.2c](https://github.com/perl11/cperl/releases/tag/cperl-5.27.2) - [perl5272cdelta](perl5272cdelta.html).

We also have:

* [5.24.2c](https://github.com/perl11/cperl/releases/tag/cperl-5.24.2) - [perl5242cdelta](perl5242cdelta.html),
* [5.22.5c](https://github.com/perl11/cperl/releases/tag/cperl-5.22.5), [perl5225cdelta](perl5225cdelta.html).

All tests pass. CPAN works.
Some fixes in my `rurban/distroprefs` repo for certain CPAN modules are needed.

v5.24.0c, v5.24.1c and v5.24.2c have
[about 24 fixes](perldelta.html#Known-Problems-fixed-elsewhere),
for problems which are not fixed in perl-5.24.1.  Ditto with 5.26,
cperl-5.22.4c has about 20 fixes which are not in the latest
perl-5.22.3. Similar numbers for v5.27.2c, as p5p is still adding
security and performance problems.
Since cperl development is about 10x faster than p5p
development, and damage done within p5p increases, these numbers do
increase over time.

![Memory usage: perl -e0](cperl-m0.png)

![Memory usage: with Config_heavy](cperl-p0.png)

![Memory usage with unicode s///i](cperl-p1.png)

![Benchmarks](cperl-bench27.png)
For all versions see [bench-all/](bench-all/index.html)

# In the latest stable releases are the following major features:

* coretypes (Int, UInt, Num, Str. lowercase native types accepted)
* types in signatures as designed and also as attribute.
* signatures are 2x faster, not 2x slower as with 5.24 or almost as slow
  as without as with 5.26.
* function return types declarations as attribute
* type-check assignments, since 5.26 also for user-types
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
  Other secure hash tables are only found in glibc, bsd or unix kernels or various
  public services.
* seperate XS and PP XS calls dynamically with a new enterxssub op
* -DI and -Dk
* added many unicode ops
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
* length and ref are optimized in boolean context
* UNITCHECK global phase introspection
* base/fields classes behave now like closed cperl classes: The ISA is readonly,
  inheritance checks are performed at compile-time already.
* Support restricted stashes, i.e. closed classes, esp. method lookup, destruction
  and readonly ISA.
* study with HASH, ARRAY, CODE
* enhanced dtrace probes
* support for long path names, > 4096
* support for unicode BOMs, setting the unicode hints
* Fast and proper object orientation. User facing classes. class, role, method,
  multi, has, is, does keywords, proper fields, Mu superclass.
* thread-safety on darwin for uselocale
* hash slice consistency, no autovivification as sub args

Most of them only would have a chance to be merged upstream if a p5p
committer would have written it.

But some features revert decisions p5p already
made. See [README.cperl](perlcperl.html).  When in doubt I went with
the decisions and policies perl5 made before 2001, before p5p went
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
and install it into `C:\cperl` via the `cperl-5.26.1.3407-win32.exe -InstallPath="C:\\cperl"`
cmdline option, or install the latest msvc `.zip` or mingw `.tar.xz` files.
Preferred is now mingw, which works fine parallel to the current strawberry perl
installation.

# Known bugs

The -d debugger fails on most signatures.

See the github issues: [github.com/perl11/cperl/issues](https://github.com/perl11/cperl/issues?q=is%3Aissue+is%3Aopen+label%3Abug)

The following CPAN modules have no patches for 5.26.1c yet:

* autovivification (mderef rpeep changes)
* TryCatch
* Catalyst::Runtime

Time::Tiny, Date::Tiny, DateTime::Tiny feature DateTime::locale broken
since 5.22.  unrelated to cperl, -f force install.

Many other packages clash with an unneeded mix of Test::More in inc/
or t/.  Some other use wrong undocumented Test-Simple calls, which the
modernized improvement complains about, or use Test2, which is
unsupported and not recommended to use in its current state.
In a Test2 branch is a fixed version which is still 20% slower.

# Known problems

Since 5.24.1c with some modernized core modules some signatures are
pretty strictly typed to catch wrong usages and enforce better code.
See the `Test::More::skip()` [FAQ](https://github.com/perl11/cperl/issues/153#issuecomment-224515895) or below.
Patches are needed for `Module::Build`, `IO::Socket::SSL` and `Net::SSLeay`.

* -d debugging with signatures is mostly broken.
* Stricter Test::More::skip
* Stricter Test::More types and API
* Readonly Config (XSConfig), use Mock::Config instead.
  (*also affects perl5 with the XSConfig module*)
* Readonly use base @ISA
  (*since 5.26.0c*)
* Missing . in @INC
  (*cperl removed . from @INC 2 years ago already, but ran the cpan tests and
  installer with PERL_USE_UNSAFE_INC. This is now a general 5.26 problem.*)
* %hash = map under [use strict](/blog/strict-hashpairs.html) (hashpairs since 5.27.0)

Breakage is much less than with a typical major perl5 release, and the
patches for most common CPAN modules are provided in
my [rurban/distroprefs](https://github.com/rurban/distroprefs/), so
the upgrade is seemless. 
E.g. Test2 (the new Test::Simple) broke >15 modules without any
patches. Test2 is not yet supported, as it is still 20% slower, and
has no significant benefit over the old Test-Simple. And they chose to break
the API and performance, instead of letting users select the new Test2 module.

Beware of modules with `inc/Test`. This is broken. Remove this dir and try
to reinstall again.

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

* [builtin ffi](https://github.com/perl11/cperl/issues/22)
  
  [code](http://github.com/perl11/cperl/commits/smoke/gh22-ffi)
  
  windows: autoinstall of binary libffi missing.
  more convenience methods needed.

* [bugfix/gh311-role-meth](https://github.com/perl11/cperl/issues/311)

  See the relevant #16 subtickets:
  compose role methods, use mro on classes, array and hash field syntax
  ($obj->array[0], $obj->hash{key}), :before, :after, :around method
  composition, class :native,
  multiple dispatch (fast for binary, slow for mega),
  tiny MOP (Mu, Metamodel::ClassHOW).

* [bugfix/gh8-cowrefcnt](https://github.com/perl11/cperl/issues/8)
  
  [code](http://github.com/perl11/cperl/commits/bugfix/gh8-cowrefcnt)
  
  works for the compiler, but does not do COW yet, i.e. slower for
  uncompiled perls, faster for compiled.
  The upstream COW implementation is still a complete mess.

* [feature/CM-367-cperl-warnings-xs-carp](http://github.com/perl11/cperl/commits/feature/CM-367-cperl-warnings-xs-carp)
* [feature/CM-367-cperl-carp-builtin](http://github.com/perl11/cperl/commits/feature/CM-367-cperl-carp-builtin)
* [feature/gh9-warnings-xs](https://github.com/perl11/cperl/issues/9)
  
  [code](http://github.com/perl11/cperl/commits/feature/gh9-warnings-xs)
  
  much faster and much less memory, but 3 minor scope tests fails.

* [feature/gh6-no-miniperl](https://github.com/perl11/cperl/issues/6)
  
  [code](http://github.com/perl11/cperl/commits/feature/gh6-no-miniperl)
  
  Need to fix some Makefile deps and break cross-references.

* [feature/CM-626-cperl-use-dots](http://github.com/perl11/cperl/commits/feature/CM-626-cperl-use-dots)
  
  works, but unsure if good enough. `.` instead of `->` works only for
  a few method calls and clashes with string concat. A disruptive
  design decision, which probably cannot be backported. Chip has a
  perl6-like patch which changes `.` to `~` for string concat also,
  but this doesn't accept valid perl5 syntax then. A blocker.

* [feature/gh102-smallhash](https://github.com/perl11/cperl/issues/102)
  
  [code](http://github.com/perl11/cperl/commits/feature/gh102-smallhash)
  
  optimize the speed for small hashes, less keys, inline 3-7 as array.
  esp. needed for the new objects. redis has a limit of 256 (zipmap)
  favoring linear search over hash lookups. with those we could think
  of using hashes again more often. now they are way too slow for everything.

* [feature/gh176-unexec](https://github.com/perl11/cperl/issues/176)
  
  [code](http://github.com/perl11/cperl/commits/feature/gh176-unexec)
  
  compile/dump to native code via emacs unexec, on most platforms.
  Questionable if to keep our private malloc soon.

* [feature/gh141-smallstring](https://github.com/perl11/cperl/issues/141)
  
  [code](http://github.com/perl11/cperl/commits/feature/gh141-smallstring)
  
  optimize space for small strings.

and various [hash tables refactorings](https://github.com/perl11/cperl/issues/24):

feature/gh24-base-hash feature/gh24-he-array feature/gh24-oldnew-hash-table
featurex/gh24-array_he featurex/gh24-hash-loop featurex/gh24-hash-loop+utf8
featurex/gh24-hash-utf8 featurex/gh24-hopscotch-hash.

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

  some compiler fixes needed.

* [feature/CM-712-cperl-types-proto](http://github.com/perl11/cperl/commits/feature/CM-712-cperl-types-proto)

  constant fold everything, not only with empty `()` protos.

* [feature/gh24-new-hash-table](https://github.com/perl11/cperl/issues/24)

  [code](http://github.com/perl11/cperl/commits/feature/gh24-new-hash-table)

  lots of small attempts, but still too hairy. might need a complete hash table rewrite.
  getting there, but not yet finished for 5.26.

* various more hash tables:

  [featurex/gh24-one-word-ahe](http://github.com/perl11/cperl/commits/featurex/gh24-one-word-ahe), 
  [featurex/gh24-open-hash](http://github.com/perl11/cperl/commits/featurex/gh24-open-hash), 
  [featurex/gh24-hopscotch-hash](http://github.com/perl11/cperl/commits/featurex/gh24-hopscotch-hash)

## Soon

* [the jit](https://github.com/perl11/cperl/issues/220) code: [feature/gh220-llvmjit](http://github.com/perl11/cperl/commits/feature/gh220-llvmjit)

* [builtin macros](https://github.com/perl11/cperl/issues/261)

* linear symbol table (not nested stashes) and optree linearization.

--

2017-12-05 rurban
