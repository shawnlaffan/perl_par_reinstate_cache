#!/usr/bin/perl

use strict;
use warnings;
use Cwd;
use Config;
use FindBin;
use File::Spec;
use File::Temp ();
use ExtUtils::MakeMaker;
use File::Path qw /remove_tree/;


use Test::More;

$ENV{PAR_TMPDIR} = File::Temp::tempdir(TMPDIR => 1, CLEANUP => 1);

sub samefiles {
    my ($f1, $f2) = @_;
    $f1 eq $f2 and return 1;
    -e $f1 && -e $f2 or return 0;
    -s $f1 == -s $f2 or return 0;
    local $/ = \65536;
    open my $fh1, '<', $f1 or return 0;
	open my $fh2, '<', $f2 or return 0;
    while (1) {
		my $c1 = <$fh1>;
		my $c2 = <$fh2>;
		last if !defined $c1 and !defined $c2;
		return 0 if !defined $c1 or !defined $c2;
		return 0 if $c1 ne $c2;
    }
    return 1;
}

chdir File::Spec->catdir($FindBin::Bin, File::Spec->updir);

my $cwd = getcwd();
my $test_dir = File::Spec->catdir($cwd, 'contrib', 'automated_pp_test');

my $parl = File::Spec->catfile($cwd, 'blib', 'script', "parl$Config{_exe}");
my $startperl = $Config{startperl};
$startperl =~ s/^#!//;

my $orig_X = $^X;
my $orig_startperl = $startperl;

if (!-e $parl) {
    print "1..0 # Skip 'parl' not found\n";
    exit;
}
elsif (!($^X = main->can_run($^X))) {
    print "1..0 # Skip '$orig_X' not found\n";
    exit;
}
elsif (!($startperl = main->can_run($startperl))) {
    print "1..0 # Skip '$orig_startperl' not found\n";
    exit;
}

# NOTE: Win32::GetShortPathName exists on cygwin, too
if ($^O eq 'MSWin32' && defined &Win32::GetShortPathName) {
    $^X = lc(Win32::GetShortPathName($^X));
    $startperl = lc(Win32::GetShortPathName($startperl));
}

if (!samefiles($startperl, $^X)) {
    print "1..0 # Skip '$^X' is not the same as '$startperl'\n";
    exit;
}

unshift @INC, File::Spec->catdir($cwd, 'inc');
unshift @INC, File::Spec->catdir($cwd, 'blib', 'lib');
unshift @INC, File::Spec->catdir($cwd, 'blib', 'script');

$ENV{PAR_GLOBAL_CLEAN} = 1;

$ENV{PATH} = join(
    $Config{path_sep},
    grep length,
        File::Spec->catdir($cwd, 'blib', 'script'),
        $ENV{PATH},
);
$ENV{PERL5LIB} = join(
    $Config{path_sep},
    grep length,
        File::Spec->catdir($cwd, 'blib', 'lib'),
        $test_dir,
        $ENV{PERL5LIB},
);

chdir $test_dir;

$ENV{PAR_TMPDIR} = $test_dir;

my $tmpfile1   = File::Spec->catfile($test_dir, 'check1.txt');
my $tmpfolder1 = File::Spec->catfile($test_dir, 'checkfolder');
my $tmpfile2   = File::Spec->catfile($tmpfolder1, 'check2.txt');

mkdir $tmpfolder1 if !-d $tmpfolder1;
foreach my $file ($tmpfile1, $tmpfile2) {
    open(my $fh, '>', $file) or die "Cannot open $file to write to";
    print {$fh} "$file\n$file\n";  #  contents don't matter for this test
    close ($fh);
}

my $script = File::Spec->catfile('script.pl');
open(my $fh, '>', $script) or die "Cannot open $script";
print {$fh} <<'END_OF_SCRIPT'
use File::Spec;
my $inc = File::Spec->catdir($ENV{PAR_TEMP}, 'inc');
print $inc;
open my $fh, '<', File::Spec->catfile($inc, 'check1.txt')
  or die "Cannot open $inc/check1.txt";
exit;
END_OF_SCRIPT
  ;
close ($fh);

my $osname = $^O;
my $exe_file = 'tester';
if ($^O =~ /Win/i) {
    $exe_file .= '.exe';
}

#  still need to ensure we are using the correct pp (i.e. not the system one)
#  also use correct extension - exe is for Windows
my @cmd = (
    'pp', '-o', $exe_file,
    '-a' => "$tmpfile1;check1.txt",
    '-a' => "$tmpfolder1;checkfolder",
    #'-v',
    $script,
);
print join ' ', @cmd, "\n";
system @cmd;

#  now run it
$ENV{PAR_GLOBAL_CLEAN} = 0;
my $inc_dir = `$exe_file`;

#  Now delete the files we packed into the exe using -a
#  These are in the par temp inc folder
diag "Deleting inc files\n";
my $success;
my $file1 = File::Spec->catfile($inc_dir, 'check1.txt');
my $dir1  = File::Spec->catfile($inc_dir, 'checkfolder');
$success  = unlink $file1;
$success  = remove_tree $dir1;
#  If the whole inc directory is deleted then it all gets re-extracted
#  and thus there are no failures to test.
#$success  = remove_tree $inc_dir;

#  A couple of sanity checks.
#  If these files are not deleted then subsequent tests will fail.
ok (!-e $file1, "$file1 was deleted");
ok (!-e $dir1,  "$dir1 was deleted");

#  Now run the PAR binary again.  We should get 0 on success.
my $error = system $exe_file;

ok (!$error, "Packed script runs after -a packed files deleted from par/inc");


done_testing();


sub can_run {
    my ($self, $cmd) = @_;

    my $_cmd = $cmd;
    return $_cmd if (-x $_cmd or $_cmd = MM->maybe_command($_cmd));

    for my $dir ((split /$Config::Config{path_sep}/, $ENV{PATH}), '.') {
        my $abs = File::Spec->catfile($dir, $_[1]);
        return $abs if (-x $abs or $abs = MM->maybe_command($abs));
    }

    return;
}

__END__
