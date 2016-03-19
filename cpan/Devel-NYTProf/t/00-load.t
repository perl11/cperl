use Test::More tests => 2;

use Config;

use_ok( 'Devel::NYTProf::Core' );

# we note the time in the test log here (the first test) and in t/zzz.t
# so we can judge how fast the set of tests ran and this the rough speed of the system
diag( "Testing Devel::NYTProf $Devel::NYTProf::Core::VERSION started at ".localtime(time) );

use_ok( 'Devel::NYTProf::Constants', qw(
    NYTP_DEFAULT_COMPRESSION NYTP_ZLIB_VERSION
) );

diag( sprintf "Compression: default level is %d, zlib version %s",
    NYTP_DEFAULT_COMPRESSION(), NYTP_ZLIB_VERSION()
);

diag "--- Perl $] Config on $Config{archname}:";
diag "\t$_: ".(defined $Config{$_} ? $Config{$_} : '(undef)')
    for qw(
        d_gettimeod d_sysconf
    );

if ("$Config{archname} $Config{osvers}" =~ /\b xen \b/x
    or -d "/proc/xen" # maybe
) {
    diag("------------------------");
    diag("--- Xen platform issues:");
    diag("It looks like this is running inside a Xen virtual machine.");
    diag("Operating system clocks may appear to be unstable in this situation,");
    diag("so tests may fail or produce odd warnings.");
    diag("See results from http://www.google.com/search?q=xen+clock+backwards");
    diag("Including https://bugs.launchpad.net/xen/+bug/146924");
    diag("And https://bugzilla.redhat.com/show_bug.cgi?id=449346");
    diag("And http://rhn.redhat.com/errata/RHSA-2009-1243.html");
    diag("In short, you may need to upgrade Xen and/or your OS.");
    diag("Note that use of NYTProf inside a virtual machine is likely to affect accuracy anyway.");
    diag("------------------------");
}

my @env = grep { /^NYTPROF/ } sort keys %ENV;
diag("--- Environment variables:") if @env;
diag("\t$_=$ENV{$_}") for @env;
