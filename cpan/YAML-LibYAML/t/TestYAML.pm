package t::TestYAML;
use lib 'inc';
use Test::Base -Base;
use blib;
use File::Path 'rmtree';
our @EXPORT = qw(rmtree);

no_diff;
delimiters ('===', '+++');
