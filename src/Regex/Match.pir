# Copyright (C) 2009, The Perl Foundation.
# $Id$

=head1 NAME

Regex::Match - Regex Match objects

=head1 DESCRIPTION

This file implements Match objects for the regex engine.

=cut

.namespace ['Regex';'Match']

.sub '' :anon :load :init
    load_bytecode 'P6object.pbc'
    .local pmc p6meta
    p6meta = new 'P6metaclass'
    $P0 = p6meta.'new_class'('Regex::Match', 'parent'=>'Capture', 'attr'=>'$!cursor $!target $!from $!to $!ast')
    .return ()
.end

=head2 Methods

=over 4

=item create

Constructs a new Regex::Match object

=cut

.sub 'create' :method
    .param pmc orig        :named( 'orig'       )
    .param pmc cursor      :named( 'cursor'     )
    .param pmc from        :named( 'from'       )
    .param pmc to          :named( 'to'         )
    .param pmc pos_caps    :named( 'pos_caps'   )
    .param pmc named_caps  :named( 'named_caps' )

    .local pmc mob
    .local pmc cap_iter
    .local pmc sub_capture
    .local string cap_key

    .local pmc parrotclass
    $P0 = self.'HOW'()
    parrotclass = getattribute $P0, 'parrotclass'
    mob = new parrotclass


    setattribute mob, '$!target', orig
    setattribute mob, '$!cursor', cursor
    setattribute mob, '$!from',   from
    setattribute mob, '$!to',     to

    cap_iter = iter pos_caps
  pos_iter_loop:
    unless cap_iter goto pos_iter_done
    $P0 = shift cap_iter
    push mob, $P0
    goto pos_iter_loop
  pos_iter_done:

    cap_iter = iter named_caps
  named_iter_loop:
    unless cap_iter goto named_iter_done
    $S0 = shift cap_iter
    $P0 = named_caps[$S0]
    mob[$S0] = $P0
    goto named_iter_loop
  named_iter_done:

    .return(mob)
.end

=item CURSOR()

Returns the Cursor associated with this match object.

=cut

.sub 'CURSOR' :method
    $P0 = getattribute self, '$!cursor'
    .return ($P0)
.end

=item from()

Returns the offset in the target string of the beginning of the match.

=cut

.sub 'from' :method
    $P0 = getattribute self, '$!from'
    .return ($P0)
.end


=item to()

Returns the offset in the target string of the end of the match.

=cut

.sub 'to' :method
    $P0 = getattribute self, '$!to'
    .return ($P0)
.end


=item chars()

Returns C<.to() - .from()>

=cut

.sub 'chars' :method
    $I0 = self.'to'()
    $I1 = self.'from'()
    $I2 = $I0 - $I1
    .return ($I2)
.end


=item orig()

Return the original item that was matched against.

=cut

.sub 'orig' :method
    $P0 = getattribute self, '$!target'
    .return ($P0)
.end


=item Str()

Returns the portion of the target corresponding to this match.

=cut

.sub 'Str' :method
    $S0 = self.'orig'()
    $I0 = self.'from'()
    $I1 = self.'to'()
    $I1 -= $I0
    $S1 = substr $S0, $I0, $I1
    .return ($S1)
.end


=item ast()

Returns the "abstract object" for the Match; if no abstract object
has been set then returns C<Str> above.

=cut

.sub 'ast' :method
    .local pmc ast
    ast = getattribute self, '$!ast'
    unless null ast goto have_ast
    ast = new ['Undef']
    setattribute self, '$!ast', ast
  have_ast:
    .return (ast)
.end

=back

=head2 Vtable functions

=over 4

=item get_bool()

Returns 1 (true) if this is the result of a successful match,
otherwise returns 0 (false).

=cut

.sub '' :vtable('get_bool') :method
    $P0 = getattribute self, '$!from'
    $P1 = getattribute self, '$!to'
    $I0 = isge $P1, $P0
    .return ($I0)
.end


=item get_integer()

Returns the integer value of the matched text.

=cut

.sub '' :vtable('get_integer') :method
    $I0 = self.'Str'()
    .return ($I0)
.end


=item get_number()

Returns the numeric value of this match

=cut

.sub '' :vtable('get_number') :method
    $N0 = self.'Str'()
    .return ($N0)
.end


=item get_string()

Returns the string value of the match

=cut

.sub '' :vtable('get_string') :method
    $S0 = self.'Str'()
    .return ($S0)
.end


=item !make(obj)

Set the "ast object" for the invocant.

=cut

.sub '!make' :method
    .param pmc obj
    setattribute self, '$!ast', obj
    .return (obj)
.end


=back

=head1 AUTHORS

Patrick Michaud <pmichaud@pobox.com> is the author and maintainer.

=cut

# Local Variables:
#   mode: pir
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4 ft=pir:
