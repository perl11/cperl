#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=256
# initialize all global vars
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 8;

my $pv_vars = {';' => "\34",
               '"' => " ",
               #"\\" => undef,
               #',' => undef,
               #'/' => "/n",
               '^A'  => undef,
               '^L'  => "\f",
               ':'  => " \n-",
               '^' => "STDOUT_TOP",
               '~' => "STDOUT"};
my $iv_vars = {'^H' => 0,
               '|' => 0,
               '%' => 0,
               '-' => 60,
               '=' => 60,
               #'{^UNICODE}' => 0,
               #'{^UTF8LOCALE}' => 1
               };

my $script = '';
$script .= sprintf('BEGIN{ $%s = "a"} $%s = "a"; print qq{not ok - \$%s = $%s\n} if $%s ne "a";'."\n", 
                   $_, $_, $_, $_, $_) for keys %$pv_vars;
$script .= sprintf('BEGIN{ $%s = 1} $%s = 1; print qq{not ok - \$%s = $%s\n} if $%s != 1;'."\n",
                   $_, $_, $_, $_, $_) for keys %$iv_vars;
$script .= 'BEGIN{ $\\ = "\n"; } $\\ = "\n"; print qq{not ok - \$\\ = $\\\n} if $\\ ne "\n";'."\n";
$script .= qq(print "ok\\n";);

ctestok(1,'C,-O3','ccode256i',$script,'#256 initialize most global vars');
ctestok(2,'C,-O3','ccode256i',
        'BEGIN{$, = " "; } $, = " "; print $, eq " " ? "ok\n" : qq{not ok - \$, = $,\n}',
        '#256 initialize $,');

# need -C -CL switches to set UNICODE
if ($] >= 5.010001) {
  ctestok(3,'C,-O3 -C','ccode231i',
        'print ${^UNICODE} ? "ok" : "not ok",  " - \${^UNICODE} = ${^UNICODE}\n";',
        '#231 initialize ${^UNICODE}');
  ctestok(4,'C,-O3 -CL','ccode231i',
        'print ${^UTF8LOCALE} == 1 ? "ok\n" : qq{not ok - \${^UTF8LOCALE} = ${^UTF8LOCALE}\n};',
        '#231 initialize ${^UTF8LOCALE}');
} else {
  ok 1, "skip -C with <5.10.1";
  ok 1, "skip -CL with <5.10.1";
}

ctestok(5,'C,-O3','ccode306i',<<'EOF', '#306 localize RS $/'); # see also #314
package foo; sub check_dol_slash { print ($/ eq "\n" ? "ok" : "not ok") ; print  "\n"} sub begin_local { local $/;} ; package main; BEGIN { foo::begin_local() }  foo::check_dol_slash();
EOF

ctestok(6,'C,-O3','ccode314i',<<'EOF', '#314 localize and set RS $/ = "b" (sv->gv magic)');
open FOO, ">", "ccode314.tmp"; print FOO "abc"; close FOO; open FOO, "<", "ccode314.tmp"; { local $/="b"; $in=<FOO>; if ($in eq "ab") { print "ok\n" } else { print qq(separator: "$/"\n\$/ is "$/"\nFAIL: "$in"\n)}}; unlink "ccode314.tmp";
EOF

ctestok(7,'C,-O3','ccode306i',<<'EOF', '#256 initialize RS $/');
BEGIN{ $/ = "1"; } print "ok\n" if $/ == "1"
EOF

ctestok(8,'C,-O3','ccode318i',<<'EOF', '#318 localize and set ORS $\ = "b"');
{ local $\ = "ok" ; print "" }
EOF

