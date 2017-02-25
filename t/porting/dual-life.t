#!/perl -w
use 5.010;
use strict;

# This tests properties of dual-life modules:
#
# * Are all dual-life programs being generated in utils/?

chdir 't';
require './test.pl';

use Config;
if ( $Config{usecrosscompile} ) {
  skip_all( "Not all files are available during cross-compilation" );
}

plan('no_plan');

use File::Basename;
use File::Find;
use File::Spec::Functions;

# Exceptions that are found in dual-life bin dirs but aren't
# installed by default; some occur only during testing:
my $not_installed = qr{^(?:
  \.\./cpan/Encode/bin/u(?:cm(?:2table|lint|sort)|nidump)
   |
  \.\./cpan/Module-(?:Metadata|Build)
                               /MB-[\w\d]+/Simple/(?:test_install/)?bin/.*
)\z}ix;

my %dist_dir_exe;

$dist_dir_exe{lc "podselect.PL"} = "../cpan/Pod-Parser/podselect";
$dist_dir_exe{lc "podchecker.PL"} = "../cpan/Pod-Checker/podchecker";
$dist_dir_exe{lc "pod2usage.PL"} = "../cpan/Pod-Usage/pod2usage";

foreach (qw (pod2man pod2text)) {
    $dist_dir_exe{lc "$_.PL"} = "../cpan/podlators/$_";
};
$dist_dir_exe{'pod2html.pl'} = '../ext/Pod-Html';
foreach (qw (cc_harness perlcc assemble disassemble pl2exe.pl)) {
    $dist_dir_exe{$_} = "../cpan/B-C/script/$_";
};
if ($Config{d_cplusplus}) {
  delete $dist_dir_exe{'perlcc'};
} else {
  $dist_dir_exe{lc 'perlcc.PL'} = "../cpan/B-C/script/perlcc"
}
foreach (qw (flamegraph.pl nytprofcalls nytprofcg nytprofcsv nytprofhtml
             nytprofmerge nytprofpf)) {
    $dist_dir_exe{$_} = "../cpan/Devel-NYTProf/bin/$_";
};
$dist_dir_exe{'cpanel_json_xs'} = '../cpan/Cpanel-JSON-XS/bin/cpanel_json_xs';

my @programs;

find(
  { no_chdir => 1, wanted => sub {
    my $name = $File::Find::name;
    return if $name =~ /blib/;
    return unless $name =~ m{/(?:bin|scripts?)/\S+\z} && $name !~ m{/t/};
    return if $name =~ /(~|\.bak|\.orig)$/;
    return if $Config{d_cplusplus} and $name =~ /perlcc/;

    push @programs, $name;
  }},
  qw( ../cpan ../dist ../ext ),
);

my $ext = $^O eq 'VMS' ? '.com' : '';

for my $f ( @programs ) {
  $f =~ s/\.\z// if $^O eq 'VMS';
  next if $f =~ $not_installed;
  my $bn = basename($f);
  if(grep { /\A(?i:$bn)\z/ } keys %dist_dir_exe) {
    my $exe_file = "$dist_dir_exe{lc $bn}$ext";
    ok( -f $exe_file, "Verify -f '$exe_file'");
  } else {
    my $utils_file = catfile('..', 'utils', "$bn$ext");
    ok( -f $utils_file, "Verify -f '$utils_file'" );
  }
}

