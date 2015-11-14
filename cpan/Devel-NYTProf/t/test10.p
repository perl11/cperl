$code = eval "sub { sleep 1; }$Devel::NYTProf::StrEvalTestPad";
$code->();
