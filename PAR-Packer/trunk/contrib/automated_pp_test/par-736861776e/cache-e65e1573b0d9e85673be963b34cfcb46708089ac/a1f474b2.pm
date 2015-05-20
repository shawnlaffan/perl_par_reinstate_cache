#line 1 "c:/strawberry_51613_x64/perl/lib/File/Spec/Unix.pm"
package File::Spec::Unix;

use strict;
use vars qw($VERSION);

$VERSION = '3.40';
$VERSION =~ tr/_//;

#line 42

sub canonpath {
    my ($self,$path) = @_;
    return unless defined $path;
    
    # Handle POSIX-style node names beginning with double slash (qnx, nto)
    # (POSIX says: "a pathname that begins with two successive slashes
    # may be interpreted in an implementation-defined manner, although
    # more than two leading slashes shall be treated as a single slash.")
    my $node = '';
    my $double_slashes_special = $^O eq 'qnx' || $^O eq 'nto';


    if ( $double_slashes_special
         && ( $path =~ s{^(//[^/]+)/?\z}{}s || $path =~ s{^(//[^/]+)/}{/}s ) ) {
      $node = $1;
    }
    # This used to be
    # $path =~ s|/+|/|g unless ($^O eq 'cygwin');
    # but that made tests 29, 30, 35, 46, and 213 (as of #13272) to fail
    # (Mainly because trailing "" directories didn't get stripped).
    # Why would cygwin avoid collapsing multiple slashes into one? --jhi
    $path =~ s|/{2,}|/|g;                            # xx////xx  -> xx/xx
    $path =~ s{(?:/\.)+(?:/|\z)}{/}g;                # xx/././xx -> xx/xx
    $path =~ s|^(?:\./)+||s unless $path eq "./";    # ./xx      -> xx
    $path =~ s|^/(?:\.\./)+|/|;                      # /../../xx -> xx
    $path =~ s|^/\.\.$|/|;                         # /..       -> /
    $path =~ s|/\z|| unless $path eq "/";          # xx/       -> xx
    return "$node$path";
}

#line 82

sub catdir {
    my $self = shift;

    $self->canonpath(join('/', @_, '')); # '' because need a trailing '/'
}

#line 95

sub catfile {
    my $self = shift;
    my $file = $self->canonpath(pop @_);
    return $file unless @_;
    my $dir = $self->catdir(@_);
    $dir .= "/" unless substr($dir,-1) eq "/";
    return $dir.$file;
}

#line 110

sub curdir { '.' }

#line 118

sub devnull { '/dev/null' }

#line 126

sub rootdir { '/' }

#line 142

my $tmpdir;
sub _tmpdir {
    return $tmpdir if defined $tmpdir;
    my $self = shift;
    my @dirlist = @_;
    {
	no strict 'refs';
	if (${"\cTAINT"}) { # Check for taint mode on perl >= 5.8.0
            require Scalar::Util;
	    @dirlist = grep { ! Scalar::Util::tainted($_) } @dirlist;
	}
	elsif ($] < 5.007) { # No ${^TAINT} before 5.8
	    @dirlist = grep { eval { eval('1'.substr $_,0,0) } } @dirlist;
	}
    }
    foreach (@dirlist) {
	next unless defined && -d && -w _;
	$tmpdir = $_;
	last;
    }
    $tmpdir = $self->curdir unless defined $tmpdir;
    $tmpdir = defined $tmpdir && $self->canonpath($tmpdir);
    return $tmpdir;
}

sub tmpdir {
    return $tmpdir if defined $tmpdir;
    $tmpdir = $_[0]->_tmpdir( $ENV{TMPDIR}, "/tmp" );
}

#line 178

sub updir { '..' }

#line 187

sub no_upwards {
    my $self = shift;
    return grep(!/^\.{1,2}\z/s, @_);
}

#line 199

sub case_tolerant { 0 }

#line 211

sub file_name_is_absolute {
    my ($self,$file) = @_;
    return scalar($file =~ m:^/:s);
}

#line 222

sub path {
    return () unless exists $ENV{PATH};
    my @path = split(':', $ENV{PATH});
    foreach (@path) { $_ = '.' if $_ eq '' }
    return @path;
}

#line 235

sub join {
    my $self = shift;
    return $self->catfile(@_);
}

#line 261

sub splitpath {
    my ($self,$path, $nofile) = @_;

    my ($volume,$directory,$file) = ('','','');

    if ( $nofile ) {
        $directory = $path;
    }
    else {
        $path =~ m|^ ( (?: .* / (?: \.\.?\z )? )? ) ([^/]*) |xs;
        $directory = $1;
        $file      = $2;
    }

    return ($volume,$directory,$file);
}


#line 303

sub splitdir {
    return split m|/|, $_[1], -1;  # Preserve trailing fields
}


#line 317

sub catpath {
    my ($self,$volume,$directory,$file) = @_;

    if ( $directory ne ''                && 
         $file ne ''                     && 
         substr( $directory, -1 ) ne '/' && 
         substr( $file, 0, 1 ) ne '/' 
    ) {
        $directory .= "/$file" ;
    }
    else {
        $directory .= $file ;
    }

    return $directory ;
}

#line 364

sub abs2rel {
    my($self,$path,$base) = @_;
    $base = $self->_cwd() unless defined $base and length $base;

    ($path, $base) = map $self->canonpath($_), $path, $base;

    my $path_directories;
    my $base_directories;

    if (grep $self->file_name_is_absolute($_), $path, $base) {
	($path, $base) = map $self->rel2abs($_), $path, $base;

    my ($path_volume) = $self->splitpath($path, 1);
    my ($base_volume) = $self->splitpath($base, 1);

    # Can't relativize across volumes
    return $path unless $path_volume eq $base_volume;

	$path_directories = ($self->splitpath($path, 1))[1];
	$base_directories = ($self->splitpath($base, 1))[1];

    # For UNC paths, the user might give a volume like //foo/bar that
    # strictly speaking has no directory portion.  Treat it as if it
    # had the root directory for that volume.
    if (!length($base_directories) and $self->file_name_is_absolute($base)) {
      $base_directories = $self->rootdir;
    }
    }
    else {
	my $wd= ($self->splitpath($self->_cwd(), 1))[1];
	$path_directories = $self->catdir($wd, $path);
	$base_directories = $self->catdir($wd, $base);
    }

    # Now, remove all leading components that are the same
    my @pathchunks = $self->splitdir( $path_directories );
    my @basechunks = $self->splitdir( $base_directories );

    if ($base_directories eq $self->rootdir) {
      return $self->curdir if $path_directories eq $self->rootdir;
      shift @pathchunks;
      return $self->canonpath( $self->catpath('', $self->catdir( @pathchunks ), '') );
    }

    my @common;
    while (@pathchunks && @basechunks && $self->_same($pathchunks[0], $basechunks[0])) {
        push @common, shift @pathchunks ;
        shift @basechunks ;
    }
    return $self->curdir unless @pathchunks || @basechunks;

    # @basechunks now contains the directories the resulting relative path 
    # must ascend out of before it can descend to $path_directory.  If there
    # are updir components, we must descend into the corresponding directories
    # (this only works if they are no symlinks).
    my @reverse_base;
    while( defined(my $dir= shift @basechunks) ) {
	if( $dir ne $self->updir ) {
	    unshift @reverse_base, $self->updir;
	    push @common, $dir;
	}
	elsif( @common ) {
	    if( @reverse_base && $reverse_base[0] eq $self->updir ) {
		shift @reverse_base;
		pop @common;
	    }
	    else {
		unshift @reverse_base, pop @common;
	    }
	}
    }
    my $result_dirs = $self->catdir( @reverse_base, @pathchunks );
    return $self->canonpath( $self->catpath('', $result_dirs, '') );
}

sub _same {
  $_[1] eq $_[2];
}

#line 469

sub rel2abs {
    my ($self,$path,$base ) = @_;

    # Clean up $path
    if ( ! $self->file_name_is_absolute( $path ) ) {
        # Figure out the effective $base and clean it up.
        if ( !defined( $base ) || $base eq '' ) {
	    $base = $self->_cwd();
        }
        elsif ( ! $self->file_name_is_absolute( $base ) ) {
            $base = $self->rel2abs( $base ) ;
        }
        else {
            $base = $self->canonpath( $base ) ;
        }

        # Glom them together
        $path = $self->catdir( $base, $path ) ;
    }

    return $self->canonpath( $path ) ;
}

#line 509

# Internal routine to File::Spec, no point in making this public since
# it is the standard Cwd interface.  Most of the platform-specific
# File::Spec subclasses use this.
sub _cwd {
    require Cwd;
    Cwd::getcwd();
}


# Internal method to reduce xx\..\yy -> yy
sub _collapse {
    my($fs, $path) = @_;

    my $updir  = $fs->updir;
    my $curdir = $fs->curdir;

    my($vol, $dirs, $file) = $fs->splitpath($path);
    my @dirs = $fs->splitdir($dirs);
    pop @dirs if @dirs && $dirs[-1] eq '';

    my @collapsed;
    foreach my $dir (@dirs) {
        if( $dir eq $updir              and   # if we have an updir
            @collapsed                  and   # and something to collapse
            length $collapsed[-1]       and   # and its not the rootdir
            $collapsed[-1] ne $updir    and   # nor another updir
            $collapsed[-1] ne $curdir         # nor the curdir
          ) 
        {                                     # then
            pop @collapsed;                   # collapse
        }
        else {                                # else
            push @collapsed, $dir;            # just hang onto it
        }
    }

    return $fs->catpath($vol,
                        $fs->catdir(@collapsed),
                        $file
                       );
}


1;
