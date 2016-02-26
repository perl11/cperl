package Devel::NYTProf::FileInfo;    # fid_fileinfo

=head1 NAME

Devel::NYTProf::FileInfo

=cut

use strict;

use Carp;
use Config;
use List::Util qw(sum max);

use Devel::NYTProf::Util qw(strip_prefix_from_paths trace_level);

use Devel::NYTProf::Constants qw(
    NYTP_FIDf_HAS_SRC NYTP_FIDf_SAVE_SRC NYTP_FIDf_IS_FAKE NYTP_FIDf_IS_PMC
    NYTP_FIDf_IS_EVAL

    NYTP_FIDi_FILENAME NYTP_FIDi_EVAL_FID NYTP_FIDi_EVAL_LINE NYTP_FIDi_FID
    NYTP_FIDi_FLAGS NYTP_FIDi_FILESIZE NYTP_FIDi_FILEMTIME NYTP_FIDi_PROFILE
    NYTP_FIDi_EVAL_FI NYTP_FIDi_HAS_EVALS NYTP_FIDi_SUBS_DEFINED NYTP_FIDi_SUBS_CALLED
    NYTP_FIDi_elements

    NYTP_SCi_CALL_COUNT NYTP_SCi_INCL_RTIME NYTP_SCi_EXCL_RTIME NYTP_SCi_RECI_RTIME
    NYTP_SCi_REC_DEPTH NYTP_SCi_CALLING_SUB
    NYTP_SCi_elements
);

# extra constants for private elements
use constant {
    NYTP_FIDi_meta            => NYTP_FIDi_elements + 1,
    NYTP_FIDi_cache           => NYTP_FIDi_elements + 2,
};

sub filename  { shift->[NYTP_FIDi_FILENAME()] }
sub eval_fid  { shift->[NYTP_FIDi_EVAL_FID()] }
sub eval_line { shift->[NYTP_FIDi_EVAL_LINE()] }
sub fid       { shift->[NYTP_FIDi_FID()] }
sub size      { shift->[NYTP_FIDi_FILESIZE()] }
sub mtime     { shift->[NYTP_FIDi_FILEMTIME()] }
sub profile   { shift->[NYTP_FIDi_PROFILE()] }
sub flags     { shift->[NYTP_FIDi_FLAGS()] }

# if an eval then return fileinfo obj for the fid that executed the eval
sub eval_fi   { shift->[NYTP_FIDi_EVAL_FI()] }
#   is_eval is true only for simple string evals (doesn't consider NYTP_FIDf_IS_EVAL)
sub is_eval   { shift->[NYTP_FIDi_EVAL_FI()] ? 1 : 0 }

sub is_fake   { shift->flags & NYTP_FIDf_IS_FAKE }
sub is_file   {
    my $self = shift;
    return not ($self->is_fake or $self->is_eval or $self->flags & NYTP_FIDf_IS_EVAL());
}

# general purpose hash - mainly a hack to help kill off Reader.pm
sub meta      { shift->[NYTP_FIDi_meta()] ||= {} }
# general purpose cache
sub cache     { shift->[NYTP_FIDi_cache()] ||= {} }

# array of fileinfo's for each string eval in the file
sub has_evals {
    my ($self, $include_nested) = @_;

    my $eval_fis = $self->[NYTP_FIDi_HAS_EVALS()]
        or return;
    return @$eval_fis if !$include_nested;

    my @eval_fis = @$eval_fis;
    # walk down tree of nested evals, adding them to @fi
    for (my $i=0; my $fi = $eval_fis[$i]; ++$i) {
        push @eval_fis, $fi->has_evals(0);
    }

    return @eval_fis;
}


sub sibling_evals {
    my ($self) = @_;
    my $parent_fi = $self->eval_fi
        or return; # not an eval
    my $eval_line = $self->eval_line;
    return grep { $_->eval_line == $eval_line } $parent_fi->has_evals;
}


sub _nullify {
    my $self = shift;
    @$self = (); # Zap!
}



# return subs defined as list of SubInfo objects
sub subs_defined {
    my ($self, $incl_nested_evals) = @_;

    return map { $_->subs_defined(0) } $self, $self->has_evals(1)
        if $incl_nested_evals;

    return values %{ $self->[NYTP_FIDi_SUBS_DEFINED()] };
}

sub subs_defined_sorted {
    my ($self, $incl_nested_evals) = @_;
    return sort { $a->subname cmp $b->subname } $self->subs_defined($incl_nested_evals);
}

