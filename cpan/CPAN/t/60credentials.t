use strict;

#use FindBin qw($Bin);
#use lib "$Bin/../lib";
#use lib "$Bin/../blib";
use CPAN;
use Test::More tests => 5;

my $TRUE = 1;
my $FALSE = undef;

test_can_get_basic_credentials();
test_get_basic_credentials_for_proxy();
test_get_basic_credentials_without_proxy();
# exit;

#############################################################################

sub test_can_get_basic_credentials {
    set_up();
    can_ok('CPAN::LWP::UserAgent', 'get_basic_credentials');
    can_ok('CPAN::HTTP::Credentials', 'get_proxy_credentials');
    can_ok('CPAN::HTTP::Credentials', 'get_non_proxy_credentials');
}

sub test_get_basic_credentials_for_proxy {
    set_up();
    $CPAN::Config->{proxy_user} = 'proxy_username';
    $CPAN::Config->{proxy_pass} = 'proxy_password';
    my @proxy_credentials =
      CPAN::LWP::UserAgent->get_basic_credentials('realm', 'uri', $TRUE);
    is_deeply(\@proxy_credentials,
              [$CPAN::Config->{proxy_user}, $CPAN::Config->{proxy_pass}],
              'get_basic_credentials for proxy');
}

sub test_get_basic_credentials_without_proxy {
    set_up();
    $CPAN::Config->{username} = 'test_username';
    $CPAN::Config->{password} = 'test_password';
    my @credentials =
      CPAN::LWP::UserAgent->get_basic_credentials('realm', 'uri', $FALSE);
    is_deeply(\@credentials,
              [$CPAN::Config->{username}, $CPAN::Config->{password}],
              'get_basic_credentials for non-proxy');
}

sub set_up {
    undef $CPAN::Config->{username};
    undef $CPAN::Config->{password};
    undef $CPAN::Config->{proxy_user};
    undef $CPAN::Config->{proxy_pass};
    undef $CPAN::HTTP::Credentials::USER;
    undef $CPAN::HTTP::Credentials::PASSWORD;
}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
