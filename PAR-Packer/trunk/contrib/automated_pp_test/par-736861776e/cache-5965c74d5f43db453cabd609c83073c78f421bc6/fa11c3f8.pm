#line 1 "C:\shawn\svn\par\trunk\lib/PAR.pm"
package PAR;
$PAR::VERSION = '1.008';

use 5.006;
use strict;
use warnings;
use Config '%Config';
use Carp qw/croak/;

# If the 'prefork' module is available, we
# register various run-time loaded modules with it.
# That way, there is more shared memory in a forking
# environment.
BEGIN {
    if (eval 'require prefork') {
        prefork->import($_) for qw/
            Archive::Zip
            File::Glob
            File::Spec
            File::Temp
            LWP::Simple
            PAR::Heavy
        /;
        # not including Archive::Unzip::Burst which only makes sense
        # in the context of a PAR::Packer'ed executable anyway.
    }
}

use PAR::SetupProgname;
use PAR::SetupTemp;

#line 311

use vars qw(@PAR_INC);              # explicitly stated PAR library files (preferred)
use vars qw(@PAR_INC_LAST);         # explicitly stated PAR library files (fallback)
use vars qw(%PAR_INC);              # sets {$par}{$file} for require'd modules
use vars qw(@LibCache %LibCache);   # I really miss pseudohash.
use vars qw($LastAccessedPAR $LastTempFile);
use vars qw(@RepositoryObjects);    # If we have PAR::Repository::Client support, we
                                    # put the ::Client objects in here.
use vars qw(@PriorityRepositoryObjects); # repositories which are preferred over local stuff
use vars qw(@UpgradeRepositoryObjects);  # If we have PAR::Repository::Client's in upgrade mode
                                         # put the ::Client objects in here *as well*.
use vars qw(%FileCache);            # The Zip-file file-name-cache
                                    # Layout:
                                    # $FileCache{$ZipObj}{$FileName} = $Member
use vars qw(%ArchivesExtracted);    # Associates archive-zip-object => full extraction path

my $ver  = $Config{version};
my $arch = $Config{archname};
my $progname = $ENV{PAR_PROGNAME} || $0;
my $is_insensitive_fs = (
    -s $progname
        and (-s lc($progname) || -1) == (-s uc($progname) || -1)
        and (-s lc($progname) || -1) == -s $progname
);

# lexical for import(), and _import_foo() functions to control unpar()
my %unpar_options;