sub _remove_sub_defined {
    my ($self, $si) = @_;
    my $subname = $si->subname;
    delete $self->[NYTP_FIDi_SUBS_DEFINED()]->{$subname}
        or carp sprintf "_remove_sub_defined: sub %s wasn't defined in %d %s",
            $subname, $self->fid, $self->filename;
}

sub _add_new_sub_defined {
    my ($self, $subinfo) = @_;
    my $subname = $subinfo->subname;
    my $subs_defined = $self->[NYTP_FIDi_SUBS_DEFINED()] ||= {};
    my $existing_si = $subs_defined->{$subname};
    croak sprintf "sub %s already defined in fid %d %s",
            $subname, $self->fid, $self->filename
        if $existing_si;

    $subs_defined->{$subname} = $subinfo;
}

=head1 METHODS

=head2 sub_call_lines

  $hash = $fi->sub_call_lines;

Returns a reference to a hash containing information about subroutine calls
made at individual lines within the source file.
Returns undef if no subroutine calling information is available.

The keys of the returned hash are line numbers. The values are references to
hashes with fully qualified subroutine names as keys. Each hash value is an
reference to an array containing an integer call count (how many times the sub
was called from that line of that file) and an inclusive time (how much time
was spent inside the sub when it was called from that line of that file).

For example, if the following was line 42 of a file C<foo.pl>:

  ++$wiggle if foo(24) == bar(42);

that line was executed once, and foo and bar were imported from pkg1, then
sub_call_lines() would return something like:

  {
      42 => {
        'pkg1::foo' => [ 1, 0.02093 ],
        'pkg1::bar' => [ 1, 0.00154 ],
      },
  }

=cut

sub sub_call_lines  { shift->[NYTP_FIDi_SUBS_CALLED()] }


=head2 evals_by_line

  # { line => { fid_of_eval_at_line => $fi, ... }, ... }
  $hash = $fi->evals_by_line;

Returns a reference to a hash containing information about string evals
executed at individual lines within a source file.

The keys of the returned hash are line numbers. The values are references to
hashes with file id integers as keys and FileInfo objects as values.

=cut

sub evals_by_line {
    my ($self) = @_;

    # find all fids that have this fid as an eval_fid
    # { line => { fid_of_eval_at_line => $fi, ... } }

    my %evals_by_line;
    for my $fi ($self->has_evals) {
        $evals_by_line{ $fi->eval_line }->{ $fi->fid } = $fi;
    }

    return \%evals_by_line;
}


sub line_time_data {
    my ($self, $levels) = @_;
    $levels ||= [ 'line' ];
    # XXX this can be optimized once the fidinfo contains directs refs to the data
    my $profile = $self->profile;
    my $fid = $self->fid;
    for my $level (@$levels) {
        my $fid_ary = $profile->get_fid_line_data($level);
        return $fid_ary->[$fid] if $fid_ary && $fid_ary->[$fid];
    }
    return undef;
}

sub excl_time { # total exclusive time for fid
    my $self = shift;
    my $line_data = $self->line_time_data([qw(sub block line)])
        || return undef;
    my $excl_time = 0;
    for (@$line_data) {
        next unless $_;
        $excl_time += $_->[0];
    }
    return $excl_time;
}


sub sum_of_stmts_count {
    my ($self, $incl_nested_evals) = @_;

    return sum(map { $_->sum_of_stmts_count(0) } $self, $self->has_evals(1))
        if $incl_nested_evals;

    my $ref = \$self->cache->{NYTP_FIDi_sum_stmts_count};
    $$ref = $self->_sum_of_line_time_data(1)
        if not defined $$ref;

    return $$ref;
}

sub sum_of_stmts_time {
    my ($self, $incl_nested_evals) = @_;

    return sum(map { $_->sum_of_stmts_time(0) } $self, $self->has_evals(1))
        if $incl_nested_evals;

    my $ref = \$self->cache->{NYTP_FIDi_sum_stmts_times};
    $$ref = $self->_sum_of_line_time_data(0)
        if not defined $$ref;

    return $$ref;
}

sub _sum_of_line_time_data {
    my ($self, $idx) = @_;
    my $line_time_data = $self->line_time_data;
    my $sum = 0;
    $sum += $_->[$idx]||0 for @$line_time_data;
    return $sum;
}


sub outer {
    my ($self, $recurse) = @_;
    my $fi  = $self->eval_fi
        or return;
    my $prev = $self;

    while ($recurse and my $eval_fi = $fi->eval_fi) {
        $prev = $fi;
        $fi = $eval_fi;
    }
    return $fi unless wantarray;
    return ($fi, $prev->eval_line);
}


