/* -*- dtrace-script -*- */
/* require and do perl files */
#pragma D option quiet

load-entry, load-return
{
    printf("%s file <%s>\n", probename == "load-entry" ? "->" : "<-",
           copyinstr(arg0));
}
