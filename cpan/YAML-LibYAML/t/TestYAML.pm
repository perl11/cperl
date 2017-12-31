package t::TestYAML;
use lib 'inc';
use Test::Base -Base;
BEGIN {
  if ($ENV{PERL_CORE}) {
    @INC = ('../../lib', '../../lib/auto', 'inc', '.');
  } else {
    require blib; blib->import();
  }
}
use File::Path 'rmtree';
our @EXPORT = qw(rmtree);

no_diff;
delimiters ('===', '+++');
