#!./perl -w
# test parsing, attribute handling of the core ffi.
# just without calling it.

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

use Config;
skip_all "no ffilib" if !$Config{useffi};
plan(tests => 8);

no warnings 'redefine';

sub check_labs_fields { # 3
  my $decl = shift;
  note $decl;
  eval $decl;
  ok(!$@, "no errors $@");
  undef *labs;
}

sub check_labs { # 4
  my $msg = shift;
  ok(!$@, "no errors $@");
  undef *labs;
}
sub check_abs { # 4
  my $msg = shift;
  ok(!$@, "no errors $@");
  undef *abs;
}

# first check ffi fields without calling the ffi (wrong sig or rettype)
# This part should be doable with miniperl also.
check_labs_fields("extern sub labs();");  # :void
check_labs_fields("extern sub labs() :int;");
check_labs_fields("sub labs() :native;"); # :void
check_labs_fields("sub labs() :native :int;");

extern sub ffilabs() :symbol("labs");
note 'extern sub ffilabs() :symbol("labs");';

extern sub labs() :int :symbol("abs");
note 'extern sub labs() :int :symbol("abs");';

# different code-path than extern above. was broken
sub llabs() :native :symbol("labs") :int;
note 'sub llabs() :native :symbol("labs") :int;';

sub abs(int $i) :native :int;
check_abs("abs :native");

# TODO: compile-time sig arity and type checking
eval { abs("0"); };
like ($@, qr/wrong type/);
eval { abs(); };
like ($@, qr/missing arg/);

# non coretype, see F<lib/ffi.t> for all types
BEGIN { %long::; }
extern sub labs(long $i) :long;
check_labs("extern labs :long");
undef %long::;

sub abs(int $i) :native("c") :int;
check_abs("abs :native('c')");

$c="c"; sub abs(int $i) :native($c) :int;
check_abs("abs :native(\$name)");
