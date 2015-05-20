use File::Spec;
my $inc = File::Spec->catdir($ENV{PAR_TEMP}, 'inc');
print "$inc\n";
#print join ' ', '@INC:', @INC, "\n";
my $fname = File::Spec->catfile($inc, 'check1.txt');
open my $fh1, '<', $fname
  or die "Cannot open $fname";
$fname = File::Spec->catfile($inc, 'checkdir1', 'check2.txt');
open my $fh2, '<', $fname
  or die "Cannot open $fname";
exit;
