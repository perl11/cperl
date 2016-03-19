package Devel::NYTProf::SubInfo;    # sub_subinfo

use strict;
use warnings;
use Carp;

use List::Util qw(sum min max);
use Data::Dumper;

use Devel::NYTProf::Util qw(
    trace_level
);
use Devel::NYTProf::Constants qw(
    NYTP_SIi_FID NYTP_SIi_FIRST_LINE NYTP_SIi_LAST_LINE
    NYTP_SIi_CALL_COUNT NYTP_SIi_INCL_RTIME NYTP_SIi_EXCL_RTIME
    NYTP_SIi_SUB_NAME NYTP_SIi_PROFILE
    NYTP_SIi_REC_DEPTH NYTP_SIi_RECI_RTIME NYTP_SIi_CALLED_BY
    NYTP_SIi_elements

    NYTP_SCi_CALL_COUNT
    NYTP_SCi_INCL_RTIME NYTP_SCi_EXCL_RTIME NYTP_SCi_RECI_RTIME
    NYTP_SCi_REC_DEPTH NYTP_SCi_CALLING_SUB
    NYTP_SCi_elements
);

# extra constants for private elements
use constant {
    NYTP_SIi_meta            => NYTP_SIi_elements + 1,
    NYTP_SIi_cache           => NYTP_SIi_elements + 2,
};


sub fid        { shift->[NYTP_SIi_FID] || 0 }

sub first_line { shift->[NYTP_SIi_FIRST_LINE] }

sub last_line  { shift->[NYTP_SIi_LAST_LINE] }

sub calls      { shift->[NYTP_SIi_CALL_COUNT] }

sub incl_time  { shift->[NYTP_SIi_INCL_RTIME] }

sub excl_time  { shift->[NYTP_SIi_EXCL_RTIME] }

sub subname    { shift->[NYTP_SIi_SUB_NAME] }

sub subname_without_package {
    my $subname = shift->[NYTP_SIi_SUB_NAME];
    $subname =~ s/.*:://;
    return $subname;
}

sub profile    { shift->[NYTP_SIi_PROFILE] }

sub package    { (my $pkg = shift->subname) =~ s/^(.*)::.*/$1/; return $pkg }

sub recur_max_depth { shift->[NYTP_SIi_REC_DEPTH] }

sub recur_incl_time { shift->[NYTP_SIi_RECI_RTIME] }


# general purpose hash - mainly a hack to help kill off Reader.pm
sub meta      { shift->[NYTP_SIi_meta()] ||= {} }
# general purpose cache
sub cache     { shift->[NYTP_SIi_cache()] ||= {} }


# { fid => { line => [ count, incl_time ] } }
sub caller_fid_line_places {
    my ($self, $merge_evals) = @_;
    carp "caller_fid_line_places doesn't merge evals yet" if $merge_evals;
    # shallow clone to remove fid 0 is_sub hack
    my %tmp = %{ $self->[NYTP_SIi_CALLED_BY] || {} };
    delete $tmp{0};
    return \%tmp;
}

sub called_by_subnames {
    my ($self) = @_;
    my $callers = $self->caller_fid_line_places || {};

    my %subnames;
    for my $sc (map { values %$_ } values %$callers) {
        my $caller_subnames = $sc->[NYTP_SCi_CALLING_SUB];
        @subnames{ keys %$caller_subnames } = (); # viv keys
    }

    return \%subnames;
}

sub is_xsub {
    my $self = shift;

    # XXX should test == 0 but some xsubs still have undef first_line etc
    # XXX shouldn't include opcode
    my $first = $self->first_line;
    return undef if not defined $first;
    return 1     if $first == 0 && $self->last_line == 0;
    return 0;
}

sub is_opcode {
    my $self = shift;
    return 0 if $self->first_line or $self->last_line;
    return 1 if $self->subname =~ m/(?:^CORE::|::CORE:)\w+$/;
    return 0;
}

sub is_anon {
    shift->subname =~ m/::__ANON__\b/;
}

sub kind {
    my $self = shift;
    return 'opcode' if $self->is_opcode;
    return 'xsub'   if $self->is_xsub;
    return 'perl';
}

