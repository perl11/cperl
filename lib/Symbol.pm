package Symbol;

=head1 NAME

Symbol - manipulate Perl symbols and their names

=head1 SYNOPSIS

    use Symbol;

    $sym = gensym;
    open($sym, '<', "filename");
    $_ = <$sym>;
    # etc.

    ungensym $sym;      # no effect

    # replace *FOO{IO} handle but not $FOO, %FOO, etc.
    *FOO = geniosym;

    print qualify("x"), "\n";              # "main::x"
    print qualify("x", "FOO"), "\n";       # "FOO::x"
    print qualify("BAR::x"), "\n";         # "BAR::x"
    print qualify("BAR::x", "FOO"), "\n";  # "BAR::x"
    print qualify("STDOUT", "FOO"), "\n";  # "main::STDOUT" (global)
    print qualify(\*x), "\n";              # returns \*x
    print qualify(\*x, "FOO"), "\n";       # returns \*x

    use strict refs;
    print { qualify_to_ref $fh } "foo!\n";
    $ref = qualify_to_ref $name, $pkg;

    use Symbol qw(delete_package);
    delete_package('Foo::Bar');
    print "deleted\n" unless exists $Foo::{'Bar::'};

=head1 DESCRIPTION

=over

=item gensym

C<Symbol::gensym> creates an anonymous glob and returns a reference
to it.  Such a glob reference can be used as a file or directory
handle.

=item ungensym SYM

For backward compatibility with older implementations that didn't
support anonymous globs, C<Symbol::ungensym> is also provided.
But it doesn't do anything.

=item geniosym

C<Symbol::geniosym> creates an anonymous IO handle.  This can be
assigned into an existing glob without affecting the non-IO portions
of the glob.

=item qualify SYM, PACKAGE

C<Symbol::qualify> turns unqualified symbol names into qualified
variable names (e.g. "myvar" -E<gt> "MyPackage::myvar").  If it is given a
second parameter, C<qualify> uses it as the default package;
otherwise, it uses the package of its caller.  Regardless, global
variable names (e.g. "STDOUT", "ENV", "SIG") are always qualified with
"main::".

Qualification applies only to symbol names (strings).  References are
left unchanged under the assumption that they are glob references,
which are qualified by their nature.

=item qualify_to_ref SYM, PACKAGE

C<Symbol::qualify_to_ref> is just like C<Symbol::qualify> except that it
returns a glob ref rather than a symbol name, so you can use the result
even if C<use strict 'refs'> is in effect.

=item delete_package PACKAGE

C<Symbol::delete_package> wipes out a whole package namespace, and in
cperl if it's a XS package calls L<DynaLoader/dl_unload_file()> also.
Note this routine is not exported by default, you may want to import
it explicitly.

With C<main> several protected core symbols are kept.
With user-packages readonly symbols, like classes are deleted.

=back

=head1 BUGS

C<Symbol::delete_package> is a bit too powerful. It undefines every symbol that
lives in the specified package. Since perl, for performance reasons, does not
perform a symbol table lookup each time a function is called or a global
variable is accessed, some code that has already been loaded and that makes use
of symbols in package C<Foo> may stop working after you delete C<Foo>, even if
you reload the C<Foo> module afterwards.

=cut

BEGIN { require 5.005; }

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(gensym ungensym qualify qualify_to_ref);
@EXPORT_OK = qw(delete_package geniosym);

$VERSION = '1.08_02';

my $genpkg = "Symbol::";
my $genseq = 0;

my %global = map {$_ => 1} qw(ARGV ARGVOUT ENV INC SIG STDERR STDIN STDOUT);

#
# Note that we never _copy_ the glob; we just make a ref to it.
# If we did copy it, then SVf_FAKE would be set on the copy, and
# glob-specific behaviors (e.g. C<*$ref = \&func>) wouldn't work.
#
sub gensym () {
    my $name = "GEN" . $genseq++;
    my $ref = \*{$genpkg . $name};
    delete $$genpkg{$name};
    $ref;
}

sub geniosym () {
    my $sym = gensym();
    # force the IO slot to be filled
    select(select $sym);
    *$sym{IO};
}

sub ungensym ($) {}

sub qualify ($;$) {
    my ($name) = @_;
    if (!ref($name) && index($name, '::') == -1 && index($name, "'") == -1) {
	my $pkg;
	# Global names: special character, "^xyz", or other. 
	if ($name =~ /^(([^a-z])|(\^[a-z_]+))\z/i || $global{$name}) {
	    # RGS 2001-11-05 : translate leading ^X to control-char
	    $name =~ s/^\^([a-z_])/'qq(\c'.$1.')'/eei;
	    $pkg = "main";
	}
	else {
	    $pkg = (@_ > 1) ? $_[1] : caller;
	}
	$name = $pkg . "::" . $name;
    }
    $name;
}

