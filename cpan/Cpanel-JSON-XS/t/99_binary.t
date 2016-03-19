use Test::More tests => 300;
use Cpanel::JSON::XS;
use B ();

my $as  = Cpanel::JSON::XS->new->ascii->shrink;
my $us  = Cpanel::JSON::XS->new->utf8->shrink;
my $bs  = Cpanel::JSON::XS->new->binary;

sub test($) {
  my $c = $_[0];
  my $js = $as->encode([$c]);
  is ($c, ((decode_json $js)->[0]), "ascii ".B::cstring($c));
  $js = $us->encode([$c]);
  is ($c, ($us->decode($js))->[0], "utf8 ".B::cstring($c));
}

sub test_bin($) {
  my $c = $_[0];
  my $js = $bs->encode([$c]);
  is ($js, $bs->encode($bs->decode($js)), "binary ".B::cstring($c));
}

srand 0; # doesn't help too much, but it's at least more deterministic

for (1..25) {
   test join "", map chr ($_ & 255), 0..$_;
   test_bin join "", map chr ($_ & 255), 0..$_;

   SKIP: {
     skip "skipped uf8 w/o binary: 5.6", 6 if $] < 5.008;
     test join "", map chr rand 255, 0..$_;
     test join "", map chr ($_ * 97 & ~0x4000), 0..$_;
     test join "", map chr (rand (2**20) & ~0x800), 0..$_;
   }

   test_bin join "", map chr rand 255, 0..$_;

   SKIP: {
     skip "skipped uf8 w binary: 5.6", 2 if $] < 5.008;
     test_bin join "", map chr ($_ * 97 & ~0x4000), 0..$_;
     test_bin join "", map chr (rand (2**20) & ~0x800), 0..$_;
   }
}
