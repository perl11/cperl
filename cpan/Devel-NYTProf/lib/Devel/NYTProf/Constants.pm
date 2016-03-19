package Devel::NYTProf::Constants;

use strict;

use Devel::NYTProf::Core;

use base 'Exporter';

our @EXPORT_OK = qw(const_bits2names);

my $const_bits2names_groups;

do {
    my $symbol_table = do { no strict; \%{"Devel::NYTProf::Constants::"} };
    my %consts = map { $_ => $symbol_table->{$_}() } grep { /^NYTP_/ } keys %$symbol_table;

    push @EXPORT_OK, keys %consts;

    for my $sym (keys %consts) {
        $sym =~ /^(NYTP_[A-Z]+[a-z])_/ or next;
        $const_bits2names_groups->{$1}{ $consts{$sym} } = $sym;
    }
};


sub const_bits2names { # const_bits2names("NYTP_FIDf",$flags)
    my ($group, $bits) = @_;
    my $names = $const_bits2names_groups->{$group} or return;
    my @names;
    for my $bit (0..31) {
        my $bitval = 1 << $bit;
        push @names, $names->{$bitval}
            if $bits & $bitval;
    }
    return @names if wantarray;
    return join " | ", @names;
}

# warn scalar const_bits2names("NYTP_FIDf", NYTP_FIDf_SAVE_SRC|NYTP_FIDf_IS_PMC);


#warn "Constants: ".join(" ", sort @EXPORT_OK);

1;
