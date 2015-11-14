sub foo {
    eval "shift;
          shift;
          bar();";
}

sub bar {
    eval '$a = 10_001; while (--$a) { ++$b }';
}

foo();
foo();
bar();
