use strict;

package Bundle::CpanTestDummies;

$Bundle::CpanTestDummies::VERSION = 1.6 + sprintf "%.6f", substr(q$Rev$,4)/1000000;

1;

__END__

=head1 NAME

Bundle::CpanTestDummies - A bundle only for testing CPAN.pm

=head1 SYNOPSIS

  --- No Synopsis ---

=head1 CONTENTS

CPAN::Test::Dummy::Perl5::Build

  # uses Module::Build

CPAN::Test::Dummy::Perl5::Build::Fails

  # has a failing test

CPAN::Test::Dummy::Perl5::Make

  # traditional MakeMaker

CPAN::Test::Dummy::Perl5::BuildOrMake

  # has both a Makefile.PL and a Build.PL

CPAN::Test::Dummy::Perl5::Make::Failearly

  # fails already when Makefile.PL is called

CPAN::Test::Dummy::Perl5::Make::Zip

  # builds a .zip distro instead of a .tar.gz

=head1 DESCRIPTION

Within the CPAN.pm t/ directory, we keep two versions of this bundle:
one like a private bundle of the user in the t/dot-cpan/Bundle/
directory and one within the CPAN::Test::Dummy::Perl5::Make distro.

=head1 AUTHOR

Andreas Koenig
