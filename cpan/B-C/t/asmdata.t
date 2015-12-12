#!/usr/bin/env perl -w
# blead cannot run -T

BEGIN {
    if ($ENV{PERL_CORE}){
	chdir('t') if -d 't';
	@INC = ('.', '../lib');
    }
    require Config;
    if ($ENV{PERL_CORE} and ($Config::Config{'extensions'} !~ /\bB\b/) ){
        print "1..0 # Skip -- Perl configured without B module\n";
        exit 0;
    }
}

use Test::More;
if (!-d '.git' or $ENV{NO_AUTHOR}) {
  plan tests => ($] < 5.009) ? 15 : 16;
}

use B ();
if ($] < 5.009) {
  use_ok('B::Asmdata', qw(%insn_data @insn_name @optype @specialsv_name));
} else { 
  use_ok('B', qw(@optype @specialsv_name));
  use_ok('B::Asmdata', qw(%insn_data @insn_name));
}

# see bytecode.pl (alias_to or argtype) and ByteLoader/bytecode.h
my @valid_type = qw(comment_t none svindex pvindex opindex U32 U16 U8 I32 IV long NV
                   PADOFFSET pvcontents strconst op_tr_array pmflags PV IV64);
my %valid_type = map {$_ => 1} @valid_type;

# check we got something.
isnt( keys %insn_data,  0,  '%insn_data exported and populated' );
isnt( @insn_name,       0,  '   @insn_name' );
isnt( @optype,          0,  '   @optype' );
isnt( @specialsv_name,  0,  '   @specialsv_name' );

# pick an op that's not likely to go away in the future
my @data = values %insn_data;
is( (grep { ref eq 'ARRAY' } @data),  @data,   '%insn_data contains arrays' );

# sort out unsupport ones, with no PUT method
# @data = grep {$_[1]} @data;
# pick one at random to test with.
my (@opnames, $random);
unless (!-d '.git' or $ENV{NO_AUTHOR}) {
  @opnames = sort keys %insn_data;
  $random = "";
} else {
  @opnames = ( (keys %insn_data)[rand @data] );
  $random = "random";
}

for my $opname (@opnames) {
  my $data = $insn_data{$opname};
  my $opidx = $data->[0];

  like( $data->[0], qr/^\d+$/,    "   op number for $random $opname:$opidx" );
  if ($data->[1]) {
    is( ref $data->[1],  'CODE',    "   PUT code ref for $opname" );

    my $putname = B::svref_2object($data->[1])->GV->NAME;
    $putname =~ s/^PUT_//;
    ok( $valid_type{$putname}, "   valid PUT name $putname for $opname" );
  } else {
    ok(1,  "   empty PUT for $opname" );
    ok(1,  "   skip valid PUT name check" );
  }
  ok( !ref $data->[2], "   GET method for $opname"  );
  my $getname = $data->[2];
  my $ok;
  if ($getname =~ /^GET_(.*)$/) {
    $ok = $valid_type{$1};
  }
  ok( $ok,             "   GET method $getname looks good"  );
  is( $insn_name[$data->[0]], $opname,    '@insn_name maps correctly' );

}

# I'm going to assume that op types will all be named /OP$/.
# Just 5.22 added a UNOP_AUX
if ($] >= 5.021007) {
  is( grep(/OP$/, @optype), scalar(@optype) - 1,  '@optype is almost all /OP$/' );
} else {
  is( grep(/OP$/, @optype), @optype,  '@optype is all /OP$/' );
}

# comment in bytecode.pl says "Nullsv *must come first so that the 
# condition ($$sv == 0) can continue to be used to test (sv == Nullsv)."
is( $specialsv_name[0],  'Nullsv',  'Nullsv come first in @special_sv_name' );

# other than that, we can't really say much more about @specialsv_name
# than it has to contain strings (on the off chance &PL_sv_undef gets 
# flubbed)
is( grep(!ref, @specialsv_name), @specialsv_name,   '  contains all strings' );

unless (!-d '.git' or $ENV{NO_AUTHOR}) {
  done_testing;
}
