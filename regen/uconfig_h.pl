#!/usr/bin/perl -w
#
# Regenerate (overwriting only if changed):
#
#    uconfig.h
#
# from uconfig.h config_h.SH
#
# Accepts the standard regen_lib -q and -v args.

use strict;
use Config;

if ($^O =~ /^(MSWin\d\d|os2|dos|mint)$/) {
    if (system('sh -c exit 0') != 0) {
        warn '#skipping uconfig_h.pl, sh not available on this platform';
        exit 0;
    }
}

require './regen/regen_lib.pl';

my ($uconfig_h, $uconfig_h_new, $config_h_sh)
    = ('uconfig.h', 'uconfig.h-new', 'config_h.SH');

$ENV{CONFIG_SH} = 'uconfig.sh';
$ENV{CONFIG_H} = $uconfig_h_new;
safer_unlink($uconfig_h_new);

my $command = 'sh ./config_h.SH';
system $command and die "`$command` failed, \$?=$?";

my $fh = open_new($uconfig_h, '>>');

read_only_bottom_close_and_rename($fh, [$ENV{CONFIG_SH}, 'config_h.SH']);
