#!./perl

my $i=1;
print "1..20\n";

sub x1 { shift; 1 }    # inlined
sub x2 { $_[0] = 1; }  # call-by-ref, not yet
sub x3 { my $x=shift; x3(--$x) if $x; } # recursive, not
sub x4 { for (0..9){x1+x2}; 1 }  # too long

print &x1 != 1 ? "not ":"", "ok ",$i++,"\n";
print x1 != 1  ? "not ":"", "ok ",$i++,"\n";
print x1() != 1  ? "not ":"", "ok ",$i++,"\n";
print main->x1() != 1  ? "not ":"", "ok ",$i++,"\n";
print main::x1([0..9]) != 1  ? "not ":"", "ok ",$i++,"\n";
print x1(0..9) != 1  ? "not ":"", "ok ",$i++,"\n";

my $a = 0;
print x2($a) != 1 ? "not ":"", "ok ",$i++,"\n";
print $a != 1     ? "not ":"", "ok ",$i++,"\n";
print x3(2) != 0  ? "not ":"", "ok ",$i++,"\n";
print x4 != 1  ? "not ":"", "ok ",$i++,"\n";

{
  no inline;

  print &x1 != 1 ? "not ":"", "ok ",$i++,"\n";
  print x1 != 1  ? "not ":"", "ok ",$i++,"\n";
  print x1() != 1  ? "not ":"", "ok ",$i++,"\n";
  print main->x1() != 1  ? "not ":"", "ok ",$i++,"\n";
  print main::x1([0..9]) != 1  ? "not ":"", "ok ",$i++,"\n";
  print x1(0..9) != 1  ? "not ":"", "ok ",$i++,"\n";

  $a = 0;
  print x2($a) != 1 ? "not ":"", "ok ",$i++,"\n";
  print $a != 1     ? "not ":"", "ok ",$i++,"\n";
  print x3(2) != 0  ? "not ":"", "ok ",$i++,"\n";
  print x4 != 1  ? "not ":"", "ok ",$i++,"\n";
}
