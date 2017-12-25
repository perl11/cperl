#!./perl

# Checks if package unicode support work as intended.

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    skip_all_without_unicode_tables();
}

plan (tests => 18);

use utf8; # Hangul only
use open qw( :utf8 :std );

package Føø::Bær { }

package 수요일 { }

package 년::이번 { }

ok 1, "sanity check. If we got this far, UTF-8 in package names is legal.";

#The next few come from comp/package.t
{

    $압 = 123;
    
    package 년;

    sub 내일 { bless []; }
    $bar = 4;
    {
        package 압십;
        $압 = 5;
    }
    
    $압십::d열시 = 6;

    $년 = 2;
    
    $년 = join(':', sort(keys %년::));
    $압십 = join(':', sort(keys %압십::));
    
    ::is $년, 'BEGIN:bar:내일:년:압십:이번::', "comp/stash.t test 1";
    ::is $압십, "BEGIN:d열시:압", "comp/stash.t test 2";
    ::is $main::압, 123, "comp/stash.t test 3";

    package 압십;

    ::is $압, 5, "comp/stash.t test 4";
    eval q(::is $압, 5, "comp/stash.t test 5";);
    eval q(package main; is $압, 123, "comp/stash.t test 6";);
    ::is $압, 5, "comp/stash.t test 7";

    #This is actually pretty bad, as caller() wasn't clean to begin with.
    package main;
    sub 여 { caller(0) }
    
    sub 섯 {
        my $s = shift;
        if ($s) {
            package 분QR;
            main::여();
        }
    }
    
    is((섯(1))[0], '분QR', "comp/stash.t test 8");
    
    my $Q = 년->내일();
    undef %년::;
    eval { $a = *년::내일{PACKAGE}; };
    is $a, "__ANON__", "comp/stash.t test 9";

    {
        local $@;
        eval { $Q->param; };
        like $@, qr/^Can't use anonymous symbol table for method lookup/, "comp/stash.t test 10";
    }
    
    like "$Q", qr/^__ANON__=/, "comp/stash.t test 11";

    is ref $Q, "__ANON__", "comp/stash.t test 12";

    package bugⅲⅱⅴⅵⅱ { #not really latin, but bear with me, I'm not Damian.
        ::is( __PACKAGE__,   'bugⅲⅱⅴⅵⅱ', "comp/stash.t test 13");
        ::is( eval('__PACKAGE__'), 'bugⅲⅱⅴⅵⅱ', "comp/stash.t test 14");
    }
}

#This comes from comp/package_block.t
{
    local $@;
    eval q[package 년 {];
    like $@, qr/\AMissing right curly /, "comp/package_block.t test";
}

# perl #105922

{
   my $latin_1 = "þackage";
   my $utf8    = "þackage";
   utf8::downgrade($latin_1);
   utf8::upgrade($utf8);

   local $@;
   eval { $latin_1->can("yadda") };
   ok(!$@, "latin1->meth works");

   local $@;
   eval { $utf8->can("yadda") };
   ok(!$@, "utf8->meth works");
}
