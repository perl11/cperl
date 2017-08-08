#!perl
# Tests that all ops can be trapped by a Safe compartment

use Config;
BEGIN {
    if ($Config{'extensions'} !~ /\bOpcode\b/ && $Config{'osname'} ne 'VMS') {
        print "1..0 #  skipped: Opcode required\n"; exit 0;
    }
    if ($ENV{PERL_CORE}) {
      require "../../t/test.pl";
    }
}

use strict;
use Test::More;
use Safe;
use Opcode qw(opdesc full_opset opset_to_ops);

# Read the op names and descriptions directly from opcode.pl
my @op;
my %code;

while (<DATA>) {
    chomp;
    die "Can't match $_" unless /^([a-z_0-9]+)\s+(.*)/;
    $code{$1} = $2;
}
my $opcodes = '../../regen/opcodes';

if (-f $opcodes) {
  open my $fh, '<', $opcodes or die "Can't open $opcodes: $!";
  while (<$fh>) {
    chomp;
    next if !$_ or /^#/;
    #my ($op, $opname) = split /\t+/; # old code which led to an unreadable opcodes table
    my ($op, @split) = split(/\s+/, $_);
    my ($i, $desc) = (0, '');
    for (@split) {
      if (/^ck_/) { # collapse desc: find ck_
        $desc = join(" ", @split[0 .. $i-1]); last;
      }
      $i++
    }
    push @op, [$op, $desc, $code{$op}];
  }
  close $fh;
} else {
  my $i = 1;
  @op = map {[$_, opdesc($_), $code{$_}]} opset_to_ops(full_opset());
}

plan(tests => scalar @op + 3);

sub testop {
    my ($op, $opname, $code) = @_;
    pass("$op : skipped") and return if $code =~ /^SKIP/;
    pass("$op : skipped") and return if $code =~ m://|~~: && $] < 5.010;
    my $c = new Safe;
    $c->deny_only($op);
    $c->reval($code);
    like($@, qr/'\Q$opname\E' trapped by operation mask/, $op);
}

foreach (@op) {
    if ($_->[2]) {
	testop(@$_);
    } else {
	local our $TODO = "No test yet for $_->[0] ($_->[1])";
	fail();
    }
}

# Test also that the errors resulting from disallowed ops do not cause
# ‘Unbalanced’ warnings.
SKIP: {
    skip "no runperl, only for PERL_CORE",3 unless $ENV{PERL_CORE};

    local $ENV{PERL_DESTRUCT_LEVEL}=2;
    unlike
	runperl(
	    switches => [ '-MSafe', '-w' ],
	    prog     => 'Safe->new->reval(q(use strict))',
	    stderr   => 1,
	),
	qr/Unbalanced/,
	'No Unbalanced warnings when disallowing ops';
    unlike
	runperl(
	    switches => [ '-MSafe', '-w' ],
	    prog     => 'Safe->new->reval(q(use strict), 1)',
	    stderr   => 1,
	),
	qr/Unbalanced/,
	'No Unbalanced warnings when disallowing ops';
    unlike
	runperl(
	    switches => [ '-MSafe', '-w' ],
	    prog     => 'Safe->new->reval('
			. 'q(BEGIN{$^H{foo}=bar};use strict), 0'
			.')',
	    stderr   => 1,
	),
	qr/Unbalanced/,
	'No Unbalanced warnings when disallowing ops with %^H set';
}

# things that begin with SKIP are skipped, for various reasons (notably
# optree modified by the optimizer -- Safe checks are done before the
# optimizer modifies the optree)

