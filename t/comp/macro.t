#!./perl

BEGIN {
    @INC = qw(. ../lib);
    chdir 't' if -d 't';
}

use experimental 'macros';
print "1..14\n";

macro checkpoint {
    state $n;
    my $i = ++$n;
    quasi { print "ok $i\n"; }
}

checkpoint;
checkpoint for (0..1);
checkpoint;

sub LOGGING () { 1 }

macro LOG($message) {
  if (LOGGING) {
    quasi { print `$message` };
  }
}

macro moo() {
    my $x = "inside macro";
    return quasi { print($x) };
}
my $x = "outside macro";
moo();    # inside macro

{   # macro called like a sub
    my $macro_visits;

    macro dasher() {
        $macro_visits++;
        quasi {}
    }

    dasher();
    is $macro_visits, 2, "calls to macro are at parse time";
    dasher();

    my $total_args;
    macro dancer($a, $b?) {
        $total_args++ if defined $a;
        $total_args++ if defined $b;
        quasi {}
    }

    dancer(17);
    is $total_args, 3, "macro call with arguments works";
    dancer(15, 10);
}

{   # macro called like a list prefix
    my $macro_visits;

    macro prancer() {
        $macro_visits++;
        quasi {}
    }

    prancer;
    is $macro_visits, 2, "macro calls without parens work";
    prancer;

    my $total_args;
    macro vixen($a, $b?) {
        $total_args++ if defined $a;
        $total_args++ if defined $b;
        quasi {}
    }

    vixen 17;
    is $total_args, 3, "macro call with arguments works";
    vixen 15, 10;
}

{
    macro comet :infix ($rhs, $lhs) {   #OK not used
        quasi { "comet!" }
    }

    my $result = 1 comet 2;
    is $result, "comet!", "can define an entirely new operator";
}

{
    macro '+' :infix ($rhs, $lhs) {
        quasi { "chickpeas" }
    }

    my $result = "grasshopper" + "motor oil";
    is $result, "chickpeas", "can shadow an existing operator";
}

{
    macro cupid {
        my $a = "I'm cupid!";
        quasi { $a }
    }

    my $result = cupid;
    is $result, "I'm cupid!", "lexical lookup from quasi to macro works";
}

#?rakudo.jvm skip "Method 'succ' not found RT #124967"
#?rakudo.moar skip "No such method 'STORE' for invocant of type 'Mu' RT #124968"
{
    my $counter = 0;

    macro donner {
        quasi { ++$counter }
    }

    is donner, 1, "lexical lookup from quasi to outside macro works";
    is donner, 2, "...twice";
}

{
    macro blitzen($param) {
        quasi { $param }
    }

    ok blitzen("onwards") ~~ AST, # XXX perl6 smartmatch
        "lexical lookup from quasi to macro params works";
}

{
    macro id($param) { $param };
    is id('x'), 'x', 'macro can return its param';
}

{
    macro funny_nil { quasi { {;}() } }
    is funny_nil(), Nil, 'Nil from an empty block turns into no code';
}

{   # RT #115500
    macro rt115500v1() {
        my $q1 = quasi { 6 };
        my $q2 = quasi { 6 * 10 };
        quasi { `$q1` + `$q2` }
    };
    is rt115500v1(), 66,
        'addition of two quasis with arithmetical expressions works (1)';
    macro rt115500v2() {
        my $q1 = quasi { 5 + 1 };
        my $q2 = quasi { 6 * 10 };
        quasi { `$q1` + `$q2` }
    };
    is rt115500v2(), 66,
        'addition of two quasis with arithmetical expressions works (2)';
}

{   # simplest possible unquote splicing
    my $unquote_splicings;
    BEGIN { $unquote_splicings = 0 }; # so it's not Any() if it doesn't work

    macro planck($x) {
        quasi { `$unquote_splicings++; $x` }
    }

    planck "length";
    is $unquote_splicings, 1, "spliced code runs at parse time";
}

{   # building an AST from smaller ones
    macro bohr() {
        my $q1 = quasi { 6 };
        my $q2 = quasi { 6 * 10 };
        my $q3 = quasi { 100 + 200 + 300 };
        quasi { `$q1` + `$q2` + `$q3` }
    }

    is bohr(), 666, "building quasis from smaller quasis works";
}

{   # building an AST incrementally
    macro einstein() {
        my $q = quasi { 2 };
        $q = quasi { 1 + `$q` };
        $q = quasi { 1 + `$q` };
        $q;
    }

    is einstein(), 4, "can build ASTs incrementally";
}

{   # building an AST incrementally in a for loop
    macro podolsky() {
        my $q = quasi { 2 };
        $q = quasi { 1 + `$q` } for 0..2;
        $q;
    }

    is podolsky(), 4, "can build ASTs in a for loop";
}

{   # using the mainline context from an unquote
    macro rosen($code) {
        my $paradox = "this shouldn't happen";
        quasi {
            `$code`();
        }
    }

    my $paradox = "EPR";
    is rosen(sub { $paradox }), "EPR", "unquotes retain their lexical context";
}

{   # unquotes must evaluate to ASTs
    throws_like 'macro bohm() { quasi { `"not an AST"` } }; bohm',
                X::TypeCheck::Splice,
                got      => Str,
                expected => AST,
                action   => 'unquote evaluation',
                line     => 1;
}

{   # RT #122746
    macro '!!' :postfix ($o) {
        quasi {
            die "Null check failed for ", "$o" unless defined `$o`;
            `$o`;
        }
    };
    my $cookies;
    throws_like { $cookies!!; }, Exception,
        message => 'Null check failed for $cookies';
}

# Tests for macros which return quasi but do not do splicing

macro four () { quasi { 2+2 } }
is(four, 4, "macro returning quasi");

{
    macro hi () { quasi :COMPILING { "hello $s" } }

    macro hey () { ({ "hello $^s" }->body) }

    my $s="world";
    is(hi(),"hello world","macros can bind in caller's lexical env");

    $s="paradise";
    is(hi(),"hello paradise","macros but it's a binding only");
    is(hey(),"hello paradise","macros but it's a binding only");
}

{
    my $x;
    macro noop ()  { $x = "Nothing happened"; quasi { } }
    noop();

    is($x,"Nothing happened", "Macros can return noops");
}

{
    macro hygienic ($ast) {
        my $x = 3;
        quasi { $x + `$ast` }
    }
    my $x = 4;
    is hygienic($x), 7, 'lexical vars in macros are not visible to the AST vars';
}
