use Test::More tests => 162;
use utf8;
use Cpanel::JSON::XS;
use warnings;

is(Cpanel::JSON::XS->new->allow_nonref->utf8->encode("ü"), "\"\xc3\xbc\"");
is(Cpanel::JSON::XS->new->allow_nonref->encode("ü"), "\"ü\"");

is(Cpanel::JSON::XS->new->allow_nonref->ascii->utf8->encode(chr 0x8000), '"\u8000"');
is(Cpanel::JSON::XS->new->allow_nonref->ascii->utf8->pretty->encode(chr 0x10402), "\"\\ud801\\udc02\"\n");

ok not defined eval { Cpanel::JSON::XS->new->allow_nonref->utf8->decode('"ü"') };
like $@, qr/malformed UTF-8/;

is(Cpanel::JSON::XS->new->allow_nonref->decode('"ü"'), "ü");
is(Cpanel::JSON::XS->new->allow_nonref->decode('"\u00fc"'), "ü");

ok not defined eval { decode_json ('"\ud801\udc02' . "\x{10204}\"", 1) };
like $@, qr/Wide character/;

SKIP: {
  skip "5.6", 1 if $] < 5.008;
  is(Cpanel::JSON::XS->new->allow_nonref->decode('"\ud801\udc02' . "\x{10204}\""), "\x{10402}\x{10204}");
}

is(Cpanel::JSON::XS->new->allow_nonref->decode('"\"\n\\\\\r\t\f\b"'), "\"\012\\\015\011\014\010");

my $utf8_love = "I \342\235\244 perl";
is(Cpanel::JSON::XS->new->ascii->encode([$utf8_love]), '["I \u00e2\u009d\u00a4 perl"]', 'utf8 enc ascii');
is(Cpanel::JSON::XS->new->latin1->encode([$utf8_love]), "[\"I \342\235\244 perl\"]", 'utf8 enc latin1');
is(Cpanel::JSON::XS->new->utf8->encode([$utf8_love]), "[\"I \303\242\302\235\302\244 perl\"]", 'utf8 enc utf8');
is(Cpanel::JSON::XS->new->binary->encode([$utf8_love]), '["I \xe2\x9d\xa4 perl"]', 'utf8 enc binary');

SKIP: {
  skip "5.6", 4 if $] < 5.008;
  my $unicode_love = "I ❤ perl";
  is(Cpanel::JSON::XS->new->ascii->encode([$unicode_love]), '["I \u2764 perl"]', 'unicode enc ascii');
  is(Cpanel::JSON::XS->new->latin1->encode([$unicode_love]), "[\"I \\u2764 perl\"]", 'unicode enc latin1');
  is(Cpanel::JSON::XS->new->utf8->encode([$unicode_love]), "[\"I \342\235\244 perl\"]", 'unicode enc utf8');
  is(Cpanel::JSON::XS->new->binary->encode([$unicode_love]), '["I \xe2\x9d\xa4 perl"]', 'unicode enc binary');
}

# TODO: test utf8 hash keys,
# test utf8 strings without any char > 0x80.

# warn on the 66 non-characters as in core
{
  BEGIN { 'warnings'->import($] < 5.014 ? 'utf8' : 'nonchar') }
  my $w = '';
  $SIG{__WARN__} = sub { $w = shift };
  my $d = Cpanel::JSON::XS->new->allow_nonref->decode('"\ufdd0"');
  my $warn = $w;
  {
    no warnings 'utf8';
    is ($d, "\x{fdd0}", substr($warn,0,31)."...");
  }
  like ($warn, qr/^Unicode non-character U\+FDD0 is/);
  $w = '';
  # higher planes
  $d = Cpanel::JSON::XS->new->allow_nonref->decode('"\ud83f\udfff"');
  $warn = $w;
  {
    no warnings 'utf8';
    is ($d, "\x{1ffff}", substr($warn,0,31)."...");
  }
  like ($w, qr/^Unicode non-character U\+1FFFF is/);
  $w = '';
  $d = Cpanel::JSON::XS->new->allow_nonref->decode('"\ud87f\udffe"');
  $warn = $w;
  {
    no warnings 'utf8';
    is ($d, "\x{2fffe}", substr($warn,0,31)."...");
  }
  like ($w, qr/^Unicode non-character U\+2FFFE is/);

  $w = '';
  $d = Cpanel::JSON::XS->new->allow_nonref->decode('"\ud8a4\uddd1"');
  $warn = $w;
  is ($d, "\x{391d1}", substr($warn,0,31)."...");
  is ($w, '');
}
{
  my $w;
  BEGIN { 'warnings'->import($] < 5.014 ? 'utf8' : 'nonchar') }
  $SIG{__WARN__} = sub { $w = shift };
  # no warning with relaxed
  my $d = Cpanel::JSON::XS->new->allow_nonref->relaxed->decode('"\ufdd0"');
  my $warn = $w;
  {
    no warnings 'utf8';
    is ($d, "\x{fdd0}", "no warning with relaxed");
  }
  is($w, undef);
}

