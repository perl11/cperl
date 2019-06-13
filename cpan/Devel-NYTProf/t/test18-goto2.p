# Test Carp::Heavy's "swap subs out from under you with goto &sub"

use lib 't';

package Test18;

sub longmess  { goto &longmess_jmp }

sub longmess_jmp  {
    # the required file deletes this longmess_jmp sub, while it's executing,
    # and replaces it with longmess_real, which we then goto into!
    require 'test18-goto2.pm'; # has to be require, not eval '...'
    goto &longmess_real;
}

longmess("Oops");
