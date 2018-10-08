use strict;

use Test::More;
use CPAN::Distroprefs;

plan tests => 21;

my $p;

# start with something simple
$p = CPAN::Distroprefs::Pref->new({
  data => {
    match => {
      distribution => "^XML",
    },
  },
});

ok($p->data);
ok($p->has_match("distribution"));
ok(!$p->has_match("perl"));
ok($p->has_any_match);
ok($p->has_valid_subkeys);

ok($p->matches({
   distribution => "XML::Parser",
}));

ok(!$p->matches({
   distribution => "Foo::XML",
}));

# still simple, but now a negated match
$p = CPAN::Distroprefs::Pref->new({
  data => {
    match => {
      not_distribution => "^XML",
    },
  },
});

ok($p->data);
ok($p->has_match("distribution"));
ok(!$p->has_match("perl"));
ok($p->has_any_match);
ok($p->has_valid_subkeys);

ok(!$p->matches({
   distribution => "XML::Parser",
}));

ok($p->matches({
   distribution => "Foo::XML",
}));

# try some complicated matches
$p = CPAN::Distroprefs::Pref->new({
  data => {
    match => {
      distribution => "^XML",
      not_distribution => "Parser",
      perlconfig => {
	osname => "linux",
        not_cc => "^gcc\$",
      },
    },
  },
});

ok(!$p->matches({
  distribution => "XML::Parser",
}));

ok($p->matches({
  distribution => "XML::Foo",
  perlconfig => {
    osname => "linux",
    cc => "cc",
  },
}));

ok(!$p->matches({
  distribution => "XML::Foo",
  perlconfig => {
    osname => "linux",
    cc => "gcc",
  },
}));

ok(!$p->matches({
  distribution => "XML::Foo",
  perlconfig => {
    osname => "darwin",
    cc => "cc",
  },
}));

# try match on module
$p = CPAN::Distroprefs::Pref->new({
  data => {
    match => {
      module => "^LWP",
      not_module => "Foo",
    },
  },
});

ok($p->matches({
   module => ["LWP::UserAgent"],
}));

ok(!$p->matches({
   module => ["LWP::UserAgent", "LWP::Foo"],
}));

ok(!$p->matches({
   module => ["Bar"],
}));

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
