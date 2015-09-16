# XSLoader for perl, not miniperl

# for a description of the variables, please have a look at the
# Porting/Glossary file, or use the url:
# http://perl5.git.perl.org/perl.git/blob/HEAD:/Porting/Glossary

package Config;
use strict;
use warnings;
use vars '%Config', '$VERSION';

$VERSION = "5.022002"; # keep that in sync with patchlevel.h manually!

# Skip @Config::EXPORT because it only contains %Config, which we special
# case below as it's not a function. @Config::EXPORT won't change in the
# lifetime of Perl 5.
my %Export_Cache = (myconfig => 1, config_sh => 1, config_vars => 1,
		    config_re => 1, compile_date => 1, local_patches => 1,
		    bincompat_options => 1, non_bincompat_options => 1,
		    header_files => 1);

@Config::EXPORT = qw(%Config);
@Config::EXPORT_OK = keys %Export_Cache;

# Need to stub all the functions to make code such as print Config::config_sh
# keep working

sub bincompat_options;
sub compile_date;
sub config_re;
sub config_sh;
sub config_vars;
sub header_files;
sub local_patches;
sub myconfig;
sub non_bincompat_options;

# Define our own import method to avoid pulling in the full Exporter:
sub import {
    shift;
    @_ = @Config::EXPORT unless @_;

    my @funcs = grep $_ ne '%Config', @_;
    my $export_Config = @funcs < @_ ? 1 : 0;

    no strict 'refs';
    my $callpkg = caller(0);
    foreach my $func (@funcs) {
	die qq{"$func" is not exported by the Config module\n}
	    unless $Export_Cache{$func};
	*{$callpkg.'::'.$func} = \&{$func};
    }

    *{"$callpkg\::Config"} = \%Config if $export_Config;
    return;
}

sub TIEHASH {
    $_[1] = {} unless $_[1];
    bless $_[1], $_[0];
}
sub DESTROY { }
sub STORE  { die "\%Config::Config is read-only\n" }
*DELETE = *CLEAR = \*STORE; # Typeglob aliasing uses less space

if (defined &XSLoader::load) {
    XSLoader::load(__PACKAGE__, $VERSION);
    %Config = ();
    tie %Config, 'Config';
} else {
    no warnings 'redefine';
    %Config:: = ();
    undef &{$_} for qw(import TIEHASH DESTROY AUTOLOAD STORE);
    require 'Config_mini.pl';
}

sub AUTOLOAD {
    if (defined &XSLoader::load) {
        require 'Config_xs_heavy.pl';
    }
    goto \&launcher unless $Config::AUTOLOAD =~ /launcher$/;
    die "&Config::AUTOLOAD failed on $Config::AUTOLOAD";
}
