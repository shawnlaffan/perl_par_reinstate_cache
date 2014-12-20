#!/usr/bin/perl
use 5.006001;
use strict;
use inc::Module::Install;

name        'PAR-Packer-WithPerl';
all_from    'lib/PAR/Packer/WithPerl.pm';

requires    'PAR::Packer' => '0.992';

include_deps 'Test::More';

auto_provides;

par_base 'SMUELLER';

if (defined($ENV{PERL5LIB}) || defined($ENV{PERLLIB})) {
    warn <<'WARNING';
*** You have extra Perl library paths set in your environment.
    Please note that these paths (set with PERL5LIB or PERLLIB)
    are not honored by perl when running under taint mode, which
    may lead to problems. This is a limitation (by design) of
    Perl, not of PAR::Packer::WARNING; but some of the problems may
    manifest here during installation.

WARNING
}

par_prehook();
WriteAll sign => 0;
par_posthook();

my %no_parl  = ();

use strict; use warnings;
sub par_prehook {
    my $bork = $no_parl{$^O};
    my $cc;
    $cc = can_cc unless $bork;
    my $par;
    $par = fetch_par('', '', !$cc) unless ($cc or $bork);
    my $exe  = $Config::Config{_exe};
    my $dynperl = $Config::Config{useshrplib} && ($Config::Config{useshrplib} ne 'false');

    if ($bork) {
        warn "Binary loading known to fail on $^O; won't generate 'script/parl$exe'!\n";
    }
    elsif (!$par and !$cc) {
        warn "No compiler found, won't generate 'src/perl$exe'!\n";
    }

    # XXX: this branch is currently not entered
    if ($cc and $par) {
        my $answer = prompt(
            "*** Pre-built PAR-Packer-WithPerl package found.  Use it instead of recompiling [y/N]?"
        );
        if ($answer !~ /^[Yy]/) {
            load('preamble')->{preamble} = '';
            $par = '';
        }
    } 

    my @bin = ("src/perl$exe");
    push @bin, ("src/staticperl$exe") if $dynperl;

    $FindBin::Bin = '.' unless -e "$FindBin::Bin/Makefile.PL";
    my $par_exe = "$FindBin::Bin/$bin[0]";

    if ($par) {
        open my $fh, '>', $par_exe or die "Cannot write to $par_exe";
        close $fh;
    }
    elsif (-f $par_exe and not -s $par_exe) {
        unlink $par_exe;
    }

    clean_files(@bin) if $par or $cc;

    makemaker_args(
        #MAN1PODS		=> {
        #},
#        EXE_FILES		=> [
#          (!$par and $cc) ? (
#            "script/parl$exe",
#            $dynperl ? (
 #               "script/parldyn$exe",
 ##           ) : (),
 #         ) : (),
 #       ],
        DIR                     => [
          (!$par and $cc) ? (
            'src'
          ) : (),
        ],
        NEEDS_LINKING	        => 1,
    );
}

sub par_posthook {
    my $exe = $Config::Config{_exe};
    return unless $exe eq '.exe';

    open my $in, '<', "$FindBin::Bin/Makefile" or return;
    open my $out, '>', "$FindBin::Bin/Makefile.new" or return;
    while (<$in>) {
        next if /^\t\$\(FIXIN\) .*\Q$exe\E$/;
        next if /^\@\[$/ or /^\]$/;
        print $out $_;
    }
    close $out;
    close $in;
    unlink "$FindBin::Bin/Makefile";
    rename "$FindBin::Bin/Makefile.new" => "$FindBin::Bin/Makefile";
}

1;
