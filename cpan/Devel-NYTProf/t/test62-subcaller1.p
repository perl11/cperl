# test determination of subroutine caller in unusual cases

# test dying from an xsub
require Devel::NYTProf::Test;
eval { Devel::NYTProf::Test::example_xsub(0, "die") };

# test dying from an xsub where the surrounding eval is an
# argument to a sub call. This used to coredump.
sub sub1 { $_[0] }
sub1 eval { Devel::NYTProf::Test::example_xsub(0, "die") };

# test sub calls (xs and perl) from within a sort block
sub sub2 { $_[0] }
# sort block on one line due to change to line numbering in perl 5.21
my @a = sort { Devel::NYTProf::Test::example_xsub(); sub2($a) <=> sub2($b); } (1,3,2);

# test sub call as a sort block
sub sub3 { $_[0] } # XXX not recorded due to limitation of perl
my @b = sort \&sub3, 3, 1, 2;

# test sub call from a subst
sub sub4 { $_[0] }
my $a = "abcbd";
$a =~ s/b/sub4(uc($1))/ge;

exit 0;