sub qualify_to_ref ($;$) {
    return \*{ qualify $_[0], @_ > 1 ? $_[1] : caller };
}

#
# of Safe.pm lineage
#
sub delete_package ($) {
    my $pkg = shift;

    # expand to full symbol table name if needed

    unless ($pkg =~ /^main::.*::$/) {
        $pkg = "main$pkg"	if	$pkg =~ /^::/;
        $pkg = "main::$pkg"	unless	$pkg =~ /^main::/;
        $pkg .= '::'		unless	$pkg =~ /::$/;
    }

    my($stem, $leaf) = $pkg =~ m/(.*::)(\w+::)$/;
    my $stem_symtab = *{$stem}{HASH} if defined $stem;
    return unless defined $stem_symtab and exists $stem_symtab->{$leaf};

    # clear all the symbols in the package
    # but special-case READONLY symbols and internal core packages
    # core protected symbols are kept. user readonly symbols, like classes are deleted.

    my $leaf_symtab = *{$stem_symtab->{$leaf}}{HASH};
    my $keep = qr/^(CORE|Internals|utf8|Error|UNIVERSAL|PerlIO|version|re)::$/;
    if ($pkg eq 'main::') {
      foreach my $name (keys %main::) {
        my $sym = $pkg . $name;
        next if $name eq '!';
        next if $name =~ $keep;
        next if Internals::SvREADONLY(${$sym});
        next if Internals::SvREADONLY(%{$sym});
        next if Internals::SvREADONLY(@{$sym});

        undef &{$sym} if defined &{$name};
        undef ${$sym} unless $name =~ /^(STD...?|!|1|2|\]|_)$/;
        undef @{$sym} if @{$name};
        undef %{$sym} if %{$name};
        undef *{$sym} unless $name =~ /^(STD...?|_)$/;
      }
    }
    elsif ($pkg =~ $keep) {
        ;
    }
    else {
      foreach my $name (keys %$leaf_symtab) {
        my $sym = $pkg . $name;
        # search in @DynaLoader::dl_modules to unload it
        if (exists ${main::}{DynaLoader}) {
          my $module = grep { $_ eq $sym } @DynaLoader::dl_modules;
          if ($module) {
            # search for the filename, load it again to return the libref handle
            # to be able to unload it
            my $Config_loaded = exists ${main::}{Config};
            my $dlext;
            if ($^O eq 'darwin') {
              $dlext = 'dylib'; $Config_loaded++;
            } elsif ($^O =~ /(MSWin32|cygwin|msys|dos)/) {
              $dlext = 'dll'; $Config_loaded++;
            } elsif ($^O =~ /(ux|ix|bsd|solaris|sunos)$/) {
              $dlext = 'so'; $Config_loaded++;
            } else {
              require Config;
              $dlext = $Config::Config{dlext};
            }
            my @modparts = split(/::/,$module);
            my $modfname = $modparts[-1];
            $modfname = &mod2fname(\@modparts) if defined &DynaLoader::mod2fname;
            my $modpname = join('/',@modparts);
            foreach (@INC) {
              $dir = "$_/auto/$modpname";
              next unless -d $dir; # skip over uninteresting directories
              # check for common cases to avoid autoload of dl_findfile
              my $try = "$dir/$modfname.$dlext";
              last if $file = ($DynaLoader::do_expand)
                ? dl_expandspec($try) : ((-f $try) && $try);
              # no luck here, save dir for possible later dl_findfile search
              push @dirs, $dir;
            }
            # last resort, let dl_findfile have a go in all known locations
            $file = dl_findfile(map("-L$_",@dirs,@INC), $modfname) unless $file;
            DynaLoader::dl_unload_file(DynaLoader::dl_load_file $file);
            &delete_package('Config') unless $Config_loaded;
          }
        }
        Internals::SvREADONLY(${$sym}, 0) if Internals::SvREADONLY(${$sym});
        Internals::SvREADONLY(%{$sym}, 0) if Internals::SvREADONLY(%{$sym});
        Internals::SvREADONLY(@{$sym}, 0) if Internals::SvREADONLY(@{$sym});
        undef *{$sym};
      }
    }

    # delete the symbol table

    %$leaf_symtab = ();
    delete $stem_symtab->{$leaf};
}

1;
