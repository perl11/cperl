#!./perl
# https://github.com/perl11/cperl/issues/390

BEGIN {
    $| = 1;
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc( '../lib' );
    skip_all("no vms envsize check yet")
      if $^O eq 'vms';
}

plan (tests => 1);

sub envsize {
  my $size = 0;
  while (($k,$v) = each %ENV) {
    $size += length($k)+1;
    $size += length($v)+1;
  }
  return $size;
}

my $size = envsize;
print STDOUT "# \%ENV: $size\n";

my $n = (131072 - $size)/2 + 1;
while (!$@) {
  eval { $ENV{'x' x $n} = 'y' x $n; };
  $n *= 2;
  #print STDERR "# \%ENV: ".envsize." ".$@."\n";
  if ($n > 0x0fffffff) {
    $@ = "Simulate Environment size error";
    # without the check we'll run into panic: hash key too long (4195876864)
    # or even worse: "Out of memory" panic or "Argument list too long" system errors
    # in subsequent exec calls.
  }
}
print STDOUT "# \%ENV: ",envsize,"\n";
ok($@ =~ /Environment size/, "Caught $@");
