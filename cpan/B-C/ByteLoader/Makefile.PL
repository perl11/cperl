use ExtUtils::MakeMaker;
use Config;
my $core = grep { $_ eq 'PERL_CORE=1' } @ARGV;
my $ccflags   = $Config{ccflags};
my $lddlflags = $Config{lddlflags};

if ( -d '.svn' or -d '.git' ) {
  $ccflags .= ' -ansi -Wall -Wextra' if $Config{cc} =~ /\bgcc/ and $Config{gccversion};
}
if ($] < 5.007) {
  # We are not called by ../Makefile.PL, but be sure about that for now.
  print "perl 5.6 does still use the builtin Bytecode compiler and ByteLoader\n";
  ExtUtils::MakeMaker::WriteEmptyMakefile;
  exit;
}
WriteMakefile(
    NAME		=> 'ByteLoader',
    VERSION_FROM	=> 'ByteLoader.pm',
    XSPROTOARG		=> '-noprototypes',
    OBJECT		=> 'byterun$(OBJ_EXT) ByteLoader$(OBJ_EXT)',
    LDDLFLAGS           => $lddlflags,
    CCFLAGS             => $ccflags,
    clean => { FILES =>
               "byterun.* *.core *.stackdump a.out *.c *.o *~ dll.base dll.exp"},

);

sub MY::depend {
  my $up = File::Spec->updir;
  my $bytecode_pl = File::Spec->catdir( '..', 'bytecode.pl' );
  return "
\$(INST_LIB)/ByteLoader.pm : ByteLoader.pm
	\$(NOECHO) \$(ABSPERLRUN) -MExtUtils::Install -e 'pm_to_blib({@ARGV}, '\''$(INST_LIB)/auto'\'', '\''$(PM_FILTER)'\'')' -- \
	  ByteLoader.pm \$(INST_LIB)/ByteLoader.pm

byterun.c : $bytecode_pl Makefile bytecode.h
	cd $up && \$(MAKE) \$(USEMAKEFILE) \$(FIRST_MAKEFILE) ByteLoader/byterun.c \$(PASTHRU)

byterun.h : $bytecode_pl Makefile
	cd $up && \$(MAKE) \$(USEMAKEFILE) \$(FIRST_MAKEFILE) ByteLoader/byterun.h \$(PASTHRU)

ByteLoader.c: byterun.h Makefile

ByteLoader\$(OBJ_EXT) : byterun.h byterun.c bytecode.h Makefile

"
}
