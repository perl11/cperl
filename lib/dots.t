#!./perl -w

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require "./test.pl";

    plan ('no_plan');

    use_ok('dots');
}

use strict;

sub Original::new { bless [1], "Original"; }
sub new { "new" }

{ use dots;
  my $obj = new Original;
  my $result = $obj.new;
  my $new = "new";
  is ($result->[0], 1,        '$obj.new   as method');
  like ($obj."new", qr/new$/, '$obj."new" as string');
  like ($obj.$new, qr/new$/,  '$obj.$new  as string');
  like ($obj. new, qr/new$/,  '$obj. new  as string');
}

{ no dots;
  my $obj = new Original;
  my $new = "new";
  like ($obj.new, qr/new$/,   '$obj.new   as string');
  like ($obj."new", qr/new$/, '$obj."new" as string');
  like ($obj.$new, qr/new$/,  '$obj.$new  as string');
  like ($obj. new, qr/new$/,  '$obj. new  as string');
}
