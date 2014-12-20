#!/usr/bin/perl -w

# Copyright (c) 2002 Mattia Barbon.
# Copyright (c) 2002 Audrey Tang.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

use strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Basename;
use Getopt::Long;
use PAR::Filter::PodStrip;
use IO::Compress::Gzip qw(gzip $GzipError);

my $chunk_size = 0;
my $strip_pod = 0;
my $compress = 0;
GetOptions(
    "c|chunk=i"         => \$chunk_size,
    "s|strip"           => \$strip_pod,
    "z|compress"        => \$compress)
    && @ARGV == 3
        or die "Usage: $0 [-c][-s][-z] file.pl file.c c_variable\n";
my ($pl_file, $c_file, $c_var) = @ARGV;

my $text = do           # a scalar reference
{
    open my $in, "<", $pl_file or die "open input file '$pl_file': $!";
    binmode $in;
    local $/ = undef;
    my $slurp = <$in>;
    close $in;
    \$slurp;
};

PAR::Filter::PodStrip->new->apply($text) if $strip_pod;

if ($compress)
{
    my $gzipped;
    my $status = gzip($text, \$gzipped)
        or die "gzip failed: $GzipError\n";
    $text = \$gzipped;
}

open my $out, ">", $c_file or die "open output file '$c_file': $!";
binmode $out;

my $name = basename($pl_file);
my $len = length $$text;

print $out <<"...";
#define name_${c_var} "$name"
#define is_compressed_${c_var} $compress
...

if ($chunk_size) 
{
    my $chunk_count = int(( $len + $chunk_size - 1 ) / $chunk_size);

    for (my $i = 0; $i < $chunk_count; $i++) {
	print_chunk( substr($$text, $i * $chunk_size, $chunk_size), "_$i" );
    }

    print $out <<"...";
#define size_${c_var} $len
static my_chunk chunks_${c_var}[] = {
...
    for (my $i = 0; $i < $chunk_count; $i++) {
        print $out " { size_${c_var}_${i}, chunk_${c_var}_${i} },\n";
    }
    print $out " { 0, NULL }\n", "};\n";
}
else
{
    # add a NUL byte so that chunk_${c_var} may be used as C string
    $$text .= "\0";
    print_chunk( $$text, "" );    
}

close $out;

exit 0;


sub print_chunk 
{
    my $chunk = reverse($_[0]);
    my $suffix = $_[1];

    my $len = length($chunk);
    print $out <<"...";
#define size_${c_var}${suffix} $len
static unsigned char chunk_${c_var}${suffix}[] = {
...

    while ($len--) {
        printf $out "0x%02x,", ord(chop($chunk));
        print $out "\n" unless $len % 16;
    }

    print $out "};\n";
}

# local variables:
# mode: cperl
# end:
