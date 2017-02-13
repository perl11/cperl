#!./perl

use strict;
use warnings;

require q(./test.pl); plan(tests => 7);

=pod

This tests the classic diamond inheritance pattern.

   <A>
  /   \
<B>   <C>
  \   /
   <D>

=cut

{
    package Diamond_A;
    sub hello { 'Diamond_A::hello' }
}
{
    package Diamond_B;
    use base 'Diamond_A';
}
{
    package Diamond_C;
    use base 'Diamond_A';     
    
    sub hello { 'Diamond_C::hello' }
}
{
    package Diamond_D;
    use base ('Diamond_B', 'Diamond_C');
    use mro 'c3';
}

ok(eq_array(
    mro::get_linear_isa('Diamond_D'),
    [ qw(Diamond_D Diamond_B Diamond_C Diamond_A) ]
), '... got the right MRO for Diamond_D');

is(Diamond_D->hello, 'Diamond_C::hello', '... method resolved itself as expected');
is(Diamond_D->can('hello')->(), 'Diamond_C::hello', '... can(method) resolved itself as expected');
is(UNIVERSAL::can("Diamond_D", 'hello')->(), 'Diamond_C::hello', '... can(method) resolved itself as expected');

# clearing @ISA in different ways [cperl #251]
{
    no warnings 'uninitialized';
    {
        package ISACLEAR;
        our @ISA = qw/XX YY ZZ/;
        mro::set_mro("ISACLEAR", "c3");
    }
    # baseline
    ok(eq_array(mro::get_linear_isa('ISACLEAR'),[qw/ISACLEAR XX YY ZZ/]));

    # this looks dumb, but it preserves existing behavior for compatibility
    #  (undefined @ISA elements treated as "main")
    # c3 merge still buggy.
    $ISACLEAR::ISA[1] = undef;
    local $::TODO = "c3 merge with deleted entries [cperl #251]";
    ok(eq_array(mro::get_linear_isa('ISACLEAR'),[qw/ISACLEAR XX main ZZ/]))
      or diag("'".join("' '",@{mro::get_linear_isa('ISACLEAR')})."'");
    undef $::TODO;

    # undef the array itself
    undef @ISACLEAR::ISA;
    ok(eq_array(mro::get_linear_isa('ISACLEAR'),[qw/ISACLEAR/]));
}
