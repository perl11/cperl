#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}
plan tests => 2;

my $cmd = <<'END';
$|++;
my $s = shift // 2;
sub rss {
  # not portable and no process module in core
  # `ps -o "comm,rss,vsize" | grep perl`
  print "\n";
}
print "# BEGIN ",scalar keys %main::," ",rss;
require Symbol;
require POSIX;

print "# GOT POSIX ",scalar keys %main::," ",rss;
sleep($s);

POSIX->import;
print "# IMPORT POSIX ",scalar keys %main::," ",rss;
sleep($s);

POSIX->unimport;
Symbol::delete_package('POSIX');
# with cperl we can safely use Symbol, with perl5 not
if ($^V =~ /c$/) {
  Symbol::delete_package('main::');
  eval 'sub rss {print"\n";}';
} else {
  for (keys %main::) {
    undef ${$_} unless /^(STD|!|0|1|2|\]|_)/;
    undef &{$_} unless /rss/;
    undef @{$_};
    undef *{$_} unless /^(STD...?|main::|DynaLoader::|Internals::|rss|_|!)$/;
    delete $main::{$_} unless /^(STD...?|main::|DynaLoader::|Internals::|rss|_|!)$/;
  }
}
print "# unloaded ",scalar keys %main::," ",rss;
sleep(0.5);

DynaLoader::dl_unload_file($_) for @DynaLoader::dl_librefs;
undef *DynaLoader::;
print "# unload XS ",scalar keys %main::," ",rss;

print "POSIX::$_\n" for keys %POSIX::;
Internals::gc() if defined \&Internals::gc; 
print "# freed ",scalar keys %main::," ",rss,"\n";
sleep(0.5);
END

my $Perl = which_perl();
my $tmpfile = tempfile();
chmod 0755, $tmpfile;
unlink_all $tmpfile;

if (!is_miniperl()) {
  open(my $f, ">", $tmpfile) || DIE("Can't open temp test file: $!");
  print $f $cmd;
  close $f;
  my $res = system("$Perl -I../lib -I../lib/auto $tmpfile 0");
  ok(!$res, "errcode: ".$?>>8);
} else {
  ok(1, "skip - no POSIX with miniperl");
}

$cmd =~ s/POSIX/parent/g;
$cmd =~ s/^DynaLoader.*$//m;
$cmd =~ s/^.+unload XS.+$//m;
open(my $f, ">", $tmpfile) || DIE("Can't open temp test file: $!");
print $f $cmd;
close $f;

my $res = system("$Perl -I../lib $tmpfile 0");
ok(!$res, "errcode: ".$?>>8);
unlink_all $tmpfile;
