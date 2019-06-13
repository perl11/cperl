# test nested string evals


sub foo { 1 }
my $code = q{
    select(undef,undef,undef,0.2);
    foo();
    eval q{
        select(undef,undef,undef,0.2);
        foo();
        eval q{
            select(undef,undef,undef,0.2);
            foo();
        }
    }
};
eval $code;
