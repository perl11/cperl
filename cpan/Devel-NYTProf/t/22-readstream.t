use Test::More;

use strict;
use Config;
use Data::Dumper;

use lib qw(t/lib);
use NYTProfTest;

use Devel::NYTProf::ReadStream qw(for_chunks);

my $pre589 = ($] < 5.008009 or $] eq "5.010000");

(my $base = __FILE__) =~ s/\.t$//;

# generate an nytprof out file
my $out = 'nytprof_readstream.out';
$ENV{NYTPROF} = "calls=2:blocks=1:file=$out";
unlink $out;

run_perl_command(qq{-d:NYTProf -e "sub A { };" -e "1;" -e "A() $Devel::NYTProf::StrEvalTestPad"});

my %prof;
my @seqn;

for_chunks {
    push @seqn, "$.";
    my $tag = shift;
    push @{ $prof{$tag} }, [ @_ ];
    if (1) {
        my @params = @_;
        not defined $_ and $_ = '(undef)' for @params;
        chomp @params;
        print "# $. $tag @params\n";
    }
} filename => $out;

my %option    = map { @$_ } @{$prof{OPTION}};
cmp_ok scalar keys %option, '>=', 17, 'enough options';
#diag Dumper(\%option);

my %attribute = map { @$_ } @{$prof{ATTRIBUTE}};
cmp_ok scalar keys %attribute, '>=', 9, 'enough attribute';
#diag Dumper(\%attribute);

ok scalar @seqn, 'should have read chunks';
is_deeply(\@seqn, [0..@seqn-1], "chunk seq");

#use Data::Dumper; warn Dumper \%prof;

is_deeply $prof{VERSION}, [ [ 5, 0 ] ];

# check for expected tags
# but not START_DEFLATE as that'll be missing if there's no zlib
# and not SRC_LINE as old perl's 
my @expected_tags = qw(
    COMMENT ATTRIBUTE OPTION DISCOUNT
    SUB_INFO SUB_CALLERS
    PID_START PID_END NEW_FID
    SUB_ENTRY SUB_RETURN
);
push @expected_tags, 'TIME_BLOCK' if $option{calls};
for my $tag (@expected_tags) {
    is ref $prof{$tag}[0], 'ARRAY', "raw $tag array seen"
        or diag Dumper $prof{$tag};
}

SKIP: {
    skip 'needs perl >= 5.8.9 or >= 5.10.1', 1 if $pre589;
    is ref $prof{SRC_LINE}[0], 'ARRAY', 'SRC_LINE';
}

# check some attributes
my %attr = map { $_->[0] => $_->[1] } @{ $prof{ATTRIBUTE} };
cmp_ok $attr{ticks_per_sec}, '>=', 1_000_000, 'ticks_per_sec';
is $attr{application}, '-e', 'application';
is $attr{nv_size}, $Config{nvsize}, 'nv_size';
cmp_ok $attr{xs_version}, '>=', 2.1, 'xs_version';
cmp_ok $attr{basetime}, '>=', $^T, 'basetime';

my @sub_info_sorted = sort { $a->[3] cmp $b->[3] } @{$prof{SUB_INFO}};
is_deeply \@sub_info_sorted, [
    [1, 1, 1, "main::A"],
    [1, 0, 0, "main::BEGIN"],
    [1, 1, 1, "main::RUNTIME"],
];

$prof{SUB_CALLERS}[0][$_] = 0 for (3,4);
is_deeply $prof{SUB_CALLERS}, [
    [ 1, 3, 1, 0, 0, '0', 0, 'main::A', 'main::RUNTIME' ]
];

is_deeply $prof{SUB_ENTRY}, [ [ 1, 3 ] ], 'SUB_ENTRY args';

$prof{SUB_RETURN}[0][$_] = 0 for (1,2);
is_deeply $prof{SUB_RETURN}, [ [ 1, 0, 0, 'main::A' ] ], 'SUB_RETURN args';

done_testing();
