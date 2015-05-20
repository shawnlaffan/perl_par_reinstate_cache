#line 1 "C:/strawberry_51613_x64/perl/vendor/lib/Archive/Zip.pm"
package Archive::Zip;

use strict;
BEGIN {
    require 5.003_96;
}
use UNIVERSAL           ();
use Carp                ();
use Cwd                 ();
use IO::File            ();
use IO::Seekable        ();
use Compress::Raw::Zlib ();
use File::Spec          ();
use File::Temp          ();
use FileHandle          ();

use vars qw( $VERSION @ISA );
BEGIN {
    $VERSION = '1.30';

    require Exporter;
    @ISA = qw( Exporter );
}

use vars qw( $ChunkSize $ErrorHandler );
BEGIN {
    # This is the size we'll try to read, write, and (de)compress.
    # You could set it to something different if you had lots of memory
    # and needed more speed.
    $ChunkSize ||= 32768;

    $ErrorHandler = \&Carp::carp;
}

# BEGIN block is necessary here so that other modules can use the constants.
use vars qw( @EXPORT_OK %EXPORT_TAGS );
BEGIN {
    @EXPORT_OK   = ('computeCRC32');
    %EXPORT_TAGS = (
        CONSTANTS => [ qw(
            FA_MSDOS
            FA_UNIX
            GPBF_ENCRYPTED_MASK
            GPBF_DEFLATING_COMPRESSION_MASK
            GPBF_HAS_DATA_DESCRIPTOR_MASK
            COMPRESSION_STORED
            COMPRESSION_DEFLATED
            COMPRESSION_LEVEL_NONE
            COMPRESSION_LEVEL_DEFAULT
            COMPRESSION_LEVEL_FASTEST
            COMPRESSION_LEVEL_BEST_COMPRESSION
            IFA_TEXT_FILE_MASK
            IFA_TEXT_FILE
            IFA_BINARY_FILE
            ) ],

        MISC_CONSTANTS => [ qw(
            FA_AMIGA
            FA_VAX_VMS
            FA_VM_CMS
            FA_ATARI_ST
            FA_OS2_HPFS
            FA_MACINTOSH
            FA_Z_SYSTEM
            FA_CPM
            FA_TOPS20
            FA_WINDOWS_NTFS
            FA_QDOS
            FA_ACORN
            FA_VFAT
            FA_MVS
            FA_BEOS
            FA_TANDEM
            FA_THEOS
            GPBF_IMPLODING_8K_SLIDING_DICTIONARY_MASK
            GPBF_IMPLODING_3_SHANNON_FANO_TREES_MASK
            GPBF_IS_COMPRESSED_PATCHED_DATA_MASK
            COMPRESSION_SHRUNK
            DEFLATING_COMPRESSION_NORMAL
            DEFLATING_COMPRESSION_MAXIMUM
            DEFLATING_COMPRESSION_FAST
            DEFLATING_COMPRESSION_SUPER_FAST
            COMPRESSION_REDUCED_1
            COMPRESSION_REDUCED_2
            COMPRESSION_REDUCED_3
            COMPRESSION_REDUCED_4
            COMPRESSION_IMPLODED
            COMPRESSION_TOKENIZED
            COMPRESSION_DEFLATED_ENHANCED
            COMPRESSION_PKWARE_DATA_COMPRESSION_LIBRARY_IMPLODED
            ) ],

        ERROR_CODES => [ qw(
            AZ_OK
            AZ_STREAM_END
            AZ_ERROR
            AZ_FORMAT_ERROR
            AZ_IO_ERROR
            ) ],

        # For Internal Use Only
        PKZIP_CONSTANTS => [ qw(
            SIGNATURE_FORMAT
            SIGNATURE_LENGTH
            LOCAL_FILE_HEADER_SIGNATURE
            LOCAL_FILE_HEADER_FORMAT
            LOCAL_FILE_HEADER_LENGTH
            CENTRAL_DIRECTORY_FILE_HEADER_SIGNATURE
            DATA_DESCRIPTOR_FORMAT
            DATA_DESCRIPTOR_LENGTH
            DATA_DESCRIPTOR_SIGNATURE
            DATA_DESCRIPTOR_FORMAT_NO_SIG
            DATA_DESCRIPTOR_LENGTH_NO_SIG
            CENTRAL_DIRECTORY_FILE_HEADER_FORMAT
            CENTRAL_DIRECTORY_FILE_HEADER_LENGTH
            END_OF_CENTRAL_DIRECTORY_SIGNATURE
            END_OF_CENTRAL_DIRECTORY_SIGNATURE_STRING
            END_OF_CENTRAL_DIRECTORY_FORMAT
            END_OF_CENTRAL_DIRECTORY_LENGTH
            ) ],

        # For Internal Use Only
        UTILITY_METHODS => [ qw(
            _error
            _printError
            _ioError
            _formatError
            _subclassResponsibility
            _binmode
            _isSeekable
            _newFileHandle
            _readSignature
            _asZipDirName
            ) ],
    );

    # Add all the constant names and error code names to @EXPORT_OK
    Exporter::export_ok_tags( qw(
        CONSTANTS
        ERROR_CODES
        PKZIP_CONSTANTS
        UTILITY_METHODS
        MISC_CONSTANTS
        ) );

}

