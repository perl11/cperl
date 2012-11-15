#!./perl
BEGIN { $| = 1; print "1..16\n"; }
my $test=1;
{
  BEGIN {push @INC, 'lib';}
  use 5.017;
  # parse valid const
  my $result = eval 'use feature "const";my const $a=1;print "# \$a=",$a,"\n";$a';
  if (!$@ and $result == 1) { print "ok $test\n"; } else { print "not ok $test - declare and set const \$i\n"; }
  $test++;
  $result = eval 'use feature "const";my const @a=(1);print "# \$a[0]=",$a[0],"\n";$a[0]';
  if (!$@ and $result == 1) { print "ok $test\n"; } else { print "not ok $test - declare and set const \@a\n"; }
  $test++;
  $result = eval 'use feature "const";my const %a=("a"=>"ok");print "# \$a{a}=",$a{a},"\n";$a{a}';
  if (!$@ and $result eq 'ok') { print "ok $test\n"; } else { print "not ok $test - declare and set const \%a $@\n"; }
  $test++;
  $result = eval 'use feature "const";my const($a,$b)=(1,2);print "# \$a,\$b=",$a,$b,"\n";$a';
  if (!$@ and $result == 1) { print "ok $test\n"; } else { print "not ok $test - list_assignment $@\n"; }
  $test++;
  $result = eval 'use feature "const";my (const $a, const $b)=(1,2);print "# \$a,\$b=",$a,$b,"\n";$a';
  if (!$@ and $result == 1) { print "ok $test\n"; } else { print "not ok $test - #TODO list_assignment2 $@\n"; }
  $test++;

  # compile-time errors
  eval 'use feature "const";my const $a=1; $a=0';
  if ($@ =~ /Invalid assignment to const variable/) { print "ok $test\n"; } else { print "not ok $test - #Invalid assignment to const variable $@\n"; }
  $test++;
  eval 'use feature "const";my const @a=(1,2,3); @a=(0);';
  if ($@ =~ /Invalid assignment to const variable/) { print "ok $test\n"; } else { print "not ok $test - #Invalid assignment to const array $@\n"; }
  $test++;
  eval 'use feature "const";my const %a=("a"=>"ok"); $a{a}=0';
  if ($@ =~ /Invalid assignment to const variable/) { print "ok $test\n"; } else { print "not ok $test - #TODO Invalid assignment to const hash $@\n"; }
  $test++;

  # throw PL_no_modify compile-time errors
  $result = eval 'use feature "const"; my const($a,$b)=(1,2); eval q($b=0);';
  if ($@ =~ /Modification of a read-only value attempted/) { print "ok $test\n"; } else { print "not ok $test - #TODO set const \$b in (\$a,\$b)\n"; }
  $test++;
  # const @a is not deep, protects only the structure, not the elements
  $result = eval 'use feature "const";my const @a=(1,2,3); $a[0]=0;$a[0]';
  if (!$@ and $result == 0) { print "ok $test\n"; } else { print "not ok $test - set \$[0] elem\n"; }
  $test++;
  eval 'use feature "const";my const @a=(1,2,3); push @a,0';
  if ($@ =~ /Modification of a read-only value attempted/) { print "ok $test\n"; } else { print "not ok $test - push const \@a\n"; }
  $test++;
  eval 'use feature "const";my const %a=(0=>1,1=>2); %a=(0=>1)';
  if ($@ =~ /Attempt to access disallowed key/) { print "ok $test\n"; } else { print "not ok $test - set const \%a restricted hash\n"; }
  $test++;

  # mixed with types
  $result = eval 'use feature "const";$int::x=0;my const int $a=1;print "# \$a=",$a,"\n";$a';
  if (!$@ and $result == 1) { print "ok $test\n"; } else { print "not ok $test - declare and set const int \$i\n"; }
  $test++;
  $result = eval 'use feature "const";my unknown $a=1;$a;';
  if ($@ =~ /No such class unknown/) { print "ok $test\n"; } else { print "not ok $test - No such class unknown\n"; }
  $test++;
  $result = eval 'use feature "const";my const unknown $a=1;$a;';
  if ($@ =~ /No such class unknown/) { print "ok $test\n"; } else { print "not ok $test - No such class unknown with const\n"; }
  $test++;
}

# lexical types without const
$result = eval '$int::x=0;my int $a=1;$a;';
if (!$@ and $result == 1) { print "ok $test\n"; } else { print "not ok $test - my int \$i\n"; }
$test++;
