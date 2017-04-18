use lib '.';
use t::TestYAMLTests tests => 8;
use utf8;

is Dump("\x{100}"), "--- \xC4\x80\n", 'Dumping wide char works';
is Load("--- \xC4\x80\n"), "\x{100}", 'Loading UTF-8 works';
is Load("\xFE\xFF\0-\0-\0-\0 \x01\x00\0\n"), "\x{100}", 'Loading UTF-16BE works';
is Load("\xFF\xFE-\0-\0-\0 \0\x00\x01\n\0"), "\x{100}", 'Loading UTF-16LE works';

my $hash = {
    '店名' => 'OpCafé',
    '電話' => <<'...',
03-5277806
0991-100087
...
    Email => 'boss@opcafe.net',
    '時間' => '11:01~23:59',
    '地址' => '新竹市 300 石坊街 37-8 號',
};

my $yaml = <<'...';
---
Email: boss@opcafe.net
地址: 新竹市 300 石坊街 37-8 號
店名: OpCafé
時間: 11:01~23:59
電話: "03-5277806\n0991-100087\n"
...

utf8::encode($yaml);

is Dump($hash), $yaml, 'Dumping Chinese hash works';
is_deeply Load($yaml), $hash, 'Loading Chinese hash works';

my $hash2 = {
    'モジュール' => [
        {
            '名前' => 'YAML',
            '作者' => {'名前' => 'インギー', '場所' => 'シアトル'},
        },
        {
            '名前' => 'Plagger',
            '作者' => {'名前' => '宮川達彦', '場所' => 'サンフランシスコ' },
        },
    ]
};

my $yaml2 = <<'...';
---
モジュール:
  - 作者:
      名前: インギー
      場所: シアトル
    名前: YAML
  - 作者:
      名前: 宮川達彦
      場所: サンフランシスコ
    名前: Plagger
...

utf8::encode($yaml2);

is Dump($hash2), $yaml2, 'Dumping Japanese hash works';
is_deeply Load($yaml2), $hash2, 'Loading Japanese hash works';
