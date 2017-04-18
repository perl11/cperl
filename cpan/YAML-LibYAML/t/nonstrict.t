use lib '.';
use t::TestYAMLTests tests => 2;

my $yaml = <<"...";
---
requires:
    Apache::Request:               1.1
    Class::Date:                   
...

ok (! eval{ Load($yaml) }, "strict yaml fails" );

{
  no warnings 'once';
  local $YAML::XS::NonStrict = 1;
  my $h;
  ok ( $h = Load($yaml), "nonstrict yaml passes" );
}

