#!/bin/bash
# t/testc.sh -c -Du,-q -B static 2>&1 |tee c.log|grep FAIL
# for p in 5.6.2 5.8.8-nt 5.8.9d 5.10.1d 5.10.1d-nt 5.11.2d 5.11.2d-nt; do make -s clean; echo perl$p; perl$p Makefile.PL; t/testc.sh -q -O0 31; done
# quiet c only: t/testc.sh -q -O0
# t/testcc.sh -DOscpSql,-v,-UB::Concise,-UIO::File,-UIO::Handle,-Uwarnings
function help {
  echo "t/testc.sh [OPTIONS] [1-$ntests]"
  echo " -D<debugflags>     for O=C or O=CC. Default: C,-DspmF,-v resp. CC,-DOscpSql,-v"
  echo " -O<0-4>            optimization level"
  echo " -f<opt>            special optimization"
  echo " -B<static|dynamic> pass to cc_harness"
  echo " -c                 continue on errors"
  echo " -k                 keep temp. files on PASS"
  echo " -E                 dump preprocessed source file with cc -E as _E.c"
  echo " -o                 orig. no -Mblib, use installed modules (5.6, 5.8)"
  echo " -a                 all. undo -Du. Unsilence scanning unused sub"
  echo " -A                 -DALLOW_PERL_OPTIONS"
  echo " -L                 make CORE test symlinks and exit"
  echo " -X<num>            view the test"
  echo " -q                 quiet"
  echo " -h                 help"
  echo "Without arguments try all $ntests tests. Without Option -Ox try -O0 to -O3 optimizations."
}

# use the actual perl from the Makefile (perl5.8.8,
# perl5.10.0d-nt, perl5.11.0, ...)
PERL=`grep "^FULLPERL =" Makefile|cut -c12-`
test -z $PERL && PERL=`grep "^PERL =" Makefile|cut -c8-`
PERL=${PERL:-perl}
PERL=`echo $PERL|sed -e's,^",,; s,"$,,'`
v510=`$PERL -e'print (($] < 5.010)?0:1)'`
v518=`$PERL -e'print (($] < 5.018)?0:1)'`
v524=`$PERL -e'print (($] < 5.024)?0:1)'`
#v522=`$PERL -e'print (($] < 5.022)?0:1)'`
PERLV=v5.`$PERL -e'print substr($],3,2)'`
XTESTC="t/CORE/$PERLV/C-COMPILED/xtestc"

function init {
BASE=`basename $0`
# if $] < 5.9 you may want to remove -Mblib for testing the core lib. -o
#Mblib="`$PERL -e'print (($] < 5.009005) ? q() : q(-Mblib))'`"
Mblib=${Mblib:--Iblib/arch -Iblib/lib} # B::C is now fully 5.6+5.8 backwards compatible
test -z $PERL_CORE || Mblib=-I../../lib
v513="`$PERL -e'print (($] < 5.013005) ? q() : q(-fno-fold,-fno-warnings,))'`"
# OCMD=${OCMD}${v513}
if [ -z "$Mblib" ]; then
    VERS="${VERS}_global";
    OCMD="$PERL $Mblib -MO=C,${v513}-Dcsp,"
    if [ $BASE = "testcc.sh" ]; then # DrOsplt
        OCMD="$PERL $Mblib -MO=CC,${v513}-DOsplt,"
    fi
else
    OCMD="$PERL $Mblib -MO=C,${v513}-DspF,-v,"
    if [ $BASE = "testcc.sh" ]; then # DoOscprSql
        OCMD="$PERL $Mblib -MO=CC,${v513}-DOpscpTql,-v,"
    fi
fi
CONT=
# 5.6: rather use -B static
#CCMD="$PERL script/cc_harness -g3"
# rest. -DALLOW_PERL_OPTIONS for -Dtlv
#CCMD="$PERL $Mblib script/cc_harness -g3 -DALLOW_PERL_OPTIONS"
CCMD="$PERL $Mblib script/cc_harness"
test -z $PERL_CORE || CCMD="$CCMD -I../.. -L../.."
LCMD=
# On some perls I also had to add $archlib/DynaLoader/DynaLoader.a to libs in Config.pm
}

function vcmd {
    test -n "$QUIET" || echo $*
    $*
}

function pass {
    echo -e -n "\033[1;32mPASS \033[0;0m"
    echo $*
}
function fail {
    echo -e -n "\033[1;31mFAIL \033[0;0m"
    echo $*
}

function runopt {
    o=$1
    optim=$2
    OCMDO1="$(echo $OCMD|sed -e s/C,/C,-O$optim,/)"
    suff="_o${optim}"
    if [ "$optim" == "0" ]; then suff=""; fi
    rm ${o}${suff} ${o}${suff}.c 2> /dev/null
    if [ $optim -lt 5 ]; then CMD=$OCMDO1
    else CMD=$OCMD
    fi
    if [ "$o" = "ccode46" -o "$o" = "cccode46" ]; then
	CMD="$CMD-fstash,"
    fi
    if [ -z $qq ]; then
	vcmd ${CMD}-o${o}${suff}.c $o.pl 2>&1 | grep -v "$o.pl syntax OK"
    else
	vcmd ${CMD}-o${o}${suff}.c $o.pl
    fi
    test -z $CPP || vcmd $CCMD ${o}${suff}.c -c -E -o ${o}${suff}_E.c
    test -n "$QUIET" || echo ${CMD}-o${o}${suff}.c $o.pl
    vcmd $CCMD ${o}${suff}.c $LCMD -o ${o}${suff}
    test -x ${o}${suff} || (test -z $CONT && exit)
    if [ -z "$QUIET" ]; then echo "./${o}${suff}"
    else echo -n "./${o}${suff} "
    fi
    mem=$(ulimit -m 2>/dev/null)
    err=$?
    test -z $err && ulimit -S -m 50000
    res=$(./${o}${suff}) || fail "./${o}${suff}" "errcode $?"
    test -z $err && ulimit -S -m $mem
    if [ "X${result[$n]}" = "X" ]; then result[$n]='ok'; fi
    if [ "X$res" = "X${result[$n]}" ]; then
	test "X$res" = "X${result[$n]}" && pass "./${o}${suff}" "=> '$res'"
        if [ -z $KEEP ]; then rm ${o}${suff}_E.c ${o}${suff}.c ${o}${suff} 2>/dev/null; fi
        true
    else
	fail "./${o}${suff}" "=> '$str' => '$res'. Expected: '${result[$n]}'"
        false
    fi
}

function emit_test {
  n=$(expr $1 + 0)
  CONTENT="${tests[${n}]}"
  if [ "x$CONTENT" != "x" ]; then
    echo -E "$CONTENT"
    echo
    if [ "x${result[$n]}" = "x" ]; then result[$n]='ok'; fi
    echo -E "### RESULT:${result[$n]}"
  fi
}

function make_t_symlink {
  n=$(expr $1 + 0)
  CONTENT="${tests[${n}]}"
  if [ "x$CONTENT" != "x" ]; then
    FILE_NUM=$(printf "%04d" $n)
    FILE="$XTESTC/${FILE_NUM}.t"
    test -e $FILE && unlink $FILE
    ln -s ../testc.pl $FILE
  fi
}

