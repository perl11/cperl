# irix_6.sh
# from Krishna Sethuraman, krishna@mit.edu
# Date: Wed Jan 18 11:40:08 EST 1995
# added `-32' to force compilation in 32-bit mode.
# otherwise, copied from irix_5.sh.

# Perl built with this hints file under IRIX 6.0.1 passes 
# all tests (`make test').

ld=ld
i_time='define'
cc="cc -32"
ccflags="$ccflags -D_POSIX_SOURCE -ansiposix -D_BSD_TYPES -Olimit 3000"
lddlflags="-32 -shared"
set `echo X "$libswanted "|sed -e 's/ socket / /' -e 's/ nsl / /' -e 's/ dl / /'`
shift
libswanted="$*"
#
# The following might be of interest if you wish to try 64-bit mode:
# irix_6_64bit.sh
# Krishna Sethuraman, krishna@mit.edu
# taken from irix_5.sh .  Changes from irix_5.sh:
# Olimit and nested comments (warning 1009) no longer accepted
# -OPT:fold_arith_limit so POSIX module will optimize
# no 64bit versions of sun, crypt, nsl, socket, dl dso's available
# as of IRIX 6.0.1 so omit those from libswanted line via `sed'.

# perl 5 built with this hints file passes most tests (`make test').
# Fails on op/subst test only. (built and tested under IRIX 6.0.1).

# i_time='define'
# ccflags="$ccflags -D_POSIX_SOURCE -ansiposix -D_BSD_TYPES -woff 1009 -OPT:fold_arith_limit=1046"
# lddlflags="-shared"
# set `echo X "$libswanted "|sed -e 's/ socket / /' -e 's/ sun / /' -e 's/ crypt / /' -e 's/ nsl / /' -e 's/ dl / /'`
# shift
# libswanted="$*"
