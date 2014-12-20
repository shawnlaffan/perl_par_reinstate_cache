package PAR::Installer::Generator;
use strict;
use 5.006;
use warnings;

our $VERSION = '0.01';
use Carp qw/croak carp/;
use File::Spec;
use File::Path ();
use YAML::Tiny;
#use FindBin;
#use PAR::Repository::Client;

=head1 NAME

PAR::Installer::Generator - Application installer generator

=head1 SYNOPSIS

  use PAR::Installer::Generator;
  my $gen = PAR::Installer::Generator->new(
    directory => './my_installer', # opens existing or creates from scratch
  );
  
  # Override default values of some parameters
  $gen->set_parameters(
    title => 'My App',
    install_modules => [ qw/ Tk App::MyApp  / ],
    install_scripts => [ qw/ my_application / ],
  );
  
  # Optionally inspect the set of parameters for the installer
  #my $hash_ref = $gen->get_parameters(); # returns internal hash!
  #my $string = $gen->parameters_as_yaml();
  
  # Optionally inspect the installer code
  #my $code = $gen->get_installer_script();
  # Optionally set a different installer script. (Beware!)
  #$gen->set_installer_script();
  
  # write custom parameters to disk
  $gen->write_parameters();
  
  # Write the installer script
  $gen->write_installer_script();

  # create binary
  $gen->generate_installer_binary();
  # or:
  $gen->generate_installer_binary(
    file => 'setup-win32.exe',
    pp_options => [qw/--verbose/], # verbose pp output
  );

=head1 DESCRIPTION

This class implements an installer generator. That means you can use
it to generate a configuration file and installer binary which can be used
to install an application. The application should be stored as one or more
packages in a so-called PAR Repository which will be accessed by
the installer.

The repository can reside in the same directory as the installer files
or it can be accessed via HTTP(S) over the network. It can contain
modules (local and CPAN modules alike) and scripts. PAR Repositories can also
contain cross-platform as well as platform specific packages so you can
package your application for several platforms on the same distribution
medium.

=head1 CONSTRUCTOR

=head2 new

Creates a new PAR::Installer::Generator object. Takes key/value pairs as
parameters. Required parameters:

C<directory>, the directory in which the installer will (or does) reside.

Upon creating the generator object, the directory will be created if it
doesn't exist and all default files (Configuration: F<installer.yml>,
Installer script: F<setup.pl>)
will be created. If it exists and the files do, too, the files
will be read.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto)||$proto;

    my %args = @_;

    my $dir = $args{directory};
    if (not defined $dir) {
        croak("new() needs a 'directory' parameter.");
    }
    elsif (-f $dir) {
        croak("The 'directory' parameter ('$dir') points at a file!");
    }
    elsif (not -d $dir and -e $dir) {
        croak("The 'directory' parameter ('$dir') exists but is not a directory.");
    }
        
    my $self = {
        setup_pl => undef,       # filled later
        parameters => undef,     # ...
        dir => $dir,
    };
    bless $self => $class;
    $self->_prepare_directory();

    return $self;
}



sub _prepare_directory {
    my $self = shift;
    my $dir = $self->{dir};

    # make sure dir exists
    if (not -d $dir) {
        File::Path::mkpath($dir)
          or croak("Could not create directory '$dir': $!");
    }
    
    my $instconf = File::Spec->catfile($dir, 'installer.yml');
    my $setuppl  = File::Spec->catfile($dir, 'setup.pl');
    
    # make sure installer.yml exists
    if (not -f $instconf) {
        open my $fh, '>', $instconf
          or die "Could not open file '$instconf' for writing: $!";
        print $fh $self->default_installer_yml();
        close $fh or die "Problem writing file '$instconf': $!";
    }
    
    $self->{parameters} = YAML::Tiny->read($instconf);
    
    # make sure setup.pl exists
    if (not -f $setuppl) {
        open my $fh, '>', $setuppl
          or die "Could not open file '$setuppl' for writing: $!";
        print $fh $self->default_setup_pl();
        close $fh or die "Problem writing file '$setuppl': $!";
    }
    
    open my $fh, '<', $setuppl
      or die "Could not open file '$setuppl' for reading: $!";
    $self->{setup_pl} = join '', <$fh>;
    close $fh;
    
    return 1;
}


=head1 INSTALLER CONFIGURATION METHODS

=head2 set_parameters

Used to set installer parameters in the F<installer.yml> file. Takes
key/value pairs which are inserted into the internal parameters hash.
This will be written out to the F<installer.yml> file by the
C<write_parameters()> method.

This sets the internal state but doesn't directly write to the disk.
See I<FILE OUTPUT METHODS>.

Returns the object for convenience.

=cut

sub set_parameters {
    my $self = shift;
    croak("Uneven number of arguments to 'set_parameters'")
      if @_ % 2;
    
    my %args = @_;
    my $hash = $self->{parameters}[0];

    $hash->{$_} = $args{$_} foreach keys %args;

    return $self;
}

=head2 get_parameters

Returns the internal (hash) representation of the F<installer.yml>
parameters as a hash reference. This is the actual internal data structure,
uncopied, so beware of unwanted action-at-a-distance.

=cut

