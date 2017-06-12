#!./perl -w
# test parsing, attribute handling of the core ffi.
# partially even calling it, but most of the functionality
# is tested in F<lib/ffi.t>.

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}

skip_all_if_miniperl;
use Config;
use B ();
skip_all "no ffilib" unless $Config{useffi};
plan(tests => 40);

no warnings 'redefine';

sub has_sym { # 2
  my $cv = B::svref_2object(shift);
  my $flags = $cv->CvFLAGS;
  ok (($flags & B::CVf_EXTERN) && ($flags & B::CVf_ISXSUB),
      "CVf_EXTERN|CVf_ISXSUB $flags");
  ok ($cv->XFFI && $cv->FFILIB, "has CvXFFI sym ".$cv->XFFI.
                                " and CvFFLIB cif ".$cv->FFILIB);
}

sub check_labs_fields { # 3
  my $decl = shift;
  note $decl;
  eval $decl;
  ok(!$@, "no errors $@");
  has_sym(\&labs);
  undef *labs;
}

sub check_labs { # 4
  my $msg = shift;
  ok(!$@, "no errors $@");
  has_sym(\&labs);
  is(labs(-1), 1, $msg);
  undef *labs;
}

# first check ffi fields without calling the ffi (wrong sig or rettype)
# This part should be doable with miniperl also.
check_labs_fields("extern sub labs();");  # :void
check_labs_fields("extern sub labs() :int;");
check_labs_fields("sub labs() :native;"); # :void
check_labs_fields("sub labs() :native :int;");

eval 'extern sub ffilabs() :symbol("labs");';
has_sym(\&ffilabs); undef *ffilabs;
undef *ffilabs;

eval 'extern sub llabs() :symbol("labs");';
has_sym(\&llabs);

# equivalence of XFFI syms
eval 'extern sub labs(int $i) :int;';
my $ori  = B::svref_2object(\&labs);
my $xsym = B::svref_2object(\&llabs);
ok ((ref $ori->XFFI eq ref $xsym->XFFI) &&
    (${$ori->XFFI} == ${$xsym->XFFI}), "same CvXFFI sym") # 17
  or note $ori->XFFI, $xsym->XFFI;
undef *llabs;

# different code-path than extern above. was broken
eval 'sub llabs() :native :symbol("labs");';
has_sym(\&llabs);

# equivalence of XFFI syms
$xsym = B::svref_2object(\&llabs);
ok ((ref $ori->XFFI eq ref $xsym->XFFI) &&
    (${$ori->XFFI} == ${$xsym->XFFI}), "same CvXFFI sym") # 17
  or note $ori->XFFI, $xsym->XFFI;
undef *llabs;

# now call it with valid sigs and types
check_labs("extern labs");

eval 'sub labs(int $i) :native :int;';
check_labs("labs :native");

# non coretype, see <lib/ffi.t> for all types
BEGIN { %long::; }
eval 'extern sub labs(int $i) :long;';
check_labs("extern abs :long");
undef %long::;

eval 'sub labs(int $i) :native("c") :int;';
check_labs("labs :native('c')");

eval '$c="c"; sub labs(int $i) :native($c) :int;';
check_labs("labs :native(\$name)");

