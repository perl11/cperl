use lib '.';
use t::TestYAMLTests;

BEGIN {
    if ($] < 5.010000) {
        plan skip_all => 'needs perl 5.10 or higher';
    }
    else {
        plan tests => 3;
    }
}

use Tie::Array;
use Tie::Hash;

my $yaml1 = <<'...';
---
- 'foo'
- 'bar'
- 'baz'
...

{
    tie my @av, 'Tie::StdArray';
    $av[0] = 'foo';
    $av[1] = 'bar';
    $av[2] = 'baz';
    is Dump(\@av), $yaml1, 'Dumping tied array works';
}

my $yaml2 = <<'...';
---
bar: 'bar'
baz: 'baz'
foo: 'foo'
...

{
    tie my %hv, 'Tie::StdHash';
    $hv{foo} = 'foo';
    $hv{bar} = 'bar';
    $hv{baz} = 'baz';
    is Dump(\%hv), $yaml2, 'Dumping tied hash works';
}

{
    package Tie::OneIterationOnly;
    my @KEYS = qw(bar baz foo);

    sub TIEHASH {
        return bless \do { my $x }, shift;
    }

    sub FIRSTKEY {
        my ($self) = @_;
        return shift @KEYS;
    }

    sub NEXTKEY {
        my ($self, $last) = @_;
        return shift @KEYS;
    }

    sub FETCH {
        my ($self, $key) = @_;
        return;
    }
}

my $yaml3 = <<'...';
--- {}
...

{
    tie my %hv, 'Tie::OneIterationOnly';
    is Dump(\%hv), $yaml3, 'Dumping tied hash works';
}


