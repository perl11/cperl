#!./perl
# compose role methods #311: currently fails
role Foo3 {
  has $a3 = 2;
  has $b3 = 2;
}
class Bar3 does Foo3 does Foo2 { #a3 b3 a
  method test {
    $self->foo2;
    print $self->a  != 1 ? "not " : "", "ok ", $test++, " # copied role field\n";
    print $self->b3 != 2 ? "not " : "", "ok ", $test++, " # copied role field\n";
  }
}
