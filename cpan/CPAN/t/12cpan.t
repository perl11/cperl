BEGIN {
    $|++;
    local $^W;
    eval "qr/qr/";
    if ($@) {
        $|=1;
        print "1..0 # SKIP no qr//\n";
        eval "require POSIX; 1" and POSIX::_exit(0);
    }
}
my $count;
use strict;
use Test::More;
use File::Spec;
sub _f ($) {
    File::Spec->catfile(split /\//, shift);
}
use File::Copy qw(cp);
unlink _f"t/CPAN/MyConfig.pm";		# cp non-overwriting on OS/2
cp _f"t/CPAN/TestConfig.pm", _f"t/CPAN/MyConfig.pm"
    or die "Could not cp t/CPAN/TestConfig.pm over t/CPAN/MyConfig.pm: $!";
unshift @INC, "t";
require CPAN::MyConfig;
require CPAN;
require CPAN::Kwalify;
require CPAN::HandleConfig;
{
    eval {CPAN::rtlpr()};
    like $@, qr/Unknown CPAN command/,q/AUTOLOAD rejects/;
    BEGIN{$count++}
}
{
    my $rdep = CPAN::Exception::RecursiveDependency->new([qw(foo bar baz)]);
    like $rdep, qr/^--not.*--$/, "not a recursive/circular dependency";
    BEGIN{$count++}
}
{
    my $rdep = CPAN::Exception::RecursiveDependency->new([qw(foo bar baz foo)]);
    like $rdep, qr/foo.+=>.+bar.+=>.+baz.+=>.+foo/s, "circular dependency";
    BEGIN{$count++}
}
{
    my $a = CPAN::Shell->expand("Module",
                                "CPAN::Test::Dummy::Perl5::Make"
                               )->distribution->author->as_string;
    like $a, qr/Andreas/, "found Andreas in CPAN::Test::Dummy::Perl5::Make";
    BEGIN{$count++}
}
{
    no strict;
    {
        package S;
        for my $m (qw(myprint mydie mywarn mysleep)){
            *$m = sub {
                return;
            }
        }
    }
    $CPAN::Frontend = $CPAN::Frontend = "S";
    $_ = "Fcntl";
    my $m = CPAN::Shell->expand(Module => $_);
    $m->uptodate;
    is($_,"Fcntl","\$_ is properly localized");
    BEGIN{$count++}
}
{
    my @s;
    BEGIN{
        @s=(
            '"a"',
            '["a"]',
            '{a=>"b"}',
            '{"a;"=>"b"}',
            '"\\\\"',
           );
        $count+=@s;
    }
    for (0..$#s) {
        my $x = eval $s[$_];
        my $y = CPAN::HandleConfig->neatvalue($x);
        my $z = eval $y;
        is_deeply($z,$x,"s[$_]");
    }
}
{
    my $this_block_count;
    BEGIN { $count += $this_block_count = 2; }
    eval { require Kwalify; require YAML; }; # most of the kwalify
                                             # stuff does not work
                                             # without yaml
    if ($@ || (($YAML::VERSION||$YAML::VERSION||0) < 0.62)) { # silence 5.005_04
        for (1..$this_block_count) {
            ok(1, "dummy Kwalify/YAML $_");
        }
    } else {
        my $data = {
                    "match" => {
                                "distribution" => "^(ABW|ADAMK)/Template-Toolkit-2.16"
                               },
                    "pl" => {
                             "args" => [
                                        "TT_EXTRAS=no"
                                       ],
                             "expect" => [
                                          "Do you want to build the XS Stash module",
                                          "n\n",
                                          "Do you want to install these components",
                                          "n\n",
                                          "Installation directory",
                                          "\n",
                                          "URL base for TT2 images",
                                          "\n",
                                         ],
                             barth => '1984',
                            },
                   };
        eval {CPAN::Kwalify::_validate("distroprefs",
                                       $data,
                                       _f("t/12cpan.t"),
                                       0)};
        ok($@,"no kwalify [$@]");
        delete $data->{pl}{barth};
        CPAN::Kwalify::_clear_cache();
        eval {CPAN::Kwalify::_validate("distroprefs",
                                       $data,
                                       _f("t/12cpan.t"),
                                       0)};
        ok(!$@,"kwalify ok");
    }
}

{
    my $this_block_count;
    BEGIN { $count += $this_block_count = 8; }

    eval { require YAML::Syck; };
    my $excuse;
    if ($@) {
        $excuse = "YAML::Syck not available";
    } elsif (($YAML::Syck::VERSION||$YAML::Syck::VERSION||0) < 0.97) { # silence 5.005_04
        $excuse = "YAML::Syck too old";
    } elsif ($] < 5.008) {
        $excuse = "Defered code segfaults on 5.6.x";
    }
    if ($excuse) {
        for (1..$this_block_count) {
            ok(1, "Skipping ($excuse) $_");
        }
    } else {
        my $yaml_file = _f('t/yaml_code.yml');

        local $CPAN::Config->{yaml_module} = 'YAML::Syck';

        {
            my $data = CPAN->_yaml_loadfile($yaml_file)->[0];

            local $::yaml_load_code_works = 0;

            my $code = $data->{code};
            is(ref $code, 'CODE', 'deserialisation returned CODE');
            $code->();
            is($::yaml_load_code_works, 0, 'running the code did the right thing');

            my $obj = $data->{object};
            isa_ok($obj, 'CPAN::DeferredCode');
            local $^W;
            my $dummy = "$obj";
            is($::yaml_load_code_works, 0, 'stringifying the obj does nothing');
        }

        {
            local $CPAN::Config->{yaml_load_code} = 1;

            my $data = CPAN->_yaml_loadfile($yaml_file)->[0];

            local $::yaml_load_code_works = 0;

            my $code = $data->{code};
            is(ref $code, 'CODE', 'deserialisation returned CODE');
            $code->();
            is($::yaml_load_code_works, 1, 'running the code did the right thing');

            my $obj = $data->{object};
            isa_ok($obj, 'CPAN::DeferredCode');
            my $dummy = "$obj";
            is($::yaml_load_code_works, 2, 'stringifying the obj ran the code');
        }
    }
}

