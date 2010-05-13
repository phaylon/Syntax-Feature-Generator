use strict;
use warnings;

# ABSTRACT: Value yielding Generators

package Syntax::Feature::Generator;

use Carp                    qw( croak );
use Devel::Declare          ();
use Data::Dump              qw( pp );
use Coro::Generator;
use B::Hooks::EndOfScope;
use Sub::Install            qw( install_sub );
use Text::Trim              qw( trim );

use aliased 'Devel::Declare::Context::Simple', 'Context';

use namespace::clean;

$Carp::Internal{ +__PACKAGE__ }++;

sub install {
    my ($class, %args) = @_;

    # passed information
    my $target  = $args{into};
    my $options = $args{options};
    my $name    = $options->{ -as }         || 'gen';
    my $yname   = $options->{ -yield_as }   || 'yield';
    # TODO check if names and options are valid
    
    # setup declarative keyword handler
    Devel::Declare->setup_for(
        $target => {
            $name => {
                const => sub {
                    my $ctx = Context->new;
                    $ctx->init(@_);
                    $class->_transform($ctx);
                },
            },
        },
    );

    # install subroutine to pickup the deparsed data
    install_sub {
        into    => $target,
        as      => $name,
        code    => $class->_export($options),
    };

    on_scope_end {
        namespace::clean->clean_subroutines($target, $name);
    };

    # the use will also need a yield subroutine, but we only install it if
    # there isn't a compatible one already.
    unless ($class->_has_yielder($yname, $target)) {

        install_sub {
            into    => $target,
            as      => $yname,
            code    => sub { yield shift },
        };

        on_scope_end {
            namespace::clean->clean_subroutines($target, $yname);
        };

        $class->_set_yielder($yname, $target);
    }

    return 1;
}

my $YielderFmt = q!%s|%s|YIELD[%s]!;

sub _has_yielder {
    my ($class, $name, $target) = @_;
    return !! $^H{ sprintf $YielderFmt, $class, $target, $name }
}

sub _set_yielder {
    my ($class, $name, $target) = @_;
    $^H{ sprintf $YielderFmt, $class, $target, $name }++;
    return 1;
}

sub _export {
    my ($class, $options) = @_;

    # use can choose to disable implicit return value yielding
    my $should_yield_return = 
        exists($options->{ -yield_return })
        ? $options->{ -yield_return }
        : 1;

    # build exported subroutine that'll pick up the deparsed data
    return sub {
        my ($args, $code, @rest) = @_;

        # this piece of code will initialise and build the generator
        my $maker = sub {

            # create closure over our passed arguments
            my $enclosed = $code->(@_);

            # the actual generator forwards to our closure
            return generator {

                # implicit return value yield has been disabled
                return $enclosed->()
                    unless $should_yield_return;

                # we yield the return value. it's safer this way since
                # there'll be at least one yield per run
                yield $enclosed->();
            };
        };

        my $caller = caller;

        # install the generator into the current package if it has a name
        if (my $name = $args->{generator_name}) {

            # TODO check if name is valid
            install_sub({
                into    => $caller,
                as      => $name,
                code    => $maker,
            });
        }

        # TODO die if context/@rest don't match

        # return the maker code reference and everything else we might've picked up
        return wantarray 
            ? ($maker, @rest) 
            : $maker;
    };
}

