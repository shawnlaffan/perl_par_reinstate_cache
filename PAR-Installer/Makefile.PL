use 5.008007;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'PAR::Installer',
    VERSION_FROM      => 'lib/PAR/Installer.pm', # finds $VERSION
    PREREQ_PM         => {
        PAR::Dist => '0.20',
        PAR => '0.956',
        PAR::Repository::Client => '0.13',
        YAML::Tiny => '0',
        FindBin => '0',
        File::Spec => '0',
        File::Path => '0',
        Config => '0',
        PAR::Repository => '0.12',
        Getopt::Long => '0',
    }, # e.g., Module::Name => 1.1
    EXE_FILES => [
        'bin/par-installer-generator',
    ],
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/PAR/Installer.pm', # retrieve abstract from module
       AUTHOR         => 'Steffen Müller <smueller@cpan.org>') : ()),
);