# Error codes
use constant AZ_OK           => 0;
use constant AZ_STREAM_END   => 1;
use constant AZ_ERROR        => 2;
use constant AZ_FORMAT_ERROR => 3;
use constant AZ_IO_ERROR     => 4;

# File types
# Values of Archive::Zip::Member->fileAttributeFormat()

use constant FA_MSDOS        => 0;
use constant FA_AMIGA        => 1;
use constant FA_VAX_VMS      => 2;
use constant FA_UNIX         => 3;
use constant FA_VM_CMS       => 4;
use constant FA_ATARI_ST     => 5;
use constant FA_OS2_HPFS     => 6;
use constant FA_MACINTOSH    => 7;
use constant FA_Z_SYSTEM     => 8;
use constant FA_CPM          => 9;
use constant FA_TOPS20       => 10;
use constant FA_WINDOWS_NTFS => 11;
use constant FA_QDOS         => 12;
use constant FA_ACORN        => 13;
use constant FA_VFAT         => 14;
use constant FA_MVS          => 15;
use constant FA_BEOS         => 16;
use constant FA_TANDEM       => 17;
use constant FA_THEOS        => 18;

# general-purpose bit flag masks
# Found in Archive::Zip::Member->bitFlag()

use constant GPBF_ENCRYPTED_MASK             => 1 << 0;
use constant GPBF_DEFLATING_COMPRESSION_MASK => 3 << 1;
use constant GPBF_HAS_DATA_DESCRIPTOR_MASK   => 1 << 3;

# deflating compression types, if compressionMethod == COMPRESSION_DEFLATED
# ( Archive::Zip::Member->bitFlag() & GPBF_DEFLATING_COMPRESSION_MASK )

use constant DEFLATING_COMPRESSION_NORMAL     => 0 << 1;
use constant DEFLATING_COMPRESSION_MAXIMUM    => 1 << 1;
use constant DEFLATING_COMPRESSION_FAST       => 2 << 1;
use constant DEFLATING_COMPRESSION_SUPER_FAST => 3 << 1;

# compression method

# these two are the only ones supported in this module
use constant COMPRESSION_STORED                 => 0; # file is stored (no compression)
use constant COMPRESSION_DEFLATED               => 8; # file is Deflated
use constant COMPRESSION_LEVEL_NONE             => 0;
use constant COMPRESSION_LEVEL_DEFAULT          => -1;
use constant COMPRESSION_LEVEL_FASTEST          => 1;
use constant COMPRESSION_LEVEL_BEST_COMPRESSION => 9;

# internal file attribute bits
# Found in Archive::Zip::Member::internalFileAttributes()

use constant IFA_TEXT_FILE_MASK => 1;
use constant IFA_TEXT_FILE      => 1;
use constant IFA_BINARY_FILE    => 0;

# PKZIP file format miscellaneous constants (for internal use only)
use constant SIGNATURE_FORMAT   => "V";
use constant SIGNATURE_LENGTH   => 4;

# these lengths are without the signature.
use constant LOCAL_FILE_HEADER_SIGNATURE   => 0x04034b50;
use constant LOCAL_FILE_HEADER_FORMAT      => "v3 V4 v2";
use constant LOCAL_FILE_HEADER_LENGTH      => 26;

