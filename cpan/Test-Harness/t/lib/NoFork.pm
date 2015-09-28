package NoFork;

BEGIN {
    *CORE::GLOBAL::fork = sub { die "you should not fork" };
}
use Config;
if ($Config::Config{d_fork}) {
  if (exists &Config::KEYS) {     # compiled Config
    *Config_FETCHorig = \&Config::FETCH;
    no warnings 'redefine';
    *Config::FETCH = sub {
      if ($_[0] and $_[1] eq 'd_fork') {
        return 0;
      } else {
        return Config_FETCHorig(@_);
      }
    }
  } else {
    tied(%Config)->{d_fork} = 0;    # uncompiled Config
  }
}

=begin TEST

Assuming not to much chdir:

  PERL5OPT='-It/lib -MNoFork' perl -Ilib bin/prove -r t

=end TEST

=cut

1;

# vim:ts=4:sw=4:et:sta
