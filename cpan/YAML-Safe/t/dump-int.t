use strict;
use warnings;
use FindBin '$Bin';
use lib $Bin;
use TestYAMLTests tests => 5;

#use Devel::Peek ();

use B ();

my $data = { int => 42 };

my $flags = B::svref_2object(\$data->{int})->FLAGS;
my $string = $flags & B::SVp_POK;
my $int = $flags & B::SVp_IOK;
#diag("Flags=$flags int=$int string=$string");

cmp_ok($string, '==', 0, "Before Dump we don't have a string");
cmp_ok($int, '>=', 0, "Before Dump we have an int");

#Devel::Peek::Dump($data->{int});

# Dump shouldn't modify the original data
my $dump = Dump $data;


my $flags2 = B::svref_2object(\$data->{int})->FLAGS;
$string = $flags2 & B::SVp_POK;
$int = $flags2 & B::SVp_IOK;
#diag("Flags=$flags 2int=$int string=$string");

cmp_ok($string, '==', 0, "After Dump we still don't have a string");
cmp_ok($int, '>=', 0, "After Dump we still have an int");

cmp_ok($flags2, '==', $flags, "Flags are the same as before ($flags == $flags2)");

#Devel::Peek::Dump($data->{int});
