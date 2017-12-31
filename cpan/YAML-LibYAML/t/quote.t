use lib '.';
use t::TestYAMLTests tests => 4;

is Dump('', [''], {foo => ''}), <<'...', 'Dumped empty string is quoted';
--- ''
---
- ''
---
foo: ''
...

is Dump({}, [{}], {foo => {}}), <<'...', 'Dumped empty map is {}';
--- {}
---
- {}
---
foo: {}
...

is Dump([], [[]], {foo => []}), <<'...', 'Dumped empty seq is []';
--- []
---
- []
---
foo: []
...

is Dump(['&1', '*1', '|2', '? foo', 'x: y', "\a\t\n\r"]), <<'...',
---
- '&1'
- '*1'
- '|2'
- '? foo'
- 'x: y'
- "\a\t\n\r"
...
'Dumped special scalars get quoted';

