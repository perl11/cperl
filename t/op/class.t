#!./perl
# mpb -Dx t/op/class.t 2>&1 | grep -A1 Foo::
BEGIN {
    #chdir 't' if -d 't';
    #require './test.pl';
}
local($\, $", $,) = (undef, ' ', '');
print "1..39\n";
my $test = 1;

# allow has hash fields (YAML::Mo)
my %h=(has,1);

class Foo {
  has $a = 0;
  has $b = 1;
  #method new         { bless [$a,$b], ref $self ? ref $self : $self }

  method meth1 {
    print "ok $test # Foo->meth1 w/ $self\n"; $test++; 
    $a + 1
  }
  multi method mul1 (Foo $self, Int $a) {
    print "ok $test # Foo->mul1\n"; $test++;
    $a * $b
  }
  # no multi dispatch yet
  #multi method mul1 (Int $a) { print "ok $test\n"; $test++; $self->a * $a }
  #multi method mul1 (Num $a) { $self->a * $a; print "ok $test\n"; $test++ }
  #multi method mul1 (Str $a) { $self->a . $a; print "ok $test\n"; $test++ }

  sub sub1 ($c)              { print "ok $test # Foo::sub1\n"; $test++; $a - $c }
}
print __PACKAGE__ ne 'main' ? "not " : "", "ok ", $test++," # curstash\n";

my $c = new Foo;
print ref $c ne "Foo" ? "not " : "", "ok ", $test++, " # ref \$c\n";
print ref Foo->new ne "Foo" ? "not " : "", "ok ", $test++, " # readonly name\n";
my $m = $c->meth1;
print $m != 1 ? "not " : "", "ok ", $test++, " # \$c->meth1\n";
$m = $c->mul1(0);
print $m != 0 ? "not " : "", "ok ", $test++, " # \$c->mul1\n";
print Foo::sub1(1) != -1 ? "not " : "", "ok ", $test++, " # sub1\n";
eval "Foo->sub1(1);";
print $@ =~ /Invalid method/ ? "" : "not ",
  "ok $test # class sub as method should error\n"; $test++;
eval "Foo::meth1('Foo');";
print $@ =~ /Invalid subroutine/ ? "" : "not ",
  "ok $test # class method as sub should error also\n"; $test++;

# created accessors
print $c->a != 0 ? "not " : "", "ok ", $test++, " # \$c->a read\n";
$c->a = 1;
print $c->a != 1 ? "not " : "", "ok ", $test++, " # \$c->a :lvalue write\n";

# allow class as methodname (B), deal with reserved names: method, class, multi
package Baz;
sub class { print "ok $test # Baz::class\n"; $test++ }
sub meth ($self) :method { print "ok $test # :method w/ self \n"; $test++ }
package main;
sub Bar::class { print "ok $test # Bar::class\n"; $test++ }
Bar::class();
Baz->class();
Bar->class();
Baz->meth();

# custom new
class Baz1 is Foo {}
print scalar @Baz1::ISA != 2 ? "not " : "", "ok ", $test++, " # \@Baz1::ISA\n";
print $Baz1::ISA[0] ne "Foo" ? "not " : "", "ok ", $test++, " # Foo\n";
print $Baz1::ISA[1] ne "Mu"  ? "not " : "", "ok ", $test++, " # Mu\n";
my $b = new Baz1;
print ref $b ne "Baz1" ? "not " : "", "ok ", $test++, " # ref \$b=",ref $b,"\n";
# compose fields
print !defined $b->a ? "not " : "", "ok ", $test++, " # \$b->a copied class w/ custom new\n";
$b->a = 1;
print $b->a != 1 ? "not " : "", "ok ", $test++, " # \$b->a = 1 copied\n";

# defaults. skipping over Foo1::new
role Foo1 { has $a = 0 }
class Baz2 is Foo1 {}
my $b1 = new Baz2;
# compose fields
print $b1->a != 0 ? "not " : "", "ok ", $test++, " # \$b1->a copied role\n";
$b1->a = 1;
print $b1->a != 1 ? "not " : "", "ok ", $test++, " # \$b1->a = 1 copied role\n";

class Baz3 { has @a; has %h; }
my Baz3 $b3 = new Baz3; # b3 must be typed, not inferred yet
$b3->a = (0,1);
print scalar $b3->a != 2 ? "not " : "", "ok ", $test++, " # array field\n";
#print $b3->a;
$b3->h = (has => "field");
print $b3->h != 1 ? "not " : "", "ok ", $test++, " # hash field\n";
#print scalar $b3->h, $b3->h;

# compose role methods #311
role Foo2 {
  has $a = 1;
  method foo2 {
    print "ok $test # copied method\n"; $test++;
    print $a != 1       ? "not " : "", "ok ", $test++, " # role lex field\n";
    print $self->a != 1 ? "not " : "", "ok ", $test++, " # role meth field\n";
  }
}
class Baz4 does Foo2 {
  method test {
    $self->foo2;
    # no lex field here
    print $self->a != 1 ? "not " : "", "ok ", $test++, " # class meth field\n";
  }
}
print "ok $test # parsed role composition\n"; $test++;
my $b4 = new Baz4;
if (1) {
  $b4->test; # type adjustment for does (copied roles)
  $b4->foo2;
} else {
  print "ok $test # TODO type adjustment for does (copied roles)\n"; $test++;
  print "ok $test #  -\"-\n"; $test++;
}

class Baz5 {
  has int $i;
}
use types 'strict'; # for easier $@ catching
my $b5;
eval { $b5 = new Baz5("wrong") };
my $typeerr = qr/^Type of arg \$i to Baz5 must be int \(not Str\)/;
my $typewarn = qr/^Type of arg \$i to Baz5 should be int \(not Str\)/;
print $@ =~ $typewarn ? "" : "not ", "ok ", $test++,
  " # compile-time typecheck Mu::new fields\n";
print $b5 && $b5->i ? "not " : "", "ok ", $test++, " # value\n";

eval { $b5 = new Baz5(1, "wrong"); }; #  arity check
print $@ =~ /Too many arguments for method / ? "" : "not ", "ok ", $test++,
  " # arity check Mu::new fields\n";
$@ = '';

my $xx = "wrong";
eval { $b5 = new Baz5($xx) };
print $@ =~ $typewarn ? "" : "not ", "ok ", $test++,
  " # run-time typecheck Mu::new fields\n";
print $b5 && $b5->i ? "not " : "", "ok ", $test++, " # value\n";

# used to crash with wrong padoffset [cperl #311]
role Foo3 {
  has $a3 = 2;
  has $b3 = 2;
}
class Bar3 does Foo3 does Foo2 { #a3 b3 a
  method test {
    $self->foo2;
    print $self->a  != 1 ? "not " : "", "ok ", $test++, " # copied role lex field\n";
    print $self->b3 != 2 ? "not " : "", "ok ", $test++, " # copied role meth field\n";
  }
}

my $b_3 = new Bar3;
my @b_f = $b_3->fields;
print @b_f == 3 ? "" : "not ", "ok $test # 3 fields composed\n"; $test++;
print $b_f[0]->name eq '$a3' ? "" : "not ", "ok $test # \$a3\n"; $test++;
print $b_f[1]->name eq '$b3' ? "" : "not ", "ok $test # \$b3\n"; $test++;
#print $b_f[2]->name eq '$a'  ? "" : "not ", "ok $test # \$a\n"; $test++;
# print "'",$_->name,",'" for @b_f;
$b_3->test;
