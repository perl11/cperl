use Test::More tests => 4;
use Cpanel::JSON::XS;

my $xs = Cpanel::JSON::XS->new->latin1->allow_nonref;

eval { $xs->decode ("[] ") };
ok (!$@);
SKIP: {
  skip "5.6", 1 if $] < 5.008;
  eval { $xs->decode ("[] x") };
  ok ($@);
}
ok (2 == ($xs->decode_prefix ("[][]"))[1]);
ok (3 == ($xs->decode_prefix ("[1] t"))[1]);

