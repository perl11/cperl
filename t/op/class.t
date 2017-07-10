#!./perl
# mpb -Dx t/op/class.t 2>&1 | grep -A1 Foo::
BEGIN {
    #chdir 't' if -d 't';
    #require './test.pl';
}
local($\, $", $,) = (undef, ' ', '');
print "1..16\n";
my $test = 1;

class Foo {
  has $a = 0;
  has $b = 1;
  method a($v?)       { if (defined $v) { $a = $v } else { $a } }
  method new          { bless [$a], ref $self ? ref $self : $self }

  method meth1 {
    print "ok $test\n"; $test++; 
    $a + 1
  }
  multi method mul1 (Foo $self, Int $a) {
    print "ok $test\n"; $test++;
    $a * $b
  }
  # no multi dispatch yet
  #multi method mul1 (Int $a) { print "ok $test\n"; $test++; $self->a * $a }
  #multi method mul1 (Num $a) { $self->a * $a; print "ok $test\n"; $test++ }
  #multi method mul1 (Str $a) { $self->a . $a; print "ok $test\n"; $test++ }

  sub sub1 ($b)              { print "ok $test\n"; $test++; Foo->a - $b }
}
print __PACKAGE__ ne 'main' ? "not " : "", "ok ", $test++," # curstash\n";

my $c = new Foo;
print ref $c ne "Foo" ? "not " : "", "ok ", $test++, " # ref \$c\n";
print ref Foo->new ne "Foo" ? "not " : "", "ok ", $test++, " # readonly name\n";
$c->meth1;
$c->mul1(0);
Foo::sub1(1);
eval "Foo->sub1(1);";
print $@ =~ /Invalid method/ ? "" : "not ",
  "ok $test # class sub as method should error\n"; $test++;
eval "Foo::meth1('Foo');";
print $@ =~ /Invalid subroutine/ ? "" : "not ",
  "ok $test # class method as sub should error also\n"; $test++;

# allow class as methodname (B), deal with reserved names: method, class, multi
package Baz;
sub class { print "ok $test\n"; $test++ }
package main;
sub Bar::class { print "ok $test\n"; $test++ }
Bar::class();
Baz->class();
Bar->class();

# custom new
class Baz1 is Foo {}
print scalar @Baz1::ISA != 2 ? "not " : "", "ok ", $test++, " # \@Baz1::ISA\n";
print $Baz1::ISA[0] ne "Foo" ? "not " : "", "ok ", $test++, "\n";
print $Baz1::ISA[1] ne "Mu"  ? "not " : "", "ok ", $test++, "\n";
my $b = new Baz1;
print ref $b ne "Baz1" ? "not " : "", "ok ", $test++, " # ref \$b=",ref $b,"\n";
# TODO compose fields
print $b->a == 0 ? "not " : "", "ok ", $test++, " #TODO \$b->a\n";
#$b->a(1);
#print $b->a == 1 ? "not " : "", "ok ", $test++, " # \$b->a(1)\n";

# defaults. skipping over Foo1::new
class Foo1 { has $a = 0 }
class Baz2 is Foo1 {}
my $b1 = new Baz2;
# TODO compose fields
#print $b1->a == 0 ? "not " : "", "ok ", $test++, " #TODO \$b1->a\n";
#$b1->a(1);
#print $b1->a == 1 ? "not " : "", "ok ", $test++, " #TODO \$b1->a(1)\n";

