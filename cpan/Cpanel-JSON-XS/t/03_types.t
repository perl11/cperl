BEGIN { $| = 1; print "1..85\n"; }
use utf8;
use Cpanel::JSON::XS;

our $test;
sub ok($;$) {
  print $_[0] ? "" : "not ", "ok ", ++$test;
  print @_ > 1 ? " # $_[1]\n" : "\n";
}
ok (!defined Cpanel::JSON::XS->new->allow_nonref->decode ('null'));
my $null   = Cpanel::JSON::XS->new->allow_nonref->decode ('null');
my $true   = Cpanel::JSON::XS->new->allow_nonref->decode ('true');
my $false  = Cpanel::JSON::XS->new->allow_nonref->decode ('false');

ok ($true == 1, sprintf("true: numified %d", 0+$true));
ok ($false == 0, sprintf("false: numified %d", 0+$false));
ok (Cpanel::JSON::XS::is_bool $true);
ok ($false == !$true);
ok (Cpanel::JSON::XS::is_bool $false);
ok ($false eq "0", "false: eq $false");
ok ($true eq "true", "true: eq $true");
ok ("$false" eq "0",     "false: stringified $false eq 0");
#ok ("$false" eq "false", "false: stringified $false eq false");
#ok ("$true" eq "1",    "true: stringified $true eq 1");
ok ("$true" eq "1", "true: stringified $true");
{
  my $FH;
  my $fn = "tmp_$$";
  open $FH, ">", $fn;
  print $FH "$false$true\n"; # printed upstream as "0". GH #29
  close $FH;
  open $FH, "<", $fn;
  my $s = <$FH>;
  close $FH;
  ok ($s eq "01\n", $s); # 11
  unlink $fn;
}

ok (++$false == 1); # turns it into true! not sure if we want that
ok (!Cpanel::JSON::XS::is_bool $false);

ok (Cpanel::JSON::XS->new->allow_nonref (1)->decode ('5') == 5);
ok (Cpanel::JSON::XS->new->allow_nonref (1)->decode ('-5') == -5);
ok (Cpanel::JSON::XS->new->allow_nonref (1)->decode ('5e1') == 50);
ok (Cpanel::JSON::XS->new->allow_nonref (1)->decode ('-333e+0') == -333);
ok (Cpanel::JSON::XS->new->allow_nonref (1)->decode ('2.5') == 2.5);

ok (Cpanel::JSON::XS->new->allow_nonref (1)->decode ('""') eq "");
ok ('[1,2,3,4]' eq encode_json decode_json ('[1,2, 3,4]'));
ok ('[{},[],[],{}]' eq encode_json decode_json ('[{},[], [ ] ,{ }]'));
ok ('[{"1":[5]}]' eq encode_json [{1 => [5]}]);
ok ('{"1":2,"3":4}' eq Cpanel::JSON::XS->new->canonical (1)->encode (decode_json '{ "1" : 2, "3" : 4 }'));
ok ('{"1":2,"3":1.2}' eq Cpanel::JSON::XS->new->canonical (1)->encode (decode_json '{ "1" : 2, "3" : 1.2 }')); #24

ok ('[true]'  eq encode_json [Cpanel::JSON::XS::true]);
ok ('[false]' eq encode_json [Cpanel::JSON::XS::false]);
ok ('[true]'  eq encode_json [\1]);
ok ('[false]' eq encode_json [\0]);
ok ('[null]'  eq encode_json [undef]);
ok ('[true]'  eq encode_json [Cpanel::JSON::XS::true]);
ok ('[false]' eq encode_json [Cpanel::JSON::XS::false]);

for $v (1, 2, 3, 5, -1, -2, -3, -4, 100, 1000, 10000, -999, -88, -7, 7, 88, 999, -1e5, 1e6, 1e7, 1e8) {
   ok ($v == ((decode_json "[$v]")->[0]));
   ok ($v == ((decode_json encode_json [$v])->[0]));
}

ok ('[1.0]' eq encode_json [1.0]);

ok (30123 == ((decode_json encode_json [30123])->[0]));
ok (32123 == ((decode_json encode_json [32123])->[0]));
ok (32456 == ((decode_json encode_json [32456])->[0]));
ok (32789 == ((decode_json encode_json [32789])->[0]));
ok (32767 == ((decode_json encode_json [32767])->[0]));
ok (32768 == ((decode_json encode_json [32768])->[0]));

my @sparse; @sparse[0,3] = (1, 4);
ok ("[1,null,null,4]" eq encode_json \@sparse);

# RFC 7159: optional 2nd allow_nonref arg
ok (32768 == decode_json("32768", 1));
ok ("32768" eq decode_json("32768", 1));
ok (1 == decode_json("true", 1));
ok (0 == decode_json("false", 1));
