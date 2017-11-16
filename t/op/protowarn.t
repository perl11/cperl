#!./perl

use strict;
use Config ();
BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc( qw(. ../lib) );
}
use warnings;

plan( tests => 6 );

use vars qw{ @warnings $sub $warn };

BEGIN {
    $warn = q{Missing ']' in prototype};
}

sub one_warning_ok {
    cmp_ok(scalar(@warnings), '==', 1, 'One warning '.join('',@_));
    cmp_ok(substr($warnings[0],0,length($warn)),'eq',$warn, $warn);
    @warnings = ();
}

sub no_warning_ok {
    cmp_ok(scalar(@warnings), '==', 0, 'No warnings '.join('',@_));
    diag $warnings[0] if @warnings;
    @warnings = ();
}

BEGIN {
    $SIG{'__WARN__'} = sub { push @warnings, @_ };
    $| = 1;
}

BEGIN { @warnings = () }

# in cperl an illegal@$  proto fails with an syntax error, not just a warning.
# but [ just warns.
$sub = sub ([) { };
BEGIN { one_warning_ok('default') }

{
    no warnings 'syntax';
    $sub = sub ([) { };
    BEGIN { no_warning_ok 'no syntax' }
}

{
    no warnings 'illegalproto';
    $sub = sub ([) { };
    BEGIN { no_warning_ok 'no illegalproto' }
}

{
    no warnings 'syntax';
    use warnings 'illegalproto';
    $sub = sub ([) { };
    BEGIN { one_warning_ok 'use illegalproto' }
}

