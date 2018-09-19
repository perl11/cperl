package ffi;

our $VERSION = '0.01c';
$VERSION =~ s/c$//;

%void::; %ptr::; %float::; %double::; %long::; %ulong::; %char::; %byte::;
%int8::; %int16::; %int64::; %uint8::; %uint16::; %uint32::; %uint64::;
%longlong::; %num32::; %num64::; %longdouble::; %bool::; %size_t::; %Pointer::;
%OpaquePointer::;

1;
__END__
# TODO: c-struct helpers, callback helpers

=head1 NAME

ffi - extern sub types and helpers

=head1 SYNOPSIS

    extern sub NAME () :CORETYPE;

    use ffi;
    extern sub NAME () :FFITYPE;

=head1 DESCRIPTION

Natively cperl defines the following L<perltypes/coretypes>, which are
valid ffi types:

    int, Int, num, Num, str, Str, uint, UInt.

TODO: C<Uni>, C<uni> for utf8-encoded strings, and C<wchar>.

Via B<use ffi> there are more types than coretypes supported:

    void, ptr, float, double, long, ulong, char, byte (U8), int8,
    int16, int64, uint8, uint16, uint32, uint64, longlong, num32,
    num64, longdouble, bool, size_t, Pointer,
    OpaquePointer (deprecated).

Matching the perl6
L<NativeCall|https://docs.perl6.org/language/nativecall> types.

=head1 COPY vs SHARE

The ffi arguments and return types default to :void.  If not void, the
declared types are matched to the given argument value and converted
if possible.

The primitive types create a new copy of the value.

The aggregate types, such as str or Str (Uni, wchar not yet) try to share
the value first, and only if not possible create a copy.
As argument an aggregate type is always shared, as return type possibly shared.

E.g.

    extern sub strchr(str $s, int $i) :str;
    print strchr("abcd", ord("c"))

The result ptr of strchr points inside the argument string, to "c"
with an offset of 2 from the "a". So we can use the SvOOK
interpretation of a string pointing to the delta, and the string is
not copied back.  But if the result of the ffi call points outside the
given string, we need to copy it.

The handling of native arrays and structs (i.e native classes) via ffi
is not implemented yet.

=cut