# PKZIP docs don't mention the signature, but Info-Zip writes it.
use constant DATA_DESCRIPTOR_SIGNATURE     => 0x08074b50;
use constant DATA_DESCRIPTOR_FORMAT        => "V3";
use constant DATA_DESCRIPTOR_LENGTH        => 12;

# but the signature is apparently optional.
use constant DATA_DESCRIPTOR_FORMAT_NO_SIG => "V2";
use constant DATA_DESCRIPTOR_LENGTH_NO_SIG => 8;

use constant CENTRAL_DIRECTORY_FILE_HEADER_SIGNATURE  => 0x02014b50;
use constant CENTRAL_DIRECTORY_FILE_HEADER_FORMAT     => "C2 v3 V4 v5 V2";
use constant CENTRAL_DIRECTORY_FILE_HEADER_LENGTH     => 42;

use constant END_OF_CENTRAL_DIRECTORY_SIGNATURE        => 0x06054b50;
use constant END_OF_CENTRAL_DIRECTORY_SIGNATURE_STRING =>
    pack( "V", END_OF_CENTRAL_DIRECTORY_SIGNATURE );
use constant END_OF_CENTRAL_DIRECTORY_FORMAT           => "v4 V2 v";
use constant END_OF_CENTRAL_DIRECTORY_LENGTH           => 18;

use constant GPBF_IMPLODING_8K_SLIDING_DICTIONARY_MASK => 1 << 1;
use constant GPBF_IMPLODING_3_SHANNON_FANO_TREES_MASK  => 1 << 2;
use constant GPBF_IS_COMPRESSED_PATCHED_DATA_MASK      => 1 << 5;

# the rest of these are not supported in this module
use constant COMPRESSION_SHRUNK    => 1;    # file is Shrunk
use constant COMPRESSION_REDUCED_1 => 2;    # file is Reduced CF=1
use constant COMPRESSION_REDUCED_2 => 3;    # file is Reduced CF=2
use constant COMPRESSION_REDUCED_3 => 4;    # file is Reduced CF=3
use constant COMPRESSION_REDUCED_4 => 5;    # file is Reduced CF=4
use constant COMPRESSION_IMPLODED  => 6;    # file is Imploded
use constant COMPRESSION_TOKENIZED => 7;    # reserved for Tokenizing compr.
use constant COMPRESSION_DEFLATED_ENHANCED => 9;   # reserved for enh. Deflating
use constant COMPRESSION_PKWARE_DATA_COMPRESSION_LIBRARY_IMPLODED => 10;

# Load the various required classes
require Archive::Zip::Archive;
require Archive::Zip::Member;
require Archive::Zip::FileMember;
require Archive::Zip::DirectoryMember;
require Archive::Zip::ZipFileMember;
require Archive::Zip::NewFileMember;
require Archive::Zip::StringMember;

use constant ZIPARCHIVECLASS => 'Archive::Zip::Archive';
use constant ZIPMEMBERCLASS  => 'Archive::Zip::Member';

# Convenience functions

sub _ISA ($$) {
    # Can't rely on Scalar::Util, so use the next best way
    local $@;
    !! eval { ref $_[0] and $_[0]->isa($_[1]) };
}

sub _CAN ($$) {
    local $@;
    !! eval { ref $_[0] and $_[0]->can($_[1]) };
}





#####################################################################
# Methods

sub new {
    my $class = shift;
    return $class->ZIPARCHIVECLASS->new(@_);
}

sub computeCRC32 {
    my ( $data, $crc );

    if ( ref( $_[0] ) eq 'HASH' ) {
        $data = $_[0]->{string};
        $crc  = $_[0]->{checksum};
    }
    else {
        $data = shift;
        $data = shift if ref($data);
        $crc  = shift;
    }

	return Compress::Raw::Zlib::crc32( $data, $crc );
}

# Report or change chunk size used for reading and writing.
# Also sets Zlib's default buffer size (eventually).
sub setChunkSize {
    shift if ref( $_[0] ) eq 'Archive::Zip::Archive';
    my $chunkSize = ( ref( $_[0] ) eq 'HASH' ) ? shift->{chunkSize} : shift;
    my $oldChunkSize = $Archive::Zip::ChunkSize;
    $Archive::Zip::ChunkSize = $chunkSize if ($chunkSize);
    return $oldChunkSize;
}

