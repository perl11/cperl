    die "Config can't be permanent" if keys %Config::;
    require Config; #this is supposed to be XS config
    require B;
    my $cv = B::svref_2object(*{'Config::FETCH'}{CODE});
    die "Config:: is not XS Config" unless $cv->CvFLAGS() & B::CVf_ISXSUB();

    #change the class name of XS Config so there can be XS and PP Config at same time
    foreach(qw( TIEHASH DESTROY DELETE CLEAR EXISTS NEXTKEY FIRSTKEY KEYS SCALAR FETCH)) {
        *{'XSConfig::'.$_} = *{'Config::'.$_}{CODE};
    }
    tie(%XSConfig, 'XSConfig');
    #delete package
    undef( *main::Config:: );
    require Data::Dumper;
    $Data::Dumper::Sortkeys = 1;
    $Data::Dumper::Useqq = 1;
    #full perl is now miniperl
    undef( *main::XSLoader::);
    require 'Config_mini.pl';
    Config->import();
    require Test::More;
    Test::More->import(tests => 3);

    $cv = B::svref_2object(*{'Config::FETCH'}{CODE});
    ok(($cv->CvFLAGS() & B::CVf_ISXSUB()) == 0, 'PP Config:: is PP');
    my($klenPP, $klenXS) = (scalar(keys %Config), scalar(keys %XSConfig));
    is($klenXS, $klenPP, 'key count same');
    is_deeply(\%XSConfig, \%Config, "cmp hashes");
    if(!Test::More->builder->is_passing){
        open(F, '>','xscfg.txt');
        print F Data::Dumper::Dumper({%XSConfig});
        close F;
        open(G, '>', 'ppcfg.txt');
        print G Data::Dumper::Dumper({%Config});
        close G;
        system('diff -u ppcfg.txt xscfg.txt');
        unlink('xscfg.txt');
        unlink('ppcfg.txt');
    }

