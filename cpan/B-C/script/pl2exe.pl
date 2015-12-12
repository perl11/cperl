#! perl
# Fake a PE/COFF header, forcing Windows to load and interpret a perl script,
# better than pl2bat
# Copyright 2005 John Tobey <jtobey@john-edwin-tobey.org>

open IN, (my $name = shift) or die "Syntax: pl2exe.pl file.pl\n";

$name =~ s/\.pl$//;
$name .= '.exe';
open (OUT, ">$name") or die "can\'t write to $name: $!\n";
binmode OUT;  # because we want to be in control

print OUT "MZ(<<'EXE_STUFF') # -*-Perl-*-\015\012";
print OUT "Here comes offset 60 .....\015\012";

# The DWORD at offset 60 holds the offset of the IMAGE_NT_HEADERS struct.
# This stuff is in winnt.h.
print OUT pack ("L", 64);

my $code_size = 512;	# actually the size of the entire
			# code section, which in this case contains
			# data as well; rounded up to a multiple of 512

# Construct the IMAGE_NT_HEADERS structure.
my $headers = "PE\0\0";		# Portable Executable signature
$headers .= pack ('SSLLLSS',	# the IMAGE_FILE_HEADER substructure
		  0x14c,	# for Intel I386 or later, and compatible
		  1,		# number of sections
		  0x4d5a83be,	# time-date stamp when we created the exe (TODO)
		  0,0,		# symbols pointer, # symbols
		  224,		# size of the IMAGE_OPTIONAL_HEADER
		  0x010f	# random flags: 0xa18e(?) for a DLL
		  );
$headers .= pack ('SCCL9S6L4SSL6',# IMAGE_OPTIONAL_HEADERS substruct
		  0x010b,	# Magic PE32 : normal 32-bit, 0x0107 would be a ROM image
		  1,0,		# linker version maj.min (that's us)
		  $code_size,
		  0,0,		# size of initialized/un- data
		  0x1000,	# RVA of entry point
		  		# (the RVA is the address when loaded,
		  		# relative to the image base)
		  0x1000,	# RVA of start of code section
		  0,		# RVA of data section, if there were one
		  0x400000,	# image base
		  0x1000,	# section alignment
		  512,		# file alignment
		  4, 0,		# OS version maj.min
		  0, 0,		# Image version
		  4, 0,		# Subsystem version
		  0,		# reserved1 zero
		  0x2000,	# size of image
		  512,		# size of headers
		  0,		# checksum; ignored
		  3,		# Subsystem 3=console app; 2=GUI app
		  0,		# DLL characteristics (obsolete)
		  0x1000,	# size of stack reserve
		  0x1000,	# size of stack commit
		  0x100000,	# size of heap reserve
		  0,		# size of heap commit
		  0,		# loader flags (obsolete)
		  16		# the number or RVA/size pairs to follow
		  );
# DATA directory (16)
$headers .= pack ('L32',	# 16 (RVA,size) pairs locating certain
		  		# important image structures; the ones
		  		# we don't have are left zero
		  0,0,          # export directory
		  0x1100, 195,	# import directory
		  0,0,  	# resource directory
                  0,0,		# exception table
                  0,0,		# security table
		  0x10f8, 8,	# base relocation table (empty, but needed)
		  0,0,		# debug
                  0,0,		# architecture specific data
                  0,0,		# global pointer
                  0,0,		# TLS dir
                  0,0,		# load config table
                  0,0,		# bound import table
                  0,0,		# import address table
                  0,0,		# delay import descriptor
                  0,0,		# COM descriptor
                  0,0		# unused
		  );
print OUT $headers;

# SECTION TABLE, We need to describe our one section.
my $section_header = pack ('a8L8',
			   '.perl',	# section name
			   464,		# raw data size
			   0x1000,	# section begin RVA
			   512,		# rounded-up data size
			   512,		# offset in file
			   0,0,0,	# relocations, line # offs, line #s
			   0xe0000060,	# flags: CODE INITIALIZED_DATA EXECUTE READ WRITE ALIGN_DEFAULT(16)
			   );