sub chunkSize {
    return $Archive::Zip::ChunkSize;
}

sub setErrorHandler {
    my $errorHandler = ( ref( $_[0] ) eq 'HASH' ) ? shift->{subroutine} : shift;
    $errorHandler = \&Carp::carp unless defined($errorHandler);
    my $oldErrorHandler = $Archive::Zip::ErrorHandler;
    $Archive::Zip::ErrorHandler = $errorHandler;
    return $oldErrorHandler;
}





######################################################################
# Private utility functions (not methods).

sub _printError {
    my $string = join ( ' ', @_, "\n" );
    my $oldCarpLevel = $Carp::CarpLevel;
    $Carp::CarpLevel += 2;
    &{$ErrorHandler} ($string);
    $Carp::CarpLevel = $oldCarpLevel;
}

# This is called on format errors.
sub _formatError {
    shift if ref( $_[0] );
    _printError( 'format error:', @_ );
    return AZ_FORMAT_ERROR;
}

# This is called on IO errors.
sub _ioError {
    shift if ref( $_[0] );
    _printError( 'IO error:', @_, ':', $! );
    return AZ_IO_ERROR;
}

# This is called on generic errors.
sub _error {
    shift if ref( $_[0] );
    _printError( 'error:', @_ );
    return AZ_ERROR;
}

# Called when a subclass should have implemented
# something but didn't
sub _subclassResponsibility {
    Carp::croak("subclass Responsibility\n");
}

# Try to set the given file handle or object into binary mode.
sub _binmode {
    my $fh = shift;
    return _CAN( $fh, 'binmode' ) ? $fh->binmode() : binmode($fh);
}

# Attempt to guess whether file handle is seekable.
# Because of problems with Windows, this only returns true when
# the file handle is a real file.  
sub _isSeekable {
    my $fh = shift;
    return 0 unless ref $fh;
    if ( _ISA($fh, 'IO::Scalar') ) {
        # IO::Scalar objects are brokenly-seekable
        return 0;
    }
    if ( _ISA($fh, 'IO::String') ) {
        return 1;
    }
    if ( _ISA($fh, 'IO::Seekable') ) {
        # Unfortunately, some things like FileHandle objects
        # return true for Seekable, but AREN'T!!!!!
        if ( _ISA($fh, 'FileHandle') ) {
            return 0;
        } else {
            return 1;
        }
    }
    if ( _CAN($fh, 'stat') ) {
        return -f $fh;
    }
    return (
        _CAN($fh, 'seek') and _CAN($fh, 'tell')
        ) ? 1 : 0;
}

# Print to the filehandle, while making sure the pesky Perl special global 
# variables don't interfere.
sub _print
{
    my ($self, $fh, @data) = @_;

    local $\;

    return $fh->print(@data);
}

# Return an opened IO::Handle
# my ( $status, fh ) = _newFileHandle( 'fileName', 'w' );
# Can take a filename, file handle, or ref to GLOB
# Or, if given something that is a ref but not an IO::Handle,
# passes back the same thing.
sub _newFileHandle {
    my $fd     = shift;
    my $status = 1;
    my $handle;

    if ( ref($fd) ) {
        if ( _ISA($fd, 'IO::Scalar') or _ISA($fd, 'IO::String') ) {
            $handle = $fd;
        } elsif ( _ISA($fd, 'IO::Handle') or ref($fd) eq 'GLOB' ) {
            $handle = IO::File->new;
            $status = $handle->fdopen( $fd, @_ );
        } else {
            $handle = $fd;
        }
    } else {
        $handle = IO::File->new;
        $status = $handle->open( $fd, @_ );
    }

    return ( $status, $handle );
}

# Returns next signature from given file handle, leaves
# file handle positioned afterwards.
# In list context, returns ($status, $signature)
# ( $status, $signature) = _readSignature( $fh, $fileName );

