use strict;
use warnings;

use Test::More;

use syntax qw( generator );

subtest 'scalar parameters' => sub {

    my $maker = gen ($n, $m) {
        yield $_ for $n .. $m;
    };

    my $count = $maker->(1, 10);
    is ref($count), 'CODE', 'parameterized maker generated code reference';

    my $calc = sub {
        my @found;
        my $safety = 0;

        while (my $value = $count->()) {

            die "Too many runs" if $safety > 15;
            $safety++;

            push @found, $value;
        }

        return \@found;
    };

    is_deeply $calc->(), [1 .. 10], 'generated incremential numbers';
    is_deeply $calc->(), [1 .. 10], 'generated incremential numbers a second time';

    done_testing;
};

subtest 'increments' => sub {

    my $by_return = gen ($n) { $n++ };
    my $ten_plus  = $by_return->(10);

    is $ten_plus->(), 10, 'first number';
    is $ten_plus->(), 11, 'second number';
    is $ten_plus->(), 12, 'third number';

    done_testing;
};

subtest 'list parameter' => sub {

    my $maker = gen (@ls) {
        yield shift @ls while @ls;
        undef;
    };

    my $shifter = $maker->(1, 2, 3);
    is ref($shifter), 'CODE', 'correct reference';

    is $shifter->(), 1, 'first item returned';
    is $shifter->(), 2, 'second item returned';
    is $shifter->(), 3, 'third item returned';
    is $shifter->(), undef, 'generator ran out of items';
    is $shifter->(), undef, 'generator state kept';

    done_testing;
};

subtest 'empty signature' => sub {

    my $maker = gen (  ) { yield 23; undef };
    is ref($maker), 'CODE', 'generator with empty parameter list returns code reference';

    my $gen = $maker->();

    is $gen->(), 23, 'generator works';
    is $gen->(), undef, 'generator runs out';

    done_testing;
};

done_testing;
