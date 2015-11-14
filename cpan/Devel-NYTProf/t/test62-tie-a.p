# test determination of subroutine caller in tie calls

{
    # calls to TIESCALAR aren't seen by perl < 5.8.9 and 5.10.1
    sub MyTie::TIESCALAR { bless {}, shift; }
    sub MyTie::FETCH { }
    sub MyTie::STORE { }
}

tie my $tied, 'MyTie', 42;  # TIESCALAR
$tied = 1;                  # STORE
if ($tied) { 1 }            # FETCH

exit 0;
