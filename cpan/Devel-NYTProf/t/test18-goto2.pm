package Test18;

sub longmess_real { return "Heavy" }

delete $Test18::{longmess_jmp};
*longmess_jmp  = *longmess_real;

my $dummy = $&; # also test sawampersand

1;