sub is_pmc {
    return (shift->flags & NYTP_FIDf_IS_PMC());
}


sub collapse_sibling_evals {
    my ($self, $survivor_fi, @donors) = @_;
    my $profile = $self->profile;

    die "Can't collapse_sibling_evals of non-sibling evals"
        if grep { $_->eval_fid  != $survivor_fi->eval_fid or
                  $_->eval_line != $survivor_fi->eval_line
                } @donors;

    my $s_ltd = $survivor_fi->line_time_data; # XXX line only
    my $s_scl = $survivor_fi->sub_call_lines;
    my %donor_fids;

    for my $donor_fi (@donors) {
        # copy data from donor to survivor_fi then delete donor
        my $donor_fid = $donor_fi->fid;
        $donor_fids{$donor_fid} = $donor_fi;

        warn sprintf "collapse_sibling_evals: processing donor fid %d: %s\n",
                $donor_fid, $donor_fi->filename
            if trace_level() >= 3;

        # XXX nested evals not handled yet
        warn sprintf "collapse_sibling_evals: nested evals in %s not handled",
                $donor_fi->filename
            if $donor_fi->has_evals;

        # for each sub defined in the donor,
        # move the sub definition to the survivor
        if (my @subs_defined = $donor_fi->subs_defined) {

            for my $si (@subs_defined) {
                warn sprintf " - moving from fid %d: sub %s\n",
                        $donor_fid, $si->subname
                    if trace_level() >= 4;
                $si->_alter_fileinfo($donor_fi, $survivor_fi);
                warn sprintf " - moving done\n"
                    if trace_level() >= 4;
            }
        }

        # for each sub call made by the donor,
        # move the sub calls to the survivor
        # 1 => { 'main::foo' => [ 1, '1.38e-05', '1.24e-05', ..., { 'main::RUNTIME' => undef } ] }
        if (my $sub_call_lines = $donor_fi->sub_call_lines) {

            my %subnames_called_by_donor;

            # merge details of subs called from $donor_fi
            while ( my ($line, $sc_hash) = each %$sub_call_lines ) {
                my $s_sc_hash = $s_scl->{$line} ||= {};
                for my $subname (keys %$sc_hash ) {
                    my $s_sc_info = $s_sc_hash->{$subname} ||= [];
                    my $sc_info   = delete $sc_hash->{$subname};
                    Devel::NYTProf::SubInfo::_merge_in_caller_info($s_sc_info, $sc_info,
                        tag => "line $line calls to $subname",
                    );

                    $subnames_called_by_donor{$subname}++;
                }
            }
            %$sub_call_lines = (); # zap

            # update subinfo (NYTP_SIi_CALLED_BY)
            $profile->subinfo_of($_)->_alter_called_by_fileinfo($donor_fi, $survivor_fi)
                for keys %subnames_called_by_donor;
        }

        # copy line time data
        my $d_ltd = $donor_fi->line_time_data || []; # XXX line only
        for my $line (0..@$d_ltd-1) {
            my $d_tld_l = $d_ltd->[$line] or next;
            my $s_tld_l = $s_ltd->[$line] ||= [];
            $s_tld_l->[$_] += $d_tld_l->[$_] for (0..@$d_tld_l-1);
            warn sprintf "%d:%d: @$s_tld_l from @$d_tld_l fid:%d\n",
                $survivor_fi->fid, $line, $donor_fid if 0;
        }

        push @{ $survivor_fi->meta->{merged_fids} }, $donor_fid;
        ++$survivor_fi->meta->{merged_fids_src_varied}
            if $donor_fi->src_digest ne $survivor_fi->src_digest;

        $donor_fi->_nullify;
    }

    # remove donors from parent NYTP_FIDi_HAS_EVALS
    if (my $eval_fis = $self->[NYTP_FIDi_HAS_EVALS()]) {
        my %donors = map { +"$_" => 1 } @donors;
        my $count = @$eval_fis;
        @$eval_fis = grep { !$donors{$_} } @$eval_fis;
        warn "_delete_eval mismatch"
            if @$eval_fis != $count - @donors;
    }

    # update sawampersand_fid if it's one of the now-dead donors
    if ($donor_fids{ $profile->attributes->{sawampersand_fid} || 0 }) {
        $profile->attributes->{sawampersand_fid} = $survivor_fi->fid;
    }

    # now the fid merging is complete...
    # look for any anon subs that are effectively duplicates
    # (ie have the same name except for eval seqn)
    # if more than one for any given name we merge them
    if (my @subs_defined = $survivor_fi->subs_defined_sorted) {

        # bucket anon subs by normalized name
        my %newname;
        for my $si (@subs_defined) {
            next unless $si->is_anon;
            (my $newname = $si->subname) =~ s/ \( ((?:re_)?) eval \s \d+ \) /(${1}eval 0)/xg;
            push @{ $newname{$newname} }, $si;
        }

        while ( my ($newname, $to_merge) = each %newname ) {
            my $survivor_si = shift @$to_merge;
            next unless @$to_merge; # nothing to do

            my $survivor_subname = $survivor_si->subname;
            warn sprintf "collapse_sibling_evals: merging %d subs into %s: %s\n",
                    scalar @$to_merge, $survivor_subname,
                    join ", ", map { $_->subname } @$to_merge
                if trace_level() >= 3;

            for my $delete_si (@$to_merge) {
                my $delete_subname = $delete_si->subname;

                # for every file that called this sub, find the lines that made the calls
                # and change the name to the new sub
                for my $caller_fid ($delete_si->caller_fids) {
                    my $caller_fi = $profile->fileinfo_of($caller_fid);
                    # sub_call_lines ==> { line => { sub => ... } }
                    for my $subs_called_on_line (values %{ $caller_fi->sub_call_lines }) {
                        my $sc_info = delete $subs_called_on_line->{$delete_subname}
                            or next;
                        my $s_sc_info = $subs_called_on_line->{$survivor_subname} ||= [];
                        Devel::NYTProf::SubInfo::_merge_in_caller_info($s_sc_info, $sc_info,
                            tag => "collapse eval $delete_subname",
                        );
                    }
                }

                $survivor_si->merge_in($delete_si);
                $survivor_fi->_remove_sub_defined($delete_si);
                $profile->_disconnect_subinfo($delete_si);
            }
        }
    }

    warn sprintf "collapse_sibling_evals done for ".$survivor_fi->filename."\n"
        if trace_level() >= 2;

    return $survivor_fi;
}


