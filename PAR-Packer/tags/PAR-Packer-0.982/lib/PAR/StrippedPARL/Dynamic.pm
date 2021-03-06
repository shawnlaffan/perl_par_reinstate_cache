package PAR::StrippedPARL::Dynamic;
use 5.006;
use strict;
use warnings;
our $VERSION = '0.958';

use base 'PAR::StrippedPARL::Base';

our $Data_Pos = tell DATA;

=head1 NAME

PAR::StrippedPARL::Dynamic - Data package containing a dynamic PARL

=head1 SYNOPSIS

  # For details, see PAR::StrippedPARL::Base.
  PAR::StrippedPARL::Dynamic->write_parl($file) or die "Some error...";

=head1 DESCRIPTION

This class is internal to PAR. Do not use it outside of PAR.

This class is basically just a container for a dynamic binary PAR loader
which doesn't include the PAR code like the F<parl> or F<parl.exe>
you are used to. If you're really curious, I'll tell you it is
just a copy of the F<myldr/par> (or F<myldr/par.exe>) file.

The data is appended during the C<make> phase of the PAR build process,
but only if applicable: If you perl is static, you won't get the dynamic
loader.

If the binary data isn't appended during the build process, the class
methods will return the empty list.

=head1 CLASS METHODS

Inherits the methods from L<PAR::StrippedPARL::Base>.

=cut

sub _data_pos {
    my $class = shift;
    return $Data_Pos;
}

=head1 AUTHORS

Steffen Mueller E<lt>smueller@cpan.orgE<gt>,
Audrey Tang E<lt>cpan@audreyt.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Steffen Mueller E<lt>smueller@cpan.orgE<gt>.

This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

__DATA__

