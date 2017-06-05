#!./perl -w

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

skip_all_if_miniperl;
no warnings 'redefine';
use Config;
skip_all "no ffilib" unless $Config{useffi};
plan(tests => 3);

eval 'extern sub labs(int $i) :int;';
is(1, labs(-1), "extern labs");

eval '
undef \&labs;
sub labs(int $i) :native :int;
';
is(1, labs(-1), "labs :native");

eval '
undef \&labs;
%long::;
extern sub labs(int $i) :long;
';
is(1, labs(-1), "extern abs :long");
undef %long::;
