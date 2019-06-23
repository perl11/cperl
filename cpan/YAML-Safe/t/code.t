use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 5;

#-------------------------------------------------------------------------------
my $sub = sub { return "Hi.\n" };
my $obj = YAML::Safe->new;

my $yaml = <<'...';
--- !!perl/code '{ "DUMMY" }'
...

is Dump($sub), $yaml,
    "Dumping a code ref works produces DUMMY";

#-------------------------------------------------------------------------------
$sub = sub { return "Bye.\n" };
bless $sub, "Barry::White";

$yaml = <<'...';
--- !!perl/code:Barry::White |-
  {
      use warnings;
      use strict;
      return "Bye.\n";
  }
...

use B::Deparse;
if (new B::Deparse -> coderef2text ( sub { no strict; 1; use strict; 1; })
      =~ 'refs') {
    $yaml =~ s/use strict/use strict 'refs'/g;
}

is $obj->enablecode->Dump($sub), $yaml,
    "Dumping a blessed code ref works (with B::Deparse) - enablecode";

#-------------------------------------------------------------------------------
$sub = sub { return "Bye.\n" };
bless $sub, "Barry::White";

$yaml = <<'...';
--- !!perl/code:Barry::White '{ "DUMMY" }'
...

is $obj->dumpcode(0)->Dump($sub), $yaml,
    "Dumping a blessed code ref works (with DUMMY again) - dumpcode(0)";

$yaml = <<'...';
--- !!perl/code:Barry::White |-
  {
      use warnings;
      use strict;
      return "Bye.\n";
  }
...

$sub = $obj->loadcode(0)->Load($yaml);
my $return = $sub->();
is($return, undef, "Loaded dummy coderef - loadcode(0)");

$sub = $obj->loadcode->Load($yaml);
$return = $sub->();
cmp_ok($return, 'eq', "Bye.\n", "Loaded coderef - loadcode");
