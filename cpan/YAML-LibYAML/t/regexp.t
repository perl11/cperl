use lib '.';
use t::TestYAMLTests tests => 18;
use Devel::Peek();

my $rx1 = qr/5050/;
my $yaml1 = Dump $rx1;

my $rx2 = qr/99999/;
bless $rx2, 'Classy';
my $yaml2 = Dump $rx2;

my $rx3 = qr/^edcba/mi;
my $yaml3 = Dump $rx3;

sub perl514 {
    # https://rt.cpan.org/Ticket/Display.html?id=62266
    skip "perl-5.14 regexp stringification is different", shift || 1 if $] > 5.013;
}

SKIP: { perl514 5;
is $yaml1, <<'...', 'Regular regexp dumps';
--- !!perl/regexp (?-xism:5050)
...

is $yaml2, <<'...', 'Blessed regular regexp dumps';
--- !!perl/regexp:Classy (?-xism:99999)
...

is $yaml3, <<'...', 'Regexp with flags dumps';
--- !!perl/regexp (?mi-xs:^edcba)
...

my $rx4 = bless $rx3, 'Bossy';
my $yaml4 = Dump $rx4;

is $yaml4, <<'...', 'Blessed regexp with flags dumps';
--- !!perl/regexp:Bossy (?mi-xs:^edcba)
...

my $unicode = "\x{100}";
my $rx5 = qr/\Q$unicode\E/;
my $yaml5 = Dump $rx5;

is $yaml5, <<"...", 'Unicode regexp dumps';
--- !!perl/regexp (?-xism:\xC4\x80)
...
}


my $rx1_ = Load($yaml1);
is ref($rx1_), 'Regexp', 'Can Load a regular regexp';
SKIP: { perl514;
is $rx1_, '(?-xism:5050)', 'Loaded regexp value is correct';
}
like "404050506060", $rx1_, 'Loaded regexp works';

my $rx2_ = Load($yaml2);
is ref($rx2_), 'Classy', 'Can Load a blessed regexp';
SKIP: { perl514;
is $rx2_, '(?-xism:99999)', 'Loaded blessed regexp value is correct';
}
ok "999999999" =~ $rx2_, 'Loaded blessed regexp works';

my $rx3_ = Load($yaml3);
is ref($rx3_), 'Regexp', 'Can Load a regexp with flags';
SKIP: { perl514;
is $rx3_, '(?mi-xs:^edcba)', 'Loaded regexp with flags value is correct';
}
like "foo\neDcBA\n", $rx3_, 'Loaded regexp with flags works';

my $rx4_ = Load("--- !!perl/regexp (?msix:123)\n");
is ref($rx4_), 'Regexp', 'Can Load a regexp with all flags';
SKIP: { perl514;
is $rx4_, '(?msix:123)', 'Loaded regexp with all flags value is correct';
}

my $rx5_ = Load("--- !!perl/regexp (?msix:\xC4\x80)\n");
is ref($rx5_), 'Regexp', 'Can Load a unicode regexp';
SKIP: { perl514;
is $rx5_, "(?msix:\x{100})", 'Loaded unicode regexp value is correct';
}
