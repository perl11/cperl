#!./perl -w
# test parsing, attribute handling of the core ffi.
# partially even calling it, but most of the functionality
# is tested in F<lib/ffi.t>.

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
    skip_all_if_miniperl();
}

use Config;
use B ();
skip_all "no ffilib" if !$Config{useffi};
plan(tests => 41);

no warnings 'redefine';

sub has_sym { # 2
  my $cv = B::svref_2object(shift);
  my $flags = $cv->CvFLAGS;
  ok (($flags & B::CVf_EXTERN) && ($flags & B::CVf_ISXSUB),
      "CVf_EXTERN|CVf_ISXSUB ".sprintf("%x", $flags));
  ok ($cv->XFFI && $cv->FFILIB, "has CvXFFI sym ".$cv->XFFI.
                                " and CvFFLIB cif ".$cv->FFILIB);
}

sub check_labs_fields { # 3
  my $decl = shift;
  eval $decl;
  ok(!$@, "no errors $decl");
  has_sym(\&labs);
  undef *labs;
}

sub check_labs { # 4
  my $msg = shift;
  ok(!$@, "no errors $@");
  has_sym(\&labs);
  is(labs(-1), 1, $msg);
}
sub check_abs { # 4
  my $msg = shift;
  ok(!$@, "no errors $@");
  has_sym(\&abs);
  is(abs(-1), 1, $msg);
}

extern sub ffilabs() :symbol("labs");
has_sym(\&ffilabs);

eval 'extern sub labs() :int :symbol("abs");';
note 'extern sub labs() :int :symbol("abs");';
# CvFFILIB handle mixup. both do exist. labs is already defined here, with
# its CvFFILIB pointing to its ffi_cif.
has_sym(\&labs);

# different code-path than extern above. was broken
sub llabs() :native :symbol("labs") :int;
has_sym(\&llabs); # possible name mixup. both do exist

sub abs(int $i) :native :int;
check_abs("abs :native");

# non coretype, see F<lib/ffi.t> for all types
BEGIN { %long::; %ulong::; }
extern sub labs(long $i) :ulong;
check_labs("extern labs :ulong");
undef *ulong;
undef *long;

# equivalence of XFFI syms: abs
TODO: {
    local $TODO = "Windows abs vs :symbol(abs)" if $^O =~ /^(MSWin32|msys)/;

    extern sub abs(int $i) :int;
    #note 'extern sub abs(int $i) :int;';
    my $ori  = B::svref_2object(\&abs);
    my $xsym = B::svref_2object(\&labs);
    ok ((ref $ori->XFFI eq ref $xsym->XFFI) &&
        (${$ori->XFFI} == ${$xsym->XFFI}), "same CvXFFI sym") # 19
      or note $ori->XFFI, $xsym->XFFI;
    undef *labs;

    # equivalence of XFFI syms: labs
    $ori  = B::svref_2object(\&ffilabs);
    $xsym = B::svref_2object(\&llabs);
    ok ((ref $ori->XFFI eq ref $xsym->XFFI) &&
        (${$ori->XFFI} == ${$xsym->XFFI}), "same CvXFFI sym") # 20
      or note $ori->XFFI, $xsym->XFFI;
    undef *llabs;
}

# now call it with valid sigs and types
check_abs("extern labs");

eval 'sub abs(int $i) :native("c") :int;';
check_abs("abs :native('c')");

SKIP: {
    skip 'variable native($c) with threads', 4 if $Config{usethreads};
    my $c="c"; sub abs(int $i) :native($c) :int;
    check_abs("abs :native(\$name)");
}

extern sub strchr(str $s, int $i) :str;
is(strchr("abcd", ord("c")), "cd", "strchr");

# check ffi fields without calling the ffi (wrong sig or rettype)
# These destroy labs() so do it at last
check_labs_fields("extern sub labs();");  # :void
check_labs_fields("extern sub labs() :int;");
check_labs_fields("sub labs() :native;"); # :void
check_labs_fields("sub labs() :native :int;");
