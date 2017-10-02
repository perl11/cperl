#!/usr/local/bin/cperl
# cperl opprof.pl | sort -rn -k2 | less

use strict;
use B;
my (%h, %p);
my $files = shift || "/tmp/cperl-opprof.*";
for my $fn (glob $files) {
  open my $f, "<", $fn;
  my $p;
  for my $s (<$f>) {
    chop;
    my $i = int $s;
    #$h{$i}++;
    $p{"$p-$i"}++ if $p;
    $p = $i;
  }
  close $f;
}

END {
  #print "ops:\n";
  #for my $k (keys %h) {
  #  print "$k\t$h{$k}\n";
  #}
  print "pairs:\n";
  my %r = reverse %p;
  my $i;
  for my $k (sort {$b <=> $a} keys %r) {
    my ($p1,$p2) = split /-/, $r{$k};
    printf "%d\t%s\t%14s %-14s\n", $k, $r{$k},
      substr(B::ppname($p1),3), substr(B::ppname($p2),3);
    last if $i++ > 10;
  }
}

# cperl opprof.pl /tmp/cperl-opprof.1001
# pairs:
# 8520	208-3	     nextstate pushmark
# 8003	208-9	     nextstate padsv
# 7864	9-13	         padsv sassign
# 7689	3-9	      pushmark padsv
# 7323	13-208	       sassign nextstate
# 4523	5-5	         const const

# cperl opprof.pl /tmp/cperl-opprof.9991
# pairs:
# 14622	5-5	         const const
# 8071	9-13	         padsv sassign
# 7817	9-5	         padsv const
# 7591	13-208	       sassign nextstate
# 6177	208-9	     nextstate padsv
# 5073	5-47	         const concat
