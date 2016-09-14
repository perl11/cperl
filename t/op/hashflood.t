#!./perl -w
# against FNV1A so far only.

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}
use strict;

plan tests => 1;

sub runperl_wo_seed {
    die "does not take a hashref"
	if ref $_[0] and ref $_[0] eq 'HASH';
    my $runperl = &_create_runperl;
    $ENV{PERL_HASH_SEED} = "0";
    my $result = `$runperl`;
    $result =~ s/\n\n/\n/g if $^O eq 'VMS';
    return $result;
}
undef *runperl;
*runperl = \&runperl_wo_seed;

# create >128 collisions, should warn. (here 8 bits: 511 collisions)
# exits at 138, so should warn 2-4 times, depending on NODEFAULT_SHAREKEYS.
# collisions easily created with an external C file, using hv_func.h
# too lazy yet to create the murmur collisions, it's trivial.
my $a = { switches=>['-w'], stderr=>1 };
fresh_perl_like(<<'EOI', qr/SECURITY: Hash flood /, $a, 'collide unseeded hash');
use Config;
my $hash_func = $Config{hash_func};
unless ($hash_func) {
  $hash_func = $] >= 5.017 ? 'ONE_AT_A_TIME_HARD' : 'ONE_AT_A_TIME_OLD';
  if ($Config{ccflags} =~ /-DPERL_HASH_FUNC_(.*) /) {
    $hash_func = $1;
  }
}
$hash_func =~ s/ONE_AT_A_TIME/OAAT/;
my $fn = "op/seed-".lc($hash_func)."-8-0.dat";
open my $fh, "<", $fn or die "$fn $!";
my (%h, $i);
while (<$fh>) {
  chomp;
  my($l,$s,$hash) = m/^(\d) (.+)\t(0x[0-9a-f]+)/;
  if (length($s) == $l) {
    $h{$s}++;
  } else {
    my $diff = $l - length($s);
    $s .= "\000" for (0..$diff);
    $h{$s}++;
  }
  if ($i++ > 137) {
    print "ok\n" if $ENV{PERL_HASH_SEED} eq "0";
    exit;
  }
}
close $fh;
EOI
