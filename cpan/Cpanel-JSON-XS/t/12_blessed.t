BEGIN { $| = 1; print "1..18\n"; }

use Cpanel::JSON::XS;

our $test;
sub ok($;$) {
  print $_[0] ? "" : "not ", "ok ", ++$test, $_[1]?"# ".$_[1]:"", "\n";
  $_[0]
}

my $o1 = bless { a => 3 }, "XX";
my $o2 = bless \(my $dummy = 1), "YY";

if (eval 'require Hash::Util') {
  if ($Hash::Util::VERSION > 0.05) {
    Hash::Util::lock_ref_keys($o1);
    print "# blessed hash is locked\n";
  }
  else {
    Hash::Util::lock_hash($o1);
    print "# hash is locked\n";
  }
}
else {
  print "# locked hashes are not supported\n";
};

sub XX::TO_JSON {
   {__,""}
}

my $js = Cpanel::JSON::XS->new;

eval { $js->encode ($o1) }; ok ($@ =~ /allow_blessed/);
eval { $js->encode ($o2) }; ok ($@ =~ /allow_blessed/);
$js->allow_blessed;
ok ($js->encode ($o1) eq "null");
ok ($js->encode ($o2) eq "null");
$js->allow_blessed(0)->convert_blessed;
ok ($js->encode ($o1) eq '{"__":""}');
ok ($js->encode ($o2) eq "null");
$js->allow_blessed->convert_blessed;
ok ($js->encode ($o1) eq '{"__":""}');
if ($] < 5.008) {
  print "ok ",++$test," # skip 5.6\n"
} else {
  # PP returns null
  ok ($js->encode ($o2) eq 'null') or print STDERR "# ",$js->encode ($o2),"\n";
}

$js->filter_json_object (sub { 5 });
$js->filter_json_single_key_object (a => sub { shift });
$js->filter_json_single_key_object (b => sub { 7 });

ok ("ARRAY" eq ref $js->decode ("[]"));
ok (5 eq join ":", @{ $js->decode ('[{}]') });
ok (6 eq join ":", @{ $js->decode ('[{"a":6}]') });
ok (5 eq join ":", @{ $js->decode ('[{"a":4,"b":7}]') });

$js->filter_json_object;
ok (7 == $js->decode ('[{"a":4,"b":7}]')->[0]{b});
ok (3 eq join ":", @{ $js->decode ('[{"a":3}]') });

$js->filter_json_object (sub { });
ok (7 == $js->decode ('[{"a":4,"b":7}]')->[0]{b});
ok (9 eq join ":", @{ $js->decode ('[{"a":9}]') });

$js->filter_json_single_key_object ("a");
ok (4 == $js->decode ('[{"a":4}]')->[0]{a});

if ($]<5.008002) {
  print "ok 18 # skip 5.6 + 5.8.1\n";
} else {
  $js->filter_json_single_key_object (a => sub { });
  ok (4 == $js->decode ('[{"a":4}]')->[0]{a});
}
