#!/usr/bin/perl
use inc::Module::Install;

name            'Module-ScanDeps';
all_from        'lib/Module/ScanDeps.pm';
install_script  'script/scandeps.pl';
sign; WriteAll;