sub _transform {
    my ($class, $ctx) = @_;

    # jump over the keyword
    $ctx->skip_declarator;

    # fetch the bareword name and the (...) signature if they are present
    my $name = $ctx->strip_name;
    my $sig  = $ctx->strip_proto;
    # TODO allow foreign package specifications
    # TODO allow prototypes and subroutine attributes

    # make sure empty signatures are really empty
    trim $sig;

    # build runtime arguments
    my %args = ( generator_name => $name );

    # inject the arguments and turn the following block into a code reference
    $class->_inject($ctx, pp(\%args) . ', sub ');

    my @inject;

    # if a signature is present, unwrap @_
    push @inject, qq! my ($sig) = \@_; !
        if $sig;

    # after the sub arguments, we return a closure over them. will pick
    # up again at _finalise_scope at the end of the inner-most sub block
    push @inject, q! sub { ! . $class->_scope_injector_call($ctx, \%args);

    # put all required stuff into the block
    $class->_block_inject($ctx, join('', @inject));

    return 1;
}

sub _scope_injector_call {
    my ($class, $ctx, $args) = @_;

    # call _finalise_scope on current class and pass the arguments
    return sprintf 
        q! BEGIN { %s->_finalise_scope(%s) }; !,
        $class,
        pp($args);
}

sub _finalise_scope {
    my ($class, $args) = @_;

    # auto-append semicolon if generator was named
    my $end = $args->{generator_name}
        ? q!};!
        : q!}!;

    # inject block ending code once current block ended
    on_scope_end {
        my $line   = Devel::Declare::get_linestr;
        my $offset = Devel::Declare::get_linestr_offset;
        substr( $line, $offset, 0 ) = $end;
        Devel::Declare::set_linestr $line;
    };
}

sub _block_inject {
    my ($class, $ctx, $inject) = @_;

    # make sure the block is there
    $class->_check_block($ctx);

    # then inject something after it opened
    $class->_inject($ctx, $inject, 1);

    return 1;
}

sub _inject {
    my ($class, $ctx, $inject, $offset) = @_;

    # defaults to current offset, can be used to jump over things
    $offset ||= 0;

    # get, change, insert and skip
    my $line = $ctx->get_linestr;
    substr( $line, $ctx->offset + $offset, 0 ) = $inject;
    $ctx->set_linestr( $line );
    $ctx->inc_offset(  length $inject );

    return 1;
}

sub _check_block {
    my ($class, $ctx) = @_;

    # fetch next non whitespace char
    $ctx->skipspace;
    my $char = substr $ctx->get_linestr, $ctx->offset, 1;

    # die loudly if it wasn't a starting block
    croak sprintf 
        q(Expected block starting with '{' in generator declaration, not '%s'),
        $char,
      unless $char eq '{';

    return 1;
}

1;

__END__

=method install

This is called by the L<syntax> dispatcher and installs the extension into the
requesting namespace.

=option -as

This option can be used to specify a different keyword name instead of C<gen>.

=option -yield_as

This option can be used to specify a different yield function name instead of
C<yield>.

=option -yield_return

Defaults to true. This option can be disabled to keep the imported generator
from implicitly yielding the return value of the generator. See also
L</Implicit Return Value Yielding>.

=head1 SYNOPSIS

    use syntax 'generator';

    # named generator
    gen range ($start, $end) {
        yield for $start .. $end;
    }

    my $counter = range(1, 10);

    while (my $num = $counter->()) {
        print "$num\n";
    }

    # anonymous generator
    my $count_up_from = gen ($num) {

        # implicit yield for return values
        $num++;
    };

    my $thousend_plus = $count_up_from->(1000);

    $thousend_plus->();     # 1000
    $thousend_plus->();     # 1001
    $thousend_plus->();     # 1002

=head1 DESCRIPTION

This syntax extension implements generators for Perl.

A generator is basically a specialised subroutine. They take parameters, and
return iterator code references. If you're not used to them yet, here is an
example. This code (using L<Syntax::Feature::Function>):

    fun from_to ($n, $m) {
        my $current = 0;
        my @range   = ($n .. $m);

        return fun {

            return undef 
                if $current > $#range;

            return $range[ $current++ ];
        };
    }

can be written like this:

    gen from_to ($n, $m) {

        yield $_ 
            for $n .. $m;

        return undef;
    }

It boils down to a fancy way of writing iterators without manually tracking
state.

=head2 Importing

The generator syntax can be imported into your package by specifying

    use syntax 'generator';

