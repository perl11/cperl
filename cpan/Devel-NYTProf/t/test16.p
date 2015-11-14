# tests given/when.  Can only be tested by Perl 5.10 or later.

use warnings;
use strict;

use feature ":5.10";

sub foo {
    my $whameth = shift;
    given ($whameth) {
        when(/\d/) {
            say "number-like";
        }
        when(/\w/) {
            say "word-like";
        }
    }
}

sub bar {
    my $zlott = shift;
    if($zlott =~ /\d/) {
        print "number-like\n";
    } elsif($zlott =~ /\w/) {
        print "word-like\n";
    } 
}


foo("baz");
foo(17);
bar("baz");
bar(17);
