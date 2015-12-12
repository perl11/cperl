#! /usr/bin/env perl
# testc.sh 46, GH #
use Test::More tests => 6;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
my $i=0;
#use B::C ();

ctestok($i++, "C,-O3", "ccode46g", <<'EOF', "empty stash");
print 'ok' unless keys %Dummy::;
EOF

ctestok($i++, "C", "ccode46g", <<'EOF', "if stash -O0");
print 'ok' unless %Exporter::;
EOF

ctestok($i++, "C,-O3", "ccode46g", <<'EOF', "if stash -O3");
print 'ok' unless %Exporter::;
EOF

ctestok($i++, "C,-O3", "ccode46g", <<'EOF', "empy keys stash, no %INC");
print 'ok' if keys %Exporter:: < 2;
EOF

ctestok($i++, "C,-O3", "ccode46g", <<'EOF', "TODO use should not skip, special but in %INC");
use Exporter; print 'ok' if keys %Exporter:: > 2;
EOF

ctestok($i++, "C,-O3", "ccode46g", <<'EOF', "use should not skip, in %INC");
use Devel::Peek; print 'ok' if keys %Devel::Peek:: > 2;
EOF

