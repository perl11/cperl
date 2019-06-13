# test sub name resolution
use Devel::NYTProf::Test qw(example_xsub);

# call XS sub directly
Devel::NYTProf::Test::example_xsub("foo");

# call XS sub imported into main
# (should still be reported as a call to Devel::NYTProf::Test::example_xsub)
example_xsub("foo");

# call XS sub as a method (ignore the extra arg)
Devel::NYTProf::Test->example_xsub();

# call XS sub as a method via subclass (ignore the extra arg)
@Subclass::ISA = qw(Devel::NYTProf::Test);
Subclass->example_xsub();

my $subname = "Devel::NYTProf::Test::example_xsub";
&$subname("foo");

# return from xsub call via an exception
# should correctly record the name of the xsub
sub will_die { die "foo\n" }
eval { example_xsub(0, \&will_die); 1; };
warn "\$@ was not the expected 'foo': $@" if $@ ne "foo\n";

# goto &$sub
sub launch { goto &$subname }
launch("foo");

# call builtin
wait();

# call builtin that exits via an exception
eval { open my $f, '<&', 'nonesuch' }; # $@ "Bad filehandle: nonesuch"