sub fileinfo {
    my $self = shift;
    my $fid  = $self->fid;
    if (!$fid) {
        return undef;    # sub not have a known fid
    }
    $self->profile->fileinfo_of($fid);
}

sub clone {             # shallow
    my $self = shift;
    return bless [ @$self ] => ref $self;
}

sub _min {
    my ($a, $b) = @_;
    $a = $b if not defined $a;
    $b = $a if not defined $b;
    # either both are defined or both are undefined here
    return undef unless defined $a;
    return min($a, $b);
}

sub _max {
    my ($a, $b) = @_;
    $a = $b if not defined $a;
    $b = $a if not defined $b;
    # either both are defined or both are undefined here
    return undef unless defined $a;
    return max($a, $b);
}


sub _alter_fileinfo {
    my ($self, $remove_fi, $new_fi) = @_;
    my $remove_fid = ($remove_fi) ? $remove_fi->fid : 0;
    my $new_fid    = (   $new_fi) ?    $new_fi->fid : 0;

    if ($self->fid == $remove_fid) {
        $self->[NYTP_SIi_FID] = $new_fid;

        $remove_fi->_remove_sub_defined($self) if $remove_fi;
        $new_fi->_add_new_sub_defined($self) if $new_fi;
    }
}


sub _alter_called_by_fileinfo {
    my ($self, $remove_fi, $new_fi) = @_;
    my $remove_fid = ($remove_fi) ? $remove_fi->fid : 0;
    my $new_fid    = (   $new_fi) ?    $new_fi->fid : 0;

    # remove mentions of $remove_fid from called-by details
    # { fid => { line => [ count, incl, excl, ... ] } }
    if (my $called_by = $self->[NYTP_SIi_CALLED_BY]) {
        my $cb = delete $called_by->{$remove_fid};

        if ($cb && $new_fid) {
            my $new_cb = $called_by->{$new_fid} ||= {};

            warn sprintf "_alter_called_by_fileinfo: %s from fid %d to fid %d\n",
                    $self->subname, $remove_fid, $new_fid
                if trace_level() >= 4;

            # merge $cb into $new_cb
            while ( my ($line, $cb_li) = each %$cb ) {
                my $dst_line_info = $new_cb->{$line} ||= [];
                _merge_in_caller_info($dst_line_info, delete $cb->{$line},
                    tag => "$line:".$self->subname,
                );
            }

        }
    }

}




# merge details of another sub into this one
# there are very few cases where this is sane thing to do
# it's meant for merging things like anon-subs in evals
# e.g., "PPI::Node::__ANON__[(eval 286)[PPI/Node.pm:642]:4]"
sub merge_in {
    my ($self, $donor, %opts) = @_;
    my $self_subname  = $self->subname;
    my $donor_subname = $donor->subname;

    warn sprintf "Merging sub %s into %s (%s)\n",
            $donor_subname, $self_subname, join(" ", %opts)
        if trace_level() >= 4;

    # see also "case NYTP_TAG_SUB_CALLERS:" in load_profile_data_from_stream()
    push @{ $self->meta->{merged_sub_names} }, $donor->subname;

    $self->[NYTP_SIi_FIRST_LINE]  = _min($self->[NYTP_SIi_FIRST_LINE], $donor->[NYTP_SIi_FIRST_LINE]);
    $self->[NYTP_SIi_LAST_LINE]   = _max($self->[NYTP_SIi_LAST_LINE],  $donor->[NYTP_SIi_LAST_LINE]);
    $self->[NYTP_SIi_CALL_COUNT] += $donor->[NYTP_SIi_CALL_COUNT];
    $self->[NYTP_SIi_INCL_RTIME] += $donor->[NYTP_SIi_INCL_RTIME];
    $self->[NYTP_SIi_EXCL_RTIME] += $donor->[NYTP_SIi_EXCL_RTIME];
    $self->[NYTP_SIi_REC_DEPTH]   = max($self->[NYTP_SIi_REC_DEPTH], $donor->[NYTP_SIi_REC_DEPTH]);
    # adding reci_rtime is correct only if one sub doesn't call the other
    $self->[NYTP_SIi_RECI_RTIME] += $donor->[NYTP_SIi_RECI_RTIME]; # XXX

    # { fid => { line => [ count, incl_time, ... ] } }
    my $dst_called_by = $self ->[NYTP_SIi_CALLED_BY] ||= {};
    my $src_called_by = $donor->[NYTP_SIi_CALLED_BY] ||  {};

    $opts{opts} ||= "merge in $donor_subname";

    # iterate over src and merge into dst
    while (my ($fid, $src_line_hash) = each %$src_called_by) {

        my $dst_line_hash = $dst_called_by->{$fid};

        # merge lines in %$src_line_hash into %$dst_line_hash
        for my $line (keys %$src_line_hash) {
            my $dst_line_info = $dst_line_hash->{$line} ||= [];
            my $src_line_info = $src_line_hash->{$line};
            delete $src_line_hash->{$line} unless $opts{src_keep};
            _merge_in_caller_info($dst_line_info, $src_line_info, %opts);
        }
    }

    return;
}


