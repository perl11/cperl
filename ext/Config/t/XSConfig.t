#!/usr/bin/perl
BEGIN {
    $| = 1;
    if (scalar keys %Config:: > 2) {
        print "1..0 #SKIP Cannot test with static or builtin Config\n";
        exit(0);
    }
}

require Config; #this is supposed to be XS config
require B;

*isXSUB = !B->can('CVf_ISXSUB')
  ? sub { shift->XSUB }
  : sub { shift->CvFLAGS & B::CVf_ISXSUB() }; #CVf_ISXSUB added in 5.9.4

#is_deeply->overload.pm wants these 2 XS modules
#can't be required once DynaLoader is removed later on
require Scalar::Util;
eval { require mro; };
my $cv = B::svref_2object(*{'Config::FETCH'}{CODE});
unless (isXSUB($cv)) {
  if (-d 'regen') { #on CPAN
    warn "Config:: is not XS Config";
  } else {
    print "1..0 #SKIP Config:: is not XS Config, miniperl?\n";
    exit(0);
  }
}

my $in_core = ! -d "regen";

# change the class name of XS Config so there can be XS and PP Config at same time
foreach (qw( TIEHASH DESTROY DELETE CLEAR EXISTS NEXTKEY FIRSTKEY KEYS SCALAR FETCH)) {
  *{'XSConfig::'.$_} = *{'Config::'.$_}{CODE};
}
tie(%XSConfig, 'XSConfig');

# delete package
undef( *main::Config:: );
require Data::Dumper;
$Data::Dumper::Useperl = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq = 0;
$Data::Dumper::Quotekeys = 0;

# full perl is now miniperl
undef( *main::XSLoader::);
require 'Config_mini.pl';
Config->import();
require 'Config_heavy.pl';
require Test::More;
Test::More->import (tests => 4);

ok(isXSUB($cv), 'XS Config:: is XS');

$cv = B::svref_2object(*{'Config::FETCH'}{CODE});
ok(!isXSUB($cv), 'PP Config:: is PP');