# security exploits via ill-formed subsequences
# see http://unicode.org/reports/tr36/#UTF-8_Exploit
# testcases from Encode/t/utf8strict.t
# All these sequences are not handled by the unsafe, fast XS decoder,
# rather passed through to the safe Perl decoder, which detects those.
my @ill =
  (# http://smontagu.damowmow.com/utf8test.html
   # The numbers below, like 2.1.2 are test numbers on this web page
   qq/80/          ,             # 3.1.1
   qq/bf/          ,             # 3.1.2
   qq/80 bf/       ,             # 3.1.3
   qq/80 bf 80/    ,             # 3.1.4
   qq/80 bf 80 bf/ ,             # 3.1.5
   qq/80 bf 80 bf 80/ ,          # 3.1.6
   qq/80 bf 80 bf 80 bf/ ,       # 3.1.7
   qq/80 bf 80 bf 80 bf 80/ ,    # 3.1.8
   qq/80 81 82 83 84 85 86 87 88 89 8a 8b 8c 8d 8e 8f 90 91 92 93 94 95 96 97 98 99 9a 9b 9c 9d 9e 9f a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 aa ab ac ad ae af b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 ba bb bc bd be bf/ , # 3.1.9
   qq/c0 20 c1 20 c2 20 c3 20 c4 20 c5 20 c6 20 c7 20 c8 20 c9 20 ca 20 cb 20 cc 20 cd 20 ce 20 cf 20 d0 20 d1 20 d2 20 d3 20 d4 20 d5 20 d6 20 d7 20 d8 20 d9 20 da 20 db 20 dc 20 dd 20 de 20 df 20/ , # 3.2.1
   qq/e0 20 e1 20 e2 20 e3 20 e4 20 e5 20 e6 20 e7 20 e8 20 e9 20 ea 20 eb 20 ec 20 ed 20 ee 20 ef 20/ , # 3.2.2
   qq/f0 20 f1 20 f2 20 f3 20 f4 20 f5 20 f6 20 f7 20/ , # 3.2.3
   qq/f8 20 f9 20 fa 20 fb 20/ , # 3.2.4
   qq/fc 20 fd 20/ ,             # 3.2.5
   qq/c0/ ,                      # 3.3.1
   qq/e0 80/ ,                   # 3.3.2
   qq/f0 80 80/ ,                # 3.3.3
   qq/f8 80 80 80/ ,             # 3.3.4
   qq/fc 80 80 80 80/ ,          # 3.3.5
   qq/df/ ,                      # 3.3.6
   qq/ef bf/ ,                   # 3.3.7
   qq/f7 bf bf/ ,                # 3.3.8
   qq/fb bf bf bf/ ,             # 3.3.9
   qq/fd bf bf bf bf/ ,          # 3.3.10
   qq/c0 e0 80 f0 80 80 f8 80 80 80 fc 80 80 80 80 df ef bf f7 bf bf fb bf bf bf fd bf bf bf bf/ , # 3.4.1
   qq/fe/ ,                      # 3.5.1
   qq/ff/ ,                      # 3.5.2
   qq/fe fe ff ff/ ,             # 3.5.3
   qq/f0 8f bf bf/ ,             # 4.2.3
   qq/f8 87 bf bf bf/ ,          # 4.2.4
   qq/fc 83 bf bf bf bf/ ,       # 4.2.5
   qq/c0 af/ ,                   # 4.1.1  # ! overflow not with perl 5.6
   qq/e0 80 af/ ,                # 4.1.2  # ! overflow not with perl 5.6
   qq/f0 80 80 af/ ,             # 4.1.3  # ! overflow not with perl 5.6
   qq/f8 80 80 80 af/ ,          # 4.1.4  # ! overflow not with perl 5.6
   qq/fc 80 80 80 80 af/ ,       # 4.1.5  # ! overflow not with perl 5.6
   qq/c1 bf/ ,                   # 4.2.1  # ! overflow not with perl 5.6
   qq/e0 9f bf/ ,                # 4.2.2  # ! overflow not with perl 5.6
   qq/c0 80/ ,                   # 4.3.1  # xx! overflow not with perl 5.6
   qq/e0 80 80/ ,                # 4.3.2  # xx! overflow not with perl 5.6
   qq/f0 80 80 80/ ,             # 4.3.3  # xx! overflow not with perl 5.6
   qq/f8 80 80 80 80/ ,          # 4.3.4  # xx! overflow not with perl 5.6
   qq/fc 80 80 80 80 80/ ,       # 4.3.5  # xx! overflow not with perl 5.6
   # non-shortest form of 5c i.e. "\\"
   qq/c1 9c/ ,                            # ! not with perl 5.6
  );

{
  # these are no multibyte codepoints, just raw utf8 bytes,
  # so most of them work with 5.6 also.
  BEGIN { $^W = 1 }
  BEGIN { 'warnings'->import($] < 5.014 ? 'utf8' : 'nonchar') }
  my $w;
  $SIG{__WARN__} = sub { $w = shift };

  for my $ill (@ill) {
    my $o = pack "C*" => map {hex} split /\s+/, $ill;
    my $d = eval { decode_json("[\"$o\"]"); };
    is ($d, undef, substr($@,0,25))
      or diag $w, ' ', $ill, "\t => ", $d->[0], " $@";
    like($@, qr/malformed UTF-8 character/, "ill-formed utf8 <$ill> throws error");
    is($d, undef, "without warning");
    $w = undef;
  }
}
