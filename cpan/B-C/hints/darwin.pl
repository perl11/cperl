# gcc -O3 (and -O2) get overly excited over B.c in MacOS X 10.1.4.
$self->{OPTIMIZE} = '-O1' if `/usr/bin/uname -v` =~ /10.1.4/;
