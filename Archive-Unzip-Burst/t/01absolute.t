# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Archive-InfoUnzip.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 4;
use Cwd;
use File::Spec;
BEGIN { use_ok('Archive::Unzip::Burst') };

chdir("t");
my $dir = Cwd::cwd();
my $file = File::Spec->catfile($dir, "foo.zip");
Archive::Unzip::Burst::unzip($file, "blah");

ok(-d "blah");
ok(-d File::Spec->catdir("blah", "t2"));
my $outfile = File::Spec->catfile("blah", "t2", "Archive-InfoUnzip.t");
ok(-f $outfile);


unlink ($outfile);
rmdir(File::Spec->catdir("blah", "t2"));
rmdir("blah");

