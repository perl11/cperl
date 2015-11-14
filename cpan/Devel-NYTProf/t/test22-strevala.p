# test merging of anon subs from evals

my $code = qq{ sub { print "sub called\n" } $Devel::NYTProf::StrEvalTestPad};

# call once from particular line
eval($code)->();

# call twice from the same line
eval($code)->(); eval($code)->();

# called from inside a string eval
eval q{
    eval($code)->(); eval($code)->();
};
