#line 1 "C:\shawn\svn\par\PAR-Packer\trunk\blib\lib/PAR/Filter/PodStrip.pm"
package PAR::Filter::PodStrip;
use 5.006;
use strict;
use warnings;
use base 'PAR::Filter';

#line 22

sub apply {
    my ($class, $ref, $filename, $name) = @_;

    no warnings 'uninitialized';

    my $data = '';
    $data = $1 if $$ref =~ s/((?:^__DATA__\r?\n).*)//ms;

    my $line = 1;
    if ($$ref =~ /^=(?:head\d|pod|begin|item|over|for|back|end|cut)\b/) {
        $$ref = "\n$$ref";
        $line--;
    }
    $$ref =~ s{(
	(.*?\n)
	(?:=(?:head\d|pod|begin|item|over|for|back|end)\b
    .*?\n)
	(?:=cut[\t ]*[\r\n]*?|\Z)
	(\r?\n)?
    )}{
	my ($pre, $post) = ($2, $3);
        "$pre#line " . (
	    $line += ( () = ( $1 =~ /\n/g ) )
	) . $post;
    }gsex;

    $$ref =~ s{^=encoding\s+\S+\s*$}{\n}mg;

    $$ref = '#line 1 "' . ($filename) . "\"\n" . $$ref
        if length $filename;
    $$ref =~ s/^#line 1 (.*\n)(#!.*\n)/$2#line 2 $1/g;
    $$ref .= $data;
}

1;

#line 85
