use ExtUtils::MakeMaker;
use strict;
use Config;

if (-d '../.git') {
    system("./update.sh") == 0
        or die "update.sh failed";
}

my @c_files = glob("*.c");
if (!@c_files and $^O eq 'MSWin32') { # win32 miniperl has no glob
    @c_files = qw(api.c dumper.c emitter.c loader.c parser.c perl_libyaml.c
                  reader.c scanner.c writer.c LibYAML.c);
}
unless (grep { /^LibYAML\.c$/i } @c_files) { # skip duplicate
    push @c_files, 'LibYAML.c';
}
my $o = $Config{_o};
my $obj_files = join ' ', map {
    my $c = $_;
    $c =~ s/\.c$/$o/;
    $c;
} @c_files;

my $DEFINE = $^O eq 'MSWin32'
  ? '-DHAVE_CONFIG_H -DYAML_DECLARE_EXPORT'
  : '-DHAVE_CONFIG_H';

WriteMakefile(
    NAME => 'YAML::XS::LibYAML',
    PREREQ_PM => { 'Test::Base' => 0.88 },
    # CCFLAGS => '-ansi -pedantic -Wall',
    # CCFLAGS => '-ansi -Wall',
    # CCFLAGS => '-pedantic -Wall',
    # CCFLAGS => '-Wall',
    DEFINE => $DEFINE,
    #FUNCLIST => [qw(Dump Load DumpFile LoadFile)],
    LIBS => [''], # e.g., '-lm'
    INC => '-I.',
    OBJECT => $obj_files,
    ABSTRACT_FROM => 'lib/YAML/XS/LibYAML.pm',
    VERSION_FROM => -f '../lib/YAML/XS.pm' ? '../lib/YAML/XS.pm' : 'lib/YAML/XS/LibYAML.pm',
    AUTHOR => 'Ingy döt Net <ingy@cpan.org>',
);
