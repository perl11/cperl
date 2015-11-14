# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;

eval "use Sub::Name 0.11; 1"
	or plan skip_all => "Sub::Name 0.11 or later required";

print "Sub::Name $Sub::Name::VERSION $INC{'Sub/Name.pm'}\n";

use Devel::NYTProf::Run qw(profile_this);

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => {
        start => 'init', compress => 1, leave => 0, stmts => 0, slowops => 0,
    },
    extra_test_count => 6,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
            #htmlopen => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs = $profile->subname_subinfo_map;

        my $sub = $subs->{'main::named'};
        ok $sub;
        is $sub->calls, 1;
        is $sub->subname, 'main::named';

        SKIP: {
            skip "Sub::Name 0.06 required for subname line numbers", 2
                if $Sub::Name::VERSION <= 0.06;
            is $sub->first_line, 3;
            is $sub->last_line,  3;
        }
    },
});

__DATA__
#!perl
use Sub::Name;
(subname 'named' => sub { print "sub called\n" })->();

my $longname = "sub34567890" x 10 x 4;
(subname $longname => sub { print "sub called\n" })->();

my $deepname = "sub345678::" x 10 x 4;
(subname $deepname => sub { print "sub called\n" })->();
