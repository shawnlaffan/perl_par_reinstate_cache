#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 5;
use Module::ScanDeps qw/scan_chunk/;

{
my $chunk=<<'EOT';
use strict;
EOT
my @array=sort (scan_chunk($chunk));
is_deeply(\@array,[sort qw{strict.pm}]);
}

{
my $chunk=<<'EOT';
use base qw(strict);
EOT
my @array=sort (scan_chunk($chunk));
is_deeply(\@array,[sort qw{base.pm strict.pm}]);
}

{
my $chunk=<<'EOT';
use parent qw(strict);
EOT
my @array=sort (scan_chunk($chunk));
is_deeply(\@array,[sort qw{parent.pm strict.pm}]);
}

{
my $chunk=<<'EOT';
use parent::doesnotexists qw(strict);
EOT
my @array=sort (scan_chunk($chunk));
is_deeply(\@array,[sort qw{parent/doesnotexists.pm}]);
}

{
my $chunk=<<'EOT';
use Catalyst qw/-Debug ConfigLoader Session::State::Cookie/
EOT
#-Debug should be skipped
my @array=sort (scan_chunk($chunk));
is_deeply(\@array,[sort qw{Catalyst.pm Catalyst/Plugin/ConfigLoader.pm Catalyst/Plugin/Session/State/Cookie.pm}]);
}


