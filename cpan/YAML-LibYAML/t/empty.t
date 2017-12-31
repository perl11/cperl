use lib '.';
use t::TestYAMLTests tests => 5;

is Dump(), '',
    'Dumping no objects produces an empty yaml stream';

{
    my @objects = Load('');
    is scalar(@objects), 0,
        'Loading empty yaml stream produces no objects';
}

{
    my @objects = Load("\n\n\n");
    is scalar(@objects), 0,
        'Loading yaml stream of empty lines produces no objects';
}

{
    my @objects = Load("   \n    \n    \n");
    is scalar(@objects), 0,
        'Loading yaml stream of blank lines produces no objects';
}

{
    my @objects = Load(<<'...');
# A comment line

                    # Another comment after a blank line
...
    is scalar(@objects), 0,
        'Loading blank lines an comments produce no objects';
}
