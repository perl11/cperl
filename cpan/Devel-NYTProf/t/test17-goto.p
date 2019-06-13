# test various forms of goto

# simple in-line goto

goto main_label;
die "should not get here";
main_label:;

sub other { } # stub for checking sub caller info

# goto &sub

sub origin {
    other();
    goto &destination;
}

sub destination {
    other();
}

origin();

# goto out of a sub

sub bar {
    goto foo_label;
}

sub foo {
    bar();
    foo_label:;
}

foo();
