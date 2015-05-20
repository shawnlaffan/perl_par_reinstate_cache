#line 1 "c:/strawberry_51613_x64/perl/vendor/lib/PAR/Dist.pm"
package PAR::Dist;
use 5.006;
use strict;
require Exporter;
use vars qw/$VERSION @ISA @EXPORT @EXPORT_OK $DEBUG/;

$VERSION    = '0.49'; # Change version in POD, too!
@ISA        = 'Exporter';
@EXPORT     = qw/
  blib_to_par
  install_par
  uninstall_par
  sign_par
  verify_par
  merge_par
  remove_man
  get_meta
  generate_blib_stub
/;

@EXPORT_OK = qw/
  parse_dist_name
  contains_binaries
/;

$DEBUG = 0;

use Carp qw/carp croak/;
use File::Spec;

#line 142

sub blib_to_par {
    @_ = (path => @_) if @_ == 1;

    my %args = @_;
    require Config;


    # don't use 'my $foo ... if ...' it creates a static variable!
    my $quiet = $args{quiet} || 0;
    my $dist;
    my $path    = $args{path};
    $dist       = File::Spec->rel2abs($args{dist}) if $args{dist};
    my $name    = $args{name};
    my $version = $args{version};
    my $suffix  = $args{suffix} || "$Config::Config{archname}-$Config::Config{version}.par";
    my $cwd;

    if (defined $path) {
        require Cwd;
        $cwd = Cwd::cwd();
        chdir $path;
    }

    _build_blib() unless -d "blib";

    my @files;
    open MANIFEST, ">", File::Spec->catfile("blib", "MANIFEST") or die $!;
    open META, ">", File::Spec->catfile("blib", "META.yml") or die $!;
    
    require File::Find;
    File::Find::find( sub {
        next unless $File::Find::name;
        (-r && !-d) and push ( @files, substr($File::Find::name, 5) );
    } , 'blib' );

    print MANIFEST join(
        "\n",
        '    <!-- accessible as jar:file:///NAME.par!/MANIFEST in compliant browsers -->',
        (sort @files),
        q(    # <html><body onload="var X=document.body.innerHTML.split(/\n/);var Y='<iframe src=&quot;META.yml&quot; style=&quot;float:right;height:40%;width:40%&quot;></iframe><ul>';for(var x in X){if(!X[x].match(/^\s*#/)&&X[x].length)Y+='<li><a href=&quot;'+X[x]+'&quot;>'+X[x]+'</a>'}document.body.innerHTML=Y">)
    );
    close MANIFEST;

    # if MYMETA.yml exists, that takes precedence over META.yml
    my $meta_file_name = "META.yml";
    my $mymeta_file_name = "MYMETA.yml";
    $meta_file_name = -s $mymeta_file_name ? $mymeta_file_name : $meta_file_name;
    if (open(OLD_META, $meta_file_name)) {
        while (<OLD_META>) {
            if (/^distribution_type:/) {
                print META "distribution_type: par\n";
            }
            else {
                print META $_;
            }

            if (/^name:\s+(.*)/) {
                $name ||= $1;
                $name =~ s/::/-/g;
            }
            elsif (/^version:\s+.*Module::Build::Version/) {
                while (<OLD_META>) {
                    /^\s+original:\s+(.*)/ or next;
                    $version ||= $1;
                    last;
                }
            }
            elsif (/^version:\s+(.*)/) {
                $version ||= $1;
            }
        }
        close OLD_META;
        close META;
    }
    
    if ((!$name or !$version) and open(MAKEFILE, "Makefile")) {
        while (<MAKEFILE>) {
            if (/^DISTNAME\s+=\s+(.*)$/) {
                $name ||= $1;
            }
            elsif (/^VERSION\s+=\s+(.*)$/) {
                $version ||= $1;
            }
        }
    }

    if (not defined($name) or not defined($version)) {
        # could not determine name or version. Error.
        my $what;
        if (not defined $name) {
            $what = 'name';
            $what .= ' and version' if not defined $version;
        }
        elsif (not defined $version) {
            $what = 'version';
        }
        
        carp("I was unable to determine the $what of the PAR distribution. Please create a Makefile or META.yml file from which we can infer the information or just specify the missing information as an option to blib_to_par.");
        return();
    }
    
    $name =~ s/\s+$//;
    $version =~ s/\s+$//;

    my $file = "$name-$version-$suffix";
    unlink $file if -f $file;

    print META << "YAML" if fileno(META);
name: $name
version: $version
build_requires: {}
conflicts: {}
dist_name: $file
distribution_type: par
dynamic_config: 0
generated_by: 'PAR::Dist version $PAR::Dist::VERSION'
license: unknown
YAML
    close META;

    mkdir('blib', 0777);
    chdir('blib');
    require Cwd;
    my $zipoutfile = File::Spec->catfile(File::Spec->updir, $file);
    _zip(dist => $zipoutfile);
    chdir(File::Spec->updir);

    unlink File::Spec->catfile("blib", "MANIFEST");
    unlink File::Spec->catfile("blib", "META.yml");

    $dist ||= File::Spec->catfile($cwd, $file) if $cwd;

    if ($dist and $file ne $dist) {
        if ( File::Copy::copy($file, $dist) ) {
          unlink $file;
        } else {
          die "Cannot copy $file: $!";
        }

        $file = $dist;
    }

    my $pathname = File::Spec->rel2abs($file);
    if ($^O eq 'MSWin32') {
        $pathname =~ s!\\!/!g;
        $pathname =~ s!:!|!g;
    };
    print << "." if !$quiet;
Successfully created binary distribution '$file'.
Its contents are accessible in compliant browsers as:
    jar:file://$pathname!/MANIFEST
.

    chdir $cwd if $cwd;
    return $file;
}

sub _build_blib {
    if (-e 'Build') {
        _system_wrapper($^X, "Build");
    }
    elsif (-e 'Makefile') {
        _system_wrapper($Config::Config{make});
    }
    elsif (-e 'Build.PL') {
        _system_wrapper($^X, "Build.PL");
        _system_wrapper($^X, "Build");
    }
    elsif (-e 'Makefile.PL') {
        _system_wrapper($^X, "Makefile.PL");
        _system_wrapper($Config::Config{make});
    }
}

#line 401

sub install_par {
    my %args = &_args;
    _install_or_uninstall(%args, action => 'install');
}

#line 422

sub uninstall_par {
    my %args = &_args;
    _install_or_uninstall(%args, action => 'uninstall');
}

sub _install_or_uninstall {
    my %args = &_args;
    my $name = $args{name};
    my $action = $args{action};

    my %ENV_copy = %ENV;
    $ENV{PERL_INSTALL_ROOT} = $args{prefix} if defined $args{prefix};

    require Cwd;
    my $old_dir = Cwd::cwd();
    
    my ($dist, $tmpdir) = _unzip_to_tmpdir( dist => $args{dist}, subdir => 'blib' );

    if ( open (META, File::Spec->catfile('blib', 'META.yml')) ) {
        while (<META>) {
            next unless /^name:\s+(.*)/;
            $name = $1;
            $name =~ s/\s+$//;
            last;
        }
        close META;
    }
    return if not defined $name or $name eq '';

    if (-d 'script') {
        require ExtUtils::MY;
        foreach my $file (glob("script/*")) {
            next unless -T $file;
            ExtUtils::MY->fixin($file);
            chmod(0555, $file);
        }
    }

    $name =~ s{::|-}{/}g;
    require ExtUtils::Install;

    if ($action eq 'install') {
        my $target = _installation_target( File::Spec->curdir, $name, \%args );
        my $custom_targets = $args{custom_targets} || {};
        $target->{$_} = $custom_targets->{$_} foreach keys %{$custom_targets};
        
        my $uninstall_shadows = $args{uninstall_shadows};
        my $verbose = $args{verbose};
        ExtUtils::Install::install($target, $verbose, 0, $uninstall_shadows);
    }
    elsif ($action eq 'uninstall') {
        require Config;
        my $verbose = $args{verbose};
        ExtUtils::Install::uninstall(
            $args{packlist_read}||"$Config::Config{installsitearch}/auto/$name/.packlist",
            $verbose
        );
    }

    %ENV = %ENV_copy;

    chdir($old_dir);
    File::Path::rmtree([$tmpdir]);

    return 1;
}

# Returns the default installation target as used by
# ExtUtils::Install::install(). First parameter should be the base
# directory containing the blib/ we're installing from.
# Second parameter should be the name of the distribution for the packlist
# paths. Third parameter may be a hash reference with user defined keys for
# the target hash. In fact, any contents that do not start with 'inst_' are
# skipped.
sub _installation_target {
    require Config;
    my $dir = shift;
    my $name = shift;
    my $user = shift || {};

    # accepted sources (and user overrides)
    my %sources = (
      inst_lib => File::Spec->catdir($dir,"blib","lib"),
      inst_archlib => File::Spec->catdir($dir,"blib","arch"),
      inst_bin => File::Spec->catdir($dir,'blib','bin'),
      inst_script => File::Spec->catdir($dir,'blib','script'),
      inst_man1dir => File::Spec->catdir($dir,'blib','man1'),
      inst_man3dir => File::Spec->catdir($dir,'blib','man3'),
      packlist_read => 'read',
      packlist_write => 'write',
    );


    my $par_has_archlib = _directory_not_empty( $sources{inst_archlib} );

    # default targets
    my $target = {
       read => $Config::Config{sitearchexp}."/auto/$name/.packlist",
       write => $Config::Config{installsitearch}."/auto/$name/.packlist",
       $sources{inst_lib} =>
            ($par_has_archlib
             ? $Config::Config{installsitearch}
             : $Config::Config{installsitelib}),
       $sources{inst_archlib}   => $Config::Config{installsitearch},
       $sources{inst_bin}       => $Config::Config{installbin} ,
       $sources{inst_script}    => $Config::Config{installscript},
       $sources{inst_man1dir}   => $Config::Config{installman1dir},
       $sources{inst_man3dir}   => $Config::Config{installman3dir},
    };
    
    # Included for future support for ${flavour}perl external lib installation
#    if ($Config::Config{flavour_perl}) {
#        my $ext = File::Spec->catdir($dir, 'blib', 'ext');
#        # from => to
#        $sources{inst_external_lib}    = File::Spec->catdir($ext, 'lib');
#        $sources{inst_external_bin}    = File::Spec->catdir($ext, 'bin');
#        $sources{inst_external_include} = File::Spec->catdir($ext, 'include');
#        $sources{inst_external_src}    = File::Spec->catdir($ext, 'src');
#        $target->{ $sources{inst_external_lib} }     = $Config::Config{flavour_install_lib};
#        $target->{ $sources{inst_external_bin} }     = $Config::Config{flavour_install_bin};
#        $target->{ $sources{inst_external_include} } = $Config::Config{flavour_install_include};
#        $target->{ $sources{inst_external_src} }     = $Config::Config{flavour_install_src};
#    }
    
    # insert user overrides
    foreach my $key (keys %$user) {
        my $value = $user->{$key};
        if (not defined $value and $key ne 'packlist_read' and $key ne 'packlist_write') {
          # undef means "remove"
          delete $target->{ $sources{$key} };
        }
        elsif (exists $sources{$key}) {
          # overwrite stuff, don't let the user create new entries
          $target->{ $sources{$key} } = $value;
        }
    }

    # apply the automatic inst_lib => inst_archlib conversion again
    # if the user asks for it and there is an archlib in the .par
    if ($user->{auto_inst_lib_conversion} and $par_has_archlib) {
      $target->{inst_lib} = $target->{inst_archlib};
    }

    return $target;
}

sub _directory_not_empty {
    require File::Find;
    my($dir) = @_;
    my $files = 0;
    File::Find::find(sub {
        return if $_ eq ".exists";
        if (-f) {
            $File::Find::prune++;
            $files = 1;
            }
    }, $dir);
    return $files;
}

#line 589

sub sign_par {
    my %args = &_args;
    _verify_or_sign(%args, action => 'sign');
}

#line 604

sub verify_par {
    my %args = &_args;
    $! = _verify_or_sign(%args, action => 'verify');
    return ( $! == Module::Signature::SIGNATURE_OK() );
}

#line 633

sub merge_par {
    my $base_par = shift;
    my @additional_pars = @_;
    require Cwd;
    require File::Copy;
    require File::Path;
    require File::Find;

    # parameter checking
    if (not defined $base_par) {
        croak "First argument to merge_par() must be the .par archive to modify.";
    }

    if (not -f $base_par or not -r _ or not -w _) {
        croak "'$base_par' is not a file or you do not have enough permissions to read and modify it.";
    }
    
    foreach (@additional_pars) {
        if (not -f $_ or not -r _) {
            croak "'$_' is not a file or you do not have enough permissions to read it.";
        }
    }

    # The unzipping will change directories. Remember old dir.
    my $old_cwd = Cwd::cwd();
    
    # Unzip the base par to a temp. dir.
    (undef, my $base_dir) = _unzip_to_tmpdir(
        dist => $base_par, subdir => 'blib'
    );
    my $blibdir = File::Spec->catdir($base_dir, 'blib');

    # move the META.yml to the (main) temp. dir.
    my $main_meta_file = File::Spec->catfile($base_dir, 'META.yml');
    File::Copy::move(
        File::Spec->catfile($blibdir, 'META.yml'),
        $main_meta_file
    );
    # delete (incorrect) MANIFEST
    unlink File::Spec->catfile($blibdir, 'MANIFEST');

    # extract additional pars and merge    
    foreach my $par (@additional_pars) {
        # restore original directory because the par path
        # might have been relative!
        chdir($old_cwd);
        (undef, my $add_dir) = _unzip_to_tmpdir(
            dist => $par
        );

        # merge the meta (at least the provides info) into the main meta.yml
        my $meta_file = File::Spec->catfile($add_dir, 'META.yml');
        if (-f $meta_file) {
          _merge_meta($main_meta_file, $meta_file);
        }

        my @files;
        my @dirs;
        # I hate File::Find
        # And I hate writing portable code, too.
        File::Find::find(
            {wanted =>sub {
                my $file = $File::Find::name;
                push @files, $file if -f $file;
                push @dirs, $file if -d _;
            }},
            $add_dir
        );
        my ($vol, $subdir, undef) = File::Spec->splitpath( $add_dir, 1);
        my @dir = File::Spec->splitdir( $subdir );
    
        # merge directory structure
        foreach my $dir (@dirs) {
            my ($v, $d, undef) = File::Spec->splitpath( $dir, 1 );
            my @d = File::Spec->splitdir( $d );
            shift @d foreach @dir; # remove tmp dir from path
            my $target = File::Spec->catdir( $blibdir, @d );
            mkdir($target);
        }

        # merge files
        foreach my $file (@files) {
            my ($v, $d, $f) = File::Spec->splitpath( $file );
            my @d = File::Spec->splitdir( $d );
            shift @d foreach @dir; # remove tmp dir from path
            my $target = File::Spec->catfile(
                File::Spec->catdir( $blibdir, @d ),
                $f
            );
            File::Copy::copy($file, $target)
              or die "Could not copy '$file' to '$target': $!";
            
        }
        chdir($old_cwd);
        File::Path::rmtree([$add_dir]);
    }
    
    # delete (copied) MANIFEST and META.yml
    unlink File::Spec->catfile($blibdir, 'MANIFEST');
    unlink File::Spec->catfile($blibdir, 'META.yml');
    
    chdir($base_dir);
    my $resulting_par_file = Cwd::abs_path(blib_to_par(quiet => 1));
    chdir($old_cwd);
    File::Copy::move($resulting_par_file, $base_par);
    
    File::Path::rmtree([$base_dir]);
}


sub _merge_meta {
  my $meta_orig_file = shift;
  my $meta_extra_file = shift;
  return() if not defined $meta_orig_file or not -f $meta_orig_file;
  return 1 if not defined $meta_extra_file or not -f $meta_extra_file;

  my $yaml_functions = _get_yaml_functions();

  die "Cannot merge META.yml files without a YAML reader/writer"
    if !exists $yaml_functions->{LoadFile}
    or !exists $yaml_functions->{DumpFile};

  my $orig_meta  = $yaml_functions->{LoadFile}->($meta_orig_file);
  my $extra_meta = $yaml_functions->{LoadFile}->($meta_extra_file);

  # I seem to remember there was this incompatibility between the different
  # YAML implementations with regards to "document" handling:
  my $orig_tree  = (ref($orig_meta) eq 'ARRAY' ? $orig_meta->[0] : $orig_meta);
  my $extra_tree = (ref($extra_meta) eq 'ARRAY' ? $extra_meta->[0] : $extra_meta);

  _merge_provides($orig_tree, $extra_tree);
  _merge_requires($orig_tree, $extra_tree);
  
  $yaml_functions->{DumpFile}->($meta_orig_file, $orig_meta);

  return 1;
}

# merge the two-level provides sections of META.yml
sub _merge_provides {
  my $orig_hash  = shift;
  my $extra_hash = shift;

  return() if not exists $extra_hash->{provides};
  $orig_hash->{provides} ||= {};

  my $orig_provides  = $orig_hash->{provides};
  my $extra_provides = $extra_hash->{provides};

  # two level clone is enough wrt META spec 1.4
  # overwrite the original provides since we're also overwriting the files.
  foreach my $module (keys %$extra_provides) {
    my $extra_mod_hash = $extra_provides->{$module};
    my %mod_hash;
    $mod_hash{$_} = $extra_mod_hash->{$_} for keys %$extra_mod_hash;
    $orig_provides->{$module} = \%mod_hash;
  }
}

# merge the single-level requires-like sections of META.yml
sub _merge_requires {
  my $orig_hash  = shift;
  my $extra_hash = shift;

  foreach my $type (qw(requires build_requires configure_requires recommends)) {
    next if not exists $extra_hash->{$type};
    $orig_hash->{$type} ||= {};
    
    # one level clone is enough wrt META spec 1.4
    foreach my $module (keys %{ $extra_hash->{$type} }) {
      # FIXME there should be a version comparison here, BUT how are we going to do that without a guaranteed version.pm?
      $orig_hash->{$type}{$module} = $extra_hash->{$type}{$module}; # assign version and module name
    }
  }
}

#line 822

sub remove_man {
    my %args = &_args;
    my $par = $args{dist};
    require Cwd;
    require File::Copy;
    require File::Path;
    require File::Find;

    # parameter checking
    if (not defined $par) {
        croak "First argument to remove_man() must be the .par archive to modify.";
    }

    if (not -f $par or not -r _ or not -w _) {
        croak "'$par' is not a file or you do not have enough permissions to read and modify it.";
    }
    
    # The unzipping will change directories. Remember old dir.
    my $old_cwd = Cwd::cwd();
    
    # Unzip the base par to a temp. dir.
    (undef, my $base_dir) = _unzip_to_tmpdir(
        dist => $par, subdir => 'blib'
    );
    my $blibdir = File::Spec->catdir($base_dir, 'blib');

    # move the META.yml to the (main) temp. dir.
    File::Copy::move(
        File::Spec->catfile($blibdir, 'META.yml'),
        File::Spec->catfile($base_dir, 'META.yml')
    );
    # delete (incorrect) MANIFEST
    unlink File::Spec->catfile($blibdir, 'MANIFEST');

    opendir DIRECTORY, 'blib' or die $!;
    my @dirs = grep { /^blib\/(?:man\d*|html)$/ }
               grep { -d $_ }
               map  { File::Spec->catfile('blib', $_) }
               readdir DIRECTORY;
    close DIRECTORY;
    
    File::Path::rmtree(\@dirs);
    
    chdir($base_dir);
    my $resulting_par_file = Cwd::abs_path(blib_to_par());
    chdir($old_cwd);
    File::Copy::move($resulting_par_file, $par);
    
    File::Path::rmtree([$base_dir]);
}


#line 888

sub get_meta {
    my %args = &_args;
    my $dist = $args{dist};
    return undef if not defined $dist or not -r $dist;
    require Cwd;
    require File::Path;

    # The unzipping will change directories. Remember old dir.
    my $old_cwd = Cwd::cwd();
    
    # Unzip the base par to a temp. dir.
    (undef, my $base_dir) = _unzip_to_tmpdir(
        dist => $dist, subdir => 'blib'
    );
    my $blibdir = File::Spec->catdir($base_dir, 'blib');

    my $meta = File::Spec->catfile($blibdir, 'META.yml');

    if (not -r $meta) {
        return undef;
    }
    
    open FH, '<', $meta
      or die "Could not open file '$meta' for reading: $!";
    
    local $/ = undef;
    my $meta_text = <FH>;
    close FH;
    
    chdir($old_cwd);
    
    File::Path::rmtree([$base_dir]);
    
    return $meta_text;
}



sub _unzip {
    my %args = &_args;
    my $dist = $args{dist};
    my $path = $args{path} || File::Spec->curdir;
    return unless -f $dist;

    # Try fast unzipping first
    if (eval { require Archive::Unzip::Burst; 1 }) {
        my $return = !Archive::Unzip::Burst::unzip($dist, $path);
        return if $return; # true return value == error (a la system call)
    }
    # Then slow unzipping
    if (eval { require Archive::Zip; 1 }) {
        my $zip = Archive::Zip->new;
        local %SIG;
        $SIG{__WARN__} = sub { print STDERR $_[0] unless $_[0] =~ /\bstat\b/ };
        return unless $zip->read($dist) == Archive::Zip::AZ_OK()
                  and $zip->extractTree('', "$path/") == Archive::Zip::AZ_OK();
    }
    # Then fall back to the system
    else {
        undef $!;
        if (_system_wrapper(unzip => $dist, '-d', $path)) {
            die "Failed to unzip '$dist' to path '$path': Could neither load "
                . "Archive::Zip nor (successfully) run the system 'unzip' (unzip said: $!)";
        }
    }

    return 1;
}

sub _zip {
    my %args = &_args;
    my $dist = $args{dist};

    if (eval { require Archive::Zip; 1 }) {
        my $zip = Archive::Zip->new;
        $zip->addTree( File::Spec->curdir, '' );
        $zip->writeToFileNamed( $dist ) == Archive::Zip::AZ_OK() or die $!;
    }
    else {
        undef $!;
        if (_system_wrapper(qw(zip -r), $dist, File::Spec->curdir)) {
            die "Failed to zip '" .File::Spec->curdir(). "' to '$dist': Could neither load "
                . "Archive::Zip nor (successfully) run the system 'zip' (zip said: $!)";
        }
    }
    return 1;
}


# This sub munges the arguments to most of the PAR::Dist functions
# into a hash. On the way, it downloads PAR archives as necessary, etc.
sub _args {
    # default to the first .par in the CWD
    if (not @_) {
        @_ = (glob('*.par'))[0];
    }

    # single argument => it's a distribution file name or URL
    @_ = (dist => @_) if @_ == 1;

    my %args = @_;
    $args{name} ||= $args{dist};

    # If we are installing from an URL, we want to munge the
    # distribution name so that it is in form "Module-Name"
    if (defined $args{name}) {
        $args{name} =~ s/^\w+:\/\///;
        my @elems = parse_dist_name($args{name});
        # @elems is name, version, arch, perlversion
        if (defined $elems[0]) {
            $args{name} = $elems[0];
        }
        else {
            $args{name} =~ s/^.*\/([^\/]+)$/$1/;
            $args{name} =~ s/^([0-9A-Za-z_-]+)-\d+\..+$/$1/;
        }
    }

    # append suffix if there is none
    if ($args{dist} and not $args{dist} =~ /\.[a-zA-Z_][^.]*$/) {
        require Config;
        my $suffix = $args{suffix};
        $suffix ||= "$Config::Config{archname}-$Config::Config{version}.par";
        $args{dist} .= "-$suffix";
    }

    # download if it's an URL
    if ($args{dist} and $args{dist} =~ m!^\w+://!) {
        $args{dist} = _fetch(dist => $args{dist})
    }

    return %args;
}


# Download PAR archive, but only if necessary (mirror!)
my %escapes;
sub _fetch {
    my %args = @_;

    if ($args{dist} =~ s/^file:\/\///) {
      return $args{dist} if -e $args{dist};
      return;
    }
    require LWP::Simple;

    $ENV{PAR_TEMP} ||= File::Spec->catdir(File::Spec->tmpdir, 'par');
    mkdir $ENV{PAR_TEMP}, 0777;
    %escapes = map { chr($_) => sprintf("%%%02X", $_) } 0..255 unless %escapes;

    $args{dist} =~ s{^cpan://((([a-zA-Z])[a-zA-Z])[-_a-zA-Z]+)/}
                    {http://www.cpan.org/modules/by-authors/id/\U$3/$2/$1\E/};

    my $file = $args{dist};
    $file =~ s/([^\w\.])/$escapes{$1}/g;
    $file = File::Spec->catfile( $ENV{PAR_TEMP}, $file);
    my $rc = LWP::Simple::mirror( $args{dist}, $file );

    if (!LWP::Simple::is_success($rc) and $rc != 304) {
        die "Error $rc: ", LWP::Simple::status_message($rc), " ($args{dist})\n";
    }

    return $file if -e $file;
    return;
}

sub _verify_or_sign {
    my %args = &_args;

    require File::Path;
    require Module::Signature;
    die "Module::Signature version 0.25 required"
      unless Module::Signature->VERSION >= 0.25;

    require Cwd;
    my $cwd = Cwd::cwd();
    my $action = $args{action};
    my ($dist, $tmpdir) = _unzip_to_tmpdir($args{dist});
    $action ||= (-e 'SIGNATURE' ? 'verify' : 'sign');

    if ($action eq 'sign') {
        open FH, '>SIGNATURE' unless -e 'SIGNATURE';
        open FH, 'MANIFEST' or die $!;

        local $/;
        my $out = <FH>;
        if ($out !~ /^SIGNATURE(?:\s|$)/m) {
            $out =~ s/^(?!\s)/SIGNATURE\n/m;
            open FH, '>MANIFEST' or die $!;
            print FH $out;
        }
        close FH;

        $args{overwrite} = 1 unless exists $args{overwrite};
        $args{skip}      = 0 unless exists $args{skip};
    }

    my $rv = Module::Signature->can($action)->(%args);
    _zip(dist => $dist) if $action eq 'sign';
    File::Path::rmtree([$tmpdir]);

    chdir($cwd);
    return $rv;
}

sub _unzip_to_tmpdir {
    my %args = &_args;

    require File::Temp;

    my $dist   = File::Spec->rel2abs($args{dist});
    my $tmpdirname = File::Spec->catdir(File::Spec->tmpdir, "parXXXXX");
    my $tmpdir = File::Temp::mkdtemp($tmpdirname)        
      or die "Could not create temporary directory from template '$tmpdirname': $!";
    my $path = $tmpdir;
    $path = File::Spec->catdir($tmpdir, $args{subdir}) if defined $args{subdir};
    _unzip(dist => $dist, path => $path);

    chdir $tmpdir;
    return ($dist, $tmpdir);
}



#line 1136

sub parse_dist_name {
    my $file = shift;
    return(undef, undef, undef, undef) if not defined $file;

    (undef, undef, $file) = File::Spec->splitpath($file);
    
    my $version = qr/v?(?:\d+(?:_\d+)?|\d*(?:\.\d+(?:_\d+)?)+)/;
    $file =~ s/\.(?:par|tar\.gz|tar)$//i;
    my @elem = split /-/, $file;
    my (@dn, $dv, @arch, $pv);
    while (@elem) {
        my $e = shift @elem;
        if (
            $e =~ /^$version$/o
            and not(# if not next token also a version
                    # (assumes an arch string doesnt start with a version...)
                @elem and $elem[0] =~ /^$version$/o
            )
        ) {
            $dv = $e;
            last;
        }
        push @dn, $e;
    }
    
    my $dn;
    $dn = join('-', @dn) if @dn;

    if (not @elem) {
        return( $dn, $dv, undef, undef);
    }

    while (@elem) {
        my $e = shift @elem;
        if ($e =~ /^(?:$version|any_version)$/) {
            $pv = $e;
            last;
        }
        push @arch, $e;
    }

    my $arch;
    $arch = join('-', @arch) if @arch;

    return($dn, $dv, $arch, $pv);
}

#line 1212

sub generate_blib_stub {
    my %args = &_args;
    my $dist = $args{dist};
    require Config;
    
    my $name    = $args{name};
    my $version = $args{version};
    my $suffix  = $args{suffix};

    my ($parse_name, $parse_version, $archname, $perlversion)
      = parse_dist_name($dist);
    
    $name ||= $parse_name;
    $version ||= $parse_version;
    $suffix = "$archname-$perlversion"
      if (not defined $suffix or $suffix eq '')
         and $archname and $perlversion;
    
    $suffix ||= "$Config::Config{archname}-$Config::Config{version}";
    if ( grep { not defined $_ } ($name, $version, $suffix) ) {
        warn "Could not determine distribution meta information from distribution name '$dist'";
        return();
    }
    $suffix =~ s/\.par$//;

    if (not -f 'META.yml') {
        open META, '>', 'META.yml'
          or die "Could not open META.yml file for writing: $!";
        print META << "YAML" if fileno(META);
name: $name
version: $version
build_requires: {}
conflicts: {}
dist_name: $name-$version-$suffix.par
distribution_type: par
dynamic_config: 0
generated_by: 'PAR::Dist version $PAR::Dist::VERSION'
license: unknown
YAML
        close META;
    }

    mkdir('blib');
    mkdir(File::Spec->catdir('blib', 'lib'));
    mkdir(File::Spec->catdir('blib', 'script'));

    return 1;
}


#line 1280

sub contains_binaries {
    require File::Find;
    my %args = &_args;
    my $dist = $args{dist};
    return undef if not defined $dist or not -r $dist;
    require Cwd;
    require File::Path;

    # The unzipping will change directories. Remember old dir.
    my $old_cwd = Cwd::cwd();
    
    # Unzip the base par to a temp. dir.
    (undef, my $base_dir) = _unzip_to_tmpdir(
        dist => $dist, subdir => 'blib'
    );
    my $blibdir = File::Spec->catdir($base_dir, 'blib');
    my $archdir = File::Spec->catdir($blibdir, 'arch');

    my $found = 0;

    File::Find::find(
      sub {
        $found++ if -f $_ and not /^\.exists$/;
      },
      $archdir
    );

    chdir($old_cwd);
    
    File::Path::rmtree([$base_dir]);
    
    return $found ? 1 : 0;
}

sub _system_wrapper {
  if ($DEBUG) {
    Carp::cluck("Running system call '@_' from:");
  }
  return system(@_);
}

# stolen from Module::Install::Can
# very much internal and subject to change or removal
sub _MI_can_run {
  require ExtUtils::MakeMaker;
  my ($cmd) = @_;

  my $_cmd = $cmd;
  return $_cmd if (-x $_cmd or $_cmd = MM->maybe_command($_cmd));

  for my $dir ((split /$Config::Config{path_sep}/, $ENV{PATH}), '.') {
    my $abs = File::Spec->catfile($dir, $cmd);
    return $abs if (-x $abs or $abs = MM->maybe_command($abs));
  }

  return;
}


# Tries to load any YAML reader writer I know of
# returns nothing on failure or hash reference containing
# a subset of Load, Dump, LoadFile, DumpFile
# entries with sub references on success.
sub _get_yaml_functions {
  # reasoning for the ranking here:
  # - XS is the de-facto standard nowadays.
  # - YAML.pm is slow and aging
  # - syck is fast and reasonably complete
  # - Tiny is only a very small subset
  # - Parse... is only a reader and only deals with the same subset as ::Tiny
  my @modules = qw(YAML::XS YAML YAML::Tiny YAML::Syck Parse::CPAN::Meta);

  my %yaml_functions;
  foreach my $module (@modules) {
    eval "require $module;";
    if (!$@) {
      warn "PAR::Dist testers/debug info: Using '$module' as YAML implementation" if $DEBUG;
      foreach my $sub (qw(Load Dump LoadFile DumpFile)) {
        no strict 'refs';
        my $subref = *{"${module}::$sub"}{CODE};
        if (defined $subref and ref($subref) eq 'CODE') {
          $yaml_functions{$sub} = $subref;
        }
      }
      $yaml_functions{yaml_provider} = $module;
      last;
    }
  } # end foreach module candidates
  if (not keys %yaml_functions) {
    warn "Cannot find a working YAML reader/writer implementation. Tried to load all of '@modules'";
  }
  return(\%yaml_functions);
}

sub _check_tools {
  my $tools = _get_yaml_functions();
  if ($DEBUG) {
    foreach (qw/Load Dump LoadFile DumpFile/) {
      warn "No YAML support for $_ found.\n" if not defined $tools->{$_};
    }
  }

  $tools->{zip} = undef;
  # A::Zip 1.28 was a broken release...
  if (eval {require Archive::Zip; 1;} and $Archive::Zip::VERSION ne '1.28') {
    warn "Using Archive::Zip as ZIP tool.\n" if $DEBUG;
    $tools->{zip} = 'Archive::Zip';
  }
  elsif (_MI_can_run("zip") and _MI_can_run("unzip")) {
    warn "Using zip/unzip as ZIP tool.\n" if $DEBUG;
    $tools->{zip} = 'zip';
  }
  else {
    warn "Found neither Archive::Zip (version != 1.28) nor ZIP/UNZIP as valid ZIP tools.\n" if $DEBUG;
    $tools->{zip} = undef;
  }

  return $tools;
}

1;

#line 1429
