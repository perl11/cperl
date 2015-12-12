#!/usr/bin/perl
# run with >=5.22 to check if $have_byteloader is already probed in B::C::Flags
# and probe if not.
# we need to run this after make to be able to use ByteLoader already

my ($fr, $fw, $s);
open $fr, "<", "lib/B/C/Flags.pm" or die "lib/B/C/Flags.pm does not exist $!";
while (<$fr>) {
  if (/\$have_byteloader = undef;/) { # not yet probed
    open $fw, ">", "lib/B/C/Flags.tmp" or die "cannot write lib/B/C/Flags.tmp $!";
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
  unlink "lib/B/C/Flags.bak" if -e "lib/B/C/Flags.bak";
  rename "lib/B/C/Flags.pm", "lib/B/C/Flags.bak";
  rename "lib/B/C/Flags.tmp", "lib/B/C/Flags.pm";
}

sub probe_byteloader {
  my $out = "probe.plc";
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