sub _readSignature {
    my $fh                = shift;
    my $fileName          = shift;
    my $expectedSignature = shift;    # optional

    my $signatureData;
    my $bytesRead = $fh->read( $signatureData, SIGNATURE_LENGTH );
    if ( $bytesRead != SIGNATURE_LENGTH ) {
        return _ioError("reading header signature");
    }
    my $signature = unpack( SIGNATURE_FORMAT, $signatureData );
    my $status    = AZ_OK;

    # compare with expected signature, if any, or any known signature.
    if ( ( defined($expectedSignature) && $signature != $expectedSignature )
        || ( !defined($expectedSignature)
            && $signature != CENTRAL_DIRECTORY_FILE_HEADER_SIGNATURE
            && $signature != LOCAL_FILE_HEADER_SIGNATURE
            && $signature != END_OF_CENTRAL_DIRECTORY_SIGNATURE
            && $signature != DATA_DESCRIPTOR_SIGNATURE ) )
    {
        my $errmsg = sprintf( "bad signature: 0x%08x", $signature );
        if ( _isSeekable($fh) )
        {
            $errmsg .=
              sprintf( " at offset %d", $fh->tell() - SIGNATURE_LENGTH );
        }

        $status = _formatError("$errmsg in file $fileName");
    }

    return ( $status, $signature );
}

# Utility method to make and open a temp file.
# Will create $temp_dir if it doesn't exist.
# Returns file handle and name:
#
# my ($fh, $name) = Archive::Zip::tempFile();
# my ($fh, $name) = Archive::Zip::tempFile('mytempdir');
#

sub tempFile {
    my $dir = ( ref( $_[0] ) eq 'HASH' ) ? shift->{tempDir} : shift;
    my ( $fh, $filename ) = File::Temp::tempfile(
        SUFFIX => '.zip',
        UNLINK => 0,        # we will delete it!
        $dir ? ( DIR => $dir ) : ()
    );
    return ( undef, undef ) unless $fh;
    my ( $status, $newfh ) = _newFileHandle( $fh, 'w+' );
    return ( $newfh, $filename );
}

# Return the normalized directory name as used in a zip file (path
# separators become slashes, etc.). 
# Will translate internal slashes in path components (i.e. on Macs) to
# underscores.  Discards volume names.
# When $forceDir is set, returns paths with trailing slashes (or arrays
# with trailing blank members).
#
# If third argument is a reference, returns volume information there.
#
# input         output
# .             ('.')   '.'
# ./a           ('a')   a
# ./a/b         ('a','b')   a/b
# ./a/b/        ('a','b')   a/b
# a/b/          ('a','b')   a/b
# /a/b/         ('','a','b')    /a/b
# c:\a\b\c.doc  ('','a','b','c.doc')    /a/b/c.doc      # on Windoze
# "i/o maps:whatever"   ('i_o maps', 'whatever')  "i_o maps/whatever"   # on Macs
sub _asZipDirName    
{
    my $name      = shift;
    my $forceDir  = shift;
    my $volReturn = shift;
    my ( $volume, $directories, $file ) =
      File::Spec->splitpath( File::Spec->canonpath($name), $forceDir );
    $$volReturn = $volume if ( ref($volReturn) );
    my @dirs = map { $_ =~ s{/}{_}g; $_ } File::Spec->splitdir($directories);
    if ( @dirs > 0 ) { pop (@dirs) unless $dirs[-1] }   # remove empty component
    push ( @dirs, defined($file) ? $file : '' );
    #return wantarray ? @dirs : join ( '/', @dirs );
    return join ( '/', @dirs );
}

# Return an absolute local name for a zip name.
# Assume a directory if zip name has trailing slash.
# Takes an optional volume name in FS format (like 'a:').
#
sub _asLocalName    
{
    my $name   = shift;    # zip format
    my $volume = shift;
    $volume = '' unless defined($volume);    # local FS format

    my @paths = split ( /\//, $name );
    my $filename = pop (@paths);
    $filename = '' unless defined($filename);
    my $localDirs = @paths ? File::Spec->catdir(@paths) : '';
    my $localName = File::Spec->catpath( $volume, $localDirs, $filename );
    unless ( $volume ) {
        $localName = File::Spec->rel2abs( $localName, Cwd::getcwd() );
    }
    return $localName;
}

1;

__END__

#line 2060
