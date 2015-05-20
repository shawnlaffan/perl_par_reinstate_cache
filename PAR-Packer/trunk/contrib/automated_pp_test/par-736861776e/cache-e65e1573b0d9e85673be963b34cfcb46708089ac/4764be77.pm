#line 1 "C:\shawn\svn\par\trunk\lib/PAR/SetupProgname.pm"
package PAR::SetupProgname;
$PAR::SetupProgname::VERSION = '1.002';

use 5.006;
use strict;
use warnings;
use Config ();

#line 26

# for PAR internal use only!
our $Progname = $ENV{PAR_PROGNAME} || $0;

# same code lives in PAR::Packer's par.pl!
sub set_progname {
    require File::Spec;

    if (defined $ENV{PAR_PROGNAME} and $ENV{PAR_PROGNAME} =~ /(.+)/) {
        $Progname = $1;
    }
    $Progname = $0 if not defined $Progname;

    if (( () = File::Spec->splitdir($Progname) ) > 1 or !$ENV{PAR_PROGNAME}) {
        if (open my $fh, $Progname) {
            return if -s $fh;
        }
        if (-s "$Progname$Config::Config{_exe}") {
            $Progname .= $Config::Config{_exe};
            return;
        }
    }

    foreach my $dir (split /\Q$Config::Config{path_sep}\E/, $ENV{PATH}) {
        next if exists $ENV{PAR_TEMP} and $dir eq $ENV{PAR_TEMP};
        my $name = File::Spec->catfile($dir, "$Progname$Config::Config{_exe}");
        if (-s $name) { $Progname = $name; last }
        $name = File::Spec->catfile($dir, "$Progname");
        if (-s $name) { $Progname = $name; last }
    }
}


1;

__END__

#line 94

