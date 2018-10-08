# check if all the modules can load stand-alone

use strict;
eval 'use warnings';

my %has_deps = (
    'blib/lib/CPAN/HTTP/Client.pm' => {
        'HTTP::Tiny' => '0.005',
    },
);

my @modules;
use File::Find;
find(\&list_modules, $ENV{PERL_CORE} ? 'lib' : 'blib/lib');

use Test::More;
plan(tests => scalar @modules);
foreach my $file (@modules) {
    #diag $file;
    system("$^X -c $file >out 2>err");
    my $fail;
    if (open ERR, '<err') {
        my $stderr = join('', <ERR>);
        if ($stderr !~ /^$file syntax OK$/m) {
            $fail = $stderr;
            # it's a terrible job to whitewash warnings we cannot prevent
            $fail =~ s/Argument \S+ isn't numeric.*\s*//;
        }
    } else {
        $fail = "Could not open 'err' file after running $file";
    }
    ok(!$fail, "Loading $file") or diag $fail;
}


sub list_modules {
    return if $_ !~ /\.pm$/;
    return if _missing_deps($File::Find::name);
    push @modules, $File::Find::name;
    return;
}

sub _missing_deps {
  my $file = shift;
  if ( my $deps = $has_deps{$file} ) {
    while ( my ($mod, $ver) = each %$deps ) {
      eval "require $mod; $mod->VERSION($ver); 1"
        or return 1;
    }
  }
  return;
}

END {
  unlink 'err';
  unlink 'out';
}
