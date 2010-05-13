use strict;
use warnings;

use FindBin;
use Test::Most;

use lib "$FindBin::Bin/lib";

throws_ok {
    require TestMissingBlock;
} qr/block/i, 'missing block error';

done_testing;