__DATA__
null		SKIP
stub		SKIP
scalar		scalar $x
pushmark	print @x
wantarray	wantarray
const		42
gvsv		SKIP (set by optimizer) $x
gv		SKIP *x
gelem		*x{SCALAR}
padsv		SKIP my $x
padav		SKIP my @x
padhv		SKIP my %x
padany		SKIP (internal)
rv2gv		*x
rv2sv		$x
av2arylen	$#x
rv2cv		f()
anoncode	sub { }
prototype	prototype 'foo'
refgen		\($x,$y)
srefgen		SKIP \$x
ref		ref
bless		bless
backtick	qx/ls/
glob		<*.c>
readline	<FH>
rcatline	SKIP (set by optimizer) $x .= <F>
regcmaybe	SKIP (internal)
regcreset	SKIP (internal)
regcomp		SKIP (internal)
match		/foo/
qr		qr/foo/
subst		s/foo/bar/
substcont	SKIP (set by optimizer)
trans		y:z:t:
transr		SKIP y:z:t: (not yet)
sassign		$x = $y
aassign		@x = @y
chop		chop @foo
schop		chop
chomp		chomp @foo
schomp		chomp
defined		defined
undef		undef
study		study
pos		pos
preinc		++$i
i_preinc	SKIP (set by optimizer) my int $i; ++$i
predec		--$i
i_predec	SKIP (set by optimizer) my int $i; --$i
postinc		$i++
i_postinc	SKIP (set by optimizer) my int $i; $i++
postdec		$i--
i_postdec	SKIP (set by optimizer) my int $i; $i--
pow		$x ** $y
multiply	$x * $y
i_multiply	SKIP (set by optimizer) my int $x; $x * 2
divide		$x / $y
i_divide	SKIP (set by optimizer) my int $x; $x / 2
modulo		$x % $y
i_modulo	SKIP (set by optimizer) my int $x; $x % 2
repeat		$x x $y
add		$x + $y
i_add		SKIP (set by optimizer) my int $x; $x+1
subtract	$x - $y
i_subtract	SKIP (set by optimizer) my int $x; $x-1
concat		$x . $y
stringify	"$x"
left_shift	$x << 1
right_shift	$x >> 1
lt		$x < $y
i_lt		SKIP (set by optimizer) my int $x; $x < 1
gt		$x > $y
i_gt		SKIP (set by optimizer) my int $x; $x > 1
le		$i <= $y
i_le		SKIP (set by optimizer) my int $x; $x <= 1
ge		$i >= $y
i_ge		SKIP (set by optimizer) my int $x; $x >= 1
eq		$x == $y
i_eq		SKIP (set by optimizer) my int $x; $x == 1
ne		$x != $y
i_ne		SKIP (set by optimizer) my int $x; $x != 1
cmp		$i <=> $y
i_cmp		SKIP (set by optimizer) my int $x; $x <=> 1
s_lt		"$x" lt $y
s_gt		"$x" gt $y
s_le		"$x" le $y
s_ge		"$x" ge $y
s_eq		"$x" eq $y
s_ne		"$x" ne $y
s_cmp		"$x" cmp $y
bit_and		$x & $y
bit_xor		$x ^ $y
bit_or		$x | $y
i_bit_and	SKIP (set by optimizer) 0+$x & $y
i_bit_xor	SKIP (set by optimizer) 0+$x ^ $y
i_bit_or	SKIP (set by optimizer) 0+$x | $y
s_bit_and	SKIP (set by optimizer) "$x" & $y
s_bit_xor	SKIP (set by optimizer) "$x" ^ $y
s_bit_or	SKIP (set by optimizer) "$x" | $y
negate		-$x
i_negate	SKIP (set by optimizer) my int $x; -$x
not		!$x
int_not		SKIP (set by optimizer) my int $x; !$x
complement	~$x
i_complement	SKIP (set by optimizer) ~$x
s_complement	SKIP (set by optimizer) ~$x
smartmatch	no warnings 'experimental::smartmatch'; $x ~~ $y
atan2		atan2 1
sin		sin 1
cos		cos 1
rand		rand
srand           srand
exp             exp 1
log             log 1
sqrt            sqrt 1
int             int
hex             hex
oct             oct
abs             abs
box_int	        SKIP (set by optimizer) my int $i; $i+1
box_uint        SKIP (set by optimizer) my uint $i; $i+1
box_str	        SKIP (set by optimizer) my str $i; $i.""
box_num	        SKIP (set by optimizer) my num $i; $i+1.0
unbox_int       SKIP (set by optimizer) my int $i; $i+1
unbox_uint      SKIP (set by optimizer) my uint $i; $i+1
unbox_str       SKIP (set by optimizer) my str $i; $i.""
unbox_num       SKIP (set by optimizer) my num $i; $i+1.0
uint_left_shift	SKIP (set by optimizer)
uint_right_shift SKIP (set by optimizer)
uint_pow	SKIP (set by optimizer)
uint_complement	SKIP (set by optimizer)
int_preinc	SKIP (set by optimizer)
int_predec	SKIP (set by optimizer)
int_postinc	SKIP (set by optimizer)
int_postdec	SKIP (set by optimizer)
int_add		SKIP (set by optimizer)
int_subtract	SKIP (set by optimizer)
int_multiply	SKIP (set by optimizer)
int_divide	SKIP (set by optimizer)
int_modulo	SKIP (set by optimizer)
int_negate	SKIP (set by optimizer)
int_not		SKIP (set by optimizer)
int_abs		SKIP (set by optimizer)
int_lt		SKIP (set by optimizer)
int_gt		SKIP (set by optimizer)
int_le		SKIP (set by optimizer)
int_ge		SKIP (set by optimizer)
int_eq		SKIP (set by optimizer)
int_ne		SKIP (set by optimizer)
num_add		SKIP (set by optimizer)
num_subtract	SKIP (set by optimizer)
num_multiply	SKIP (set by optimizer)
num_divide	SKIP (set by optimizer)
num_atan2	SKIP (set by optimizer)
num_pow		SKIP (set by optimizer)
num_sin		SKIP (set by optimizer)
num_cos		SKIP (set by optimizer)
num_exp		SKIP (set by optimizer)
num_log		SKIP (set by optimizer)
num_sqrt	SKIP (set by optimizer)
length		length
substr		substr $x, 1
vec		vec
index		index
rindex		rindex
sprintf		sprintf '%s', 'foo'
formline	formline
ord		ord
chr		chr
crypt		crypt 'foo','bar'
ucfirst		ucfirst
lcfirst		lcfirst
uc		uc
lc		lc
quotemeta	quotemeta
rv2av		@a
aelemfast	SKIP (set by optimizer)
aelemfast_lex	SKIP (set by optimizer)
aelem		$a[1]
i_aelem		SKIP (set by optimizer)
int_aelem	SKIP (set by optimizer)
n_aelem		SKIP (set by optimizer)
num_aelem	SKIP (set by optimizer)
s_aelem		SKIP (set by optimizer)
str_aelem	SKIP (set by optimizer)
aslice		@a[1,2]
each		each %h
values		values %h
keys		keys %h
delete		delete $h{Key}
exists		exists $h{Key}
rv2hv		%h
helem		$h{kEy}
hslice		@h{kEy}
kvhslice	SKIP (not yet)
multiconcat	SKIP (set by optimizer)
multideref	SKIP (set by optimizer)
unpack		unpack
pack		pack
split		split /foo/
join		join $a, @b
list		@x = (1,2)
lslice		SKIP @x[1,2]
anonlist	[1,2]
anonhash	{ a => 1 }
splice		splice @x, 1, 2, 3
push		push @x, $x
pop		pop @x
shift		shift @x
unshift		unshift @x
sort		sort @x
reverse		reverse @x
grepstart	grep { $_ eq 'foo' } @x
grepwhile	SKIP grep { $_ eq 'foo' } @x
mapstart	map $_ + 1, @foo
mapwhile	SKIP (set by optimizer)
range		SKIP
flip		1..2
flop		1..2
and		$x && $y
or		$x || $y
xor		$x xor $y
cond_expr	$x ? 1 : 0
andassign	$x &&= $y
orassign	$x ||= $y
method		Foo->$x()
entersub	f()
enterxssub	SKIP (no dynamic loading)
leavesub	sub f{} f()
leavesublv	sub f:lvalue{return $x} f()
signature       sub f($a){$x} f()
caller		caller
warn		warn
die		die
reset		reset
lineseq		SKIP
nextstate	SKIP
dbstate		SKIP (needs debugger)
unstack		while(0){}
enter		SKIP
leave		SKIP
scope		SKIP
enteriter	SKIP
iter		SKIP
enterloop	SKIP
leaveloop	SKIP
return		return
last		last
next		next
redo		redo THIS
dump		dump
goto		goto THERE
exit		exit 0
open		open FOO
close		close FOO
pipe_op		pipe FOO,BAR
fileno		fileno FOO
umask		umask 0755, 'foo'
binmode		binmode FOO
tie		tie
untie		untie
tied		tied
dbmopen		dbmopen
dbmclose	dbmclose
sselect		SKIP (set by optimizer)
select		select FOO
getc		getc FOO
read		read FOO
enterwrite	write
leavewrite	SKIP
prtf		printf
print		print
sysopen		sysopen
sysseek		sysseek
sysread		sysread
syswrite	syswrite
send		send
recv		recv
eof		eof FOO
tell		tell
seek		seek FH, $pos, $whence
truncate	truncate FOO, 42
fcntl		fcntl
ioctl		ioctl
flock		flock FOO, 1
socket		socket
sockpair	socketpair
bind		bind
connect		connect
listen		listen
accept		accept
shutdown	shutdown
gsockopt	getsockopt
ssockopt	setsockopt
getsockname	getsockname
getpeername	getpeername
lstat		lstat FOO
stat		stat FOO
ftrread		-R
ftrwrite	-W
ftrexec		-X
fteread		-r
ftewrite	-w
fteexec		-x
ftis		-e
fteowned	SKIP -O
ftrowned	SKIP -o
ftzero		-z
ftsize		-s
ftmtime		-M
ftatime		-A
ftctime		-C
ftsock		-S
ftchr		-c
ftblk		-b
ftfile		-f
ftdir		-d
ftpipe		-p
ftlink		-l
ftsuid		-u
ftsgid		-g
ftsvtx		-k
fttty		-t
fttext		-T
ftbinary	-B
chdir		chdir '/'
chown		chown
chroot		chroot
unlink		unlink 'foo'
chmod		chmod 511, 'foo'
utime		utime
rename		rename 'foo', 'bar'
link		link 'foo', 'bar'
symlink		symlink 'foo', 'bar'
readlink	readlink 'foo'
mkdir		mkdir 'foo'
rmdir		rmdir 'foo'
open_dir	opendir DIR
readdir		readdir DIR
telldir		telldir DIR
seekdir		seekdir DIR, $pos
rewinddir	rewinddir DIR
closedir	closedir DIR
fork		fork
wait		wait
waitpid		waitpid
system		system
exec		exec
kill		kill
getppid		getppid
getpgrp		getpgrp
setpgrp		setpgrp
getpriority	getpriority
setpriority	setpriority
time		time
tms		times
localtime	localtime
gmtime		gmtime
alarm		alarm
sleep		sleep 1
shmget		shmget
shmctl		shmctl
shmread		shmread
shmwrite	shmwrite
msgget		msgget
msgctl		msgctl
msgsnd		msgsnd
msgrcv		msgrcv
semget		semget
semctl		semctl
semop		semop
require		use strict
dofile		do 'file'
hintseval	SKIP eval "1+1"
entereval	eval "1+1"
leaveeval	eval "1+1"
entertry	SKIP eval { 1+1 }
leavetry	SKIP eval { 1+1 }
ghbyname	gethostbyname 'foo'
ghbyaddr	gethostbyaddr 'foo'
ghostent	gethostent
gnbyname	getnetbyname 'foo'
gnbyaddr	getnetbyaddr 'foo'
gnetent		getnetent
gpbyname	getprotobyname 'foo'
gpbynumber	getprotobynumber 42
gprotoent	getprotoent
gsbyname	getservbyname 'name', 'proto'
gsbyport	getservbyport 'a', 'b'
gservent	getservent
shostent	sethostent
snetent		setnetent
sprotoent	setprotoent
sservent	setservent
ehostent	endhostent
enetent		endnetent
eprotoent	endprotoent
eservent	endservent
gpwnam		getpwnam
gpwuid		getpwuid
gpwent		getpwent
spwent		setpwent
epwent		endpwent
ggrnam		getgrnam
ggrgid		getgrgid
ggrent		getgrent
sgrent		setgrent
egrent		endgrent
getlogin	getlogin
syscall		syscall
lock		SKIP
setstate	SKIP
method_named	$x->y()
method_super	SKIP (not yet)
method_redir	SKIP (not yet)
method_redir_super SKIP (not yet)
entergiven	SKIP (not yet)
leavegiven	SKIP (not yet)
enterwhen	SKIP (not yet)
leavewhen	SKIP (not yet)
break		SKIP (not yet)
continue	SKIP (not yet)
dor		$x // $y
dorassign	$x //= $y
once		SKIP {use feature 'state'; state $foo = 42;}
say		SKIP {use feature 'say'; say "foo";}
aeach		SKIP each @t
akeys		SKIP keys @t
avalues		SKIP values @t
custom		SKIP (no way)
coreargs       	SKIP (not yet)
runcv		SKIP (not yet)
fc		SKIP (not yet)
padcv		SKIP (not yet)
introcv		SKIP my sub x {$x} x()
clonecv		SKIP my sub x {$x} x()
padrange	SKIP (not yet)
refassign	SKIP (not yet)
lvref		SKIP (not yet)
lvrefslice     	SKIP (not yet)
lvavref     	SKIP (not yet)
anonconst 	SKIP (not yet)
