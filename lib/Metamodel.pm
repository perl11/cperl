# perl6 MOP for cperl. NYI

=pod

=head1 NAME

Metamodel - Metaobject representing a cperl class

=head1 SYNOPSIS

  ...

=head1 DESCRIPTION

See L<https://docs.perl6.org/type/Metamodel::ClassHOW>

=head1 ROLES

See F<lib/Metamodel.pm>

=cut

role Metamodel::Naming {
  method name {}
  method set_name {}
}
role Metamodel::AttributeContainer {
  method add_attribute {}
  method attributes {}
  method set_rw {}
  method rw {}
}
role Metamodel::Finalization {
  method setup_finalization {}
  method destroyers {}
}
role Metamodel::MethodContainer {
  method add_method {}
  method methods {}
  method method_table {}
  method lookup {}
}
role Metamodel::PrivateMethodContainer {
  method add_private_method {}
  method private_method_table {}
}
role Metamodel::RoleContainer {
  method add_role {}
  method roles_to_compose {}
}
role Metamodel::MultipleInheritance {
  method add_parent {}
  method parents {}
  method hides {}
  method hidden {}
  method set_hidden {}
}
role Metamodel::MROBasedMethodDispatch {
  method find_method {}
  method find_method_qualified {}
}
role Metamodel::Trusting {
  method add_trustee {}
  method trusts {}
  method is_trusted {}
}

=head1 CLASSES

=head2 Metamodel::ClassHOW

Metamodel::ClassHOW is the meta class behind the class keyword.
See L<https://docs.perl6.org/type/Metamodel::ClassHOW>

=cut

class Metamodel::ClassHOW
  does Metamodel::Naming
  #does Metamodel::Documenting
  #does Metamodel::Versioning
  #does Metamodel::Stashing
  does Metamodel::AttributeContainer
  does Metamodel::MethodContainer
  does Metamodel::PrivateMethodContainer
  #does Metamodel::MultiMethodContainer
  does Metamodel::RoleContainer
  does Metamodel::MultipleInheritance
  #does Metamodel::DefaultParent
  #does Metamodel::C3MRO
  does Metamodel::MROBasedMethodDispatch
  #does Metamodel::MROBasedTypeChecking
  does Metamodel::Trusting
  #does Metamodel::BUILDPLAN
  #does Metamodel::Mixins
  #does Metamodel::ArrayType
  #does Metamodel::BoolificationProtocol
  #does Metamodel::REPRComposeProtocol
  #does Metamodel::InvocationProtocol
  does Metamodel::Finalization
{
  method add_fallback {}
  method can {}
  method lookup {}
  method compose {}
}

=head3 METHODS

=over 4

=item Metamodel::ClassHOW->add_fallback

=item Metamodel::ClassHOW->can

=item Metamodel::ClassHOW->lookup

=item Metamodel::ClassHOW->compose

=back

=cut
