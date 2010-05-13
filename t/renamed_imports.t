use strict;
use warnings;

use Test::More;

use syntax 
    'generator',
    'generator' => {
        -as             => 'unusedonlywanttoseeifyieldsdontclash',
    },
    'generator' => { 
        -as             => 'genloop', 
        -yield_return   => 0, 
        -yield_as       => 'sendout',
    };

subtest 'normal' => sub {

    my $it = (gen { yield $_ for 1 .. 2; undef })->();
    is $it->(), 1, 'first value';
    is $it->(), 2, 'second value';
    is $it->(), undef, 'end of line';
    is $it->(), 1, 'reentry';

    done_testing;
};

subtest 'looped' => sub {

    my $it = (genloop { sendout $_ for 1 .. 2; undef })->();
    is $it->(), 1, 'first value';
    is $it->(), 2, 'second value';
    is $it->(), 1, 'reentry';

    done_testing;
};

subtest 'looped with foreign yield' => sub {

    my $it = (genloop { yield $_ for 1 .. 2; undef })->();
    is $it->(), 1, 'first value';
    is $it->(), 2, 'second value';
    is $it->(), 1, 'reentry';

    done_testing;
};

done_testing;
