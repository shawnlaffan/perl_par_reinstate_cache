use ExtUtils::MakeMaker;
use Config;
use vars qw/$os $osmakefile $osmaketarget $osobjext @winobjs $windllcmd $winsys/;
require File::Spec;
$Verbose = 1;
my $exe = $Config::Config{_exe};
my $o   = $Config::Config{obj_ext};

my $unzipdir = "unzip-5.52";

my $toptargettext;

if ( $^O =~ /^MSWin/i ) {
    my $cleanfiles;
    
    for(@winobjs) {
        $cleanfiles .= qq($unzipdir/$_$o );
    }
    
    if( $winsys eq 'vc' ) {
        $cleanfiles .= qq($unzipdir/windll.res $unzipdir/unzip32.lib $unzipdir/unzip32.exp $unzipdir/unzip32.dll);
    } else {
        $cleanfiles .= qq($unzipdir/windllrc.o $unzipdir/windll.o $unzipdir/unzip32.dll);
    }
    
    $toptargettext = "all :: dll
pure_all :: dll
dll :
\tcd $unzipdir && $windllcmd
";
    
    WriteMakefile(
      NAME   => 'Archive::Unzip::Burst',
      clean  => {'FILES' => $cleanfiles },
      test   => { 'TESTS' => '' },
    );

} # end if win32
else {
  if (not defined $os) {
    die "The Makefile.PL in res/ is designed to be included by the main Makefile.PL!";
  }

  my $objects;
  if ($os eq 'unix' or $os eq 'win32') {
    $objects = join(' ', map {File::Spec->catfile($unzipdir, "$_$osobjext$o")} qw|unzip crc32 crctab crypt envargs explode extract fileio globals inflate list match process ttyio unreduce unshrink zipinfo api|, "$os");
  }
  else {
    die "Funny OS. Don't know what to link.";
  }

  $toptargettext = "all :: static

pure_all :: static

static ::       libmyunzip\$(LIB_EXT)

libmyunzip\$(LIB_EXT): \$(O_FILES)
	\$(AR) cr libmyunzip\$(LIB_EXT) $objects
	\$(RANLIB) libmyunzip\$(LIB_EXT)
";

  WriteMakefile(
    NAME   => 'Archive::Unzip::Burst',
    #SKIP   => [qw(all static static_lib dynamic dynamic_lib)],
    DEFINE            => '-fPIC -DDLL -O3', # e.g., '-DHAVE_SOMETHING'
    INC               => "-I. -Iunzip-5.52 -Iunzip-5.52/$os", # e.g., '-I. -I/usr/include/other'
    clean  => {
      'FILES' => "libmyunzip\$(LIB_EXT) $objects $unzipdir/unzipstb.o $unzipdir/*.so $unzipdir/*.dll $unzipdir/*.so.* $unzipdir/unzip_shlib$exe $unzipdir/Makefile $unzipdir/*.o"
    },
    OBJECT            => $objects,
  );

} # end if not win32

sub MY::top_targets {
    "
$toptargettext
";
}
