#!./perl
# mpb -Dx t/op/class.t 2>&1 | grep -A1 Foo::
BEGIN {
    #chdir 't' if -d 't';
    #require './test.pl';
}
local($\, $", $,) = (undef, ' ', '');
print "1..24\n";
my $test = 1;

class Foo {
  has $a = 0;
  has $b = 1;
  #method new         { bless [$a,$b], ref $self ? ref $self : $self }

  method meth1 {
    print "ok $test # Foo->meth1\n"; $test++; 
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
package main;
sub Bar::class { print "ok $test # Bar::class\n"; $test++ }
Bar::class();
Baz->class();
Bar->class();

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