sub get_parameters {
    my $self = shift;
    return $self->{parameters}[0];
}

=head2 parameters_as_yaml

This method dumps the internal representation of F<installer.yml>
as a YAML string and returns that string.

=cut

sub parameters_as_yaml {
    my $self = shift;
    return $self->{parameters}->write_string();
}


=head1 SETUP SCRIPT METHODS

=head2 get_installer_script

Returns the current implementation of the installer script.

=cut

sub get_installer_script {
    my $self = shift;
    return $self->{setup_pl};
}

=head2 set_installer_script

Sets a new implementation of the installer script. Use this only
if you really know what you're doing.

This sets the internal state but doesn't directly write to the disk.
See I<FILE OUTPUT METHODS>.

=cut

sub set_installer_script {
    my $self = shift;
    my $script = shift;
    croak('Cannot set installer script to an undefined value');
    $self->{setup_pl} = $script;
    return $self;
}


=head1 FILE OUTPUT METHODS

These actually write to the disk.

=head2 write_parameters

Writes the installer configuration as YAML to the F<installer.yml> file
in the specified installer directory.

Returns the object for convenience.

=cut

sub write_parameters {
    my $self = shift;
    $self->{parameters}->write(
        File::Spec->catfile($self->{dir}, 'installer.yml')
    );
    return $self;
}

=head2 write_installer_script

Writes the installer script to the C<setup.pl> file
in the specified installer directory.

Returns the object for convenience.

=cut

sub write_installer_script {
    my $self = shift;
    my $file = File::Spec->catfile($self->{dir}, 'setup.pl');
    open my $fh, '>', $file
      or die "Could not open installer script file '$file' for writing: $!";
    print $fh $self->{setup_pl};
    close $fh;
    return $self;
}

=head2 write_all

Calls both C<write_parameters> and C<write_installer_script> to
write the complete installer state to disk.

Returns the object for convenience.

=cut

sub write_all {
    my $self = shift;
    return $self->write_parameters()->write_installer_script();
}

=head2 generate_installer_binary

Generates the installer binary from the installer script F<setup.pl>
using the C<pp> utility that comes with the L<PAR> module.
The generated binary will be runnable on the platform it
was generated on (such as i386 win32, etc.) without an installed
copy of perl.

Takes a couple of optional named arguments: C<file> sets the name of the
output file relative to the specified installer directory.
C<pp_options> should be a reference to an array of additional
parameters to the system call to pp. See below for details on the pp call.

You should not use the C<-o> (output file name) option of pp nor any of the
options that change the output type (like C<-p> causing output of a
.par file or C<-P> causing output of a Perl script.). The C<-C> or C<--clean>
option is always set since the installer should not leave any traces of
itself on the system.

=cut


sub generate_installer_binary {
    my $self = shift;

    my $default_filename = $^O =~ /win32/i ? 'setup.exe' : 'setup.bin';
    my %args = (
        file => $default_filename,
        pp_options => [],
        @_
    );

    my @pp_call = (
        'pp',
        @{$args{pp_options}},
        '-C', # leave no traces
        '-o' => File::Spec->catfile($self->{dir}, $args{file}),
        File::Spec->catfile($self->{dir}, 'setup.pl'),
    );
    
    print "Running pp...\n";
    
    system(
        @pp_call
    ) and die $!;
    
    print "Control returned from pp.\n";

    return 1;
}


=head1 MISCELLANEOUS METHODS


=head2 default_setup_pl

Returns the default contents of a F<setup.pl>.

=cut

sub default_setup_pl {
    return <<'DEFAULT_SETUP_PL';
#!/usr/bin/perl
use strict;
use warnings;

use FindBin;
use File::Spec;

#use PAR { repository => File::Spec->catdir($FindBin::Bin, 'installer') };

use PAR::Dist;
use PAR::Installer;

my $Usage = <<HERE;
Usage: $0 Install-Path
HERE

my $path = $ARGV[0];
if (not defined $path) {
    print $Usage;
    exit(1);
}

my $installer = PAR::Installer->new(
    config => File::Spec->catfile($FindBin::Bin, 'installer.yml'),
    target => $path,
);

$installer->install();
DEFAULT_SETUP_PL
}

=head2 default_installer_yml

Returns the default contents of a F<installer.yml>.

=cut

sub default_installer_yml {
    return <<'YAML';
---
title: My Application
install_modules:
  - App::MyApp
install_scripts:
  - my_application
source_repositories:
  - myapp
sub_targets:
  inst_lib: $AppDir/lib
  inst_archlib: $AppDir/lib
  inst_script: $AppDir/bin
  inst_bin: $AppDir/bin
  inst_man1dir: $AppDir/man1
  inst_man3dir: $AppDir/man3
  packlist_read: $AppDir/.packlist
  packlist_write: $AppDir/.packlist
YAML
}





1;

__END__

=head1 SEE ALSO

This module is directly related to the C<PAR> project. You need to have
basic familiarity with it.

See L<PAR::Installer>, L<PAR>, L<PAR::Repository>, L<PAR::Repository::Client>,
L<PAR::Dist>, etc.

=head1 AUTHOR

Steffen Müller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Steffen Müller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6 or,
at your option, any later version of Perl 5 you may have available.

=cut

