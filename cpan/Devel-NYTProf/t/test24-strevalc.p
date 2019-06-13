# test 'collapsing' of string evals
my @src = (
    (("1+1")            x 2),
    (("eval '1+1'")     x 2),
    (("sub { 1 }->()")  x 2),
);
for my $src (@src) {
    eval $src;
}
