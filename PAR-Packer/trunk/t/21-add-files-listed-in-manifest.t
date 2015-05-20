#!/usr/bin/perl

#  Test that added files (via -a flag) are listed in the packed manifest.yml file.
#  Much of this is a copy of 20-pp.t but seems to be
#  needed if we retain the sanity checks at the top.  

use strict;
use warnings;
use Cwd;
use Config;
use FindBin;
use File::Spec;
use File::Temp ();
use ExtUtils::MakeMaker;
use File::Path qw /remove_tree/;
use PAR ();

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
#my $test_dir = File::Spec->catdir($cwd, 'contrib', 'automated_pp_test');
my $test_dir = File::Temp::tempdir(TMPDIR => 1, CLEANUP => 1);

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

$ENV{PAR_GLOBAL_CLEAN} = 1;

chdir $test_dir;

$ENV{PAR_TMPDIR} = $test_dir;

my $tmpfile1 = File::Spec->catfile($test_dir, 'check1.txt');
my $tmpdir1  = File::Spec->catfile($test_dir, 'checkdir1');
my $tmpfile2 = File::Spec->catfile($tmpdir1,  'check2.txt');

mkdir $tmpdir1 if !-d $tmpdir1;
foreach my $file ($tmpfile1, $tmpfile2) {
    open(my $fh, '>', $file) or die "Cannot open $file to write to";
    print {$fh} "$file\n$file\n";  #  contents don't matter for this test
    close ($fh);
}


my $script = File::Spec->catfile('script.pl');
open(my $fh, '>', $script) or die "Cannot open $script";
print {$fh} <<'END_OF_SCRIPT'
use File::Spec;
print "$ENV{PAR_TEMP}\n";
END_OF_SCRIPT
  ;
close ($fh);

my $osname = $^O;
my $exe_file = 'tester' . $Config{_exe};

#  Not using script approach, as pp->go() allows for debugger step-through
#my $pp_script = File::Spec->catdir($cwd, 'blib', 'script', 'pp');

my @cmd = (
    #$pp_script,
    '-o' => $exe_file,
    '-a' => "$tmpfile1;check1.txt",
    '-a' => "$tmpdir1;checkdir1",
    #'-v',
    $script,
);
#print join ' ', @cmd, "\n";
#system @cmd;
my $opts = join ' ', @cmd;
$opts =~ s'\\'\\\\'g;  #  CLUNKY, but quotemeta is overzealous and also escapes dashes and spaces
$ENV{PP_OPTS} = $opts;
print "\$ENV{PP_OPTS} = $ENV{PP_OPTS}\n";
use pp;
pp->go();

#  now run it
$ENV{PAR_GLOBAL_CLEAN} = 0;
print "...running PAR exe...\n";
my $feedback = `$exe_file`;
my @feedback = split "\n", $feedback;
my $par_tmp_dir  = $feedback[0];
my $manifest_file = File::Spec->catfile ($par_tmp_dir, 'inc', 'MANIFEST');
open(my $manifest_fh, '<', $manifest_file)
  or die "Cannot open $manifest_file for reading";

my $path1 = "check1.txt";
my $path2 = "checkdir1/check2.txt";

my ($has_file1, $has_file2);

while (my $line = <$manifest_fh>) {
    chomp $line;
    #print "...$line...\n";
    if ($line =~ m/^$path1$/) {
        $has_file1 ++
    }
    if ($line =~ m/^$path2$/) {
        $has_file2 ++
    }
};


is ($has_file1, 1, "Manifest includes $path1");
is ($has_file2, 1, "Manifest includes $path2");


#  go back to the start dir so the File::Temp cleanup will work
chdir $cwd;

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
