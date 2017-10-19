#!./perl
# mpb -Dx t/op/class1.t 2>&1 | grep -A1 Foo::
#BEGIN {
    #chdir 't' if -d 't';
    #require './test.pl';
#}
local($\, $", $,) = (undef, ' ', '');
print "1..5\n";
my $test = 1;

# compose role methods
role Foo2 {
  has $a = 1; # [7]
  method foo2 {
    print "ok $test # copied method\n"; $test++;
    print $a != 1       ? "not " : "", "ok ", $test++, " # role lex field\n";
    print $self->a != 1 ? "not " : "", "ok ", $test++, " # role meth field\n";
  }
}

role Foo3 {
  has $a3 = 2; # [2]
  has $b3 = 3; # [3]
}

eval q|class Bar3 does Foo3 does Foo2 {
  method test {
    $self->foo2;
    print $self->a  != 1 ? "not " : "", "ok ", $test++, " # copied role lex field\n";
    print $self->a3 != 2 ? "not " : "", "ok ", $test++, " # copied role meth field\n";
    print $self->b3 != 3 ? "not " : "", "ok ", $test++, " # copied role meth field\n";
  }
}|;

my $b_3 = new Bar3;
$b_3->test;
