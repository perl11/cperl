sub recurs {
    my $depth = shift;
    select(undef, undef, undef, 0.3);
    recurs($depth-1) if $depth > 1;
}

recurs(3); # recurs gets called twice
    
