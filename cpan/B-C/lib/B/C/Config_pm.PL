#! perl
# dummy Config.pm creator to please regen/lib_cleanup and the installer

use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use Cwd;

# List explicitly here the variables you want Configure to
# generate.  Metaconfig only looks for shell variables, so you
# have to mention them as if they were shell variables, not
# %Config entries.  Thus you write
#  $startperl
# to ensure Configure will look for $Config{startperl}.
# Wanted:  $archlibexp

# This forces PL files to create target in same directory as PL file.
# This is so that make depend always knows where to find PL derivatives.
$origdir = cwd;
chdir dirname($0);
$file = basename($0, '.PL');
$file .= '.com' if $^O eq 'VMS';

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

# In this section, perl variables will be expanded during extraction.
# You can use $Config{...} to use Configure variables.

print OUT <<"!GROK!THIS!";
# written by B::C Makefile.PL. $extra_{cflags,libs} need a leading space if used.
package B::C::Config;

!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';

$VERSION = '1.54';
$B::C::REVISION = '';

# -fav-init optimization
$have_independent_comalloc = 0;
$use_declare_independent_comalloc = 0;

# broken or patched upstream 5.22 ByteLoader. undef for yet undecided
$have_byteloader = 0;
# cperl 5.22.2:
$have_op_rettype = 0;
$have_HEK_STATIC = 1;
# use extra compiler flags, after ccopts, resp. ldopts
$extra_cflags = "";
$extra_libs = "";
# cperl core specific
@deps = qw( AnyDBM_File AutoLoader B B::AV B::Asmdata B::BINOP B::BM B::C B::C::Config B::C::InitSection B::C::Section B::CC B::COP B::CV B::FAKEOP B::FM B::GV B::HE B::HV B::INVLIST B::IO B::IV B::LEXWARN B::LISTOP B::LOGOP B::LOOP B::MAGIC B::METHOP B::NULL B::NV B::OBJECT B::OP B::PADLIST B::PADNAME B::PADNAMELIST B::PADOP B::PMOP B::PV B::PVIV B::PVLV B::PVMG B::PVNV B::PVOP B::REGEXP B::RHE B::RV B::SPECIAL B::STASHGV B::SV B::SVOP B::Section B::UNOP B::UNOP_AUX B::UV CORE CORE::GLOBAL Carp Config DB DynaLoader EV Encode Errno Exporter Exporter::Heavy ExtUtils ExtUtils::Constant ExtUtils::Constant::ProxySubs Fcntl FileHandle IO IO::File IO::Handle IO::Poll IO::Seekable IO::Socket IO::Socket::SSL Int Internals Net Net::DNS Num O POSIX PerlIO PerlIO::Layer PerlIO::scalar Regexp SelectSaver Str Symbol UInt UNIVERSAL XSConfig XSLoader __ANON__ arybase arybase::mg attributes constant coretypes int main mro num re str strict threads uint utf8 vars version warnings warnings::register Socket Socket );

our %Config = (
!NO!SUBS!

for my $k (qw(archname cc ccflags d_c99_variadic_macros d_dlopen d_isinf d_isnan d_longdbl
              dlext i_dlfcn
              ivdformat ivsize longsize mad nvgformat ptrsize static_ext usecperl
              usedl useithreads uselongdouble usemultiplicity usemymalloc uvuformat))
  my $v = $Config{$k};
  if (!defined $v) {
    $v = 'undef';
  } else {
    $v =~ s/'/\\'/g;
    if ($v !~ /^\d+$/) {
      $v = "'".$v."'";
    }
  }
  print OUT "\t$k => $v,\n";
}
print OUT <<'!NO!SUBS!';
);

1;
!NO!SUBS!

close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
