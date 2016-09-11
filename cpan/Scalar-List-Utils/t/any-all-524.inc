#!./perl

warnings->unimport('experimental::lexical_topic')
  if !$Config{usecperl} and $] > 5.018;
my $_ = "foo";
my $ok = any { $_ eq "a" } qw(a b c);
#warn $ok;
ok( $ok, 'any my $_');
