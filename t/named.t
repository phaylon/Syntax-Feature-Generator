use strict;
use warnings;

use Test::More;

use syntax qw( generator );

gen range ($n, $m) { yield $_ for $n .. $m }

subtest 'named generator' => sub {

    my $count = range(1, 5);
    is ref($count), 'CODE', 'maker subroutine returned code reference';

    my $collect = do {

        my @found;
        my $safety = 10;

        while (my $value = $count->()) {

            $safety--;
            die "Too many runs" unless $safety;

            push @found, $value;
        }

        \@found;
    };

    is_deeply $collect, [1..5], 'named generator generated correct values';

    done_testing;
};

do {
    package GenTest;
    use syntax 'generator';

    gen swapped ($class, $n, $m) { 
        yield  "$class $n"; 
        return "$class $m";
    }
};

subtest 'class bound generator' => sub {
    
    my $swapper = GenTest->swapped(23, 17);
    is ref($swapper), 'CODE', 'maker subroutine returned code reference';

    is $swapper->(), 'GenTest 23', 'first value correct';
    is $swapper->(), 'GenTest 17', 'second value correct';
    is $swapper->(), 'GenTest 23', 'back to first value';
    is $swapper->(), 'GenTest 17', 'and again the second one';

    done_testing;
};

done_testing;
