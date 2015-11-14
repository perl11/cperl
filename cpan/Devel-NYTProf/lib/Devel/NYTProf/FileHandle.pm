#!perl
use strict;
use warnings;

package Devel::NYTProf::FileHandle;

# We have to jump through some hoops to load a second XS file from the same
# shared object.

require DynaLoader;
require Devel::NYTProf::Core;

my $c_name = 'boot_Devel__NYTProf__FileHandle';
my $c = DynaLoader::dl_find_symbol_anywhere($c_name);

die "Can't locate '$c_name' in Devel::NYTProf shared object" unless $c;
my $xs = DynaLoader::dl_install_xsub(__PACKAGE__ . '::bootstrap', $c, __FILE__);
&$xs(__PACKAGE__, $Devel::NYTProf::Core::VERSION);

