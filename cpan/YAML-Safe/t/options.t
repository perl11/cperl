use strict;
use Test::More tests => 52;
use YAML::Safe;
my $obj = YAML::Safe->new;

my %boolopts = (
  "disableblessed" => 0,
  "nonstrict" => 0,
  "enablecode" => 0,
  "loadcode" => 0,
  "dumpcode" => 0,
  "noindentmap" => 0,
  "canonical" => 0,
  "openended" => 0,
  "quotenum" => 1,
  "unicode" => 1);
my %intopts = (
  "indent" => 2,
  "wrapwidth" => 80);
my %stropts = (
               # default and allowed values
  "boolean" => [undef, "JSON::PP", "boolean" ],
  "encoding" => [ "any", "any", "utf8", "utf16le", "utf16be" ],
  "linebreak" => [ "any", "any", "cr", "ln", "crln" ] );

while (my ($b, $def) = each %boolopts) {
  my $getter = "get_". $b;
  is ($obj->$getter, $def == 0 ? '' : 1, "default $b is $def");
  $obj->$b; # turns it on
  is ($obj->$getter, 1, "$b turned on");
  $obj->$b($def == 0 ? 0 : 1); # switch it
  is ($obj->$getter, $def == 0 ? '' : 1, "$b switched");
}

while (my ($b, $def) = each %intopts) {
  my $getter = "get_". $b;
  is ($obj->$getter, $def, "default $b");
  $obj->$b(8);
  is ($obj->$getter, 8, "set $b to 8");
  eval { $obj->$b(-1) };
  like($@, qr/Invalid YAML::Safe->$b value -1/, "error with -1");
}

while (my ($b, $defa) = each %stropts) {
  my $getter = "get_". $b;
  my $def = shift @$defa;
  my @vals = @$defa;
  is ($def, $obj->$getter, "default $b");
  # note "$b: $def | ",join" ",@vals;
  for (@vals) {
    if ($b eq 'boolean') {
      eval { $obj->$b($_) }; # may fail in load_module()
    } else {
      $obj->$b($_);
    }
    if ($b eq 'boolean' and $@) {
      ok (1, "skip $b($_) $@");
      # $obj = YAML::Safe->new unless $obj;
    } else {
      is ($_, $obj->$getter, "set $b to $_");
    }
  }
  eval { $obj->$b("42") };
  like($@, qr/Invalid YAML::Safe->$b value 42/, "$b error with 42");
}