# Should return the filename that the application used when loading the file
# For evals should remove the @INC portion from within the "(eval N)[$path]"
# and similarly for Class::MOP #line evals "... defined at $path".
# This is a bit of a fudge. Filename handling should be improved in the profiler.
sub filename_without_inc {
    my $self = shift;
    my $f    = [$self->filename];
    strip_prefix_from_paths([$self->profile->inc], $f,
        qr/(?: ^ | \[ | \sdefined\sat\s )/x
    );
    return $f->[0];
}


sub abs_filename {
    my $self = shift;

    my $filename = $self->filename;

    # strip of autosplit annotation, if any
    $filename =~ s/ \(autosplit into .*//;

    # if it's a .pmc then assume that's the file we want to look at
    # (because the main use for .pmc's are related to perl6)
    $filename .= "c" if $self->is_pmc;

    # search profile @INC if filename is not absolute
    my @files = ($filename);
    if ($filename !~ m/^\//) {
        my @inc = $self->profile->inc;
        @files = map { "$_/$filename" } @inc;
    }

    for my $file (@files) {
        return $file if -f $file;
    }

    # returning the still-relative filename is better than returning an undef
    return $filename;
}

# has source code stored within the profile data file
sub has_savesrc {
    my $self = shift;
    return $self->profile->{fid_srclines}[ $self->fid ];
}

sub srclines_array {
    my $self = shift;

    if (my $srclines = $self->has_savesrc) {
        my $copy = [ @$srclines ]; # shallow clone
        shift @$copy; # line 0 not used
        return $copy;
    }

    my $filename = $self->abs_filename;
    if (open my $fh, "<", $filename) {
        return [ <$fh> ];
    }

    return undef;
}

sub src_digest {
    my $self = shift;
    return $self->cache->{src_digest} ||= do {
        my $srclines_array = $self->srclines_array || [];
        my $src = join "\n", @$srclines_array;
        # return empty string for digest if there's no src
        ($src) ? join ",", (
                    scalar @$srclines_array, # number of lines
                    length $src,             # total length
                    unpack("%32C*",$src) )   # 32-bit checksum
                : '';
    };
}


sub normalize_for_test {
    my $self = shift;

    # normalize eval sequence numbers in 'file' names to 0
    $self->[NYTP_FIDi_FILENAME] =~ s/ \( ((?:re_)?) eval \s \d+ \) /(${1}eval 0)/xg
        if not $ENV{NYTPROF_TEST_SKIP_EVAL_NORM};

    # normalize flags to avoid failures due to savesrc and perl version
    $self->[NYTP_FIDi_FLAGS] &= ~(NYTP_FIDf_HAS_SRC|NYTP_FIDf_SAVE_SRC);

    # '1' => { 'main::foo' => [ 1, '1.38e-05', '1.24e-05', ..., { 'main::RUNTIME' => undef } ] }
    for my $subscalled (values %{ $self->sub_call_lines }) {

        for my $subname (keys %$subscalled) {
            my $sc = $subscalled->{$subname};
            $sc->[NYTP_SCi_INCL_RTIME] =
            $sc->[NYTP_SCi_EXCL_RTIME] =
            $sc->[NYTP_SCi_RECI_RTIME] = 0;

            if (not $ENV{NYTPROF_TEST_SKIP_EVAL_NORM}) {
                # normalize eval sequence numbers in anon sub names to 0
                (my $newname = $subname) =~ s/ \( ((?:re_)?) eval \s \d+ \) /(${1}eval 0)/xg;
                if ($newname ne $subname) {
                    warn "Normalizing $subname to $newname overwrote other called-by data\n"
                        if $subscalled->{$newname};
                    $subscalled->{$newname} = delete $subscalled->{$subname};
                }
            }
        }

    }
}


sub summary {
    my ($fi) = @_;
    return sprintf "fid%d: %s",
            $fi->fid, $fi->filename_without_inc;
}

sub dump {      
    my ($self, $separator, $fh, $path, $prefix, $opts) = @_;

    my @values = @{$self}[
        NYTP_FIDi_FILENAME, NYTP_FIDi_EVAL_FID, NYTP_FIDi_EVAL_LINE, NYTP_FIDi_FID,
        NYTP_FIDi_FLAGS, NYTP_FIDi_FILESIZE, NYTP_FIDi_FILEMTIME
    ];
    $values[0] = $self->filename_without_inc;
    # also remove possible remaining perl version seen in some cpantesters
    # http://www.cpantesters.org/cpan/report/bf913910-bfdd-11df-a657-c9f38a00995b
    $values[0] =~ s!^$Config{version}/!!o;

    printf $fh "%s[ %s ]\n", $prefix, join(" ", map { defined($_) ? $_ : 'undef' } @values);

    if (not $opts->{skip_internal_details}) {

        for my $si ($self->subs_defined_sorted) {
            my ($fl, $ll) = ($si->first_line, $si->last_line);
            defined $_ or $_ = 'undef' for ($fl, $ll);
            printf $fh "%s%s%s%s%s%s-%s\n", 
                $prefix, 'sub', $separator,
                $si->subname(' and '),  $separator,
                $fl, $ll;
        }

        # { line => { subname => [...] }, ... }
        my $sub_call_lines = $self->sub_call_lines;
        for my $line (sort { $a <=> $b } keys %$sub_call_lines) {
            my $subs_called = $sub_call_lines->{$line};

            for my $subname (sort keys %$subs_called) {
                my @sc = @{$subs_called->{$subname}};
                $sc[NYTP_SCi_CALLING_SUB] = join "|", sort keys %{ $sc[NYTP_SCi_CALLING_SUB] };

                printf $fh "%s%s%s%s%s%s%s[ %s ]\n", 
                    $prefix, 'call', $separator,
                    $line,  $separator, $subname, $separator,
                    join(" ", map { defined($_) ? $_ : 'undef' } @sc)
            }
        }

        # string evals, group by the line the eval is on
        my %eval_lines;
        for my $eval_fi ($self->has_evals(0)) {
            push @{ $eval_lines{ $eval_fi->eval_line } }, $eval_fi;
        }
        for my $line (sort { $a <=> $b } keys %eval_lines) {
            my $eval_fis = $eval_lines{$line};

            my @has_evals = map { $_->has_evals(1) } @$eval_fis;
            my @merged_fids = map { @{ $_->meta->{merged_fids}||[]} } @$eval_fis;

            printf $fh "%s%s%s%d%s[ count %d nested %d merged %d ]\n", 
                $prefix, 'eval', $separator,
                $eval_fis->[0]->eval_line, $separator,
                scalar @$eval_fis, # count of evals executed on this line
                scalar @has_evals, # count of nested evals they executed
                scalar @merged_fids, # count of evals merged (collapsed) away
        }

    }

}   

# vim: ts=8:sw=4:et
1;
