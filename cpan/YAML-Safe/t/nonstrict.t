use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 3;

my $obj = YAML::Safe->new;
my $yaml = <<"...";
---
requires:
    Apache::Request:               1.1
    Class::Date:                   
...

ok (! eval{ $obj->Load($yaml) }, "strict yaml fails" );
like ($@, qr/control characters are not allowed/, "with the correct error message" );
ok ( $obj->nonstrict->Load($yaml), "nonstrict yaml passes" );
