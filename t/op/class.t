#!./perl
# mpb -Dx t/op/class.t 2>&1 | grep -A1 Foo::
BEGIN {
    #chdir 't' if -d 't';
    #require './test.pl';
}

class Foo {
  #has a = 0;
  method meth1        {$self->a + 1}
  multi mul1 (Int $a) {$self->a * $a}
  #multi mul1 (Num $a) {$self->a * $a}
  #multi mul1 (Str $a) {$self->a . $a}
  sub sub1 ($b)       {$b + 1}
}
