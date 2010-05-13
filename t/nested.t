use strict;
use warnings;

use Test::More;

use syntax qw( generator );

gen over (@values) {
    yield $_ for @values;
}

gen swapped ($n, $m) {
    yield $n->();
    $m->();
}

my $it = swapped(
    over(qw( foo bar baz )),
    over(1 .. 3),
);

my @found;
while (my $value = $it->()) {
    push @found, $value;
}

is_deeply \@found, [foo => 1, bar => 2, baz => 3], 'correct order in nested yields';

done_testing;
