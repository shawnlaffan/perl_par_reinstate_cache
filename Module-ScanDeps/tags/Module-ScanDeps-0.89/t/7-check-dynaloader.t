#!perl

use Test::More;
use Config ();

use Module::ScanDeps;
use Cwd;

unless( $Config::Config{usedl} ){
    plan('skip_all', 'Sorry, no dynamic loading');
}

plan(tests => 2);

my $rv = scan_deps_runtime(
            files   => [ 't/data/check-dynaloader/Bar.pm' ],
            recurse => 1,
            compile => 1,
         );


my ( $entry ) =  grep { /^auto\b.*\bCwd\.$Config::Config{dlext}/ } keys %$rv;

ok( $entry, 'we have some key that looks like it pulled in the Cwd shared lib' );

# build a path the the Cwd library based on the entry in %INC and our Module::ScanDeps path
( my $cwd_bundle_path = $INC{ 'Cwd.pm' } ) =~ s/Cwd\.pm$/$entry/;

is( $rv->{$entry}->{file}, $cwd_bundle_path, 'the full bundle path we got looks legit' );


__END__

