package Devel::NYTProf::SubCallInfo;

use strict;
use warnings;
use Carp;

use Devel::NYTProf::Constants qw(
    NYTP_SCi_CALL_COUNT
    NYTP_SCi_INCL_RTIME NYTP_SCi_EXCL_RTIME NYTP_SCi_RECI_RTIME
    NYTP_SCi_REC_DEPTH NYTP_SCi_CALLING_SUB
    NYTP_SCi_elements
);

sub calls      { shift->[NYTP_SCi_CALL_COUNT] }

sub incl_time  { shift->[NYTP_SCi_INCL_RTIME] }

sub excl_time  { shift->[NYTP_SCi_EXCL_RTIME] }

sub recur_max_depth { shift->[NYTP_SCi_REC_DEPTH] }

sub recur_incl_time { shift->[NYTP_SCi_RECI_RTIME] }


# vim:ts=8:sw=4:et
1;
