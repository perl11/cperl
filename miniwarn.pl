#! perl
my $arg = shift;
my $tgt = "lib/warnings.pm";
my $src = ($^X =~ /miniperl/ and $arg ne 'perl')
  ? "ext/warnings/warnings.boot" : "ext/warnings/warnings.pm";
if ($arg eq 'perl' or (!-e $tgt or -M $tgt >= -M $src)) {
  my $ro;
  if (!-w $tgt) { # EUMM makes it readonly
    chmod(0600, $tgt);
    $ro++;
  }
  print $src =~ /\.pm$/ ? "Enable" : "Disable", " warnings\n";
  `cp $src $tgt`;
  chmod(0400, $tgt) if $ro;
}
