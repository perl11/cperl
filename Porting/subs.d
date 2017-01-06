/* -*- dtrace-script -*- */

#pragma D option quiet

sub-entry, sub-return
{
    /*
     * Borrowed and modified from the Python DTrace example
     * at <http://blogs.sun.com/levon/entry/python_and_dtrace_in_build>
     */
    printf("%s %s::%s (%s:%d)\n", probename == "sub-entry" ? "->" : "<-",
           copyinstr(arg3), copyinstr(arg0), copyinstr(arg1), arg2);
}