print OUT $section_header;

print OUT "\015\012\015\012";
print OUT "-------------that was the IMAGE_NT_HEADERS struct-------------";
print OUT "\015\012------------------------\015\012";
print OUT "--------Now comes the code (at offset 512, if you please)-----";
print OUT "\015\012\015\012";

# Next comes the code.
# It performs fixups, prepends "perl -x " to the command line,
# launches perl, and returns perl's exit status. See at the end.

print OUT pack ("H*", "b8cc114000833dcc1140000074168b1085d27d06");
print OUT pack ("H*", "01500483c004ff0283c00483380075eaa1481140");
print OUT pack ("H*", "00ffd089c389c731c0b9f7fffffffcf2ae89f829");
print OUT pack ("H*", "d883e1fc01ccbec311400089e7b908000000f3a4");
print OUT pack ("H*", "89de89c1f3a489e383ec7cb91b00000089e731c0");
print OUT pack ("H*", "f3ab895c2404c74424284400000089e083c02889");
print OUT pack ("H*", "44242083c04489442424a140114000ffd021c075");
print OUT pack ("H*", "046a64eb258b4424446aff50a14c114000ffd021");
print OUT pack ("H*", "c074046a65eb0f8b4424446a665450a150114000");
print OUT pack ("H*", "ffd0a144114000ffd0");

print OUT "\015\012\015\012";
print OUT "-------here's the data, at file offset 760: -------";
print OUT "\015\012\015\012";

# Print out a dummy relocation table.
# The code is not relocatable--it must be loaded at 0x400000.
# But to allow programs to load it with LoadLibrary() and access
# its resources, the file must contain this table.
print OUT pack ('LL', 0x1000,8);

# The import table.  Contains RVAs and names.
# (we import 5 functions from KERNEL32.DLL)
print OUT pack ('L5', 0x1128, # (unbound IAT)
                      0,      # TimeDateStamp
                      0,      # ForwarderChain
                      0x1158, # DLL Name RVA
		      0x1140);# Import Address Table RVA
print OUT pack ('L5', 0,0,0,0,0); # Ordinals of our KERNEL32 names, 0=unused
print OUT pack ('L6', 0x1166, 0x1178, 0x1186, 0x1198, 0x11ae, 0);
# Not sure if we really need to do this twice, but why argue:
print OUT pack ('L6', 0x1166, 0x1178, 0x1186, 0x1198, 0x11ae, 0);
# Gee it would be nice if C<pack> knew how to align things...
print OUT "KERNEL32.DLL\0\0";
print OUT "\0\0CreateProcessA\0\0"; 	# 1140
print OUT "\0\0ExitProcess\0";		# 1144
print OUT "\0\0GetCommandLineA\0";	# 1148
print OUT "\0\0WaitForSingleObject\0";	# 114c
print OUT "\0\0GetExitCodeProcess\0";	# 1150

# Our initialized data:
print OUT "perl -x \0"; # 11c3
# align 4
print OUT pack ('L*', 0);

# Let Perl know we're done.  We no longer care about CRLF.
print OUT "\nEXE_STUFF\nif 0;\n\n";

$_ = <IN>;
unless ($_ =~ /^\#!.*perl/ ) {
    print OUT "#!perl\n";
}
print OUT $_, <IN>;
close IN;
close OUT;
chmod 0755, $name;

__END__

