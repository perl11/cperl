package ffi;

our $VERSION = '0.01c';
$VERSION =~ s/c$//;

%void::; %ptr::; %float::; %double::; %long::; %ulong::; %char::; %byte::;
%int8::; %int16::; %int64::; %uint8::; %uint16::; %uint32::; %uint64::;
%longlong::; %num32::; %num64::; %longdouble::; %bool::; %size_t::; %Pointer::;
%OpaquePointer::;

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

Via B<use ffi> there are more types than coretypes supported:

void, ptr, float, double, long, ulong, char, byte (U8), int8, int16,
int64, uint8, uint16, uint32, uint64, longlong, num32, num64,
longdouble, bool, size_t, Pointer, OpaquePointer (deprecated).

Matching the perl6
L<NativeCall|https://docs.perl6.org/language/nativecall> types.

=cut
