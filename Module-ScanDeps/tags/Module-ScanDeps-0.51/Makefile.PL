#!/usr/bin/perl

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME		=> 'Module::ScanDeps',
    ABSTRACT		=> 'Recursively scan Perl programs for dependencies',
    AUTHOR		=> 'Autrijus Tang <autrijus@autrijus.org>',
    VERSION_FROM	=> 'lib/Module/ScanDeps.pm',
    EXE_FILES		=> [ 'script/scandeps.pl' ],
);

__END__

use inc::Module::Install;

name		('Module-ScanDeps');
author		('Autrijus Tang <autrijus@autrijus.org>');
abstract	('Recursively scan Perl programs for dependencies');
version_from	('lib/Module/ScanDeps.pm');
install_script	('script/scandeps.pl');
license		('perl');
sign		(1);

&WriteAll;