function make_symlinks {
  MAX=9999
  test -d $XTESTC || mkdir $XTESTC
  rm -f $XTESTC/*.t ||:
  for b in $(seq $MAX); do
    make_t_symlink $b
  done
}

function ctest {
    n=$(expr $1 + 0)
    str=$2

    if [ $BASE = "testcc.sh" ]; then
      o="cccode$n"
    else
      o="ccode$n"
    fi
    if [ -z "$str" ]; then
        if [ "$n" = "08" ]; then n=8; fi
        if [ "$n" = "09" ]; then n=9; fi
	echo "${tests[${n}]}" > ${o}.pl
        str="${tests[${n}]}"
    else
	echo "$str" > ${o}.pl
    fi
    if [ -z "$str" ]; then
      true
    else
      if [ $OPTIM -ge 0 ]; then
	runopt "$o" "$OPTIM"
      else # -1
	rm $o.c $o ${o}_o.c ${o}_o 2> /dev/null
	vcmd ${OCMD}-o$o.c $o.pl
        test -s $o.c || (echo "empty $o.c"; test -z $CONT && exit 2)
	test -z $CPP || vcmd $CCMD $o.c -c -E -o ${o}_E.c
        test -n "$QUIET" || echo ${OCMD}-o$o.c $o.pl
	vcmd $CCMD $o.c $LCMD -o $o
	test -x $o || (test -z $CONT && exit)
	if [ -z "$QUIET" ]; then echo "./$o"
	else echo -n "./$o "
        fi
	res=$(./$o) || (fail "./${o}${suff}" "'$?' = $?"; test -z $CONT && exit 1)
        if [ "X${result[$n]}" = "X" ]; then result[$n]='ok'; fi
	if [ "X$res" = "X${result[$n]}" ]; then
	    pass "./$o" "'$str' => '$res'"
            if [ -z $KEEP ]; then rm ${o}_E.c ${o}.c ${o} 2>/dev/null; fi
	    if [ $BASE = "testcc.sh" ]; then
	      runopt $o 1 && \
	        runopt $o 2
            else
	      runopt $o 1 && \
	        runopt $o 2 && \
	        runopt $o 3 && \
	        true #runopt $o 4
            fi
	    true
	else
	    fail "./$o" "'$str' => '$res' Expected: '${result[$n]}'"
	    test -z $CONT && exit 3
	fi
      fi
    fi
}

ntests=3000
declare -a tests[$ntests]
declare -a result[$ntests]
ncctests=23
declare -a cctests[$((100+$ncctests))]
declare -a ccresult[$((100+$ncctests))]
tests[1]='print "hi"'
result[1]='hi'
tests[2]='for (1,2,3) { print if /\d/ }'
result[2]='123'
tests[3]='$_ = "xyxyx"; %j=(1,2); s/x/$j{print("z")}/ge; print $_'
result[3]='zzz2y2y2'
tests[4]='$_ = "xyxyx"; %j=(1,2); s/x/$j{print("z")}/g; print $_'
if [[ $v518 -gt 0 ]]; then
  result[4]='zzz2y2y2'
else
  result[4]='z2y2y2'
fi
tests[5]='print split /a/,"bananarama"'
result[5]='bnnrm'
tests[6]="{package P; sub x {print 'ya'} x}"
result[6]='ya'
tests[7]='@z = split /:/,"b:r:n:f:g"; print @z'
result[7]='brnfg'
tests[8]='sub AUTOLOAD { print 1 } &{"a"}()'
result[8]='1'
tests[9]='my $l_i = 3; $x = sub { print $l_i }; &$x'
result[9]='3'
tests[10]='my $i_i = 1;
my $foo = sub {
  $i_i = shift if @_
}; print $i_i;
print &$foo(3),$i_i;'
result[10]='133'
# index: do fbm_compile or not
tests[11]='$x="Cannot use"; print index $x, "Can"'
result[11]='0'
tests[12]='my $i_i=6; eval "print \$i_i\n"; print ""'
result[12]='6'
tests[13]='BEGIN { %h=(1=>2,3=>4) } print $h{3}'
result[13]='4'
tests[14]='open our $T,"a"; print "ok";'
# __DATA__ handles still broken non-threaded 5.10
tests[15]='print <DATA>
__DATA__
a
b'
result[15]='a
b'
tests[16]='BEGIN{tie @a, __PACKAGE__;sub TIEARRAY {bless{}} sub FETCH{1}}; print $a[1]'
result[16]='1'
tests[17]='my $i_ir=3; print 1 .. $i_ir'
result[17]='123'
# custom key sort
tests[18]='my $h = { a=>3, b=>1 }; print sort {$h->{$a} <=> $h->{$b}} keys %$h'
result[18]='ba'
# fool the sort optimizer by my $p, pp_sort works ok on CC
tests[19]='print sort { my $p; $b <=> $a } 1,4,3'
result[19]='431'
# not repro: something like this is broken in original 5.6 (Net::DNS::ZoneFile::Fast)
# see new test 33
tests[20]='$a="abcd123";my $r=qr/\d/;print $a =~ $r;'
result[20]='1'
# broken on early alpha and 5.10: run-time labels.
tests[21]='sub skip_on_odd{next NUMBER if $_[0]% 2}NUMBER:for($i=0;$i<5;$i++){skip_on_odd($i);print $i;}'
result[21]='024'
# broken in original perl 5.6
tests[22]='my $fh; BEGIN { open($fh,"<","/dev/null"); } print "ok";';
# broken in perl 5.8
tests[23]='package MyMod; our $VERSION = 1.3; print "ok";'
# works in original perl 5.6, broken with latest B::C in 5.6, 5.8
tests[24]='sub level1{return(level2()?"fail":"ok")} sub level2{0} print level1();'
# enforce custom ncmp sort and count it. fails as CC in all. How to enforce icmp?
# <=5.6 qsort needs two more passes here than >=5.8 merge_sort
# 5.12 got it backwards and added 4 more passes.
tests[25]='print sort { $i++; $b <=> $a } 1..4'
result[25]="4321"
# lvalue sub
tests[26]='sub a:lvalue{my $a=26; ${\(bless \$a)}}sub b:lvalue{${\shift}}; print ${a(b)}';
result[26]="26"
# xsub constants (constant folded). newlib: 0x200, glibc: 0x100
tests[27]='use Fcntl ();my $a=Fcntl::O_CREAT(); print "ok" if ( $a >= 64 && &Fcntl::O_CREAT >= 64 );'
# require $fname
tests[28]='my($fname,$tmp_fh);while(!open($tmp_fh,">",($fname=q{ccode28_} . rand(999999999999)))){$bail++;die "Failed to create a tmp file after 500 tries" if $bail>500;}print {$tmp_fh} q{$x="ok";1;};close($tmp_fh);sleep 1;require "./$fname";END{unlink($fname);};print $x;'
# multideref with static index and sv and dynamic gv ptrs
tests[29]='my (%b,%h); BEGIN { %b=(1..8);@a=(1,2,3,4); %h=(1=>2,3=>4) } $i=0; my $l=-1; print $h->{$b->{3}},$h->{$a[-1]},$a[$i],$a[$l],$h{3}'
result[29]='144'
# special old IO handling
tests[291]='use IO;print "ok"'
# run-time context of .., fails in CC
tests[30]='@a=(4,6,1,0,0,1);sub range{(shift @a)..(shift @a)}print range();while(@a){print scalar(range())}'
result[30]='456123E0'
# AUTOLOAD w/o goto xsub
tests[31]='package MockShell;sub AUTOLOAD{my $p=$AUTOLOAD;$p=~s/.*:://;print(join(" ",$p,@_),";");} package main; MockShell::date();MockShell::who("am","i");MockShell::ls("-l");'
result[31]='date;who am i;ls -l;'
# CC entertry/jmpenv_jump/leavetry
tests[32]='eval{print "1"};eval{die 1};print "2";'
result[32]='12'
# C qr test was broken in 5.6 -- needs to load an actual file to test. See test 20.
# used to error with Can't locate object method "save" via package "U??WVS?-" (perhaps you forgot to load "U??WVS?-"?) at /usr/lib/perl5/5.6.2/i686-linux/B/C.pm line 676.
# fails with new constant only. still not repro (r-magic probably)
tests[33]='BEGIN{unshift @INC,("t");} use qr_loaded_module; print "ok" if qr_loaded_module::qr_called_in_sub("name1")'
# init of magic hashes. %ENV has e magic since a0714e2c perl.c
# (Steven Schubiger      2006-02-03 17:24:49 +0100 3967) i.e. 5.8.9 but not 5.8.8
tests[34]='my $x=$ENV{TMPDIR};print "ok"'
# static method_named. fixed with 1.16
tests[35]='package dummy;my $i=0;sub meth{print $i++};package main;dummy->meth(1);my dummy $o = bless {},"dummy";$o->meth("const");my $meth="meth";$o->$meth("const");dummy->$meth("const");dummy::meth("dummy","const")'
result[35]='01234'
# HV self-ref
tests[36]='my ($rv, %hv); %hv = ( key => \$rv ); $rv = \%hv; print "ok";'
# AV self-ref
tests[37]='my ($rv, @av); @av = ( \$rv ); $rv = \@av; print "ok";'
# constant autoload loop crash test
tests[38]='for(1 .. 1024) { if (open(my $null_fh,"<","/dev/null")) { seek($null_fh,0,SEEK_SET); close($null_fh); $ok++; } }if ($ok == 1024) { print "ok"; }'
# check re::is_regexp, and on 5.12 if being upgraded to SVt_REGEXP
# => Undefined subroutine &re::is_regexp with B-C-1.19, even with -ure
tests[39]='{$a=qr/x/;print($]<5.010?1:re::is_regexp($a))}'
result[39]='1'
# String with a null byte -- used to generate broken .c on 5.6.2 with static pvs
tests[40]='my $var="this string has a null \\000 byte in it";print "ok";'
# Shared scalar, n magic. => Don't know how to handle magic of type \156.
usethreads=""
#usethreads="`$PERL -MConfig -e'print ($Config{useithreads} ? q(use threads;) : q())'`"
#usethreads='BEGIN{use Config; unless ($Config{useithreads}) {print "ok"; exit}} '
#;threads->create(sub{$s="ok"})->join;
# not yet testing n, only P
tests[41]=$usethreads'use threads::shared;{my $s="ok";share($s);print $s}'
# Shared aggregate, P magic
tests[42]=$usethreads'use threads::shared;my %h : shared; print "ok"'
# Aggregate element, n + p magic
tests[43]=$usethreads'use threads::shared;my @a : shared; $a[0]="ok"; print $a[0]'
# perl #72922 (5.11.4 fails with magic_killbackrefs)
tests[44]='use Scalar::Util "weaken";my $re1=qr/foo/;my $re2=$re1;weaken($re2);print "ok" if $re3=qr/$re1/;'
# test dynamic loading
tests[45]='use Data::Dumper ();Data::Dumper::Dumpxs({});print "ok";'
# issue 79: Exporter:: stash missing in main::
#tests[46]='use Exporter; if (exists $main::{"Exporter::"}) { print "ok"; }'
tests[46]='use Exporter; print "ok" if %main::Exporter::'
#tests[46]='use Exporter; print "ok" if scalar(keys(%main::Exporter::)) > 2'
# non-tied av->MAGICAL
tests[47]='@ISA=(q(ok));print $ISA[0];'
# END block del_backref with bytecode only
tests[48]='my $s=q{ok};END{print $s}'
# even this failed until r1000 (AvFILL 3 of END)
#tests[48]='print q{ok};END{}'
# no-fold
tests[49]='print q(ok) if "test" =~ /es/i;'
# @ISA issue 64
tests[50]='package Top;sub top{q(ok)};package Next;our @ISA=qw(Top);package main;print Next->top();'
# XXX TODO sigwarn $w = B::NULL without -v
tests[51]='$SIG{__WARN__}=sub{print "ok"};warn 1;'
# check if general signals work
tests[511]='BEGIN{$SIG{USR1}=sub{$w++;};} kill USR1 => $$; print q(ok) if $w'
#-------------
# issue27
tests[527]='require LWP::UserAgent;print q(ok);'
#issue 24
tests[124]='my %H;dbmopen(%H,q(f),0644);print q(ok);'
tests[68]='package A;
sub test {
  use Data::Dumper ();
  /^(.*?)\d+$/;
  "Some::Package"->new();
}
print "ok"'
# issue71
tests[71]='
package my;
our @a;
sub f {
  my($alias,$name)=@_;
  unshift(@a, $alias => $name);
  my $find = "ok";
  my $val = $a[1];
  if ( ref($alias) eq "Regexp" && $find =~ $alias ) {
    eval $val;
  }
  $find
}
package main;
*f=*my::f;
print "ok" if f(qr/^(.*)$/ => q("\L$1"));'
# object call: method_named with args.
tests[72]='package dummy;sub meth{print "ok"};package main;my dummy $o = bless {},"dummy"; $o->meth("const")'
# object call: dynamic method_named with args.
tests[73]='package dummy;sub meth{print "ok"};package main;my $meth="meth";my $o = bless {},"dummy"; $o->$meth("const")'
tests[74]='package dummy;
my $invoked_as_script = !caller();
__PACKAGE__->script(@ARGV) if $invoked_as_script;
sub script {my($package,@args)=@_;print "ok"}'
# issue 71_2+3: cop_warnings issue76 and const destruction issue71 fixed
# ok with "utf-8-strict"
tests[75]='use Encode;
my $x = "abc";
print "ok" if "abc" eq Encode::decode("UTF-8", $x);'
tests[76]='use warnings;
{ no warnings q(void); # issue76 lexwarn
  length "ok";
  print "ok"
};'
tests[81]='%int::;  #create int package for types
sub x(int,int) { @_ } #cvproto
my $o = prototype \&x;
if ($o eq "int,int") {print "o"}else{print $o};
sub y($) { @_ } #cvproto
my $p = prototype \&y;
if ($p eq q($)) {print "k"}else{print $p};
require bytes;
sub my::length ($) { # possible prototype mismatch vs _
  if ( bytes->can(q(length)) ) {
     *length = *bytes::length;
     goto &bytes::length;
  }
  return CORE::length( $_[0] );
}
print my::length($p);'
result[81]='ok1'
tests[90]='my $s = q(test string);
$s =~ s/(?<first>test) (?<second>string)/\2 \1/g;
print q(o) if $s eq q(string test);
q(test string) =~ /(?<first>\w+) (?<second>\w+)/;
print q(k) if $+{first} eq q(test);'
tests[901]='my %errs = %!; # t/op/magic.t Errno compiled in
print q(ok) if defined ${"!"}{ENOENT};'
tests[902]='my %errs = %{"!"}; # t/op/magic.t Errno to be loaded at run-time
print q(ok) if defined ${"!"}{ENOENT};'
# issue #199
tests[903]='"abc" =~ /(.)./; print "ok" if "21" eq join"",@+;'
# issue #220
tests[904]='my $content = "ok\n";
while ( $content =~ m{\w}g ) {
    $_ .= "$-[0]$+[0]";
}
print "ok" if $_ eq "0112";'
# IO handles
tests[91]='# issue59
use strict;
use warnings;
use IO::Socket;
my $remote = IO::Socket::INET->new( Proto => "tcp", PeerAddr => "perl.org", PeerPort => "80" );
print $remote "GET / HTTP/1.0" . "\r\n\r\n";
my $result = <$remote>;
$result =~ m|HTTP/1.1 200 OK| ? print "ok" : print $result;
close $remote;'
tests[93]='#SKIP
my ($pid, $out, $in);
BEGIN {
  local(*FPID);
  $pid = open(FPID, "echo <<EOF |");    # DIE
  open($out, ">&STDOUT");		# EASY
  open(my $tmp, ">", "pcc.tmp");	# HARD to get filename, WARN
  print $tmp "test\n";
  close $tmp;				# OK closed
  open($in, "<", "pcc.tmp");		# HARD to get filename, WARN
}
# === run-time ===
print $out "o";
kill 0, $pid; 			     # BAD! warn? die?
print "k" if "test" eq read $in, my $x, 4;
unlink "pcc.tmp";
'
result[93]='o'
tests[931]='my $f;BEGIN{open($f,"<README");}read $f,my $in, 2; print "ok"'
tests[932]='my $f;BEGIN{open($f,">&STDOUT");}print $f "ok"'
tests[95]='use IO::Socket::SSL();
my IO::Handle $handle = IO::Socket::SSL->new(SSL_verify_mode =>0);
$handle->blocking(0);
print "ok";'
tests[96]='defined(&B::OP::name) || print q(ok)'
tests[97]='use v5.12; print q(ok);'

# from here on we test CC specifics only

# CC types and arith
tests[101]='my ($r_i,$i_i,$d_d)=(0,2,3.0); $r_i=$i_i*$i_i; $r_i*=$d_d; print $r_i;'
result[101]='12'
# CC cond_expr, stub, scope
tests[102]='if ($x eq "2"){}else{print "ok"}'
# CC stringify, srefgen
tests[103]='require B; my $x=1e1; my $s="$x"; print ref B::svref_2object(\$s)'
result[103]='B::PV'
# CC reset
tests[104]='@a=(1..4);while($a=shift@a){print $a;}continue{$a=~/2/ and reset q(a);}'
result[104]='12'
# CC -ftype-attr
#tests[105]='$int::dummy=0;$double::dummy=0;my int $r;my $i:int=2;our double $d=3.0; $r=$i*$i; $r*=$d; print $r;'
tests[105]='%int::;%double::;my int $r;my int $i=2;our double $d=3.0; $r=$i*$i; $r*=$d; print $r;'
result[105]='12'
# issue 296
tests[106]='my $s=q{ok};END{print $s}END{$x = 0}'

# issue31
tests[131]='package Ccode31i;my $regex = qr/\w+/;sub test {print ("word" =~ m/^$regex$/o ? "ok\n" : "not ok\n");}
package main; &Ccode31i::test();'
# issue35
tests[110]='sub new{}sub test{{my $x=1;my $y=$x+1;}my $x=2;if($x!=3){4;}} print q(ok)'
# issue36
tests[111]='sub f{shift==2}sub test{while(1){last if f(2);}while(1){last if f(2);}} print q(ok)'
# issue37
tests[112]='my $x;$x||=1;print "ok" if $x;'
# issue38
tests[113]='my $x=2;$x=$x||3;print "ok" if $x==2;'
# issue39
tests[114]='sub f1{0}sub f2{my $x;if(f1()){}if($x){}else{[$x]}}my @a=f2();print "ok";'
# issue42
tests[115]='sub f1{1}f1();print do{7;2},"\n";'
result[115]='2'
# issue44
tests[116]='my @a=(1,2);print $a[0],"\n";'
result[116]='1'
# issue45
tests[117]='my $x;$x//=1;print "ok" if $x;'
# issue46
tests[118]='my $pattern="x";"foo"=~/$pattern/o;print "ok";'
# issue47
tests[119]='my $f=sub{while(1){return(1);}};print $f->(),"\n";'
result[119]='1'
# issue48
tests[120]='sub f{()}print((my ($v)=f())?1:2,"\n");'
result[120]='2'
# issue49
tests[121]='while(1){while(1){last;}last;}print "ok"'
# issue51
tests[122]='my ($p1,$p2)=(80,80);if($p1<=23&&23<=$p2){print "telnet\n";}elsif ($p1 <= 80 && 80 <= $p2){print "http\n";}else{print "fail\n"}'
result[122]='http'
# issue52
tests[123]='my $x;my $y = 1;$x and $y == 2;print $y == 1 ? "ok\n" : "fail\n";'
# issue55
tests[124]='LOOP:{my $sub=sub{last LOOP;}; $sub->() } print "ok";'
# issue125 DynaLoader::bootstrap_inherit [perl #119577]
tests[125]='use Net::LibIDN; print q(ok);'
# saving recursive functions sometimes recurses in the compiler. this not, but Moose stucks in Pod::Simple
tests[99]='package my;sub recurse{my $i=shift;recurse(++$i)unless $i>5000;print"ok";exit};package main;my::recurse(1)'
if [[ $v518 -gt 0 ]]; then
  tests[130]='no warnings "experimental::lexical_subs";use feature "lexical_subs";my sub p{q(ok)}; my $a=\&p;print p;'
fi
tests[137]='"to" =~ /t(?{ print "ok"})o/;'
tests[138]='print map { chr $_ } qw/97 98 99/;'
result[138]='abc'
tests[140]='my %a;print "ok" if !%a;'
#tests[141]='print "ok" if "1" > 0'
tests[141]='@x=(0..1);print "ok" if $#x == "1"'
tests[142]='$_ = "abc\x{1234}";chop;print $_ eq "abc" ? "ok" : $_;'
tests[143]='BEGIN {
  package Net::IDN::Encode;
  our $DOT = qr/[\.]/; #works with my!
  my $RE  = qr/xx/;
  sub domain_to_ascii {
    my $x = shift || "";
    $x =~ m/$RE/o;
    return split( qr/($DOT)/o, $x);
  }
}
package main;
Net::IDN::Encode::domain_to_ascii(42);
print "ok\n";'
tests[1431]='BEGIN{package Foo;our $DOT=qr/[.]/;};package main;print "ok\n" if "dot.dot" =~ m/($Foo::DOT)/'
tests[1432]='BEGIN{$DOT=qr/[.]/}print "ok\n" if "dot.dot" =~ m/($DOT)/'
tests[144]='print index("long message\0xx","\0")'
result[144]='12'
tests[145]='my $bits = 0; for (my $i = ~0; $i; $i >>= 1) { ++$bits; }; print $bits'
result[145]=`$PERL -MConfig -e'print 8*$Config{ivsize}'`
if [[ $v524 -eq 0 ]]; then # Use of strings with code points over 0xFF as arguments to bitwise xor (^) operator is deprecated in perl 5.24
  tests[146]='my $a = v120.300; my $b = v200.400; $a ^= $b; print sprintf("%vd", $a);'
  result[146]='176.188'
fi
tests[148]='open(FH, ">", "ccode148i.tmp"); print FH "1\n"; close FH; print -s "ccode148i.tmp"'
result[148]='2'
tests[149]='format Comment =
ok
.

{
  local $~ = "Comment";
  write;
}'
tests[150]='print NONEXISTENT "foo"; print "ok" if $! == 9'
tests[1501]='$! = 0; print NONEXISTENT "foo"; print "ok" if $! == 9'
tests[152]='print "ok" if find PerlIO::Layer "perlio"'
tests[154]='$SIG{__WARN__} = sub { die "warning: $_[0]" }; opendir(DIR, ".");closedir(DIR);print q(ok)'
tests[156]='use warnings;
no warnings qw(portable);
use XSLoader;
XSLoader::load() if $ENV{force_xsloader}; # trick for perlcc to force xloader to be compiled
{
    my $q = 12345678901;
    my $x = sprintf("%llx", $q);
    print "ok\n" if hex $x == 0x2dfdc1c35;
    exit;
}'
tests[157]='$q = 18446744073709551615;print scalar($q)."\n";print scalar(18446744073709551615)."\n";'
result[157]='18446744073709551615
18446744073709551615'
tests[1571]='my $a = 9223372036854775807; print "ok\n" if ++$a == 9223372036854775808;'
# duplicate of 148
tests[158]='open W, ">ccodetmp" or die "1: $!";print W "foo";close W;open R, "ccodetmp" or die "2: $!";my $e=eof R ? 1 : 0;close R;print "$e\n";'
result[158]='0'
tests[159]='@X::ISA = "Y"; sub Y::z {"Y::z"} print "ok\n" if  X->z eq "Y::z"; delete $X::{z}; exit'
# see 188
tests[160]='sub foo { (shift =~ m?foo?) ? 1 : 0 }
print "ok\n";'
tests[161]='sub PVBM () { foo } { my $dummy = index foo, PVBM } print PVBM'
result[161]='foo'
# duplicate of 142
tests[162]='$x = "\x{1234}"; print "ok\n" if ord($x) == 0x1234;'
tests[163]='# WontFix
my $destroyed = 0;
sub  X::DESTROY { $destroyed = 1 }
{
	my $x;
	BEGIN {$x = sub { }  }
	$x = bless {}, 'X';
}
print qq{ok\n} if $destroyed == 1;'
# duplicate of 148
tests[164]='open(DUPOUT,">&STDOUT");close(STDOUT);open(F,">&DUPOUT");print F "ok\n";'
tests[165]='use warnings;
sub recurse1 {
    unshift @_, "x";
    no warnings "recursion";
    goto &recurse2;
}
sub recurse2 {
    my $x = shift;
    $_[0] ? +1 + recurse1($_[0] - 1) : 0
}
print "ok\n" if recurse1(500) == 500;'
tests[166]='my $ok = 1;
foreach my $chr (60, 200, 600, 6000, 60000) {
  my ($key, $value) = (chr ($chr) . "\x{ABCD}", "$chr\x{ABCD}");
  chop($key, $value);
  my %utf8c = ( $key => $value );
  my $tempval = sprintf q($utf8c{"\x{%x}"}), $chr;
  my $ev = eval $tempval;
  $ok = 0 if !$ev or $ev ne $value;
} print "ok" if $ok'
tests[167]='$a = "a\xFF\x{100}";
eval {$b = crypt($a, "cd")};
print $@;'
result[167]='Wide character in crypt at ccode167.pl line 2.'
tests[168]='my $start_time = time;
eval {
    local $SIG{ALRM} = sub { die "ALARM !\n" };
    alarm 1;
    # perlfunc recommends against using sleep in combination with alarm.
    1 while (time - $start_time < 3);
};
alarm 0;
print $@;
print "ok\n" if $@ eq "ALARM !\n";'
result[168]='ALARM !
ok'
tests[169]='#TODO Attribute::Handlers
package MyTest;
use Attribute::Handlers;
sub Check :ATTR {
    print "called\n";
    print "ok\n" if ref $_[4] eq "ARRAY" && join(",", @{$_[4]}) eq join(",", qw/a b c/);
}
sub a_sub :Check(qw/a b c/) {
    return 42;
}
print a_sub()."\n";'
result[169]='called
ok
42'
tests[170]='eval "sub xyz (\$) : bad ;"; print "~~~~\n$@~~~~\n"'
result[170]='~~~~
Invalid CODE attribute: bad at (eval 1) line 1.
BEGIN failed--compilation aborted at (eval 1) line 1.
~~~~'
tests[172]='package Foo;
use overload q("") => sub { "Foo" };
package main;
my $foo = bless {}, "Foo";
print "ok\n" if "$foo" eq "Foo";'
tests[173]='# WontFix
use constant BEGIN   => 42; print "ok 1\n" if BEGIN == 42;
use constant INIT   => 42; print "ok 2\n" if INIT == 42;
use constant CHECK   => 42; print "ok 3\n" if CHECK == 42;'
result[173]='Prototype mismatch: sub main::BEGIN () vs none at ./ccode173.pl line 2.
Constant subroutine BEGIN redefined at ./ccode173.pl line 2.
ok 1
ok 2
ok 3'
tests[174]='
my $str = "\x{10000}\x{800}";
no warnings "utf8";
{ use bytes; $str =~ s/\C\C\z//; }
my $ref = "\x{10000}\0";
print "ok 1\n" if ~~$str eq $ref;
$str = "\x{10000}\x{800}";
{ use bytes; $str =~ s/\C\C\z/\0\0\0/; }
my $ref = "\x{10000}\0\0\0\0";
print "ok 2\n" if ~~$str eq $ref;'
result[174]='ok 1
ok 2'
tests[175]='{
  # note that moving the use in an eval block solve the problem
  use warnings NONFATAL => all;
  $SIG{__WARN__} = sub { "ok - expected warning\n" };
  my $x = pack( "I,A", 4, "X" );
  print "ok\n";
}'
result[175]='ok - expected warning
ok'
tests[176]='use Math::BigInt; print Math::BigInt::->new(5000000000);'
result[176]='5000000000'
tests[177]='use version; print "ok\n" if version::is_strict("4.2");'
if [[ $v524 -eq 0 ]]; then
  tests[178]='BEGIN { $hash  = { pi => 3.14, e => 2.72, i => -1 } ;} print scalar keys $hash;'
  result[178]='3'
fi
tests[179]='#TODO smartmatch subrefs
{
    package Foo;
    sub new { bless {} }
}
package main;
our $foo = Foo->new;
our $bar = $foor; # required to generate the wrong behavior
my $match = eval q($foo ~~ undef) ? 1 : 0;
print "match ? $match\n";'
result[179]='match ? 0'
tests[180]='use feature "switch"; use integer; given(3.14159265) { when(3) { print "ok\n"; } }'
tests[181]='sub End::DESTROY { $_[0]->() };
my $inx = "OOOO";
$SIG{__WARN__} = sub { print$_[0] . "\n" };
{
    $@ = "XXXX";
    my $e = bless( sub { die $inx }, "End")
}
print q(ok)'
tests[182]='#TODO stash-magic delete renames to ANON
my @c; sub foo { @c = caller(0); print $c[3] } my $fooref = delete $::{foo}; $fooref -> ();'
result[182]='main::__ANON__'
tests[183]='main->import(); print q(ok)'
tests[184]='use warnings;
sub xyz { no warnings "redefine"; *xyz = sub { $a <=> $b }; &xyz }
eval { @b = sort xyz 4,1,3,2 };
print defined $b[0] && $b[0] == 1 && $b[1] == 2 && $b[2] == 3 && $b[3] == 4 ? "ok\n" : "fail\n";
exit;
{
    package Foo;
    use overload (qw("" foo));
}
{
    package Bar;
    no warnings "once";
    sub foo { $ENV{fake} }
}
'
# usage: t/testc.sh -O3 -Dp,-UCarp 185
tests[185]='my $a=pack("U",0xFF);use bytes;print "not " unless $a eq "\xc3\xbf" && bytes::length($a) == 2; print "ok\n";'
tests[186]='eval q/require B/; my $sub = do { package one; \&{"one"}; }; delete $one::{one}; my $x = "boom"; print "ok\n";'
# duplicate of 182
tests[187]='my $glob = \*Phoo::glob; undef %Phoo::; print ( ( "$$glob" eq "*__ANON__::glob" ) ? "ok\n" : "fail with $$glob\n" );'
# See also GH 252 + 360
tests[188]='package aiieee;sub zlopp {(shift =~ m?zlopp?) ? 1 : 0;} sub reset_zlopp {reset;}
package main; print aiieee::zlopp(""), aiieee::zlopp("zlopp"), aiieee::zlopp(""), aiieee::zlopp("zlopp");
aiieee::reset_zlopp(); print aiieee::zlopp("zlopp")'
result[188]='01001'
tests[191]='# WontFix
BEGIN{sub plan{42}} {package Foo::Bar;} print((exists $Foo::{"Bar::"} && $Foo::{"Bar::"} eq "*Foo::Bar::") ? "ok\n":"bad\n"); plan(fake=>0);'
tests[192]='use warnings;
{
 no warnings qw "once void";
 my %h; # We pass a key of this hash to the subroutine to get a PVLV.
 sub { for(shift) {
  # Set up our glob-as-PVLV
  $_ = *hon;
  # Assigning undef to the glob should not overwrite it...
  {
   my $w;
   local $SIG{__WARN__} = sub { $w = shift };
   *$_ = undef;
   print ( $w =~ m/Undefined value assigned to typeglob/ ? "ok" : "not ok");
  }
 }}->($h{k});
}'
tests[193]='unlink q{not.a.file}; $! = 0; open($FOO, q{not.a.file}); print( $! ne 0 ? "ok" : q{error: $! should not be 0}."\n"); close $FOO;'
tests[194]='$0 = q{ccdave with long name}; #print "pid: $$\n";
$s=`ps w | grep "$$" | grep "[c]cdave"`;
print ($s =~ /ccdave with long name/ ? q(ok) : $s);'
tests[1941]='$0 = q{ccdave}; #print "pid: $$\n";
$s=`ps auxw | grep "$$" | grep "ccdave"|grep -v grep`;
print q(ok) if $s =~ /ccdave/'
# VmRSS memory usage
tests[1942]='$s=<DATA>;print `ps -p $$ -O rss,vsz,pmem`;
__DATA__
a'
# duplicate of 152
tests[195]='use PerlIO;  eval { require PerlIO::scalar }; find PerlIO::Layer "scalar"; print q(ok)'
tests[196]='package Foo;
sub new { bless {}, shift }
DESTROY { $_[0] = "foo" }
package main;
eval q{\\($x, $y, $z) = (1, 2, 3);};
my $m;
$SIG{__DIE__} = sub { $m = shift };
{ my $f = Foo->new }
print "m: $m\n";'
result[196]='m: Modification of a read-only value attempted at ccode196.pl line 3.'
tests[197]='package FINALE;
{
    $ref3 = bless ["ok - package destruction"];
    my $ref2 = bless ["ok - lexical destruction\n"];
    local $ref1 = bless ["ok - dynamic destruction\n"];
    1;
}
DESTROY {
    print $_[0][0];
}'
result[197]='ok - dynamic destruction
ok - lexical destruction
ok - package destruction'
# duplicate of 150
tests[198]='{
  open(my $NIL, qq{|/bin/echo 23}) or die "fork failed: $!";
  $! = 1;
  close $NIL;
  if($! == 5) { print}
}'
result[198]='23'
# duplicate of 90
tests[199]='"abc" =~ /(.)./; print @+; print "end\n"'
result[199]='21end'
tests[200]='use Encode::Byte; use Encode::KR; print "ok\n"'
tests[2000]='%u=("\x{123}"=>"fo"); print "ok" if $u{"\x{123}"} eq "fo"'
tests[2001]='BEGIN{%u=("\x{123}"=>"fo");} print "ok" if $u{"\x{123}"} eq "fo";'
tests[201]='use Storable;*Storable::CAN_FLOCK=sub{1};print qq{ok\n}'
tests[2011]='sub can {require Config; import Config;return $Config{d_flock}}
use IO::File;
can();
print "ok\n";'
tests[203]='#TODO <5.22 perlio layers
use open(IN => ":crlf", OUT => ":encoding(cp1252)");
open F, "<", "/dev/null";
my %l = map {$_=>1} PerlIO::get_layers(F, input  => 1);
print $l{crlf} ? q(ok) : keys(%l);'
# issue 29
tests[2900]='use open qw(:std :utf8);
BEGIN{ `echo ö > xx.bak`; }
open X, "xx.bak";
$_ = <X>;
print unpack("U*", $_), " ";
print $_ if /\w/;'
result[2900]='24610 ö'
tests[207]='use warnings;
sub asub { }
asub(tests => 48);
my $str = q{0};
$str =~ /^[ET1]/i;
{
    no warnings qw<io deprecated>;
    print "ok 1\n" if opendir(H, "t");
    print "ok 2" if open(H, "<", "TESTS");
}'
result[207]='ok 1
ok 2'
tests[208]='sub MyKooh::DESTROY { print "${^GLOBAL_PHASE} MyKooh " }  my $my =bless {}, MyKooh;
sub OurKooh::DESTROY { print "${^GLOBAL_PHASE} OurKooh" }our $our=bless {}, OurKooh;'
if [[ `$PERL -e'print (($] < 5.014)?0:1)'` -gt 0 ]]; then
  result[208]='RUN MyKooh DESTRUCT OurKooh'
else
  result[208]=' MyKooh  OurKooh'
fi
tests[210]='$a = 123;
package xyz;
sub xsub {bless [];}
$x1 = 1; $x2 = 2;
$s = join(":", sort(keys %xyz::));
package abc;
my $foo;
print $xyz::s'
result[210]='s:x1:x2:xsub'
tests[212]='$blurfl = 123;
{
    package abc;
    $blurfl = 5;
}
$abc = join(":", sort(keys %abc::));
package abc;
print "variable: $blurfl\n";
print "eval: ". eval q/"$blurfl\n"/;
package main;
sub ok { 1 }'
result[212]='variable: 5
eval: 5'
tests[214]='
my $expected = "foo";
sub check(_) { print( (shift eq $expected) ? "ok\n" : "not ok\n" ) }
$_ = $expected;
check;
undef $expected;
&check; # $_ not passed'
result[214]='ok
ok'
tests[215]='eval { $@ = "t1\n"; do { die "t3\n" }; 1; }; print ":$@:\n";'
result[215]=':t3
:'
tests[216]='eval { $::{q{@}}=42; }; print qq{ok\n}'
# priority, fails since 5.18
tests[219]='package OverloadTest; use overload qw("") => sub { ${$_[0]} }; package main;
my $foo = bless \(my $bar = "ok"), "OverloadTest"; print $foo."\n";'
tests[2190]='package Foo; use overload; sub import { overload::constant "integer" => sub { return shift }}; package main; BEGIN { $INC{"Foo.pm"} = "/lib/Foo.pm" }; use Foo; my $result = eval "5+6"; print "$result\n"'
result[2190]='11'
# old issue 220 see 904
tests[220]='BEGIN { $^H{dooot} = 1 }
sub hint_fetch {
    my $key = shift;
    my @results = caller(0);
    $results[10]->{$key};
}
print qq{ok\n} if hint_fetch("dooot");'
tests[2201]='BEGIN { $^H{dчастt} = 1 }
sub hint_fetch {
    my $key = shift;
    my @results = caller(0);
    $results[10]->{$key};
}
print qq{ok\n} if hint_fetch("dчастt");'
tests[2231]='use strict; eval q({ $x = sub }); print $@'
result[2231]='Illegal declaration of anonymous subroutine at (eval 1) line 1.'
tests[222]='my $qr = qr/(?{<<END})/;
boom
END
print "ok";
'
tests[223]='<*> and print qq{ok\n}'
tests[224]='use bytes; my $p = "\xB6"; my $u = "\x{100}"; my $pu = "\xB6\x{100}"; print ( $p.$u eq $pu ? "ko\n" : "ok\n" );'
tests[225]='$_ = $dx = "\x{10f2}"; s/($dx)/$dx$1/; $ok = 1 if $_ eq "$dx$dx"; $_ = $dx = "\x{10f2}"; print qq{end\n};'
result[225]='end'
tests[226]='# WontFix
@INC = (); dbmopen(%H, $file, 0666)'
result[226]='No dbm on this machine at -e line 1.'
tests[227]='open IN, "/dev/null" or die $!; *ARGV = *IN; foreach my $x (<>) { print $x; } close IN; print qq{ok\n}'
tests[229]='sub yyy () { "yyy" } print "ok\n" if( eval q{yyy} eq "yyy");'
#issue 30
tests[230]='sub f1 { my($self) = @_; $self->f2;} sub f2 {} sub new {} print "@ARGV\n";'
result[230]=' '
tests[232]='use Carp (); exit unless Carp::longmess(); print qq{ok\n}'
tests[234]='$c = 0; for ("-3" .. "0") { $c++ } ; print "$c"'
result[234]='4'
# t/testc.sh -O3 -Dp,-UCarp,-v 235
tests[235]='BEGIN{$INC{"Carp.pm"}="/dev/null"} $d = pack("U*", 0xe3, 0x81, 0xAF); { use bytes; $ol = bytes::length($d) } print $ol'
result[235]='6'
# -O3
tests[236]='sub t { if ($_[0] == $_[1]) { print "ok\n"; } else { print "not ok - $_[0] == $_[1]\n"; } } t(-1.2, " -1.2");'
tests[237]='print "\000\000\000\000_"'
result[237]='_'
tests[238]='sub f ($);
sub f ($) {
  my $test = $_[0];
  write;
  format STDOUT =
ok @<<<<<<<
$test
.
}
f("");
'
tests[2381]='sub is { $_[0] eq $_[1] and print "ok\n"}
use constant INIT => 5; is(INIT, 5)'
tests[239]='my $x="1";
format STDOUT =
ok @<<<<<<<
$x
.
write;print "\n";'
result[239]='ok 1'
tests[240]='my $a = "\x{100}\x{101}Aa";
print "ok\n" if "\U$a" eq "\x{100}\x{100}AA";
my $b = "\U\x{149}cD"; # no pb without that line'
tests[241]='package Pickup; use UNIVERSAL qw( can ); if (can( "Pickup", "can" ) != \&UNIVERSAL::can) { print "not " } print "ok\n";'
tests[242]='$xyz = ucfirst("\x{3C2}");
$a = "\x{3c3}foo.bar";
($c = $a) =~ s/(\p{IsWord}+)/ucfirst($1)/ge;
print "ok\n" if $c eq "\x{3a3}foo.Bar";'
tests[243]='use warnings "deprecated"; print hex(${^WARNINGS}) . " "; print hex(${^H})'
result[243]='0 598'
tests[244]='print "($_)\n" for q{-2}..undef;'
result[244]='(-2)
(-1)
(0)'
tests[245]='%INC = (); require XSLoader; XSLoader::load("Cwd"); print qq{ok}'
tests[2450]='sub foo {
    my ( $a, $b ) = @_;
    print "a: ".ord($a)." ; b: ".ord($b)." [ from foo ]\n";
}
print "a: ". ord(lc("\x{1E9E}"))." ; ";
print "b: ". ord("\x{df}")."\n";
foo(lc("\x{1E9E}"), "\x{df}");'
result[2450]='a: 223 ; b: 223
a: 223 ; b: 223 [ from foo ]'
tests[246]='no warnings "experimental::const_attr"; print qq{ok} if &{sub () : const { 42 }} == 42;'
# see t/issue235.t test 2
tests[2460]='sub foo($\@); eval q/foo "s"/; print $@'
result[2460]='Not enough arguments for main::foo at (eval 1) line 1, at EOF'
tests[247]='# WontFix
no warnings; $[ = 1; $big = "N\xabN\xab"; print qq{ok\n} if rindex($big, "N", 3) == 3'
tests[248]='#WONTFIX lexical $_ in re-eval
{my $s="toto";my $_="titi";{$s =~ /to(?{ print "-$_-$s-\n";})to/;}}'
result[248]='-titi-toto-'
tests[249]='use version; print version::is_strict(q{01}) ? 1 : q(ok)'
tests[2501]='#TODO version
use warnings qw/syntax/; use version; $withversion::VERSION = undef; eval q/package withversion 1.1_;/; print $@;'
result[2501]='Misplaced _ in number at (eval 1) line 1.
Invalid version format (no underscores) at (eval 1) line 1, near "package withversion "
syntax error at (eval 1) line 1, near "package withversion 1.1_"'
if [[ $v518 -gt 0 ]]; then
  tests[250]='use feature q/evalbytes/; print "ok\n" if evalbytes("1+7") == 8'
fi
tests[251]='sub f;print "ok" if exists &f'
tests[2511]='#TODO 5.18
sub f :lvalue;print "ok" if exists &f'
tests[2512]='sub f ();print "ok" if exists &f'
tests[2513]='sub f ($);print "ok" if exists &f'
tests[2514]='sub f;print "ok" if exists &f'
# see also 188
tests[252]='package bar; sub search { shift =~ m?bar? ? 1 : 0 } sub reset_zlopp { reset } package foo; sub ZZIP { shift =~ m?ZZIP? ? 1 : 0 } package main; foo::ZZIP("ZZIP"); bar::reset_zlopp(); !foo::ZZIP("ZZIP") and print "ok"'
# same as 188
tests[2520]='package aiieee;sub zlopp {(shift =~ m?zlopp?) ? 1 : 0;} sub reset_zlopp {reset;}
package main; print aiieee::zlopp(""), aiieee::zlopp("zlopp"), aiieee::zlopp(""), aiieee::zlopp("zlopp");
aiieee::reset_zlopp(); print "ok" if aiieee::zlopp("zlopp") eq "01001"'
tests[2521]='package aiieee;sub zlopp { (shift =~ m?zlopp?) ? 1 : 0 } sub reset_zlopp { reset }
package main;
aiieee::zlopp("");
aiieee::zlopp("zlopp");
aiieee::reset_zlopp();
print "ok\n" if aiieee::zlopp("zlopp");'
tests[253]='use Unicode::UCD q/prop_invmap/; my @list = prop_invmap("Uppercase_Mapping"); print "ok"'
tests[2530]='INIT{require "t/TestBC.pm"}plan(tests=>2);is("\x{2665}", v9829);is(v9829,"\x{2665}");'
result[2530]='1..2
ok 1
ok 2'
tests[254]='Foo->UNIVERSAL::can("boogie"); print "ok" unless eval q/Foo->boogie(); 1/;'
tests[2540]='#TODO destroy upgraded lexvar
my $flag = 0;
sub  X::DESTROY { $flag = 1 }
{
  my $x;              # x only exists in that scope
  BEGIN { $x = 42 }   # pre-initialized as IV
  $x = bless {}, "X"; # run-time upgrade and bless to call DESTROY
  # undef($x);        # value should be free when exiting scope
}
print "ok\n" if $flag;'
# duplicate of 185, bytes_heavy
tests[255]='$a = chr(300);
my $l = length($a);
my $lb;
{ use bytes; $lb = length($a); }
print( ( $l == 1 && $lb == 2 ) ? "ok\n" : "l -> $l ; lb -> $lb\n" );'
tests[256]='BEGIN{ $| = 1; } print "ok\n" if $| == 1'
tests[2561]='BEGIN{ $/ = "1"; } print "ok\n" if $/ == "1"'
tests[259]='use JSON::XS; print encode_json([\0])'
result[259]='[false]'
tests[260]='sub FETCH_SCALAR_ATTRIBUTES {''} sub MODIFY_SCALAR_ATTRIBUTES {''}; my $a :x=1; print $a'
result[260]='1'
tests[261]='q(12-feb-2015) =~ m#(\d\d?)([\-\./])(feb|jan)(?:\2(\d\d+))?#; print $4'
result[261]='2015'
tests[262]='use POSIX'
result[262]=' '
tests[263]='use JSON::XS; print encode_json []'
result[263]='[]'
tests[264]='no warnings; warn "$a.\n"'
result[264]='.'
tests[269]='use constant roref => \2; eval { for (roref) { $_ = 42 } }; print $@'
tests[270]='*x = *STDOUT; print {*x{IO}} "ok\n";'
tests[271]='my $FALSE = 0;
END { delete $ENV{"Boom"} if $FALSE }

my $kid = open my $fh, "-|";
if ($kid) { # parent
    my $read = <$fh>;
    close($fh) or die "cannot close pipe from kid proc: $!";
    print "ok\n";
}
else { # child
    print "$$\n";
    exit;
}'
tests[272]='$d{""} = qq{ok\n}; print $d{""};'
tests[2721]='BEGIN{$d{""} = qq{ok\n};} print $d{""};'
tests[273]='package _charnames; sub foo { ($name =~ /^(\p{_Perl_Charname_Begin})/) and return; } print "ok\n";'
tests[2731]='print "ok" if "\N{KELVIN SIGN}" eq "\N{KELVIN SIGN}"'
tests[274]='package Foo;
sub match { shift =~ m?xyz? ? 1 : 0; }
sub match_reset { reset; }
package Bar;
sub match { shift =~ m?xyz? ? 1 : 0; }
sub match_reset { reset; }
package main;
print "1..5\n";
print "ok 1\n" if Bar::match("xyz");
print "ok 2\n" unless Bar::match("xyz");
print "ok 3\n" if Foo::match("xyz");
print "ok 4\n" unless Foo::match("xyz");
Foo::match_reset();
print "ok 5\n" if Foo::match("xyz");
print "ok 6\n" if !Bar::match("xyz");
'
result[274]='1..5
ok 1
ok 2
ok 3
ok 4
ok 5'
# ignored xop
tests[2740]='use Devel::Peek; my %hash = ( a => 1 ); Dump(%hash) if $ENV{FALSE}; print "ok\n"'
# call xop (failed with -O1)
tests[2741]='use Devel::Peek; my %hash = ( a => 1 ); Dump(%hash); print "ok\n"'
if [[ $v518 -gt 0 ]]; then
  tests[276]='sub t2 : lvalue; print qq/ok\n/'
fi
tests[277]='sub t2 : lvalue; print "ok"'
tests[2770]='format OUT =
bar ~~
.
open(OUT, ">/dev/null"); write(OUT); close OUT; print q(ok)'
tests[278]='my $ok; sub X::DESTROY { $ok = 1 } { my $x; BEGIN { $x = 42 } $x = bless {}, "X"; } print qq/ok\n/ if $ok;'
tests[279]='*TIESCALAR = sub {}; tie my $var => "main", 42; <${var}>; print qq/ok\n/'
tests[280]='my $z=0; my $li2="c"; my $rh={foo=>["ok"]}; print $rh->{"foo"}->[$li2+$z];'
tests[2800]='package M; $| = 1; sub DESTROY {eval {print "Farewell ",ref($_[0])};} package main; bless \$A::B, q{M}; *A:: = \*B::;'
result[2800]='Farewell M'
tests[2811]='"I like pie" =~ /(I) (like) (pie)/; "@-" eq  "0 0 2 7" and print "ok\n"; print "\@- = @-\n\@+ = @+\nlen \@- = ",scalar @-'
result[2811]='ok
@- = 0 0 2 7
@+ = 10 1 6 10
len @- = 4'
if [[ $v518 -gt 0 ]]; then
    tests[281]='# nested formats >5.18
open(NEST, ">Op_write.tmp");
format NEST =
@<<<
{
    my $birds = "birds";
    local *NEST = *BIRDS{FORMAT};
    write NEST;
    format BIRDS =
@<<<<<
$birds;
.
    "nest"
}
.
write NEST; close NEST;
print `cat Op_write.tmp`;'
    result[281]='birds
nest'
fi
tests[282]='use vars qw($glook $smek $foof); $glook = 3; $smek = 4; $foof = "halt and cool down"; my $rv = \*smek; *glook = $rv; my $pv = ""; $pv = \*smek; *foof = $pv; print "ok\n";'
tests[283]='#238 Undefined format "STDOUT"
format =
ok
.
write'
tests[2841]='#-O3 only
my $x="123456789";
format OUT =
^<<~~
$x
.
open OUT, ">ccode.tmp";
write(OUT);
close(OUT);
print `cat "ccode.tmp"`'
result[2841]='123
456
789'

# issue 287 with Inf and NaN
tests[2870]='my $i = "Inf" + 0; print $i <= 0 ? "not $i " : "", "ok\n";'
tests[2871]='my $i = "-Inf" + 0; print $i >= 0 ? "not $i " : "", "ok\n";'
tests[2872]='my $i = "NaN" + 0; print $i <= 0 ? "not $i " : "", "ok\n"'

tests[284]='use Encode; find_encoding("euc-jp") and print qq/ok\n/'
# mojibake
tests[288]='use utf8; package Ｄiᚪၚd_A; sub ᕘ { "A" } package Ｄiᚪၚd_B; our @ISA = ("Ｄiᚪၚd_A"); sub ᕘ { "B => " . (shift)->SUPER::ᕘ } package Ｄiᚪၚd_C; our @ISA = ("Ｄiᚪၚd_B"); sub ᕘ { "C => " . (shift)->SUPER::ᕘ } Ｄiᚪၚd_C->ᕘ eq "C => B => A" and print "ok";'
tests[289]='no warnings; sub z_zwap (&); print qq{ok\n} if eval q{sub z_zwap {return @_}; 1;}'
tests[2901]='sub f;print "ok" if exists &f && not defined &f;'
tests[290]='print "ok\n"if "IO::File" eq ref *STDOUT{IO}'
tests[293]='use Coro; print q(ok)'
tests[294]='#!perl -w
BEGIN { $SIG{__WARN__} = sub { my $s = shift; do { warn $s; die $s } if $s =~ qr{Constant subroutine.*redefined}i }; }
use File::Glob;
File::Glob->can("XXX")->() if $ENV{ABCD};
print qq/ok\n/'
if [[ $v518 -gt 0 ]]; then
  tests[295]='my @a = qw/ok/; my @to = (); s/(\w)(?{push @to, $1})/,$1,/g for @a; print "ok\n" if "@to" eq "o k";'
fi
tests[2950]='"zzaaabbb" =~ m/(a+)(b+)/ and print "@- : @+\n"'
result[2950]='2 2 5 : 8 5 8'
if [[ $v510 -gt 0 ]]; then
  tests[298]='
package D1; sub testmeth { "wrong" }
package C1; our @ISA = qw/D1/; sub testmeth { "right" }
package B1; our @ISA = qw/D1/;
package A1; use mro "c3"; our @ISA = qw/B1 C1/; sub testmeth { shift->next::method }
A1->testmeth() eq "right" and print "ok\n"'
fi
if [[ $v518 -gt 0 && $v524 -eq 0 ]]; then
  tests[299]='no warnings qw{experimental::lexical_topic}; my $s = "ok\n"; my $_ = "not ok\n"; my $r = $s =~ /ok(?{ print qq[$_] })/;'
fi
tests[2990]='#TODO version
package Pickup; use UNIVERSAL qw( VERSION ); print qq{ok\n} if VERSION "UNIVERSAL";'
tests[300]='format STDERR =
.
my $stdout = *STDOUT{IO};
my $stderr = *STDERR{FORMAT};
print ref($stdout).q/ || /.ref($stderr)'
result[300]='IO::File || FORMAT'
tests[3000]='use mro;print @{mro::get_linear_isa("mro")};'
result[3000]='mro'
tests[3010]='{ package A; use mro "c3";  sub foo { "A::foo" } } { package B; use base "A"; use mro "c3"; sub foo { (shift)->next::method() } } print qq{ok\n} if B->foo eq "A::foo";'
tests[301]='use utf8; use warnings; sub Ṩp맅싵Ş { "foo" } sub abcd { "bar" } my $w; $SIG{__WARN__} = sub { $w = $_[0] }; *{"Ṩp맅싵Ş"} = \&{"xyz"}; print "W1" if $w; $w = ""; *{"abcd"} = \&{"xyz"}; print "W2" if $w;'
result[301]="W1W2"
if [[ $v518 -gt 0 ]]; then
  tests[302]='use feature "say"; eval q{say "ok"}; print $@ if($@);'
  tests[304]='no warnings; use feature "lexical_subs"; my sub a; print qq/ok\n/'
  tests[305]='my $gen = sub { sub () { 8 } }; my $sub = &$gen; print qq/ok\n/'
fi
tests[3050]='use constant ASCII => eval { require Encode; Encode::find_encoding("ascii"); } || 0; print ASCII->encode("www.google.com")'
result[3050]='www.google.com'
tests[3051]='INIT{ sub ASCII { eval { require Encode; Encode::find_encoding("ASCII"); } || 0; }} print ASCII->encode("www.google.com")'
result[3051]='www.google.com'
tests[3052]='use Net::DNS::Resolver; my $res = Net::DNS::Resolver->new; $res->send("www.google.com"), print q(ok)'
tests[365]='use constant JP => eval { require Encode; Encode::find_encoding("euc-jp"); } || 0; print JP->encode("www.google.com")'
result[365]='www.google.com'
tests[306]='package foo; sub check_dol_slash { print ($/ eq "\n" ? "ok" : "not ok") ; print  "\n"} sub begin_local { local $/;} ; package main; BEGIN { foo::begin_local() }  foo::check_dol_slash();'
tests[308]='print (eval q{require Net::SSLeay;} ? qq{ok\n} : $@);'
tests[309]='#-O0 only
sub Regexp::DESTROY() { print qq/ok\n/ } my $rx = qr//; undef($rx)'
tests[3090]='print $_,": ",(eval q{require }.$_.q{;} ? qq{ok\n} : $@) for qw(Net::LibIDN Net::SSLeay);'
result[3090]='Net::LibIDN: ok
Net::SSLeay: ok'
tests[310]='package foo;
sub dada { my $line = <DATA> }
print dada;
__DATA__
ok
b
c
'
tests[312]='require Scalar::Util; eval "require List::Util"; print "ok"'
tests[314]='open FOO, ">", "ccode314.tmp"; print FOO "abc"; close FOO; open FOO, "<", "ccode314.tmp"; { local $/="b"; $in=<FOO>; if ($in eq "ab") { print "ok\n" } else { print qq(separator: "$/"\n\$/ is "$/"\nFAIL: "$in"\n)}}; unlink "ccode314.tmp"'
tests[3141]='open FOO, ">", "ccode3141.tmp"; print FOO "abc"; close FOO; open FOO, "<", "ccode3141.tmp"; { $/="b"; $in=<FOO>; if ($in eq "ab") { print "ok\n" } else { print qq(separator: "$/"\n\$/ is "$/"\nFAIL: "$in"\n)}}; unlink "ccode3141.tmp"'
tests[316]='
package Diamond_A; sub foo {};
package Diamond_B; use base "Diamond_A";
package Diamond_C; use base "Diamond_A";
package Diamond_D; use base ("Diamond_B", "Diamond_C"); use mro "c3";
package main; my $order = mro::get_linear_isa("Diamond_D");
              print $order->[3] eq "Diamond_A" ? "ok" : "not ok"; print "\n"'

tests[3170]='use Net::SSLeay();use IO::Socket::SSL();Net::SSLeay::OpenSSL_add_ssl_algorithms(); my $ssl_ctx = IO::Socket::SSL::SSL_Context->new(SSL_server => 1); print q(ok)'
tests[3180]='{ local $\ = "ok" ; print "" }'

if [[ $v518 -gt 0 ]]; then
  tests[317]='my $ok;
  sub kt { $ok = 1 }
  our $nested = qr/ (.) (??{ kt $1 }) /x;
  my $re = qr/^ ( (??{ $nested }) ) $ /x;
  "foo" =~ $re;
  print "ok\n" if $ok'
fi

tests[319]='#TODO Wide character warnings missing (bytes layer ignored)
use warnings q{utf8}; my $w; local $SIG{__WARN__} = sub { $w = $_[0] }; my $c = chr(300); open F, ">", "a"; binmode(F, ":bytes:"); print F $c,"\n"; close F; print $w'
if [[ $v518 -gt 0 ]]; then
    tests[318]='use utf8; ＬＯＯＰ: { last ＬＯＯＰ } print qq(ok\n)'
    tests[320]='use utf8; sub участники { print qq{ok\n} } $::{"участники"}->()'

    tests[321]='use utf8;
    {
        # illegal character for one identifier
       my $chr = "\N{POUND SIGN}";
       # commenting this eval make the test pass
       eval "\$$chr = 1;";
    }
    {
        my $i = 0x100;
        my $chr = chr($i);
        eval "my \$$chr = 42;";
        my $re = qr/^\p{_Perl_IDStart}$/;
        print qq/ok\n/ if $chr =~ $re;
    }'
fi
tests[3200]='#TODO No warnings reading in invalid utf8 stream (utf8 layer ignored)
use warnings "utf8"; local $SIG{__WARN__} = sub { $@ = shift }; open F, ">", "a"; binmode F; my ($chrE4, $chrF6) = (chr(0xE4), chr(0xF6)); print F "foo", $chrE4, "\n"; print F "foo", $chrF6, "\n"; close F; open F, "<:utf8", "a";  undef $@; my $line = <F>; print q(ok) if $@ =~ /utf8 "\xE4" does not map to Unicode/;'
tests[324]='package Master;
use mro "c3";
sub me { "Master" }
package Slave;
use mro "c3";
use base "Master";
sub me { "Slave of ".(shift)->next::method }
package main;
print Master->me()."\n";
print Slave->me()."\n";
'
result[324]='Master
Slave of Master'
tests[326]='
package Diamond_C; sub maybe { "Diamond_C::maybe" } package Diamond_D; use base "Diamond_C"; use mro "c3"; sub maybe { "Diamond_D::maybe => " . ((shift)->maybe::next::method() || 0) } package main; print "ok\n" if Diamond_D->maybe;'
tests[328]='#WONTFIX re-eval lex/global mixup
my $code = q[{$blah = 45}]; our $blah = 12; eval "/(?$code)/"; print "$blah\n"'
result[328]=45
# probably a duplicate of 295
tests[329]='#WONTFIX re-eval lex/global mixup
$_ = q{aaa}; my @res; pos = 1; s/\Ga(?{push @res, $_, $`})/xx/g; print "ok\n" if "$_ @res" eq "axxxx aaa a aaa aa"; print "$_ @res\n"'
result[329]='ok
axxxx aaa a aaa aa'
tests[330]='"\x{101}a" =~ qr/\x{100}/i && print "ok\n"'
tests[331]='package Count;sub getline {print "ok\n"};BEGIN { *The::Count:: = \*Count::; };exists &The::Count::getline ? The::Count->getline() : do {eval "require Devel::Peek;"; Dump(\%The::Count::)}'
tests[3310]='use 5.010; use charnames ":full"; my $char = q/\N{LATIN CAPITAL LETTER A WITH MACRON}/; my $a = eval qq ["$char"]; print length($a) == 1 ? "ok\n" : "$a\n".length($a)."\n"'
tests[332]='#TODO re-eval no_modify, probably WONTFIX
use re "eval"; our ( $x, $y, $z ) = 1..3; $x =~ qr/$x(?{ $y = $z++ })/; undef $@; print "ok\n"'
tests[333]='use encoding "utf8";
my @hiragana =  map {chr} ord("ぁ")..ord("ん"); my @katakana =  map {chr} ord("ァ")..ord("ン"); my $hiragana = join(q{} => @hiragana); my $katakana = join(q{} => @katakana); my %h2k; @h2k{@hiragana} = @katakana; $str = $hiragana; $str =~ s/([ぁ-ん])/$h2k{$1}/go; print $str eq $katakana ? "ok\n" : "not ok\n$hiragana\n$katakana\n";'
tests[335]='use POSIX (); print POSIX::M_SQRT2;'
result[335]='1.41421356237309'
tests[338]='use utf8; my $l = "ñ"; my $re = qr/ñ/; print $l =~ $re ? qq{ok\n} : length($l)."\n".ord($l)."\n";'
tests[340]='eval q/use Net::DNS/; my $new = "IO::Socket::INET6"->can("new") or die "die at new"; my $inet = $new->("IO::Socket::INET6", LocalAddr => q/localhost/, Proto => "udp", LocalPort => undef); print q(ok) if ref($inet) eq "IO::Socket::INET6";'
tests[342]='use IO::Socket::INET6 (); my $sock = IO::Socket::INET6->new( Blocking => 1, PeerAddr => q/127.0.0.1/, PeerPort => 22 ); print "ok\n";'
# used to fail in the inc-i340 branches CORE/base/lex.t 54
tests[3401]='sub foo::::::bar { print "ok\n"; } foo::::::bar;'
# wontfix on -O3: static string *end for "main::bar"
tests[345]='eval q/use Sub::Name; 1/ or die "no Sub::Name"; subname("main::bar", sub { 42 } ); print "ok\n";'
# those work fine:
tests[3451]='eval q/use Sub::Name; 1/ or die "no Sub::Name"; subname("bar", sub { 42 } ); print "ok\n";'
tests[3452]='eval q/use Sub::Name; 1/ or die "no Sub::Name"; $bar="main::bar"; subname($bar, sub { 42 } ); print "ok\n";'
tests[348]='package Foo::Bar; sub baz { 1 }
package Foo; sub new { bless {}, shift } sub method { print "ok\n"; }
package main; Foo::Bar::baz();
my $foo = sub {
  Foo->new
}->();
$foo->method;'
tests[350]='#TODO 5.18-5.22 dbg
package Foo::Moose; use Moose; has bar => (is => "rw", isa => "Int");
package main; my $moose = Foo::Moose->new; print "ok" if 32 == $moose->bar(32);'
tests[351]='{ BEGIN { *Mover:: = *Mover2::; *Mover2:: = *foo;} 
package Mover;
@ISA = "door"; sub door::dohtem { "dohtem" } print "ok\n";}'
tests[352]='package Foo;my $rand = 0;INIT { *reader = sub () { $rand };}
print qq/ok\n/;'
tests[354]='BEGIN { push @INC, "t"; }
use Ccode354i ();
my $token = { expansion => "abcd", };
print Ccode354i::check($token);'
tests[368]='use EV; print q(ok)'
tests[369]='
use EV;
use Coro;
use Coro::Timer;
my @a;
push @a, async {
  while() {
    warn $c++;
    Coro::Timer::sleep 1;
  };
};
push @a, async {
  while() {
    warn $d++;
    Coro::Timer::sleep 0.5;
  };
};
schedule;
print q(ok)'
tests[1960]='use EV; my $w = EV::timer 1, 1,sub{print"ok\n";exit}; EV::loop'
tests[371]='package foo;use Moose;
has "x" => (isa => "Int", is => "rw", required => 1);
has "y" => (isa => "Int", is => "rw", required => 1);
sub clear { my $self = shift; $self->x(0); $self->y(0); }
__PACKAGE__->meta->make_immutable;
package main;
my $f = foo->new( x => 5, y => 6);
print $f->x . "\n";'
result[371]='5'

if [[ $v518 -gt 0 ]]; then
  tests[372]='use utf8; require mro; my $f_gen = mro::get_pkg_gen('ᕘ'); undef %ᕘ::; mro::get_pkg_gen('ᕘ'); delete $::{"ᕘ::"}; print "ok";'
  tests[373]='package foo; BEGIN {undef %foo::} sub doof { caller(0) } print qq/ok\n/ if +(doof())[3] =~ qr/::doof/'
fi
tests[2050]='use utf8;package 텟ţ::ᴼ; sub ᴼ_or_Ḋ { "ok" } print ᴼ_or_Ḋ;'
tests[2051]='use utf8;package ƂƂƂƂ; sub ƟK { "ok" } package ƦƦƦƦ; use base "ƂƂƂƂ"; my $x = bless {}, "ƦƦƦƦ"; print $x->ƟK();'
tests[2052]='{ package Diӑmond_A; sub fಓ { "ok" } } { package Diӑmond_B; use base q{Diӑmond_A}; use mro "c3"; sub fಓ { (shift)->next::method() } } print Diӑmond_B->fಓ();'
# silly compiler warnings test, only usable with -q
tests[2053]='use strict; BEGIN { $SIG{__WARN__} = sub { die "Dying on warning: ", @_ } } print q{ok}'
# empty keys multideref
tests[2054]='my %h; $h{""} = q/boom/; print qq{ok\n}'
tests[2055]='our %h; $h{""} = q/boom/; print qq{ok\n}'
# GH issues:
tests[2790]='*TIESCALAR = sub {}; tie my $var => "main", 42; <${var}>; print qq/ok\n/'
tests[2230]='# 5.22 SEGV with missing gv_list[0] svop_list[0]
<*.*> and print qq{ok\n}'
tests[3060]='INIT { $SIG{__WARN__} = sub { die } } print "ok\n";'
tests[3061]='END { $SIG{__WARN__} = sub { die } } print "ok\n";'
tests[2191]='sub foo1 ($\@); eval q{ foo1 "s" }; print $@ =~ /^Not enough/ ? "ok" : "";'
tests[2192]='sub foo1 ($\%); eval q{ foo1 "s" }; print $@ =~ /^Not enough/ ? "ok" : "";'
tests[2193]='{local $^W = 1; my $warn = "";
local $SIG{__WARN__} = sub { $warn .= join("",@_) };
eval q(sub badproto4 (@ $b ar) { 1; });
print $warn =~ /Prototype after .@. for main::badproto4/ ? "ok" : $warn;}'
# GH 330
tests[3300]='#WONTFIX
*STDOUT; sub IO::Handle::self { $_[0] };
(*STDOUT->self . "") =~ m/^GLOB/ and print "ok\n"'
tests[3301]='#WORKAROUND 3300
IO::Handle->new if $ENV{none}; *STDOUT; sub IO::Handle::self { $_[0] };
(*STDOUT->self . "") =~ m/^GLOB/ and print "ok\n"'
tests[367]='#BROKEN since 5.22 (METHOP for binc)
use Math::BigInt;
my $x = Math::BigInt->new('1' x 20);
print "ok" if ++$x eq "11111111111111111112";'
tests[390]='print test(); print test();
sub test() {
    *test = sub ()  { "k" };
    "o";
}'
tests[391]='use warnings "closed"; eval "warn qq(\n); print qq(ok\n)";'
tests[400]='#TODO
use Class::XSAccessor constructor => "new", accessors => [ "foo" ];
my $o = main::->new( foo => "ok" );
print $o->foo,"\n";'
tests[4001]='require Class::XSAccessor;
Class::XSAccessor->import(constructor => "new", accessors => [ "foo" ]);
my $o = main::->new( foo => "ok" );
print $o->foo,"\n";'
tests[4002]='use Class::XSAccessor;
Class::XSAccessor->import(constructor => "new", accessors => [ "foo" ]);
my $o = main::->new( foo => "ok" );
print $o->foo,"\n";'
tests[411]='#TODO run-time regcomp of \p{}
our ( $q, $myre );
BEGIN { $q = qr[\p{IsWord}] }
eval q/$myre = qr[^$q]/; # add ^ to force the RegExp to be recompiled
print qq[ok\n] if q[hello] =~ $myre;'
tests[4111]='our ( $q, $myre );
BEGIN { $q = qr[\p{IsWord}] }
eval q/$myre = qr[$q]/; # this works
print qq[ok\n] if q[hello] =~ $myre;'

init

#
# getopts for -q -k -E -Du,-q -v -O2, -a -c -fro-inc
while getopts "XLhaAckoED:B:O:f:q" opt
do
  if [ "$opt" = "q" ]; then
    QUIET=1
    CCMD="$CCMD -q"
  fi
  if [ "$opt" = "o" ]; then Mblib=" "; init; fi
  if [ "$opt" = "c" ]; then CONT=1; fi
  if [ "$opt" = "k" ]; then KEEP=1; fi
  if [ "$opt" = "E" ]; then CPP=1; fi
  if [ "$opt" = "h" ]; then help; exit; fi
  # -D options: u,-q for quiet, no -D for verbose, -D- for no gcc warnings
  if [ "$opt" = "D" ]; then
    OCMD="$PERL $Mblib -MO=C,-D${OPTARG},"
    if [ $BASE = "testcc.sh" ]; then
        OCMD="$PERL $Mblib -MO=CC,-D${OPTARG},"
    fi
    if [ -z "${OPTARG/-/}" ]; then
        CCMD="$CCMD -d"
    fi
  fi
  # -B dynamic or -B static
  if [ "$opt" = "B" ]; then
    CCMD="$CCMD -B${OPTARG}"
  fi
  if [ "$opt" = "O" ]; then OPTIM="$OPTARG"; fi
  if [ "$opt" = "f" ]; then
    OCMD="$(echo $OCMD|sed -e "s/C,/C,-f$OPTARG,/")"
  fi
  if [ "$opt" = "a" ]; then # replace -Du, by -Do
    OCMD="$(echo $OCMD|sed -r -e 's/(-D.*)u,/\1o,/')"
  fi
  if [ "$opt" = "A" ]; then
      CCMD="$CCMD -DALLOW_PERL_OPTIONS"
  fi
  if [ "$opt" = "L" ]; then
    make_symlinks
    exit
  fi
  if [ "$opt" = "X" ]; then
    shift
    emit_test $1
    exit
  fi
done

if [ "$(perl -V:gccversion)" != "gccversion='';" ]; then
    if [ "$(uname)" = "xxDarwin" ]; then
	CCMD="$CCMD -g -fno-var-tracking"
    else
	CCMD="$CCMD -g3"
    fi
fi

if [ -z $OPTIM ]; then OPTIM=-1; fi # all

if [ -z "$QUIET" ]; then
    make
else
    # O from 5.6 does not support -qq
    qq="`$PERL -e'print (($] < 5.007) ? q() : q(-qq,))'`"
    # replace -D*,-v by -q
    OCMD="$(echo $OCMD    |sed -e 's/-D.*,//' -e 's/,-v,/,/' -e s/-MO=/-MO=$qq/)"
    OCMDO1="$(echo $OCMDO1|sed -e 's/-D.*,//' -e 's/,-v,/,/' -e s/-MO=/-MO=$qq/)"
    OCMDO2="$(echo $OCMDO2|sed -e 's/-D.*,//' -e 's/,-v,/,/' -e s/-MO=/-MO=$qq/)"
    OCMDO3="$(echo $OCMDO3|sed -e 's/-D.*,//' -e 's/,-v,/,/' -e s/-MO=/-MO=$qq/)"
    OCMDO4="$(echo $OCMDO4|sed -e 's/-D.*,//' -e 's/,-v,/,/' -e s/-MO=/-MO=$qq/)"
    # gnu make?
    make -s >/dev/null || make 2&>1 >/dev/null
fi

# need to shift the options
while [ -n "$1" -a "${1:0:1}" = "-" ]; do shift; done

if [ -n "$1" ]; then
  while [ -n "$1" ]; do
    ctest $1
    shift
  done
else
  for b in $(seq $ntests); do
    ctest $b
  done
  if [ $BASE = "testcc.sh" ]; then
    for b in $(seq 101 $(($ncctests+100))); do
      ctest $b
    done
  fi
fi

# 562  c:  15,25,27
# 58   c:  27,29_i
# 58  cc:  15,18,21,25,26_o,27,29
# 510  c:  15
# 510 cc:  11,15,29
# 511  c:  11,15,16,29

#  http://www.nntp.perl.org/group/perl.perl5.porters/2005/07/msg103315.html
#  FAIL for B::CC should be covered by test 18