sub _merge_in_caller_info {
    my ($dst_line_info, $src_line_info, %opts) = @_;
    my $tag = ($opts{tag}) ? " $opts{tag}" : "";

    if (!@$src_line_info) {
        carp sprintf "_merge_in_caller_info%s skipped (empty donor)", $tag
            if trace_level();
        return;
    }

    if (trace_level() >= 5) {
        carp sprintf "_merge_in_caller_info%s merging from $src_line_info -> $dst_line_info:", $tag;
        warn sprintf " . %s\n", _fmt_sc($src_line_info);
        warn sprintf " + %s\n", _fmt_sc($dst_line_info);
    }
    if (!@$dst_line_info) {
        @$dst_line_info = (0) x NYTP_SCi_elements;
        $dst_line_info->[NYTP_SCi_CALLING_SUB] = undef;
    }

    # merge @$src_line_info into @$dst_line_info
    $dst_line_info->[$_] += $src_line_info->[$_] for (
        NYTP_SCi_CALL_COUNT, NYTP_SCi_INCL_RTIME, NYTP_SCi_EXCL_RTIME,
    );
    $dst_line_info->[NYTP_SCi_REC_DEPTH] = max($dst_line_info->[NYTP_SCi_REC_DEPTH],
                                                $src_line_info->[NYTP_SCi_REC_DEPTH]);
    # ug, we can't really combine recursive incl_time, but this is better than undef
    $dst_line_info->[NYTP_SCi_RECI_RTIME] = max($dst_line_info->[NYTP_SCi_RECI_RTIME],
                                                $src_line_info->[NYTP_SCi_RECI_RTIME]);

    my $src_cs = $src_line_info->[NYTP_SCi_CALLING_SUB]|| {};
    my $dst_cs = $dst_line_info->[NYTP_SCi_CALLING_SUB]||={};
    $dst_cs->{$_} = $src_cs->{$_} for keys %$src_cs;

    warn sprintf " = %s\n", _fmt_sc($dst_line_info)
        if trace_level() >= 5;

    return;
}

sub _fmt_sc {
    my ($sc) = @_;
    return "(empty)" if !@$sc;
    my $dst_cs = $sc->[NYTP_SCi_CALLING_SUB]||{};
    my $by = join " & ", sort keys %$dst_cs;
    sprintf "calls %d%s",
        $sc->[NYTP_SCi_CALL_COUNT], ($by) ? ", by $by" : "";
}


sub caller_fids {
    my ($self, $merge_evals) = @_;
    my $callers = $self->caller_fid_line_places($merge_evals) || {};
    my @fids = keys %$callers;
    return @fids;    # count in scalar context
}

sub caller_count { return scalar shift->caller_places; } # XXX deprecate later

# array of [ $fid, $line, $sub_call_info ], ...
sub caller_places {
    my ($self, $merge_evals) = @_;
    my $callers = $self->caller_fid_line_places || {};

    my @callers;
    for my $fid (sort { $a <=> $b } keys %$callers) {
        my $lines_hash = $callers->{$fid};
        for my $line (sort { $a <=> $b } keys %$lines_hash) {
            push @callers, [ $fid, $line, $lines_hash->{$line} ];
        }
    }

    return @callers; # scalar: number of distinct calling locations
}

