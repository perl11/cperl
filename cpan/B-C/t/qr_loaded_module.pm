# This has to be in a seperate file to test for the previous 5.6 breakage
package qr_loaded_module;
my $var = 1;
my $qr_with_var = qr/^_?[^\W_0-9]\w*$var/;
sub qr_called_in_sub {
	$_[0] =~ $qr_with_var;
}
1;