# called on "use PAR"
sub import {
    my $class = shift;

    PAR::SetupProgname::set_progname();
    PAR::SetupTemp::set_par_temp_env();

    $progname = $ENV{PAR_PROGNAME} ||= $0;
    $is_insensitive_fs = (-s $progname and (-s lc($progname) || -1) == (-s uc($progname) || -1));

    my @args = @_;
    
    # Insert PAR hook in @INC.
    unshift @INC, \&find_par   unless grep { $_ eq \&find_par }      @INC;
    push @INC, \&find_par_last unless grep { $_ eq \&find_par_last } @INC;

    # process args to use PAR 'foo.par', { opts }, ...;
    foreach my $par (@args) {
        if (ref($par) eq 'HASH') {
            # we have been passed a hash reference
            _import_hash_ref($par);
        }
        elsif ($par =~ /[?*{}\[\]]/) {
           # implement globbing for PAR archives
           require File::Glob;
           foreach my $matched (File::Glob::glob($par)) {
               push @PAR_INC, unpar($matched, undef, undef, 1);
           }
        }
        else {
            # ordinary string argument => file
            push @PAR_INC, unpar($par, undef, undef, 1);
        }
    }

    return if $PAR::__import;
    local $PAR::__import = 1;

    require PAR::Heavy;
    PAR::Heavy::_init_dynaloader();

    # The following code is executed for the case where the
    # running program is itself a PAR archive.
    # ==> run script/main.pl
    if (unpar($progname)) {
        # XXX - handle META.yml here!
        push @PAR_INC, unpar($progname, undef, undef, 1);

        _extract_inc($progname);
        if ($LibCache{$progname}) {
          # XXX bad: this us just a good guess
          require File::Spec;
          $ArchivesExtracted{$progname} = File::Spec->catdir($ENV{PAR_TEMP}, 'inc');
        }

        my $zip = $LibCache{$progname};
        my $member = _first_member( $zip,
            "script/main.pl",
            "main.pl",
        );

        if ($progname and !$member) {
            require File::Spec;
            my @path = File::Spec->splitdir($progname);
            my $filename = pop @path;
            $member = _first_member( $zip,
                "script/".$filename,
                "script/".$filename.".pl",
                $filename,
                $filename.".pl",
            )
        }

        # finally take $ARGV[0] as the hint for file to run
        if (defined $ARGV[0] and !$member) {
            $member = _first_member( $zip,
                "script/$ARGV[0]",
                "script/$ARGV[0].pl",
                $ARGV[0],
                "$ARGV[0].pl",
            ) or die qq(PAR.pm: Can't open perl script "$ARGV[0]": No such file or directory);
            shift @ARGV;
        }


        if (!$member) {
            die "Usage: $0 script_file_name.\n";
        }

        _run_member($member);
    }
}


# import() helper for the "use PAR {...};" syntax.
sub _import_hash_ref {
    my $opt = shift;

    # hash slice assignment -- pass all of the options into unpar
    local @unpar_options{keys(%$opt)} = values(%$opt);

    # check for incompatible options:
    if ( exists $opt->{repository} and exists $opt->{file} ) {
        croak("Invalid PAR loading options. Cannot have a 'repository' and 'file' option at the same time.");
    }
    elsif (
        exists $opt->{file}
        and (exists $opt->{install} or exists $opt->{upgrade})
    ) {
        my $e = exists($opt->{install}) ? 'install' : 'upgrade';
        croak("Invalid PAR loading options. Cannot combine 'file' and '$e' options.");
    }
    elsif ( not exists $opt->{repository} and not exists $opt->{file} ) {
        croak("Invalid PAR loading options. Need at least one of 'file' or 'repository' options.");
    }

    # load from file
    if (exists $opt->{file}) {
        croak("Cannot load undefined PAR archive")
          if not defined $opt->{file};

        # for files, we default to loading from PAR archive first
        my $fallback = $opt->{fallback};
        $fallback = 0 if not defined $fallback;
        
        if (not $fallback) {
            # load from this PAR arch preferably
            push @PAR_INC, unpar($opt->{file}, undef, undef, 1);
        }
        else {
            # load from this PAR arch as fallback
            push @PAR_INC_LAST, unpar($opt->{file}, undef, undef, 1);
        }
        
    }
    else {
        # Deal with repositories elsewhere
        my $client = _import_repository($opt);
        return() if not $client;

        if (defined $opt->{run}) {
            # run was specified
            # run the specified script from the repository
            $client->run_script( $opt->{run} );
            return 1;
        }
        
        return 1;
    }

    # run was specified
    # run the specified script from inside the PAR file.
    if (defined $opt->{run}) {
        my $script = $opt->{run};
        require PAR::Heavy;
        PAR::Heavy::_init_dynaloader();
        
        # XXX - handle META.yml here!
        _extract_inc($opt->{file});

        my $zip = $LibCache{$opt->{file}};
        my $member = _first_member( $zip,
            (($script !~ /^script\//) ? ("script/$script", "script/$script.pl") : ()),
            $script,
            "$script.pl",
        );
        
        if (not defined $member) {
            croak("Cannot run script '$script' from PAR file '$opt->{file}'. Script couldn't be found in PAR file.");
        }
        
        _run_member_from_par($member);
    }

    return();
}


# This sub is invoked by _import_hash_ref if a {repository}
# option is found
# Returns the repository client object on success.
sub _import_repository {
    my $opt = shift;
    my $url = $opt->{repository};

    eval "require PAR::Repository::Client; 1;";
    if ($@ or not eval PAR::Repository::Client->VERSION >= 0.04) {
        croak "In order to use the 'use PAR { repository => 'url' };' syntax, you need to install the PAR::Repository::Client module (version 0.04 or later) from CPAN. This module does not seem to be installed as indicated by the following error message: $@";
    }
    
    if ($opt->{upgrade} and not eval PAR::Repository::Client->VERSION >= 0.22) {
        croak "In order to use the 'upgrade' option, you need to install the PAR::Repository::Client module (version 0.22 or later) from CPAN";
    }

    if ($opt->{dependencies} and not eval PAR::Repository::Client->VERSION >= 0.23) {
        croak "In order to use the 'dependencies' option, you need to install the PAR::Repository::Client module (version 0.23 or later) from CPAN";
    }

    my $obj;

    # Support existing clients passed in as objects.
    if (ref($url) and UNIVERSAL::isa($url, 'PAR::Repository::Client')) {
        $obj = $url;
    }
    else {
        $obj = PAR::Repository::Client->new(
            uri                 => $url,
            auto_install        => $opt->{install},
            auto_upgrade        => $opt->{upgrade},
            static_dependencies => $opt->{dependencies},
        );
    }

    if (exists($opt->{fallback}) and not $opt->{fallback}) {
        unshift @PriorityRepositoryObjects, $obj; # repository beats local stuff
    } else {
        push @RepositoryObjects, $obj; # local stuff beats repository
    }
    # these are tracked separately so we can check for upgrades early
    push @UpgradeRepositoryObjects, $obj if $opt->{upgrade};

    return $obj;
}

# Given an Archive::Zip obj and a list of files/paths,
# this function returns the Archive::Zip::Member for the
# first of the files found in the ZIP. If none is found,
# returns the empty list.
sub _first_member {
    my $zip = shift;
    foreach my $name (@_) {
        my $member = _cached_member_named($zip, $name);
        return $member if $member;
    }
    return;
}

# Given an Archive::Zip object, this finds the first 
# Archive::Zip member whose file name matches the
# regular expression
sub _first_member_matching {
    my $zip = shift;
    my $regex = shift;

    my $cache = $FileCache{$zip};
    $cache = $FileCache{$zip} = _make_file_cache($zip) if not $cache;

    foreach my $name (keys %$cache) {
      if ($name =~ $regex) {
        return $cache->{$name};
      }
    }

    return();
}


sub _run_member_from_par {
    my $member = shift;
    my $clear_stack = shift;
    my ($fh, $is_new, $filename) = _tempfile($member->crc32String . ".pl");

    if ($is_new) {
        my $file = $member->fileName;
        print $fh "package main;\n";
        print $fh "#line 1 \"$file\"\n";
        $member->extractToFileHandle($fh);
        seek ($fh, 0, 0);
    }

    $ENV{PAR_0} = $filename; # for Pod::Usage
    { do $filename;
      CORE::exit($1) if ($@ =~/^_TK_EXIT_\((\d+)\)/);
      die $@ if $@;
      exit;
    }
}

sub _run_member {
    my $member = shift;
    my $clear_stack = shift;
    my ($fh, $is_new, $filename) = _tempfile($member->crc32String . ".pl");

    if ($is_new) {
        my $file = $member->fileName;
        print $fh "package main; shift \@INC;\n";
        if (defined &Internals::PAR::CLEARSTACK and $clear_stack) {
            print $fh "Internals::PAR::CLEARSTACK();\n";
        }
        print $fh "#line 1 \"$file\"\n";
        $member->extractToFileHandle($fh);
        seek ($fh, 0, 0);
    }

    unshift @INC, sub { $fh };

    $ENV{PAR_0} = $filename; # for Pod::Usage
    { do 'main';
      CORE::exit($1) if ($@ =~/^_TK_EXIT_\((\d+)\)/);
      die $@ if $@;
      exit;
    }
}

sub _run_external_file {
    my $filename = shift;
    my $clear_stack = shift;
    require 5.008;
    open my $ffh, '<', $filename
      or die "Can't open perl script \"$filename\": $!";

    my $clearstack = '';
    if (defined &Internals::PAR::CLEARSTACK and $clear_stack) {
        $clear_stack = "Internals::PAR::CLEARSTACK();\n";
    }
    my $string = "package main; shift \@INC;\n$clearstack#line 1 \"$filename\"\n"
                 . do { local $/ = undef; <$ffh> };
    close $ffh;

    open my $fh, '<', \$string
      or die "Can't open file handle to string: $!";

    unshift @INC, sub { $fh };

    $ENV{PAR_0} = $filename; # for Pod::Usage
    { do 'main';
      CORE::exit($1) if ($@ =~/^_TK_EXIT_\((\d+)\)/);
      die $@ if $@;
      exit;
    }
}

sub get_canary_file_name {
    return '_PAR_CANARY.txt';
}

# extract the contents of a .par (or .exe) or any
# Archive::Zip handle to the PAR_TEMP/inc directory.
# returns that directory.
sub _extract_inc {
    my $file_or_azip_handle = shift;
    my $force_extract = shift;
    my $inc = "$PAR::SetupTemp::PARTemp/inc";
    my $dlext = defined($Config{dlext}) ? $Config::Config{dlext} : '';
    my $inc_exists = -d $inc;
    my $is_handle = ref($file_or_azip_handle) && $file_or_azip_handle->isa('Archive::Zip::Archive');

    #  canary file name needs to use CRC string or something to make it more unique
    my $inc_canary = "$inc/" . get_canary_file_name();  
    my $inc_canary_exists = -e $inc_canary;

    require File::Spec;

    if (!$inc_exists or $force_extract or !$inc_canary_exists) {
        for (1 .. 10) { mkdir("$inc.lock", 0755) and last; sleep 1 }
        
        undef $@;
        if (!$is_handle) {
          # First try to unzip the *fast* way.
          eval {
            require Archive::Unzip::Burst;
            Archive::Unzip::Burst::unzip($file_or_azip_handle, $inc)
              and die "Could not unzip '$file_or_azip_handle' into '$inc'. Error: $!";
              die;
          };

          # This means the fast module is there, but didn't work.
          if ($@ =~ /^Could not unzip/) {
            die $@;
          }
        }

        # either failed to load Archive::Unzip::Burst or got an A::Zip handle
        # fallback to slow way.
        if ($is_handle || $@) {
          my $zip;
          if (!$is_handle) {
            open my $fh, '<', $file_or_azip_handle
              or die "Cannot find '$file_or_azip_handle': $!";
            binmode($fh);
            bless($fh, 'IO::File');

            $zip = Archive::Zip->new;
            ( $zip->readFromFileHandle($fh, $file_or_azip_handle) == Archive::Zip::AZ_OK() )
                or die "Read '$file_or_azip_handle' error: $!";
          }
          else {
            $zip = $file_or_azip_handle;
          }

          mkdir($inc) if not -d $inc;

          for ( $zip->memberNames() ) {
              s{^/}{};

              # Skip DLLs (these will be handled by the dynaloader hook) 
              # except for those placed in File::ShareDir directories.
              next if (m{\.\Q$dlext\E[^/]*$} && !m{^lib/auto/share/(dist|module)/}); 

              my $outfile =  File::Spec->catfile($inc, $_);
              next if -e $outfile and not -w _;
              $zip->extractMember($_, "$inc/" . $_);
          }
        }
        
        rmdir("$inc.lock");

        $ArchivesExtracted{$is_handle ? $file_or_azip_handle->fileName() : $file_or_azip_handle} = $inc;
    }

    # add the freshly extracted directories to @INC,
    # but make sure there's no duplicates
    my %inc_exists = map { ($_, 1) } @INC;
    unshift @INC, grep !exists($inc_exists{$_}),
                  grep -d,
                  map File::Spec->catdir($inc, @$_),
                  [ 'lib' ], [ 'arch' ], [ $arch ],
                  [ $ver ], [ $ver, $arch ], [];

    return $inc;
}


# This is the hook placed in @INC for loading PAR's
# before any other stuff in @INC
sub find_par {
    my @args = @_;

    # if there are repositories in upgrade mode, check them
    # first. If so, this is expensive, of course!
    if (@UpgradeRepositoryObjects) {
        my $module = $args[1];
        $module =~ s/\.pm$//;
        $module =~ s/\//::/g;
        foreach my $client (@UpgradeRepositoryObjects) {
            my $local_file = $client->upgrade_module($module);

            # break the require if upgrade_module has been required already
            # to avoid infinite recursion
            if (exists $INC{$args[1]}) {
                # Oh dear. Check for the possible return values of the INC sub hooks in
                # perldoc -f require before trying to understand this.
                # Then, realize that if you pass undef for the file handle, perl (5.8.9)
                # does NOT use the subroutine. Thus the hacky GLOB ref.
                my $line = 1;
                no warnings;
                return (\*I_AM_NOT_HERE, sub {$line ? ($_="1;",$line=0,return(1)) : ($_="",return(0))});
            }

            # Note: This is likely not necessary as the module has been installed
            # into the system by upgrade_module if it was available at all.
            # If it was already loaded, this will not be reached (see return right above).
            # If it could not be loaded from the system and neither found in the repository,
            # we simply want to have the normal error message, too!
            #
            #if ($local_file) {
            #    # XXX load with fallback - is that right?
            #    return _find_par_internals([$PAR_INC_LAST[-1]], @args);
            #}
        }
    }
    my $rv = _find_par_internals(\@PAR_INC, @args);

    return $rv if defined $rv or not @PriorityRepositoryObjects;

    # the repositories that are prefered over locally installed modules
    my $module = $args[1];
    $module =~ s/\.pm$//;
    $module =~ s/\//::/g;
    foreach my $client (@PriorityRepositoryObjects) {
        my $local_file = $client->get_module($module, 0); # 1 == fallback
        if ($local_file) {
            # Not loaded as fallback (cf. PRIORITY) thus look at PAR_INC
            # instead of PAR_INC_LAST
            return _find_par_internals([$PAR_INC[-1]], @args);
        }
    }
    return();
}

# This is the hook placed in @INC for loading PAR's
# AFTER any other stuff in @INC
# It also deals with loading from repositories as a
# fallback-fallback ;)
sub find_par_last {
    my @args = @_;
    # Try the local PAR files first
    my $rv = _find_par_internals(\@PAR_INC_LAST, @args);
    return $rv if defined $rv;

    # No repositories => return
    return $rv if not @RepositoryObjects;

    my $module = $args[1];
    $module =~ s/\.pm$//;
    $module =~ s/\//::/g;
    foreach my $client (@RepositoryObjects) {
        my $local_file = $client->get_module($module, 1); # 1 == fallback
        if ($local_file) {
            # Loaded as fallback thus look at PAR_INC_LAST
            return _find_par_internals([$PAR_INC_LAST[-1]], @args);
        }
    }
    return $rv;
}


# This routine implements loading modules from PARs
# both for loading PARs preferably or as fallback.
# To distinguish the cases, the first parameter should
# be a reference to the corresponding @PAR_INC* array.
sub _find_par_internals {
    my ($INC_ARY, $self, $file, $member_only) = @_;

    my $scheme;
    foreach (@$INC_ARY ? @$INC_ARY : @INC) {
        my $path = $_;
        if ($] < 5.008001) {
            # reassemble from "perl -Ischeme://path" autosplitting
            $path = "$scheme:$path" if !@$INC_ARY
                and $path and $path =~ m!//!
                and $scheme and $scheme =~ /^\w+$/;
            $scheme = $path;
        }
        my $rv = unpar($path, $file, $member_only, 1) or next;
        $PAR_INC{$path}{$file} = 1;
        $INC{$file} = $LastTempFile if (lc($file) =~ /^(?!tk).*\.pm$/);
        return $rv;
    }

    return;
}

sub reload_libs {
    my @par_files = @_;
    @par_files = sort keys %LibCache unless @par_files;

    foreach my $par (@par_files) {
        my $inc_ref = $PAR_INC{$par} or next;
        delete $LibCache{$par};
        delete $FileCache{$par};
        foreach my $file (sort keys %$inc_ref) {
            delete $INC{$file};
            require $file;
        }
    }
}

#sub find_zip_member {
#    my $file = pop;
#
#    foreach my $zip (@LibCache) {
#        my $member = _first_member($zip, $file) or next;
#        return $member;
#    }
#
#    return;
#}

sub read_file {
    my $file = pop;

    foreach my $zip (@LibCache) {
        my $member = _first_member($zip, $file) or next;
        return scalar $member->contents;
    }

    return;
}

sub par_handle {
    my $par = pop;
    return $LibCache{$par};
}

my %escapes;
sub unpar {
    my ($par, $file, $member_only, $allow_other_ext) = @_;
	return if not defined $par;
    my $zip = $LibCache{$par};
    my @rv = $par;

    # a guard against (currently unimplemented) recursion
    return if $PAR::__unpar;
    local $PAR::__unpar = 1;

    unless ($zip) {
        # URL use case ==> download
        if ($par =~ m!^\w+://!) {
            require File::Spec;
            require LWP::Simple;

            # reflector support
            $par .= "pm=$file" if $par =~ /[?&;]/;

            # prepare cache directory
            $ENV{PAR_CACHE} ||= '_par';
            mkdir $ENV{PAR_CACHE}, 0777;
            if (!-d $ENV{PAR_CACHE}) {
                $ENV{PAR_CACHE} = File::Spec->catdir(File::Spec->tmpdir, 'par');
                mkdir $ENV{PAR_CACHE}, 0777;
                return unless -d $ENV{PAR_CACHE};
            }

            # Munge URL into local file name
            # FIXME: This might result in unbelievably long file names!
            # I have run into the file/path length limitations of linux
            # with similar code in PAR::Repository::Client.
            # I suspect this is even worse on Win32.
            # -- Steffen
            my $file = $par;
            if (!%escapes) {
                $escapes{chr($_)} = sprintf("%%%02X", $_) for 0..255;
            }
            {
                use bytes;
                $file =~ s/([^\w\.])/$escapes{$1}/g;
            }

            $file = File::Spec->catfile( $ENV{PAR_CACHE}, $file);
            LWP::Simple::mirror( $par, $file );
            return unless -e $file and -f _;
            $par = $file;
        }
        # Got the .par as a string. (reference to scalar, of course)
        elsif (ref($par) eq 'SCALAR') {
            my ($fh) = _tempfile();
            print $fh $$par;
            $par = $fh;
        }
        # If the par is not a valid .par file name and we're being strict
        # about this, then also check whether "$par.par" exists
        elsif (!(($allow_other_ext or $par =~ /\.par\z/i) and -f $par)) {
            $par .= ".par";
            return unless -f $par;
        }

        require Archive::Zip;
        $zip = Archive::Zip->new;

        my @file;
        if (!ref $par) {
            @file = $par;

            open my $fh, '<', $par;
            binmode($fh);

            $par = $fh;
            bless($par, 'IO::File');
        }

        Archive::Zip::setErrorHandler(sub {});
        my $rv = $zip->readFromFileHandle($par, @file);
        Archive::Zip::setErrorHandler(undef);
        return unless $rv == Archive::Zip::AZ_OK();

        push @LibCache, $zip;
        $LibCache{$_[0]} = $zip;
        $FileCache{$_[0]} = _make_file_cache($zip);

        # only recursive case -- appears to be unused and unimplemented
        foreach my $member ( _cached_members_matching($zip, 
            "^par/(?:$Config{version}/)?(?:$Config{archname}/)?"
        ) ) {
            next if $member->isDirectory;
            my $content = $member->contents();
            next unless $content =~ /^PK\003\004/;
            push @rv, unpar(\$content, undef, undef, 1);
        }
        
        # extract all shlib dlls from the .par to $ENV{PAR_TEMP}
        # Intended to fix problem with Alien::wxWidgets/Wx...
        # NOTE auto/foo/foo.so|dll will get handled by the dynaloader
        # hook, so no need to pull it out here.
        # Allow this to be disabled so caller can do their own caching
        # via import({no_shlib_unpack => 1, file => foo.par})
        if(not $unpar_options{no_shlib_unpack} and defined $ENV{PAR_TEMP}) {
            my @members = _cached_members_matching( $zip,
              qr#^shlib/$Config{archname}/.*\.\Q$Config{dlext}\E(?:\.|$)#
            );
            foreach my $member (@members) {
                next if $member->isDirectory;
                my $member_name = $member->fileName;
                next unless $member_name =~ m{
                        \/([^/]+)$
                    }x
                    or $member_name =~ m{
                        ^([^/]+)$
                    };
                my $extract_name = $1;
                my $dest_name =
                    File::Spec->catfile($ENV{PAR_TEMP}, $extract_name);
                # but don't extract it if we've already got one
                $member->extractToFileNamed($dest_name)
                    unless(-e $dest_name);
            }
        }

        # Now push this path into usual library search paths
        my $separator = $Config{path_sep};
        my $tempdir = $ENV{PAR_TEMP};
        foreach my $key (qw(
            LD_LIBRARY_PATH
            LIB_PATH
            LIBRARY_PATH
            PATH
            DYLD_LIBRARY_PATH
        )) {
           if (defined $ENV{$key} and $ENV{$key} ne '') {
               # Check whether it's already in the path. If so, don't
               # append the PAR temp dir in order not to overflow the
               # maximum length for ENV vars.
               $ENV{$key} .= $separator . $tempdir
                 unless grep { $_ eq $tempdir } split $separator, $ENV{$key};
           }
           else {
               $ENV{$key} = $tempdir;
           }
       }
    
    }

    $LastAccessedPAR = $zip;

    return @rv unless defined $file;

    my $member = _first_member($zip,
        "lib/$file",
        "arch/$file",
        "$arch/$file",
        "$ver/$file",
        "$ver/$arch/$file",
        $file,
    ) or return;

    return $member if $member_only;

    my ($fh, $is_new);
    ($fh, $is_new, $LastTempFile) = _tempfile($member->crc32String . ".pm");
    die "Bad Things Happened..." unless $fh;

    if ($is_new) {
        $member->extractToFileHandle($fh);
        seek ($fh, 0, 0);
    }

    return $fh;
}

sub _tempfile {
    my ($fh, $filename);
    if ($ENV{PAR_CLEAN} or !@_) {
        require File::Temp;

        if (defined &File::Temp::tempfile) {
            # under Win32, the file is created with O_TEMPORARY,
            # and will be deleted by the C runtime; having File::Temp
            # delete it has the only effect of giving ugly warnings
            ($fh, $filename) = File::Temp::tempfile(
                DIR     => $PAR::SetupTemp::PARTemp,
                UNLINK  => ($^O ne 'MSWin32' and $^O !~ /hpux/),
            ) or die "Cannot create temporary file: $!";
            binmode($fh);
            return ($fh, 1, $filename);
        }
    }

    require File::Spec;

    # untainting tempfile path
    local $_ = File::Spec->catfile( $PAR::SetupTemp::PARTemp, $_[0] );
    /^(.+)$/ and $filename = $1;

    if (-r $filename) {
        open $fh, '<', $filename or die $!;
        binmode($fh);
        return ($fh, 0, $filename);
    }

    open $fh, '+>', $filename or die $!;
    binmode($fh);
    return ($fh, 1, $filename);
}

# Given an Archive::Zip object, this generates a hash of
#   file_name_in_zip => file object
# and returns a reference to that.
# If we broke the encapsulation of A::Zip::Member and
# accessed $member->{fileName} directly, that would be
# *significantly* faster.
sub _make_file_cache {
    my $zip = shift;
    if (not ref($zip)) {
        croak("_make_file_cache needs an Archive::Zip object as argument.");
    }
    my $cache = {};
    foreach my $member ($zip->members) {
        $cache->{$member->fileName()} = $member;
    }
    return $cache;
}

# given an Archive::Zip object, this finds the cached hash
# of Archive::Zip member names => members,
# and returns all member objects whose file names match
# a regexp
# Without file caching, it just uses $zip->membersMatching
sub _cached_members_matching {
    my $zip = shift;
    my $regex = shift;

    my $cache = $FileCache{$zip};
    $cache = $FileCache{$zip} = _make_file_cache($zip) if not $cache;

    return map {$cache->{$_}}
        grep { $_ =~ $regex }
        keys %$cache;
}

# access named zip file member through cache. Fall
# back to using Archive::Zip (slow)
sub _cached_member_named {
    my $zip = shift;
    my $name = shift;

    my $cache = $FileCache{$zip};
    $cache = $FileCache{$zip} = _make_file_cache($zip) if not $cache;
    return $cache->{$name};
}


# Attempt to clean up the temporary directory if
# --> We're running in clean mode
# --> It's defined
# --> It's an existing directory
# --> It's empty
END {
  if (exists $ENV{PAR_CLEAN} and $ENV{PAR_CLEAN}
      and exists $ENV{PAR_TEMP} and defined $ENV{PAR_TEMP} and -d $ENV{PAR_TEMP}
  ) {
    local($!); # paranoid: ignore potential errors without clobbering a global variable!
    rmdir($ENV{PAR_TEMP});
  }
}

1;

__END__

#line 1257
