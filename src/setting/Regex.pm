#! nqp

=begin

Regex methods and functions

=end

=begin item match
Match C<$text> against C<$regex>.  If the C<$global> flag is
given, then return an array of all non-overlapping matches.
=end item

our sub match ($text, $regex, :$global?) {
    my $match := $text ~~ $regex;
    if $global {
        my @matches;
        while $match {
            @matches.push($match);
            $match := $match.CURSOR.parse($text, :rule($regex), :c($match.to));
        }
        @matches;
    }
    else {
        $match;
    }
}


=begin item subst
Substitute an match of C<$regex> in C<$text> with C<$replacement>,
returning the substituted string.  If C<$global> is given, then
perform the replacement on all matches of C<$text>.
=end item

our sub subst ($text, $regex, $repl, :$global?) {
    my @matches := $global ?? match($text, $regex, :global)
                           !! [ $text ~~ $regex ];
    my $is_code := pir::isa($repl, 'Sub');
    my $offset  := 0;
    my $result  := pir::new__Ps('StringBuilder');

    for @matches -> $match {
        if $match {
            pir::push($result, pir::substr($text, $offset, $match.from - $offset))
                if $match.from > $offset;
            pir::push($result, $is_code ?? $repl($match) !! $repl);
            $offset := $match.to;
        }
    }

    my $chars := pir::length($text);
    pir::push($result, pir::substr($text, $offset, $chars))
        if $chars > $offset;

    ~$result;
}

=begin item split
Splits C<$text> on occurences of C<$regex>
=end item

our multi sub split (Regex::Regex $regex, $text) {
    my $pos := 0;
    my @result;
    my $looking := 1;
    while $looking {
        my $match :=
            Regex::Cursor.parse($text, :rule($regex), :c($pos)) ;

        if ?$match {
            my $from := $match.from();
            my $to := $match.to();
            my $prefix := pir::substr__sPii($text, $pos, $from-$pos);
            @result.push($prefix);
            $pos := $match.to();
        } else {
            my $len := pir::length($text);
            if $pos < $len {
                @result.push(pir::substr__ssi($text, $pos) );
            }
            $looking := 0;
        }
    }
    return @result;
}

# Use parrot's split for plain strings.
our multi sub split($string, $text) {
    # op split produces RSA. So, convert it to RPA.
    my @res;
    @res.push($_) for pir::split($string, $text);
    @res;
}

# vim: ft=perl6
