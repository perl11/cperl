#!/usr/bin/perl
# run with >=5.22 to check if $have_byteloader is already probed in B::C::Config
# and probe if not.
# we need to run this after make to be able to use ByteLoader already

my ($fr, $fw, $s);
open $fr, "<", "lib/B/C/Config.pm" or die "lib/B/C/Config.pm does not exist $!";
while (<$fr>) {
  if (/\$have_byteloader = undef;/) { # not yet probed
    open $fw, ">", "lib/B/C/Config.tmp" or die "cannot write lib/B/C/Config.tmp $!";
    my $check = probe_byteloader(); # returns 1 or 0
    s/\$have_byteloader = undef;/\$have_byteloader = $check;/;
    print $fw $s; # write what we read until now
  }
  if ($fw) {
    print $fw $_ ;
  } else {
    $s .= $_;
  }
}
close $fr;
if ($fw) {
  close $fw;
  unlink "lib/B/C/Config.bak" if -e "lib/B/C/Config.bak";
  rename "lib/B/C/Config.pm", "lib/B/C/Config.bak";
  rename "lib/B/C/Config.tmp", "lib/B/C/Config.pm";
}

sub probe_byteloader {
  my $out = "probe.plc";
  # This requires the dynamic/static target C.so to be built before [cpan #120161]
  if ($] > 5.021) {
    require Config;
    system "$Config::Config{make} linkext";
  }
  system "$^X -Mblib -MO=-qq,Bytecode,-H,-o$out -e'print q(ok)'";
  return "0" unless -s $out;
  my $ret = `$^X -Mblib $out`;
  unlink $out;
  if ($ret ne "ok") {
    warn "Warning: Broken perl5.22, unpatched for ByteLoader.\n".
      "  Try 'cpan App::perlall; perlall build 5.22.0 --patches=Compiler'\n".
      "  or try cperl5.22.2\n";
    return "0";
  }
  return "1";
}
