#! perl
my $arg = shift;
my $mode = ($^X =~ /miniperl/ and $arg ne 'perl')
         ? "mini" : "perl";

if ($mode eq 'mini') {
  print "Disable warnings\n";
  copy($mode, "ext/warnings/warnings.boot"  => "lib/warnings.pm");
} else {
  print "Enable warnings\n";
  copy($mode, "ext/warnings/warnings.pm"  => "lib/warnings.pm");
}

sub copy($mode, $src, $tgt) {
  if ($arg eq 'perl' or (!-e $tgt or -M $tgt >= -M $src)) {
    my $ro;
    if (!-w $tgt) { # EUMM makes it readonly
      chmod(0600, $tgt);
      $ro++;
    }
    `cp $src $tgt`;
    chmod(0400, $tgt) if $ro;
  }
}
