use vars qw/$b/;
BEGIN {
  $b = eval "sub {1}";
}
&$b;
&$b;
