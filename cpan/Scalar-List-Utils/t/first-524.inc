#!./perl

warnings->unimport('experimental::lexical_topic')
  if !$Config{usecperl} and $] > 5.018;
my $_ = 1;
$v = first { $_ > 6 } 2,4,6,12;
is($v, 12, 'first with lexical my');
