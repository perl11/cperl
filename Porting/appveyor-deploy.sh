#!/bin/bash

set -x

# do reproducible cygwin or mingw builds.
# msvc is done in t/appveyor-smoke.bat
# C:\projects\cperl
test -n $APPVEYOR_BUILD_FOLDER && cd $APPVEYOR_BUILD_FOLDER
builddate=`perl -ne'/^cf_time=.(.*).$/ and print $1' config.sh`
ver=$(perl Porting/perl_version)
if [ x$CYGWIN = x1 ]; then
    make=make
    destdir=/cygdrive/c/cperl
    projdir=/cygdrive/c/projects/cperl
    taggedtar=${APPVEYOR_REPO_TAG_NAME}-cygwin-${PLATFORM}.tar.xz
    nightlytar=cperl-${APPVEYOR_BUILD_VERSION}-cygwin-${PLATFORM}.tar.xz
    find=find
else
    make="gmake -C win32"
    destdir=/c/cperl
    projdir=/c/projects/cperl
    taggedtar=${APPVEYOR_REPO_TAG_NAME}-mingw-${PLATFORM}.tar.xz
    nightlytar=cperl-${APPVEYOR_BUILD_VERSION}-mingw-${PLATFORM}.tar.xz
    #find=/c/cygwin/bin/find
    find=/c/MinGW/msys/1.0/bin/find
fi
# nightly or tagged release?
if [ x$APPVEYOR_REPO_TAG_NAME = x ]; then
    # from /c/cperl to /c/Projects/cperl
    # cannot use absolute c:\cperl\bla -> Cannot connect to C: resolve failed
    tar=$projdir/$nightlytar
else
    tar=$projdir/$taggedtar
fi

export PERL_HASH_SEED=0
$make -s install DESTDIR=$destdir || exit

touch $destdir/lib/cperl/site_cperl/$ver/.empty
for d in `$find $destdir -type d -empty`; do touch "$d"/.empty; done

# mingw tar cannot do --no-dereference
$find $destdir -depth -newermt "$builddate" -print0 | \
    xargs -0r touch --date="$builddate"

cd $destdir
rm -f $tar
tar Jcf $tar *
# TODO
#sha1sum $tar
