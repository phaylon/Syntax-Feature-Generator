use strict;
use warnings;

use Test::More;

use syntax qw( generator );

subtest 'no parameters, no name, default return' => sub {

    my $maker = gen { 23 };
    is ref($maker), 'CODE', 'gen returned code reference';

    my $gen = $maker->();
    is ref($gen), 'CODE', 'maker returned code reference';

    is $gen->(), 23, 'generator returned value';
    is $gen->(), 23, 'value is returned repeatedly';

    done_testing;
};

subtest 'no parameters, no name, yield' => sub {

    my $maker = gen { yield 23 };
    is ref($maker), 'CODE', 'gen returned code reference';

    my $gen = $maker->();
    is ref($gen), 'CODE', 'maker returned code reference';

    is $gen->(), 23, 'generator returned value';
    is $gen->(), undef, 'second run runs out';
    is $gen->(), 23, 'generator returned value again';
    is $gen->(), undef, 'fourth run runs out again';

    done_testing;
};

subtest 'no parameters, no name, yield and implicit return' => sub {

    my $maker = gen { yield 23; 17 };
    is ref($maker), 'CODE', 'gen returned code reference';

    my $gen = $maker->();
    is ref($gen), 'CODE', 'maker returned code reference';

    is $gen->(), 23, 'generator returned value';
    is $gen->(), 17, 'second run runs out';
    is $gen->(), 23, 'generator returned value again';
    is $gen->(), 17, 'fourth run runs out again';

    done_testing;
};

subtest 'inside expression' => sub {

    my @result = gen { yield 23; 17 }, 2, 3;
    my $maker  = shift @result;

    is ref($maker), 'CODE', 'iterator';
    is_deeply \@result, [2, 3], 'rest';

    done_testing;
};

done_testing;