{
    my $this_block_count;
    my @no_proxy;
    BEGIN {
        @no_proxy = ({
                      domain => "at",
                      expect => 1,
                     },
                     {
                      domain => "kh",
                      expect => 0,
                     },
                    );
        $this_block_count = 3 * @no_proxy;
        $count += $this_block_count;
    }
    my $ftp = "CPAN::FTP";
    $CPAN::Config->{http_proxy} = "http://myproxy.local/";
    $CPAN::Config->{proxy_user} = "myproxyuser";
    $CPAN::Config->{proxy_pass} = "myproxypass";
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    for my $n (@no_proxy) {
        $CPAN::Config->{no_proxy} = $n->{domain};
        my $pftpvars = $ftp->_proxy_vars("http://battambang.kh/");
        for my $k (qw(http_proxy proxy_user proxy_pass)) {
            my $v = defined $pftpvars->{$k} ? $pftpvars->{$k} : "UNDEF";
            ok($n->{expect}
               ==
               !!$pftpvars->{$k},
               "found $k\[$v] on domain[$n->{domain}]");
        }
    }
}

{
    my $this_block_count;
    BEGIN {
        $this_block_count = 2;
        $count += $this_block_count;
    }
    use CPAN::FirstTime;
    my $keys = keys %CPAN::FirstTime::prompts;
    ok $keys>=105, "found keys[$keys] prompts";
    my $join = join "", %CPAN::FirstTime::prompts;
    my $length = length $join;
    ok $length>=20468, "found length[$length] prompts";
}

BEGIN{plan tests => $count}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
