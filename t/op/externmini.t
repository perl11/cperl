#!./perl -w
# test compile-time parsing, attribute handling of the core ffi.
# and check that without useffi/DynaLoader run-time calls error and return undef.

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

skip_all "only miniperl" unless is_miniperl();
use Config;
plan(tests => 16);

extern sub ffilabs() :symbol("labs");
extern sub xlabs(int $i) :int :symbol("abs");
# different code-path than extern above. was broken
sub llabs() :native :symbol("labs") :int;
sub xabs(int $i) :native :int;

# compile-time sig arity and type checking
is (eval 'xabs("0")', undef, "wrong call returns undef");
like ($@, qr/Type of arg \$i to xabs must be int \(not Str\)/, 'compile-time type check');
is (eval 'xabs();', undef, "wrong call returns undef");
like ($@, qr/Not enough arguments for extern call xabs. Missing \$i/, 'compile-time arity check');
is (eval 'xabs(0,1,2);', undef, "wrong call returns undef");
like ($@, qr/Too many arguments for extern call xabs exceeding max 1 args/, 'compile-time arity check');
$@ = '';

check_xlabs('extern sub xlabs(int $i) :int :symbol("abs")');

# non coretype, see F<lib/ffi.t> for all types
BEGIN { %long::; }
extern sub labs(long $i) :long;
check_labs("extern labs :long");
undef %long::;

SKIP: {
    skip 'variable native($c) with threads', 2 if $Config{usethreads};
    eval q|
      my $c="c"; sub labs(long $i) :native($c) :long;
    |;
    check_labs("labs :native(\$name)");
}

check_labs_fields("extern sub labs();");  # :void
check_labs_fields("extern sub labs() :int;");
check_labs_fields("sub labs() :native;"); # :void
check_labs_fields("sub labs() :native :int;");

sub check_labs_fields { # 1
  my $decl = shift;
  eval $decl;
  ok(!$@, $decl);
  undef *labs;
}

sub check_labs { # 2
  my $msg = shift;
  my $res;
  eval { $res = labs(-1); };
  is ($res, undef, $msg);
  like ($@, qr/Null extern sub symbol/, 'Null');
  undef *labs;
}
sub check_xabs { # 1
  my $msg = shift;
  eval { $res = xabs(-1); };
  is ($res, undef, $msg);
  like ($@, qr/Null extern sub symbol/, 'Null');
  undef *xabs;
  $@ = '';
}
sub check_xlabs { # 1
  my $msg = shift;
  eval { $res = xlabs(-1); };
  is ($res, undef, $msg);
  like ($@, qr/Null extern sub symbol/, 'Null');
  undef *xabs;
  $@ = '';
}
