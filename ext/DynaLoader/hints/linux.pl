# XXX Configure test needed.
# Some Linux releases like to hide their <nlist.h>
$self->{CCFLAGS} = $Config{ccflags} . ' -I/usr/include/libelf'
	if -f "/usr/include/libelf/nlist.h";
# Some silly modules like mod_perl use DynaLoader.a in a shared
# module, so add cccdlflags if we're going for a shared libperl
$self->{CCFLAGS} = ($self->{CCFLAGS} || $Config{ccflags}) . " $Config{cccdlflags}"
	if $Config{'useshrplib'} eq 'true';

1;
