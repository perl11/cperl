#!/usr/bin/perl -w

use strict;
local($\, $", $,) = (undef, ' ', '');
print "1..31\n";
my $test = 1;

#use Test::More tests => 1;
# BEGIN { use_ok('fields'); }

class Foo {
    has $foo;
    has @bar;
    has %baz :const;
}
my @cf = Foo->fields;
print @cf != 3 ? "not " : "", "ok ", $test++, " # 3 class->fields =",scalar @cf,"\n";
print ref $cf[0] ne "fields" ? "not " : "", "ok ", $test++, " # ref \$cf[0]\n";
print $cf[0]->name ne '$foo' ? "not " : "", "ok ", $test++, " # name\n";
print $cf[1]->name ne '@bar' ? "not " : "", "ok ", $test++, " # name\n";
print $cf[2]->name ne '%baz' ? "not " : "", "ok ", $test++, " # name\n";
print $cf[0]->package ne 'Foo' ? "not " : "", "ok ", $test++, " # package\n";
print defined($cf[0]->type) ? "not " : "", "ok ", $test++, " # type\n";
print $cf[0]->const ? "not " : "", "ok ", $test++, " # const\n";
print $cf[2]->const ? "" : "not ", "ok ", $test++, " # const\n";

my $o = new Foo;
my @of = $o->fields;
print @of != 3 ? "not " : "", "ok ", $test++, " # 3 \$obj->fields\n";
print ref $of[0] ne "fields" ? "not " : "", "ok ", $test++, " # ref \$of[0]\n";
print $of[0]->name ne '$foo' ? "not " : "", "ok ", $test++, " # name\n";
print $of[2]->name ne '%baz' ? "not " : "", "ok ", $test++, " # name\n";
print $of[0]->package ne 'Foo' ? "not " : "", "ok ", $test++, " # package\n";
print defined($of[0]->type) ? "not " : "", "ok ", $test++, " # type\n";
print $of[0]->const ? "not " : "", "ok ", $test++, " # const\n";
print $of[2]->const ? "" : "not ", "ok ", $test++, " # const\n";
print defined($of[0]->get_value) ? "not " : "", "ok ", $test++, " # get_value\n";

class Foo1 {
    has int $foo = 1;
    has Str $bar = "xx";
    has Num $baz :const = 1.0;
}
@cf = Foo1->fields;
print $cf[0]->type ne 'int' ? "not " : "", "ok ", $test++, " # type\n";
print $cf[1]->type ne 'Str' ? "not " : "", "ok ", $test++, " # type\n";
print $cf[2]->type ne 'Num' ? "not " : "", "ok ", $test++, " # type\n";
print $cf[0]->const ? "not " : "", "ok ", $test++, " # const\n";
print $cf[2]->const ? "" : "not ", "ok ", $test++, " # const\n";
#print $cf[0]->get_value != 1    ? "not " : "", "ok ", $test++, " # get_value\n";
#print $cf[1]->get_value ne "xx" ? "not " : "", "ok ", $test++, " # get_value\n";
#print $cf[2]->get_value != 1.0  ? "not " : "", "ok ", $test++, " # get_value\n";
my $o1 = new Foo1;
@of = $o1->fields;
print $of[0]->type ne 'int' ? "not " : "", "ok ", $test++, " # type\n";
print $of[1]->type ne 'Str' ? "not " : "", "ok ", $test++, " # type\n";
print $of[2]->type ne 'Num' ? "not " : "", "ok ", $test++, " # type\n";
print $of[0]->const ? "not " : "", "ok ", $test++, " # const\n";
print $of[2]->const ? "" : "not ", "ok ", $test++, " # const\n";
print $of[0]->get_value != 1    ? "not " : "", "ok ", $test++, " # get_value\n";
print $of[1]->get_value ne "xx" ? "not " : "", "ok ", $test++, " # get_value\n";
print $of[2]->get_value != 1.0  ? "not " : "", "ok ", $test++, " # get_value\n";
