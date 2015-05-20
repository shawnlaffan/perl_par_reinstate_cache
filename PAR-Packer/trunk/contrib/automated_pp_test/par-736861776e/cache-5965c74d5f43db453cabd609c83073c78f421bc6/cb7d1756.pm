#line 1 "C:/strawberry_51613_x64/perl/lib/integer.pm"
package integer;

our $VERSION = '1.00';

#line 82

$integer::hint_bits = 0x1;

sub import {
    $^H |= $integer::hint_bits;
}

sub unimport {
    $^H &= ~$integer::hint_bits;
}

1;
