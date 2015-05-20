#line 1 "C:\shawn\svn\par\PAR-Packer\trunk\blib\lib/PAR/Filter.pm"
package PAR::Filter;
use 5.006;
use strict;
use warnings;
our $VERSION = '0.03';

#line 64

sub new {
    my $class = shift;
    require "PAR/Filter/$_.pm" foreach @_;
    bless(\@_, $class);
}

sub apply {
    my ($self, $ref, $name) = @_;
    my $filename = $name || '-e';

    if (!ref $ref) {
	$name ||= $filename = $ref;
	local $/;
	open my $fh, $ref or die $!;
	binmode($fh);
	my $content = <$fh>;
	$ref = \$content;
	return $ref unless length($content);
    }

    "PAR::Filter::$_"->new->apply( $ref, $filename, $name ) foreach @$self;

    return $ref;
}

1;

#line 106
