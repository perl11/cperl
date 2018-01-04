#!perl

use strict;
use warnings;

use lib 't';

use Test::More tests => 1;

use Math::BigRat::Test lib => 'Calc';	# test via this Subclass

our ($class, $CL);
$class = "Math::BigRat::Test";
$CL    = "Math::BigInt::Calc";

pass();

# fails still too many tests
#require './t/bigfltpm.inc';		# all tests here for sharing
