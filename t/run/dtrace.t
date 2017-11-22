#!./perl

my ($Perl, @dtrace);
my $lockfile = "dtrace.lock";

BEGIN {
    chdir 't' if -d 't';
    @INC = ('.', '../lib');
    require './test.pl';

    skip_all_without_config("usedtrace");

    @dtrace = ($Config::Config{dtrace});
    $Perl = which_perl();

    my $result = `@dtrace -V` or skip_all("@dtrace unavailable");
    #if ($ENV{TEST_JOBS} and int($ENV{TEST_JOBS}) > 1 and $^O eq 'darwin') {
      # interferes with fresh_perl => SEGV
      # skip_all("dtrace darwin with parallel testing. unset TEST_JOBS");
    #}

    $result = `@dtrace -qZnBEGIN -c'$Perl -e 1' 2>&1`;
    if ($? and $^O eq 'darwin') {
        if ($result =~ /dtrace: system integrity protection is on/) {
            skip_all("Workaround: csrutil disable; csrutil enable --without dtrace");
        }
        @dtrace = ('sudo','-n',@dtrace);
        $result = `@dtrace -qZnBEGIN -c'$Perl -e 1' 2>&1`;
    }
    $? &&
      skip_all("Apparently can't probe using @dtrace (perhaps you need root?): $result");
    if ($result =~ /dtrace: system integrity protection is on/) {
        skip_all("Workaround: csrutil disable; csrutil enable --without dtrace");
    }

    $lockfile = "dtrace.lock";
    -f $lockfile && sleep(5+rand()) &&
      skip_all("$lockfile exists. Tests cannot run concurrently");
    my $fh;
    open $fh, ">", $lockfile;
    print $fh $$;
    close $fh;
}
END { unlink $lockfile; }

use strict;
use warnings;

plan(tests => 9);

dtrace_like(
    '1',
    'BEGIN { trace(42+666) }',
    qr/708/,
    'really running DTrace',
);

dtrace_like(
    'package My;
        sub outer { Your::inner() }
     package Your;
        sub inner { }
     package Other;
        My::outer();
        Your::inner();',

    'perl$target:::sub-entry { printf("-> %s::%s at %s line %d!\n", copyinstr(arg3), copyinstr(arg0), copyinstr(arg1), arg2) }
     perl$target:::sub-return { printf("<- %s::%s at %s line %d!\n", copyinstr(arg3), copyinstr(arg0), copyinstr(arg1), arg2) }',

     qr/-> My::outer at tmp.* line 2!
-> Your::inner at tmp.* line 4!
<- Your::inner at tmp.* line 4!
<- My::outer at tmp.* line 2!
-> Your::inner at tmp.* line 4!
<- Your::inner at tmp.* line 4!/,

    'traced multiple function calls',
);

dtrace_like(
    '1',
    'perl$target:::phase-change { printf("%s -> %s; ", copyinstr(arg1), copyinstr(arg0)) }',
    qr/START -> RUN; RUN -> DESTRUCT;/,
    'phase changes of a simple script',
);

# this code taken from t/opbasic/magic_phase.t which tests all of the
# transitions of ${^GLOBAL_PHASE}. instead of printing (which will
# interact nondeterministically with the DTrace output), we increment
# an unused variable for side effects
dtrace_like(<< 'MAGIC_OP',
    my $x = 0;
    BEGIN { $x++ }
    CHECK { $x++ }
    INIT  { $x++ }
    sub Moo::DESTROY { $x++ }

    my $tiger = bless {}, Moo::;

    sub Kooh::DESTROY { $x++ }

    our $affe = bless {}, Kooh::;

    END { $x++ }
MAGIC_OP

    'perl$target:::phase-change { printf("%s -> %s; ", copyinstr(arg1), copyinstr(arg0)) }',

     qr/START -> CHECK; CHECK -> INIT; INIT -> RUN; RUN -> END; END -> DESTRUCT;/,

     'phase-changes in a script that exercises all of ${^GLOBAL_PHASE}',
);

