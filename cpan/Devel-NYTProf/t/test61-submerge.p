# test merging of sub info and sub callers
# which is applied to, e.g., anon subs inside evals

sub foo { print "foo @_\n" }

my $code = qq{ sub { foo() } $Devel::NYTProf::StrEvalTestPad};

eval($code)->(); eval($code)->(); eval($code)->();
