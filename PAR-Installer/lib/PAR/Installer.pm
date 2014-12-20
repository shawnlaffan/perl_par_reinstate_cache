package PAR::Installer;
use strict;
use 5.006;
use warnings;

our $VERSION = '0.01';
use FindBin;
use File::Spec;
use File::Path ();
use Config '%Config';
use Carp qw/croak carp/;
use YAML::Tiny;
use PAR::Repository::Client;

=head1 NAME

PAR::Installer - Installers for Perl applications

=head1 SYNOPSIS

  # used by the generated installer scripts.

=head1 DESCRIPTION

This is software in an early development stage. It B<should> work,
but the interface may change somewhat and a lot of features are still
missing.

C<PAR::Installer> and its companion modules are a framework for
creating installers for Perl applications. Creating an installer for
a Perl application involves several steps:

=over 2

=item *

Create a PAR repository from your application (script), the modules
you wrote for it and any modules from CPAN it might use. Details
on PAR repositories can be understood by refering to the
L<PAR::Repository> module.

=item *

Prepare the installer's directory structure.For example, run
C<par-installer-generator --directory my_app>

=item *

Write an installer configuration file (in YAML format). You should use
the stub in F<my_app/installer.yml>

(This file specifies the name of the repository, what to install
where, the application title, etc.)

=item *

Generate the installer binary. For example like this:
C<par-installer-generator --directory my_app --generate>

=item *

If you want users to be able to use your installer on different platforms,
repeat the last step on the various platforms. (Make sure to
write to different files or you will overwrite the other installers.
Example: C<par-installer-generator -d my_app -o setup.win32.exe --generate>)

=item *

Burn the installer directory structure and the PAR repository of your
application on a CD and ship that to your customers.

=back

The above procedure covers only the basic steps and can be
customized to your needs.

=head1 METHODS

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto)||$proto;

    my %args = @_;
    my $config = YAML::Tiny->read( $args{config} );
    croak('Could not read configuration file') if not defined $config;
    $config = $config->[0];
    
    my $self = bless {
        config => $config,
        target => $args{target},
    } => $class;
    
    my $target = $self->{target};
    if (not defined $target) {
        croak "No installation target";
    }

    return $self;
}

sub config {
    my $self = shift;
    my $key = shift;
    $self->{config}{$key} = shift if @_;
    return $self->{config}{$key};
}

sub install {
    my $self = shift;
    my $target = $self->{target};

    if (-d $target) {
        croak("Target path '$target' exists. Not overwriting.\n");
    }
    
    unless ( eval {File::Path::mkpath($target)} ) {
        croak("Could not create target path '$target'");
    }

    my $clients = $self->get_repositories();
    my $sub_targets = $self->get_sub_targets;
    foreach my $client (@$clients) {
        $client->installation_targets(%$sub_targets);
    }
    
    $self->install_modules;
    $self->install_scripts;
}

sub install_scripts {
    my $self = shift;
    my $target = $self->{target};

    my $scripts = $self->config('install_scripts');
    my @scripts = @{$scripts};
    my $clients = $self->get_repositories();
    
    
    foreach my $script (@scripts) {
        my $success;
        foreach my $client (@$clients) {
            $success = $client->install_script($script);
            last if $success;
        }
        unless ($success) {
            croak("Failed to install script '$script': It was not found in any source repositories");
        }
    }

    return 1;
}

sub install_modules {
    my $self = shift;
    my $target = $self->{target};

    my $modules = $self->config('install_modules');
    my @modules = @{$modules};
    my $clients = $self->get_repositories();
    
    
    foreach my $module (@modules) {
        my $success;
        foreach my $client (@$clients) {
            $success = $client->install_module($module);
            last if $success;
        }
        unless ($success) {
            croak("Failed to install module '$module': It was not found in any source repositories");
        }
    }

    return 1;
}

sub get_sub_targets {
    my $self = shift;
    if ($self->{sub_targets}) {
        return {%{$self->{sub_targets}}};
    }
    
    my $sub_targets = $self->config('sub_targets');
    $sub_targets = {} if not defined $sub_targets;

    my %default = (
        inst_lib => '$AppDir/lib',
        inst_archlib => '$AppDir/lib',
        inst_script => '$AppDir/bin',
        inst_bin => '$AppDir/bin',
        inst_man1dir => '$AppDir/man1',
        inst_man3dir => '$AppDir/man3',
        packlist_read => '$AppDir/.packlist',
        packlist_write => '$AppDir/.packlist',
    );

    foreach my $key (keys %default) {
        $sub_targets->{$key} = $default{$key}
          if not defined $sub_targets->{$key};
    }

    my $AppDir = $self->{target};
    foreach my $key (keys %$sub_targets) {
        $sub_targets->{$key} = eval '"' . $sub_targets->{$key} . '"';
        die "Error while getting sub-targets from configuration: $@" if $@;
    }
    
    $self->{sub_targets} = $sub_targets;
    return {%{$sub_targets}};
}

sub get_repositories {
    my $self = shift;
    if ( ref($self->{clients}) eq 'ARRAY' ) {
        return [@{$self->{clients}}];
    }

    my $repos = $self->{config}{source_repositories};

    croak("'source_repositories' configuration entry has to be an array")
      if not ref($repos) eq 'ARRAY';

    my @clients;
    foreach my $repo (@$repos) {
        # relative path
        if ($repo !~ /^\w+:\/\//) {
            my @path_elems = File::Spec->splitpath($repo);
            $repo = File::Spec->catdir($FindBin::Bin, @path_elems);
        }
        
        # Create client
        my $client;
        eval {
            $client = PAR::Repository::Client->new(
                uri => $repo,
            );
        };
        if ($@) {
            croak("Could not create repository client for URI '$repo': $@");
        }
        elsif (not defined $client) {
            croak("Could not create repository client for URI '$repo'");
        }

        push @clients, $client;
    }

    $self->{clients} = \@clients;

    return [@clients];
}

1;

__END__

=head1 SEE ALSO

This module is directly related to the C<PAR> project. You need to have
basic familiarity with it.

The installer generator is implemented in L<PAR::Installer::Generator>.

See L<PAR>, L<PAR::Repository>, L<PAR::Repository::Client>,
L<PAR::Dist>, etc.

=head1 AUTHOR

Steffen Müller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Steffen Müller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6 or,
at your option, any later version of Perl 5 you may have available.

=cut

