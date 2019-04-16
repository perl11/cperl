#!./perl

use FileCache maxopen => 2;
my @files = map { $_ . $$ } qw(foo bar baz quux);
my $pid = $$;
END { 1 while unlink @files }

use Test::More tests => 5;

{# Test 2: that we actually adhere to maxopen
  for my $path ( @files ){
    cacheout $path;
    print $path "$path 1\n";
  }
  
  my @cat;
  for my $path ( @files ){
    ok(fileno($path) || $path =~ /^(?:foo|bar)$pid$/);
    next unless fileno($path);
    print $path "$path 2\n";
    close($path);
    open($path, '<', $path);
    <$path>;
    push @cat, <$path>;
    close($path);
  }
  ok( grep(/^(?:baz|quux)$pid 2$/, @cat) == 2 );
}
