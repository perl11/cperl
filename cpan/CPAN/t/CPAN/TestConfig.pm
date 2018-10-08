use Cwd ();
my($cwd,$rcwd);
my $Iswin = $^O eq "MSWin32";
if ($Iswin) {
  $cwd = Cwd::getdcwd();
  $rcwd = Cwd::realpath($cwd);
} else {
  $cwd = $rcwd = Cwd::cwd();
}
$CPAN::Config = {
                 $Iswin ? () : (
                                'make_install_make_command' => q[make],
                                'mbuild_install_build_command' => q[./Build],
                               ),
                 '7yYQS7' => 'vGcVJQ', # verifies that we really loaded this file
                 'auto_commit' => 0,
                 'build_cache' => q[100],
                 'build_dir' => qq[$cwd/t/dot-cpan/build],
                 #'bzip2' => q[/bin/bzip2],
                 'cache_metadata' => q[0],
                 colorize_output=>0,
                 'cpan_home' => qq[$cwd/t/dot-cpan],
                 #'curl' => q[],
                 #'ftp' => q[],
                 'ftp_proxy' => q[],
                 'getcwd' => q[cwd],
                 #'gpg' => q[/usr/bin/gpg],
                 #'gzip' => q[/bin/gzip],
                 'histfile' => qq[$cwd/t/dot-cpan/histfile],
                 'histsize' => q[100],
                 'http_proxy' => q[],
                 'inactivity_timeout' => q[0],
                 'index_expire' => q[1],
                 'inhibit_startup_message' => q[0],
                 'keep_source_where' => qq[$cwd/t/dot-cpan/sources],
                 #'lynx' => q[],
                 'load_module_verbosity' => q[v],
                 #'make' => q[/usr/bin/make],
                 'make_arg' => q[],
                 'make_install_arg' => q[UNINST=1],
                 'makepl_arg' => q[],
                 'mbuild_arg' => q[],
                 'mbuild_install_arg' => q[--uninst 1],
                 'mbuildpl_arg' => q[],
                 #'ncftp' => q[],
                 #'ncftpget' => q[],
                 'no_proxy' => q[],
                 #'pager' => q[less],
                 'prefer_installer' => q[MB],
                 'prerequisites_policy' => q[follow],
                 'scan_cache' => q[atstart],
                 #'shell' => q[/usr/bin/zsh],
                 'show_upload_date' => q[0],
                 #'tar' => q[/bin/tar],
                 'term_is_latin' => q[0],
                 'term_ornaments' => q[0],
                 #'unzip' => q[/usr/bin/unzip],
                 'urllist' => [qq[file://$rcwd/t/CPAN]],
                 'wait_list' => [q[wait://ls6.informatik.uni-dortmund.de:1404]],
                 #'wget' => q[/usr/bin/wget],
                 'yaml_load_code' => q[0],
                };

__END__

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