=pod

  # base: 401000
  objdump -D --target=binary --architecture i386 $code

   0:   b8 cc 11 40 00          mov    $0x4011cc,%eax
   5:   83 3d cc 11 40 00 00    cmpl   $0x0,0x4011cc
   c:   74 16                   je     0x24
   e:   8b 10                   mov    (%eax),%edx
  10:   85 d2                   test   %edx,%edx
  12:   7d 06                   jge    0x1a
  14:   01 50 04                add    %edx,0x4(%eax)
  17:   83 c0 04                add    $0x4,%eax
  1a:   ff 02                   incl   (%edx)
  1c:   83 c0 04                add    $0x4,%eax
  1f:   83 38 00                cmpl   $0x0,(%eax)
  22:   75 ea                   jne    0xe
  24:   a1 48 11 40 00          mov    0x401148,%eax
  29:   ff d0                   call   *%eax		; GetCommandLineA
  2b:   89 c3                   mov    %eax,%ebx
  2d:   89 c7                   mov    %eax,%edi
  2f:   31 c0                   xor    %eax,%eax
  31:   b9 f7 ff ff ff          mov    $0xfffffff7,%ecx
  36:   fc                      cld
  37:   f2 ae                   repnz scas %es:(%edi),%al
  39:   89 f8                   mov    %edi,%eax
  3b:   29 d8                   sub    %ebx,%eax
  3d:   83 e1 fc                and    $0xfffffffc,%ecx
  40:   01 cc                   add    %ecx,%esp
  42:   be c3 11 40 00          mov    $0x4011c3,%esi  ; prepend 'perl -x '
  47:   89 e7                   mov    %esp,%edi
  49:   b9 08 00 00 00          mov    $0x8,%ecx
  4e:   f3 a4                   rep movsb %ds:(%esi),%es:(%edi)
  50:   89 de                   mov    %ebx,%esi
  52:   89 c1                   mov    %eax,%ecx
  54:   f3 a4                   rep movsb %ds:(%esi),%es:(%edi)
  56:   89 e3                   mov    %esp,%ebx
  58:   83 ec 7c                sub    $0x7c,%esp
  5b:   b9 1b 00 00 00          mov    $0x1b,%ecx
  60:   89 e7                   mov    %esp,%edi
  62:   31 c0                   xor    %eax,%eax
  64:   f3 ab                   rep stos %eax,%es:(%edi)
  66:   89 5c 24 04             mov    %ebx,0x4(%esp)
  6a:   c7 44 24 28 44 00 00    movl   $0x44,0x28(%esp)
  71:   00
  72:   89 e0                   mov    %esp,%eax
  74:   83 c0 28                add    $0x28,%eax
  77:   89 44 24 20             mov    %eax,0x20(%esp)
  7b:   83 c0 44                add    $0x44,%eax
  7e:   89 44 24 24             mov    %eax,0x24(%esp)
  82:   a1 40 11 40 00          mov    0x401140,%eax
  87:   ff d0                   call   *%eax		; if (!CreateProcessA)
  89:   21 c0                   and    %eax,%eax
  8b:   75 04                   jne    0x91
  8d:   6a 64                   push   $0x64
  8f:   eb 25                   jmp    0xb6		;   abnormal exit
  91:   8b 44 24 44             mov    0x44(%esp),%eax ; else
  95:   6a ff                   push   $0xffffffff
  97:   50                      push   %eax
  98:   a1 4c 11 40 00          mov    0x40114c,%eax
  9d:   ff d0                   call   *%eax		; if (!WaitForSingleObject)
  9f:   21 c0                   and    %eax,%eax
  a1:   74 04                   je     0xa7
  a3:   6a 65                   push   $0x65
  a5:   eb 0f                   jmp    0xb6		;   abnormal exit
  a7:   8b 44 24 44             mov    0x44(%esp),%eax ; else
  ab:   6a 66                   push   $0x66		;   exit with child code
  ad:   54                      push   %esp
  ae:   50                      push   %eax
  af:   a1 50 11 40 00          mov    0x401150,%eax
  b4:   ff d0                   call   *%eax		; GetExitCodeProcess
  b6:   a1 44 11 40 00          mov    0x401144,%eax
  bb:   ff d0                   call   *%eax		; ExitProcess

=cut
