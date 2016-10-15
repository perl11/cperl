use strict; use warnings;

package YAML::XS;
our $VERSION = '0.75';

use base 'Exporter';

@YAML::XS::EXPORT = qw(Load Dump);
@YAML::XS::EXPORT_OK = qw(LoadFile DumpFile);
%YAML::XS::EXPORT_TAGS = (
    all => [qw(Dump Load LoadFile DumpFile)],
);
# $YAML::XS::NonStrict = 1;      # for Load
# $YAML::XS::DisableCode = 0;    # for Load
# $YAML::XS::DisableBlessed = 0; # for Load
# $YAML::XS::UseCode = 0;        # for Dump
# $YAML::XS::DumpCode = 0;       # for Dump

$YAML::XS::QuoteNumericStrings = 1;

use YAML::XS::LibYAML qw(Load LoadFile Dump DumpFile);
use Scalar::Util qw/ openhandle /;

# XXX Figure out how to lazily load this module.
# So far I've tried using the C function:
#      load_module(PERL_LOADMOD_NOIMPORT, newSVpv("B::Deparse", 0), NULL);
# But it didn't seem to work.
use B::Deparse;

# XXX The following code should be moved from Perl to C.
$YAML::XS::coderef2text = sub {
    my $coderef = shift;
    my $deparse = B::Deparse->new();
    my $text;
    eval {
        local $^W = 0;
        $text = $deparse->coderef2text($coderef);
    };
    if ($@) {
        warn "YAML::XS failed to dump code ref:\n$@";
        return;
    }
    $text =~ s[BEGIN \{\$\{\^WARNING_BITS\} = "UUUUUUUUUUUU\\001"\}]
              [use warnings;]g;

    return $text;
};

$YAML::XS::glob2hash = sub {
    my $hash = {};
    for my $type (qw(PACKAGE NAME SCALAR ARRAY HASH CODE IO)) {
        my $value = *{$_[0]}{$type};
        $value = $$value if $type eq 'SCALAR';
        if (defined $value) {
            if ($type eq 'IO') {
                my @stats = qw(device inode mode links uid gid rdev size
                               atime mtime ctime blksize blocks);
                undef $value;
                $value->{stat} = {};
                map {$value->{stat}{shift @stats} = $_} stat(*{$_[0]});
                $value->{fileno} = fileno(*{$_[0]});
                {
                    local $^W;
                    $value->{tell} = tell(*{$_[0]});
                }
            }
            $hash->{$type} = $value;
        }
    }
    return $hash;
};

use constant _QR_MAP => {
    '' => sub { qr{$_[0]} },
    x => sub { qr{$_[0]}x },
    i => sub { qr{$_[0]}i },
    s => sub { qr{$_[0]}s },
    m => sub { qr{$_[0]}m },
    ix => sub { qr{$_[0]}ix },
    sx => sub { qr{$_[0]}sx },
    mx => sub { qr{$_[0]}mx },
    si => sub { qr{$_[0]}si },
    mi => sub { qr{$_[0]}mi },
    ms => sub { qr{$_[0]}sm },
    six => sub { qr{$_[0]}six },
    mix => sub { qr{$_[0]}mix },
    msx => sub { qr{$_[0]}msx },
    msi => sub { qr{$_[0]}msi },
    msix => sub { qr{$_[0]}msix },
};

sub __qr_loader {
    if ($_[0] =~ /\A  \(\?  ([ixsm]*)  (?:-  (?:[ixsm]*))?  : (.*) \)  \z/x) {
        my $sub = _QR_MAP->{$1} || _QR_MAP->{''};
        &$sub($2);
    }
    else {
        qr/$_[0]/;
    }
}

1;