my $klenXS = scalar(keys %XSConfig);
my $copy = 0;
my %Config_copy;
if (exists $XSConfig{canned_gperf}) { #fix up PP Config to look like XS Config
  #to see in CPAN Testers reports if the builder had gperf or not
  warn "This XS Config was built with the canned XS file\n";
  $copy = 1;
  for (keys %Config) {
    $Config_copy{$_} = $Config{$_};
  }
  # See Config_xs.PL:
  # postprocess the values a bit:
  # reserve up to 39 config_args
  for (0..39) {
    my $k = "config_arg".$_;
    $Config_copy{$k} = '' unless exists $Config{$k};
  }
  # these qw blocks are created with genkeys.PL in the cpan repo
  my @cannedkeys = qw(

          arflags bin_ELF bootstrap_charset canned_gperf ccstdflags
          ccwarnflags charsize cf_epoch config_argc config_args
          d_memrchr d_re_comp d_regcmp dlltool dtraceobject
          dtracexnolibs git_ancestor git_commit_date git_remote_branch
          git_unpushed hostgenerate hostosname hostperl incpth
          installhtmldir installhtmlhelpdir ld_can_script
          libdb_needs_pthread mad malloc_cflags passcat sysroot
          targetdir targetenv targethost targetmkdir targetport
          useversionedarchname

  );
    unless ($in_core) { # cperl doesn't need these, CPAN does
        push @cannedkeys , qw(

          ARCH BuiltWithPatchPerl Mcc PERL_PATCHLEVEL
          ccflags_nolargefiles charbits config_heavy d_acosh
          d_asctime64 d_asinh d_atanh d_attribut
          d_attribute_deprecated d_attribute_format d_attribute_malloc
          d_attribute_nonnull d_attribute_noreturn d_attribute_pure
          d_attribute_unused d_attribute_warn_unused_result
          d_backtrace d_builtin_arith_overflow d_builtin_choose_expr
          d_builtin_expect d_c99_variadic_macros d_cbrt d_clearenv
          d_copysign d_cplusplus d_ctermid d_ctime64 d_difftime64
          d_dir_dd_fd d_dladdr d_duplocale d_erf d_erfc d_exp2 d_expm1
          d_fdclose d_fdim d_fegetround d_fma d_fmax d_fmin
          d_fp_classify d_fp_classl d_fpgetround d_freelocale
          d_fs_data_s d_fstatfs d_fstatvfs d_futimes
          d_gdbm_ndbm_h_uses_prototypes d_gdbmndbm_h_uses_prototypes
          d_getaddrinfo d_getfsstat d_getmnt d_getmntent d_getnameinfo
          d_gmtime64 d_hasmntopt d_hypot d_ilogb d_inc_version_list
          d_inetntop d_inetpton d_ip_mreq d_ip_mreq_source d_ipv6_mreq
          d_ipv6_mreq_source d_isblank d_isfinitel d_isinfl d_isless
          d_isnormal d_j0 d_j0l d_lc_monetary_2008 d_ldexpl d_lgamma
          d_lgamma_r d_libname_unique d_llrint d_llrintl d_llround
          d_llroundl d_localtime64 d_localtime_r_needs_tzset d_log1p
          d_log2 d_logb d_lrint d_lrintl d_lround d_lroundl
          d_malloc_good_size d_malloc_size d_mktime64
          d_modfl_pow32_bug d_modflproto d_nan d_ndbm
          d_ndbm_h_uses_prototypes d_nearbyint d_newlocale d_nextafter
          d_nexttoward d_nv_zero_is_allbits_zero d_prctl
          d_prctl_set_name d_printf_format_null d_pseudofork
          d_ptrdiff_t d_regcomp d_remainder d_remquo d_rint d_round
          d_scalbn d_sfio d_siginfo_si_addr d_siginfo_si_band
          d_siginfo_si_errno d_siginfo_si_fd d_siginfo_si_pid
          d_siginfo_si_status d_siginfo_si_uid d_siginfo_si_value
          d_signbit d_sin6_scope_id d_sitearch d_sockaddr_in6
          d_sockaddr_sa_len d_stat d_statfs_f_flags d_statfs_s
          d_static_inline d_statvfs d_strlcat d_strlcpy d_tgamma
          d_timegm d_trunc d_truncl d_unsetenv d_uselocale d_ustat
          d_vendorscript d_vms_case_sensitive_symbols d_wcscmp
          d_wcsxfrm defvoidused dl_so_eq_ext doop_cflags
          doubleinfbytes doublekind doublemantbits doublenanbytes
          dtrace extern_C found_libucb from gccansipedantic git_branch
          git_commit_id git_commit_id_title git_describe
          git_uncommitted_changes gnulibc_version hash_func html1dir
          html1direxp html3dir html3direxp i_assert i_bfd i_dld
          i_execinfo i_fenv i_gdbm_ndbm i_gdbmndbm i_mallocmalloc
          i_mntent i_quadmath i_sfio i_stdbool i_stdint i_sysmount
          i_syspoll i_sysstatfs i_sysstatvfs i_sysvfs i_ustat
          i_xlocale ieeefp_h initialinstalllocation installhtml1dir
          installhtml3dir installsitehtml1dir installsitehtml3dir
          installsiteman1dir installsiteman3dir installsitescript
          installvendorhtml1dir installvendorhtml3dir
          installvendorman1dir installvendorman3dir
          installvendorscript ldflags_nolargefiles libs_nolargefiles
          libswanted_nolargefiles longdblinfbytes longdblkind
          longdblmantbits longdblnanbytes madlyh madlyobj madlysrc
          mistrustnm nv_overflows_integers_at nvmantbits op_cflags
          perl_patchlevel perl_revision perl_static_inline
          perl_subversion perl_version ppmarch pthread_h_first
          regexec_cflags rm_try run sGMTIME_max sGMTIME_min
          sLOCALTIME_max sLOCALTIME_min sitehtml1dir sitehtml1direxp
          sitehtml3dir sitehtml3direxp siteman1dir siteman1direxp
          siteman3dir siteman3direxp sitescript sitescriptexp
          st_ino_sign st_ino_size targetsh to toke_cflags
          usecbacktrace usecperl usedevel usedtrace
          usekernprocpathname usensgetexecutablepath usequadmath
          userelocatableinc usesfio vendorhtml1dir vendorhtml1direxp
          vendorhtml3dir vendorhtml3direxp vendorman1dir
          vendorman1direxp vendorman3dir vendorman3direxp vendorscript
          vendorscriptexp voidflags yacc yaccflags

        );
  }
  if (!$in_core and $] < 5.027) { # for older CPAN installs
    # deleted with v5.27.5/v5.27.2c
    push @cannedkeys , qw(

            ansi2knr d_bcmp d_bcopy d_bzero d_charvspr d_dbl_dig
            d_index d_memchr d_memcmp d_memcpy d_memmove d_memset
            d_safebcpy d_safemcpy d_sanemcmp d_sprintf_returns_strlen
            d_strchr d_strctcpy d_strerrm d_strerror d_volatile
            d_vprintf i_assert i_float i_limits i_math i_memory
            i_stdarg i_stdlib i_string i_values i_varargs i_varhdr
            prototype strings vaproto

      );
  }
  for my $k (@cannedkeys) {
    $Config_copy{$k} = '' unless exists $Config{$k};
  }
  is (scalar keys %Config_copy, $klenXS, 'same adjusted key count');
} else {
  is (scalar(keys %Config), $klenXS, 'same key count');
}

is_deeply ($copy ? \%Config_copy : \%Config, \%XSConfig, "cmp PP to XS hashes");

# old Test::Builders dont have is_passing
if ( Test::More->builder->can('is_passing')
      ? !Test::More->builder->is_passing() : 1 ) {
# 2>&1 because output string not captured on solaris
# http://cpantesters.org/cpan/report/fa1f8f72-a7c8-11e5-9426-d789aef69d38
  my $diffout = `diff --help 2>&1`;
  if (index($diffout, 'Usage: diff') != -1 #GNU
      || index($diffout, 'usage: diff') != -1) { #Solaris
    open my $f, '>','xscfg.txt';
    print $f Data::Dumper::Dumper({%XSConfig});
    close $f;
    open my $g, '>', 'ppcfg.txt';
  
    print $g ($copy
              ? Data::Dumper::Dumper({%Config_copy})
              : Data::Dumper::Dumper({%Config}));
    close $g;
    system('diff -U 0 ppcfg.txt xscfg.txt > cfg.diff');
    unlink('xscfg.txt');
    unlink('ppcfg.txt');
    if (-s 'cfg.diff') {
      open my $h , '<','cfg.diff';
      local $/;
      my $file = <$h>;
      close $h;
      diag($file);
    }
    unlink('cfg.diff');
  } else {
    diag('diff not available, can\'t output config delta');
  }
}