See L</syntax> for a discussion of the syntax extension dispatcher. The default
name for the generator keyword is C<gen> and the default yield function is
C<yield>.

You can override the generator keyword by using the L</-as> option:

    use syntax generator => { -as => 'generator' };

    generator up_to ($n) { yield $_ for 0 .. $n }

You can also use the L</-yield_as> option to import the yield function into a
different symbol:

    use syntax generator => {
        -as         => 'gensub',
        -yield_as   => 'yreturn',
    };

    gensub countdown ($n) { yreturn $n while $n-- }

=head2 Argument Value Scope

A generator can specify a parameter signature to capture lexical values for the
iterator initialisation:

    gen up ($n) { $n++ }

The C<($n)> part will be rewritten to a C<my ($n) = @_> that captures the
arguments before the iterator closure is established. At the moment, the C<@_>
array will not contain the passed parameters, since it is not the iterator that
received the arguments, but the generator. This might change in the future, but
for not it is better to stay clear of C<@_>.

The example above works without explicit yield because the iterator code
reference closed over the C<$n> lexical. Whenever the iterator runs out
(reaches the end of the subroutine) it will implicitly yield the returned value
(unless L</-yield_return> is disabled.

=head2 Named Generators

A generator qualifies as named if it has a name bareword specified directly
after the keyword. The generator will be installed in the current package under
the specified name:

    package MyCounter;
    use Moose;

    use syntax 'generator';

    has start => (is => 'rw');
    has stop  => (is => 'rw');

    gen iterator ($step) {

        $step ||= 1;

        my $current = $self->start;

        while ($current <= $self->stop) {

            yield $current;
            $current += $step;
        }

        return;
    }

    # ...

    my $counter  = MyCounter->new(start => 3, stop => 15);
    my $iterator = $counter->iterator(2);
    
    # 3, 5, 7, 9, 11, 13, 15
    while ($my $n = $iterator->()) { print "$n\n" }

When you give your generator a name you can omit the following semicolon.

=head2 Anonymous Generators

Anonymous generators are generators without a specified name. They are also
treated like expressions rather than statements. This means you'll have to
insert a following semicolon yourself:

    # named
    gen foo { ... }

    # anonymous
    my $foo = gen { ... };

The iterator references that are returned are normal Perl code references. For
now, there is no detectable difference between a generated iterator or a code
reference created with C<sub { ... }>. This is for compatibility reasons.

=head2 Implicit Return Value Yielding

By default L<Coro::Generator> will reenter a subroutine body after it finished.
This means you'll have an endless loop if you fail to hit any explicit yield
points. Since iterators with a false return value as end signifier are more
common in Perl than cyclic lists, this extension will implicitly yield the 
value returned by the generator via implicit or explicit return. The iterator
will start from the beginning after an implicit return value yield has been
performed.

You can disable this protection (or common-usecase-simplification depending on
what side you're on) by specifying the L</-yield_return> option:

    use syntax generator => { -yield_return => 0 };

    gen range ($n, $m) { yield $_ for $n .. $m }

    my $count = range(1, 3);

    # 1, 2, 3, 1, 2, 3, ...
    while (my $i = $count->()) {
        print "$i\n";
    }

Of course, you don't have to settle for the one or the other. You can simply
import the other one under a different keyword:

    use syntax 
        'generator',
        'generator' => { -as => 'genloop' };

    gen A ($n, $m) { 
        yield $_ for $n .. $m;
        undef;
    }

    genloop B ($n, $m) {
        yield $_ for $n .. $m;
        undef;
    }

    # 1, 2, 3, undef, 1, 2, 3, undef, ...
    my $iter_A = A(1, 3);

    # 1, 2, 3, 1, 2, 3, ...
    my $iter_B = B(1, 3);

As you can see, you can use the same yield function for both generator types.

=head1 SEE ALSO

L<syntax>,
L<Coro::Generator>,
L<http://en.wikipedia.org/wiki/Generator_%28computer_science%29>

=cut