sub normalize_for_test {
    my $self = shift;
    my $profile = $self->profile;

    # normalize eval sequence numbers in anon sub names to 0
    $self->[NYTP_SIi_SUB_NAME] =~ s/ \( ((?:re_)?) eval \s \d+ \) /(${1}eval 0)/xg
        if $self->[NYTP_SIi_SUB_NAME] =~ m/__ANON__/
        && not $ENV{NYTPROF_TEST_SKIP_EVAL_NORM};

    # zero subroutine inclusive time
    $self->[NYTP_SIi_INCL_RTIME] = 0;
    $self->[NYTP_SIi_EXCL_RTIME] = 0;
    $self->[NYTP_SIi_RECI_RTIME] = 0;

    # { fid => { line => [ count, incl, excl, ... ] } }
    my $callers = $self->[NYTP_SIi_CALLED_BY] || {};

    # calls from modules shipped with perl cause problems for tests
    # because the line numbers vary between perl versions, so here we
    # edit the line number of calls from these modules
    for my $fid (keys %$callers) {
        next if not $fid;
        my $fileinfo = $profile->fileinfo_of($fid) or next;
        next if $fileinfo->filename !~ /(AutoLoader|Exporter)\.pm$/;

        # normalize the lines X,Y,Z to 1,2,3
        my %lines = %{ delete $callers->{$fid} };
        my @lines = @lines{sort { $a <=> $b } keys %lines};
        $callers->{$fid} = { map { $_ => shift @lines } 1..@lines };
    }

    for my $sc (map { values %$_ } values %$callers) {
        # zero per-call-location subroutine inclusive time
        $sc->[NYTP_SCi_INCL_RTIME] =
        $sc->[NYTP_SCi_EXCL_RTIME] =
        $sc->[NYTP_SCi_RECI_RTIME] = 0;

        if (not $ENV{NYTPROF_TEST_SKIP_EVAL_NORM}) {
            # normalize eval sequence numbers in anon sub names to 0
            my $names = $sc->[NYTP_SCi_CALLING_SUB]||{};
            for my $subname (keys %$names) {
                (my $newname = $subname) =~ s/ \( ((?:re_)?) eval \s \d+ \) /(${1}eval 0)/xg;
                next if $newname eq $subname;
                warn "Normalizing $subname to $newname overwrote other calling-sub data\n"
                    if $names->{$newname};
                $names->{$newname} = delete $names->{$subname};
            }
        }

    }
    return $self->[NYTP_SIi_SUB_NAME];
}

sub dump {
    my ($self, $separator, $fh, $path, $prefix) = @_;

    my ($fid, $l1, $l2, $calls) = @{$self}[
        NYTP_SIi_FID, NYTP_SIi_FIRST_LINE, NYTP_SIi_LAST_LINE, NYTP_SIi_CALL_COUNT
    ];
    my @values = @{$self}[
        NYTP_SIi_INCL_RTIME, NYTP_SIi_EXCL_RTIME,
        NYTP_SIi_REC_DEPTH, NYTP_SIi_RECI_RTIME
    ];
    printf $fh "%s[ %s:%s-%s calls %s times %s ]\n",
        $prefix,
        map({ defined($_) ? $_ : 'undef' } $fid, $l1, $l2, $calls),
        join(" ", map { defined($_) ? $_ : 'undef' } @values);

    my @caller_places = $self->caller_places;
    for my $cp (@caller_places) {
        my ($fid, $line, $sc) = @$cp;
        my @sc = @$sc;
        $sc[NYTP_SCi_CALLING_SUB] = join "|", sort keys %{ $sc[NYTP_SCi_CALLING_SUB] };
        printf $fh "%s%s%s%d:%d%s[ %s ]\n",
            $prefix,
            'called_by', $separator,
            $fid, $line, $separator,
            join(" ", map { defined($_) ? $_ : 'undef' } @sc);
    }

    # where a sub has had others merged into it, list them
    my $merge_subs = $self->meta->{merged_sub_names} || [];
    for my $ms (sort @$merge_subs) {
        printf $fh "%s%s%s%s\n",
            $prefix, 'merge_donor', $separator, $ms;
    }
}

# vim:ts=8:sw=4:et
1;
