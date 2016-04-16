#!/usr/bin/perl -w

# Test that rel2abs() works correctly when the process is under a symlink
# See [rt.cpan.org 47637]

use strict;

use File::Path;
use File::Spec;

# Do this to simulate already being inside a symlinked directory
# and having $ENV{PWD} set.
use Cwd qw(chdir);

use Test::More;

plan skip_all => "needs symlink()" if !eval { symlink("", ""); 1 };

plan tests => 1;

my $real_dir = "for_rel2abs_test";
my $symlink  = "link_for_rel2abs_test";
mkdir $real_dir or die "Can't make $real_dir: $!";
END { rmtree $real_dir }

symlink $real_dir, $symlink or die "Can't symlink $real_dir => $symlink: $!";
END { unlink $symlink }

chdir $symlink or die "Can't chdir into $symlink: $!";
push @INC, '../../../lib' if $ENV{PERL_CORE};

TODO: {
  local $TODO = 'Need to find a way to make cwd work reliably under symlinks"';
  like( File::Spec->rel2abs("."), qr/$symlink/ );
}

# So the unlinking works
chdir "..";