dtrace_like(<< 'PHASES',
    my $x = 0;
    sub foo { $x++ }
    sub bar { $x++ }
    sub baz { $x++ }

    INIT { foo() }
    bar();
    END { baz() }
PHASES

    '
    BEGIN { starting = 1 }

    perl$target:::phase-change                            { phase    = copyinstr(arg0) }
    perl$target:::phase-change /copyinstr(arg0) == "RUN"/ { starting = 0 }
    perl$target:::phase-change /copyinstr(arg0) == "END"/ { ending   = 1 }

    perl$target:::sub-entry /copyinstr(arg0) != phase && (starting || ending)/ {
        printf("%s during %s; ", copyinstr(arg0), phase);
    }
    ',

     qr/foo during INIT; baz during END;/,

     'make sure sub-entry and phase-change interact well',
);

dtrace_like(<< 'PERL_SCRIPT',
    my $tmp = "foo";
    $tmp =~ s/f/b/;
    chop $tmp;
PERL_SCRIPT
    << 'D_SCRIPT',
    perl$target:::op-entry { printf("op-entry <%s>\n", copyinstr(arg0)) }
D_SCRIPT
    [
        qr/op-entry <subst>/,
        qr/op-entry <schop>/,
    ],
    'basic op probe',
);

if (is_miniperl()) {
  # dies when loading XSLoader
  ok(1, "SKIP miniperl");
  ok(1, "SKIP miniperl");
  exit;
}

my $tmp = tempfile();
open my $fh,'>',$tmp;
print $fh "42";
close $fh;

dtrace_like(<< "PERL_SCRIPT",
    BEGIN { \@INC = ('.', '../lib') }
    use vars;
    require HTTP::Tiny;
    do "./$tmp";
PERL_SCRIPT
    << 'D_SCRIPT',
    perl$target:::load-entry   { printf("load-entry <%s>\n", copyinstr(arg0)) }
    perl$target:::load-return  { printf("load-return <%s>\n", copyinstr(arg0)) }
D_SCRIPT
    [
      # the original test made sure that each file generated a load-entry then a load-return,
      # but that had a race condition when the kernel would push the perl process onto a different
      # CPU, so the DTrace output would appear out of order
      qr{load-entry <vars\.pm>.*load-entry <HTTP/Tiny\.pm>.*load-entry <\Q./$tmp\E>}s,
      qr{load-return <vars\.pm>.*load-return <HTTP/Tiny\.pm>.*load-return <\Q./$tmp\E>}s,
    ],
    'load-entry, load-return probes',
);
unlink $tmp;

sub dtrace_like {
    my ($perl, $probes, $expected, $name) = @_;
    my ($fh, $tmp, $src);
    $tmp = tempfile();
    $src = $tmp . ".pl";
    $tmp .= ".d";
    open $fh, ">", $tmp;
    print $fh $probes;
    close $fh;
    register_tempfile($tmp, $src);
    open $fh, ">", $src;
    print $fh $perl;
    close $fh;
    local $/;
    my $result = `@dtrace -q -s $tmp -c"$Perl $src"`;

    # make sure that dtrace is all done and successful
    my $child_exit_status = $? >> 8;
    unlink($tmp); unlink($src);
    if ($child_exit_status != 0) {
      ok(0, "DTrace error: $result");
      if (ref($expected) eq 'ARRAY') {
        shift @$expected;
        ok(0, "SKIP") for @$expected;
      }
      return;
    }

    undef $::TODO;
  TODO: {
      if ($name =~ / #TODO(.*)/) {
          $::TODO = $1 ? $1 : $^O;
          $name =~ s/ #TODO.*//;
      }
      if (ref($expected) eq 'ARRAY') {
        for (@$expected) {
          like($result, $_, $name)
            or diag($result);
        }
      }
      else {
        like($result, $expected, $name)
          or diag($result);
      }
    }
}

